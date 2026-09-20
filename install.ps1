# Quartus II 13.1 (64-bit) 简体中文汉化包 - 安装脚本
# 用法: powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 [-QuartusBin64 "D:\altera\13.1\quartus\bin64"]
param(
    [string]$QuartusBin64 = ""
)
$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$PkgDir = Join-Path $Root "zhcn-dlls"
$Files = @("sys_qui.dll", "gcl_afcq.dll", "saui_aseq.dll")
$BackupDirName = "zh_CN_backup"

# 原版 (pristine) SHA256 —— 安装器以此确认目标安装是本补丁对应的原版 13.1 64 位
$PristineSha = @{
    "sys_qui.dll"  = "bce217b64891261a89a9b5d7ba837c414671d1aba6470d6bce37a7f96cb36f59"
    "gcl_afcq.dll" = "f6f29e363d18032ccde8494717a9501eb90819277242a602537f91ba65df7e44"
    "saui_aseq.dll"= "9df5423121834f8cbda17ea1eea1f06b4e6f4d52571b5d77b666e248078f5a65"
}

function Get-FileSha256([string]$Path) {
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLower()
}

function Find-QuartusBin64 {
    if ($QuartusBin64 -ne "") { return $QuartusBin64 }
    # 1) QUARTUS_ROOTDIR 环境变量（指向 ...\quartus）
    if ($env:QUARTUS_ROOTDIR) {
        $p = Join-Path $env:QUARTUS_ROOTDIR "bin64"
        if (Test-Path (Join-Path $p "quartus.exe")) { return $p }
    }
    # 2) PATH 上的 quartus.exe
    $cmd = Get-Command quartus.exe -ErrorAction SilentlyContinue
    if ($cmd) { return Split-Path -Parent $cmd.Source }
    # 3) 常见安装位置扫描
    foreach ($drive in @("C:", "D:", "E:", "F:", "G:")) {
        $hits = Get-ChildItem -Path $drive\ -Filter "quartus.exe" -Recurse -Depth 4 -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -like "*quartus\bin64*" }
        if ($hits) { return Split-Path -Parent $hits[0].FullName }
    }
    return ""
}

# ---------- 0) Quartus 必须未运行 ----------
$q = Get-Process quartus -ErrorAction SilentlyContinue
if ($q) { Write-Host "[X] 检测到 Quartus 正在运行，请先退出 Quartus 再安装。" -ForegroundColor Red; exit 1 }

# ---------- 1) 定位 bin64 ----------
$bin = Find-QuartusBin64
if ($bin -eq "" -or -not (Test-Path (Join-Path $bin "quartus.exe"))) {
    Write-Host "[X] 未找到 Quartus II 13.1 安装目录。" -ForegroundColor Red
    Write-Host "    请用 -QuartusBin64 参数指定，例如:" -ForegroundColor Red
    Write-Host '    powershell -ExecutionPolicy Bypass -File install.ps1 -QuartusBin64 "C:\altera\13.1\quartus\bin64"'
    exit 1
}
Write-Host "[i] Quartus bin64: $bin"

# ---------- 2) 校验当前状态 ----------
$state = @{}
foreach ($f in $Files) {
    $target = Join-Path $bin $f
    if (-not (Test-Path $target)) { Write-Host "[X] 缺少文件: $target" -ForegroundColor Red; exit 1 }
    $state[$f] = Get-FileSha256 $target
}
$patchedSha = @{}
foreach ($f in $Files) { $patchedSha[$f] = Get-FileSha256 (Join-Path $PkgDir $f) }

$allPatched = $true; $allPristine = $true
foreach ($f in $Files) {
    if ($state[$f] -ne $patchedSha[$f]) { $allPatched = $false }
    if ($state[$f] -ne $PristineSha[$f]) { $allPristine = $false }
}
if ($allPatched) { Write-Host "[i] 汉化包已经安装，无需重复操作。" -ForegroundColor Yellow; exit 0 }
if (-not $allPristine) {
    Write-Host "[X] 目标 DLL 与原版 Quartus II 13.1 (64-bit) 不匹配，拒绝安装。" -ForegroundColor Red
    Write-Host "    本补丁只能安装在未被修改过的原版 13.1 64 位上。" -ForegroundColor Red
    foreach ($f in $Files) { Write-Host ("    {0}: {1}" -f $f, $state[$f]) }
    exit 1
}

# ---------- 3) 备份原版（不覆盖已有备份） ----------
$backupDir = Join-Path $bin $BackupDirName
$manifest = Join-Path $backupDir "manifest.json"
if (Test-Path $manifest) {
    Write-Host "[i] 已存在原版备份 ($BackupDirName)，保留不动。" -ForegroundColor Yellow
} else {
    New-Item -ItemType Directory -Path $backupDir | Out-Null
    $doc = [ordered]@{
        backup_at_utc = (Get-Date).ToUniversalTime().ToString("o")
        quartus_bin64 = $bin
        files = [ordered]@{}
    }
    foreach ($f in $Files) {
        Copy-Item (Join-Path $bin $f) (Join-Path $backupDir $f)
        $doc.files[$f] = $state[$f]
    }
    $doc | ConvertTo-Json | Set-Content -Encoding UTF8 $manifest
    Write-Host "[+] 原版已备份到 $backupDir"
}

# ---------- 4) 安装并校验 ----------
foreach ($f in $Files) {
    Copy-Item (Join-Path $PkgDir $f) (Join-Path $bin $f) -Force
    $now = Get-FileSha256 (Join-Path $bin $f)
    if ($now -ne $patchedSha[$f]) {
        Write-Host "[X] 写入校验失败: $f" -ForegroundColor Red; exit 1
    }
}
Write-Host ""
Write-Host "[OK] 汉化安装完成。启动 Quartus II 即可看到中文菜单。" -ForegroundColor Green
Write-Host "     如需还原英文原版，运行 卸载.bat 即可。" -ForegroundColor Green
