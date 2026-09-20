# Quartus II 13.1 (64-bit) 简体中文汉化包 - 卸载脚本（还原英文原版）
# 用法: powershell -NoProfile -ExecutionPolicy Bypass -File uninstall.ps1 [-QuartusBin64 "D:\altera\13.1\quartus\bin64"]
param(
    [string]$QuartusBin64 = ""
)
$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$PkgDir = Join-Path $Root "zhcn-dlls"
$Files = @("sys_qui.dll", "gcl_afcq.dll", "saui_aseq.dll")
$BackupDirName = "zh_CN_backup"

function Get-FileSha256([string]$Path) {
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLower()
}

function Find-QuartusBin64 {
    if ($QuartusBin64 -ne "") { return $QuartusBin64 }
    if ($env:QUARTUS_ROOTDIR) {
        $p = Join-Path $env:QUARTUS_ROOTDIR "bin64"
        if (Test-Path (Join-Path $p "quartus.exe")) { return $p }
    }
    $cmd = Get-Command quartus.exe -ErrorAction SilentlyContinue
    if ($cmd) { return Split-Path -Parent $cmd.Source }
    foreach ($drive in @("C:", "D:", "E:", "F:", "G:")) {
        $hits = Get-ChildItem -Path $drive\ -Filter "quartus.exe" -Recurse -Depth 4 -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -like "*quartus\bin64*" }
        if ($hits) { return Split-Path -Parent $hits[0].FullName }
    }
    return ""
}

# ---------- 0) Quartus 必须未运行 ----------
$q = Get-Process quartus -ErrorAction SilentlyContinue
if ($q) { Write-Host "[X] 检测到 Quartus 正在运行，请先退出 Quartus 再卸载。" -ForegroundColor Red; exit 1 }

# ---------- 1) 定位 bin64 ----------
$bin = Find-QuartusBin64
if ($bin -eq "" -or -not (Test-Path (Join-Path $bin "quartus.exe"))) {
    Write-Host "[X] 未找到 Quartus II 13.1 安装目录（可用 -QuartusBin64 指定）。" -ForegroundColor Red
    exit 1
}
Write-Host "[i] Quartus bin64: $bin"

# ---------- 2) 校验当前是汉化版（幂等：已是原版则直接收尾） ----------
$patchedSha = @{}
foreach ($f in $Files) { $patchedSha[$f] = Get-FileSha256 (Join-Path $PkgDir $f) }
$anyPatched = $false
foreach ($f in $Files) {
    if ((Get-FileSha256 (Join-Path $bin $f)) -eq $patchedSha[$f]) { $anyPatched = $true }
}
if (-not $anyPatched) {
    Write-Host "[i] 当前未安装汉化包，无需卸载。" -ForegroundColor Yellow
    exit 0
}

# ---------- 3) 备份目录与清单 ----------
$backupDir = Join-Path $bin $BackupDirName
$manifest = Join-Path $backupDir "manifest.json"
if (-not (Test-Path $manifest)) {
    Write-Host "[X] 未找到原版备份 $manifest ，无法安全还原。" -ForegroundColor Red
    Write-Host "    如果安装后清理过该目录，请改用 Quartus 安装包修复或重装对应组件。" -ForegroundColor Red
    exit 1
}
$doc = Get-Content $manifest -Raw | ConvertFrom-Json

# ---------- 4) 还原原版并校验 ----------
foreach ($f in $Files) {
    $src = Join-Path $backupDir $f
    if (-not (Test-Path $src)) { Write-Host "[X] 备份缺少 $f，中止。" -ForegroundColor Red; exit 1 }
    Copy-Item $src (Join-Path $bin $f) -Force
}
foreach ($f in $Files) {
    $now = Get-FileSha256 (Join-Path $bin $f)
    if ($now -ne $doc.files.$f) {
        Write-Host "[X] 还原校验失败: $f" -ForegroundColor Red; exit 1
    }
}
Remove-Item $backupDir -Recurse -Force
Write-Host ""
Write-Host "[OK] 已还原英文原版 Quartus II 13.1，备份目录已清理。" -ForegroundColor Green
