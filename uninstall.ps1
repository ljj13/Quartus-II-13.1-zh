# Quartus II 13.1 (64-bit) 简体中文汉化包 - 卸载脚本（还原安装前的文件）
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

function FilesEqual([string]$A, [string]$B) {
    [System.Linq.Enumerable]::SequenceEqual(
        [System.IO.File]::ReadAllBytes($A), [System.IO.File]::ReadAllBytes($B))
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

# ---------- 2) 备份目录 ----------
$backupDir = Join-Path $bin $BackupDirName
$manifest = Join-Path $backupDir "manifest.json"

# ---------- 3) 已安装检测（无备份目录 → 视为未安装） ----------
if (-not (Test-Path $manifest)) {
    $allSame = $true
    foreach ($f in $Files) {
        if (-not (FilesEqual (Join-Path $bin $f) (Join-Path $PkgDir $f))) { $allSame = $false }
    }
    if ($allSame) {
        Write-Host "[i] 当前未安装汉化包，无需卸载。" -ForegroundColor Yellow
        exit 0
    }
    Write-Host "[i] 未检测到本补丁的备份目录 ($BackupDirName) —— 大概率从未安装过，无需卸载。" -ForegroundColor Yellow
    Write-Host "    若你曾安装并手动删除了备份目录，自动还原已不可能，请改用 Quartus 安装包修复。" -ForegroundColor Yellow
    exit 0
}

# ---------- 4) 还原安装前的文件 ----------
foreach ($f in $Files) {
    $src = Join-Path $backupDir $f
    if (-not (Test-Path $src)) { Write-Host "[X] 备份缺少 $f，中止。" -ForegroundColor Red; exit 1 }
    Copy-Item $src (Join-Path $bin $f) -Force
}
Remove-Item $backupDir -Recurse -Force
Write-Host ""
Write-Host "[OK] 已还原安装前的文件，备份目录已清理。" -ForegroundColor Green
