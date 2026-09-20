# .zhcn 节 / QCN1 文本池格式规格

本文档描述本补丁在 `sys_qui.dll` / `gcl_afcq.dll` 中追加的 `.zhcn` 自定义节的内容布局，
以及三类修改的落盘方式。`tools/extract_translations.py` 可按此规格从成品反向提取全部词条。

## 1. 节本身

- 追加在 DLL 节表末尾，名称 `.zhcn`，`Characteristics = 0x40000040`
  （`IMAGE_SCN_INITIALIZED_DATA | IMAGE_SCN_MEM_READ`）
- `VirtualSize` = 实际使用的字节数；`SizeOfRawData` 按 `FileAlignment`（0x200）向上取整
- 头部同步修改：`FILE_HEADER.NumberOfSections + 1`、
  `OPTIONAL_HEADER.SizeOfInitializedData += SizeOfRawData`、
  `SizeOfImage = align_up(节 VA + VirtualSize, SectionAlignment)`
- 文件偏移：节原始数据紧跟原文件末尾（对齐边界），不改写任何既有字节

## 2. QCN1 池布局（小端）

```text
偏移      大小   内容
0x00      4     magic 'QCN1'
0x04      4     version = 1
0x08      4     count（词条数；sys_qui=17，gcl_afcq=133）
0x0C      4     reserved = 0
0x10      16*N  词条表，每条：
                 +0x00 u32 blob_offset   —— 相对节起始的字节偏移
                 +0x04 u32 blob_bytes    —— 含结尾 NUL 的字节数
                 +0x08 u32 original_rva  —— 原英文字符串在 .rdata 的 RVA（保留原文，不覆写）
                 +0x0C u32 flags = 1
0x10+16N  ...   blobs：UTF-8 + NUL；每条起始 8 字节对齐，对齐填充清零
```

`pool_order`（词条表顺序）由发布 manifest 固化；同一构建内序列化结果逐字节确定。

## 3. 引用重定向（relocation）

原英文字符串的消费方式有两类，重定向后均指向中文 blob：

- **数据指针**：`.data`/`.rdata` 中 8 字节小端 VA（Qt QAction 指针表，gcl 簇每词条 2 个），
  改写为 `ImageBase + .zhcn VA + blob_offset`；每个位点在 `.reloc` 中有对应的
  `IMAGE_REL_BASED_DIR64` 表项
- **代码引用**：`.text` 中 `48 8D/8B modrm=??05`（LEA/MOV r64, [rip+disp32]）指令的
  4 字节位移改写为新目标 VA 的相对位移

数量：gcl 270 qword + 1 disp32（`&Copy`，gcl_afcq.dll:0xd90ac）；sys_qui 17 disp32；
saui 无池无重写。凡重定向后原英文串不再被任何引用消费的，原字节保持原样。

## 4. 原位覆写（in_place）

译文 + NUL 字节数不超过原串存储跨度（`len(原文)+1`）时，直接在原位置覆写，
并用 `0x00` 填满剩余跨度。共 48 处：gcl 42、sys_qui 5、saui 1（信息栏）。
写入前要求确认消费路径的 `QString::fromAscii_helper` 长度参数为 -1（NUL 结尾语义）。

## 5. 编解码前提

Qt 4 通过 `codecForCStrings` 把 `const char*` 转 `QString`。补丁在 `sys_qui.dll`
初始化路径注入了把进程级编解码器设为 UTF-8 的代码（code cave + 指令改写），
否则池中的 UTF-8 中文会按 Latin1 解码成乱码。

注意：`QObject::tr()` / `QCoreApplication::translate` 路径不受该编解码器控制，
凡走此路径的字符串（如 saui_dset.dll 中的实例）一律不做修改。

## 6. 校验

- 池自校验：逐条回读 blob，`blob[-1] == 0` 且内容 == 译文 UTF-8
- 引用完备性：全部 288 个重写位点（270+1+17）逐一回读，目标 == 对应 blob VA；
  每个 relocation 词条 ≥1 个位点且指针指向 blob 起始
- 逐字节记账：与 pristine 的全部差异必须落在预期改动区间内（节头、.zhcn、
  重写位点、in_place 跨度、编解码 stub）
