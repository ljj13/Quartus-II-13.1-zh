#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从成品 DLL（汉化版 vs 备份原版）反提取全部翻译对照表 → docs/translations.csv。

数据来源：
  - 词条池（relocation）：解析 .zhcn 节 QCN1 池（原文仍在 .rdata 原位置，未被覆写）
  - 原位覆写（in_place）：pristine 与汉化版逐字节 diff。重写位点（指向 .zhcn 的
    qword 指针 + RIP 相对 disp32）先行显式扫描剔除并自校验数量；sys_qui 的
    UTF-8 编解码 stub 字节按可打印性自动剔除并单独计数。

用法：python tools/extract_translations.py   （需要 pip install pefile）
"""
import csv
import os
import struct

import pefile

BIN = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "..",
                                    "Quartus", "bin64"))
BAK = os.path.join(BIN, "zh_CN_backup")
OUT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..",
                                    "docs", "translations.csv"))
IB = 0x180000000
FILES = ["sys_qui.dll", "gcl_afcq.dll", "saui_aseq.dll"]
EXPECT_SITES = {"sys_qui.dll": 17, "gcl_afcq.dll": 271, "saui_aseq.dll": 0}


def read_cstring(buf, off, limit=256):
    end = buf.find(b"\x00", off, off + limit)
    if end < 0:
        end = off + limit
    return buf[off:end]


def printable_ascii(b):
    return len(b) >= 2 and all(0x20 <= c <= 0x7E for c in b)


def diff_ranges(a, b):
    n = min(len(a), len(b))
    out, i = [], 0
    while i < n:
        if a[i] != b[i]:
            j = i
            while j < n and a[j] != b[j]:
                j += 1
            out.append((i, j))
            i = j
        else:
            i += 1
    return out


def rewrite_sites(cur, pe, zhcn):
    """成品中所有指向 .zhcn 的重写位点（文件偏移区间）：qword 指针 + disp32 指令。"""
    zh_va = IB + zhcn.VirtualAddress
    zh_hi = zh_va + zhcn.Misc_VirtualSize
    sites = set()
    pos, needle = 0, b"\x80\x01\x00\x00\x00"      # .zhcn VA 高字节特征
    while True:
        pos = cur.find(needle, pos)
        if pos < 0:
            break
        off = pos - 3
        if off >= 0:
            val = struct.unpack_from("<Q", cur, off)[0]
            if zh_va <= val < zh_hi:
                sites.add((off, off + 8))
        pos += 1
    for s in pe.sections:
        if not (s.Characteristics & 0x20000000):
            continue
        raw = cur[s.PointerToRawData: s.PointerToRawData + s.SizeOfRawData]
        i = 0
        while i < len(raw) - 7:
            if raw[i] == 0x48 and raw[i + 1] in (0x8D, 0x8B) and \
                    (raw[i + 2] & 0xC7) == 0x05:
                disp = struct.unpack_from("<i", raw, i + 3)[0]
                tgt = IB + s.VirtualAddress + i + 7 + disp
                if zh_va <= tgt < zh_hi:
                    sites.add((s.PointerToRawData + i,
                               s.PointerToRawData + i + 7))
                i += 7
                continue
            i += 1
    return sites


rows = []
extra_spans = []
counts = {}
for name in FILES:
    cur = open(os.path.join(BIN, name), "rb").read()
    pri = open(os.path.join(BAK, name), "rb").read()
    pe = pefile.PE(data=cur, fast_load=True)
    zhcn = next((s for s in pe.sections
                 if bytes(s.Name).rstrip(b"\x00") == b".zhcn"), None)

    # ---- 词条池 ----
    n_pool = 0
    if zhcn is not None:
        raw_off = zhcn.PointerToRawData
        hdr = cur[raw_off:raw_off + 16]
        assert hdr[:4] == b"QCN1", name
        count = struct.unpack_from("<I", hdr, 8)[0]
        for i in range(count):
            blob_off, blob_n, orig_rva, _flags = struct.unpack_from(
                "<IIII", cur, raw_off + 16 + i * 16)
            blob = cur[raw_off + blob_off: raw_off + blob_off + blob_n]
            assert blob[-1] == 0
            translation = blob[:-1].decode("utf-8")
            o_off = pe.get_offset_from_rva(orig_rva)
            original = read_cstring(cur, o_off)
            rows.append({"file": name, "kind": "pool",
                         "original": original.decode("ascii"),
                         "translation": translation,
                         "rva": hex(orig_rva)})
            n_pool += 1

    # ---- 重写位点（显式扫描 + 自校验） ----
    sites = rewrite_sites(cur, pe, zhcn) if zhcn is not None else set()
    assert len(sites) == EXPECT_SITES[name], (name, len(sites))

    # ---- 原位覆写（diff 按 pristine 字符串跨度归组，剔除 PE 头区/.zhcn/重写位点） ----
    min_raw = min(s.PointerToRawData for s in pe.sections)
    ranges = []
    for (a, b) in diff_ranges(pri, cur):
        if b <= min_raw:                              # PE 头字段/节表
            continue
        if zhcn is not None and a >= len(pri):        # .zhcn 追加原始数据
            continue
        if any(a < s1 and s0 < b for (s0, s1) in sites):   # 指针/指令重写
            continue
        ranges.append((a, b))

    n_ip = 0
    consumed = 0
    while consumed < len(ranges):
        a = ranges[consumed][0]
        start = pri.rfind(b"\x00", max(0, a - 256), a) + 1   # 所在字符串跨度
        end_nul = pri.find(b"\x00", a)
        end = (end_nul + 1) if end_nul >= 0 else a + 1
        nxt = consumed
        while nxt < len(ranges) and ranges[nxt][0] < end and \
                ranges[nxt][1] <= end:
            nxt += 1
        if nxt == consumed:                   # 越界片段：单独消费，防死循环
            end = ranges[consumed][1]
            nxt = consumed + 1
            end_nul = min(end_nul if end_nul >= 0 else end, end)
        consumed = nxt
        original = pri[start:end_nul]
        translated = cur[start:cur.find(b"\x00", start)]
        if not printable_ascii(original):
            extra_spans.append((name, hex(start), hex(end)))
            continue                                  # 编解码 stub 等非文本
        try:
            translation = translated.decode("utf-8")
            assert any(ord(c) > 0x7F for c in translation)
        except (UnicodeDecodeError, AssertionError):
            extra_spans.append((name, hex(start), hex(end)))
            continue
        rows.append({"file": name, "kind": "in_place",
                     "original": original.decode("ascii"),
                     "translation": translation,
                     "rva": hex(pe.get_rva_from_offset(start))})
        n_ip += 1
    pe.close()
    counts[name] = (n_pool, n_ip)

rows.sort(key=lambda r: (FILES.index(r["file"]), int(r["rva"], 16)))
os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w", encoding="utf-8-sig", newline="") as fh:
    w = csv.writer(fh)
    w.writerow(["file", "kind", "original", "translation", "rva"])
    for r in rows:
        w.writerow([r["file"], r["kind"], r["original"], r["translation"], r["rva"]])

total = sum(a + b for a, b in counts.values())
for name in FILES:
    print(f"{name}: pool {counts[name][0]} + in_place {counts[name][1]} "
          f"(rewrite sites {EXPECT_SITES[name]})")
print(f"total = {total} rows -> {OUT}")
print(f"非文本 diff（编码 stub 等，不入表）: {len(extra_spans)} 处")
for n, a, b in extra_spans:
    print("  ", n, a, b)
