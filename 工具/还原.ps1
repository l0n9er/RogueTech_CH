param(
    [string]$gameRoot = "",
    [string]$backupName = ""
)
$ErrorActionPreference = 'Stop'
$enc = New-Object Text.UTF8Encoding $false

# 控制台输出编码: 与 安装.bat 的 chcp 936 一致
try {
    $cp = [Console]::OutputEncoding.CodePage
    if ($cp -ne 936 -and $cp -ne 65001) {
        [Console]::OutputEncoding = [Text.Encoding]::GetEncoding(936)
    }
} catch { }

$packRoot = Split-Path $PSScriptRoot -Parent

function Say($m)  { Write-Host $m }
function Ok($m)   { Write-Host ("      " + $m) }
function Warn($m) { Write-Host ("      警告: " + $m) -ForegroundColor Yellow }

# ---------- 定位游戏目录 ----------
if ([string]::IsNullOrWhiteSpace($gameRoot)) {
    $gameRoot = & (Join-Path $PSScriptRoot 'find-game.ps1')
    if ([string]::IsNullOrWhiteSpace($gameRoot)) {
        Write-Host ""
        Write-Host " 找不到游戏目录（未找到 BattleTech.exe）。" -ForegroundColor Yellow
        Write-Host '  请用 -gameRoot 参数指定，例如：' -ForegroundColor Yellow
        Write-Host '   powershell -File "工具\还原.ps1" -gameRoot "E:\Steam\steamapps\common\BATTLETECH"' -ForegroundColor Yellow
        Write-Host ""
        exit 1
    }
} else {
    if (-not [IO.File]::Exists((Join-Path $gameRoot "BattleTech.exe"))) {
        Write-Host ""
        Write-Host (" 指定的游戏目录无效（未找到 BattleTech.exe）: " + $gameRoot) -ForegroundColor Yellow
        Write-Host ""
        exit 1
    }
}

# ---------- 游戏运行中则拒绝 ----------
$proc = Get-Process -Name BattleTech -ErrorAction SilentlyContinue
if ($proc) {
    Write-Host ""
    Write-Host (" 检测到游戏正在运行（PID " + $proc.Id + "）。") -ForegroundColor Yellow
    Write-Host " 请先完全退出游戏，再运行还原。" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

# ---------- 选择备份目录 ----------
$backupRoot = Join-Path $packRoot "backup"
if (-not [IO.Directory]::Exists($backupRoot)) {
    Write-Host (" 找不到备份目录: " + $backupRoot) -ForegroundColor Yellow
    Write-Host " 没有可还原的备份。" -ForegroundColor Yellow
    exit 1
}

if (-not [string]::IsNullOrWhiteSpace($backupName)) {
    $stampDir = Join-Path $backupRoot $backupName
    if (-not [IO.Directory]::Exists($stampDir)) {
        Write-Host (" 指定的备份不存在: " + $stampDir) -ForegroundColor Yellow
        exit 1
    }
} else {
    # 默认: 最新的一个时间戳备份
    $stampDir = Get-ChildItem $backupRoot -Directory |
                Where-Object { $_.Name -match '^\d{8}-\d{6}$' } |
                Sort-Object Name -Descending |
                Select-Object -First 1 -ExpandProperty FullName
    if ($null -eq $stampDir) {
        Write-Host (" 备份目录下没有时间戳备份: " + $backupRoot) -ForegroundColor Yellow
        exit 1
    }
}
$stamp = Split-Path $stampDir -Leaf

# ---------- 格式检测: 新备份保留目录结构; 旧备份是把路径下划线压扁的文件 ----------
# 旧格式无法可靠映射回原路径, 直接报错并提示, 防止还原错位
$flattened = @(Get-ChildItem $stampDir -File -Force -ErrorAction SilentlyContinue |
               Where-Object { $_.Name -match '^BattleTech_Data_' -or $_.Name -match '^Mods_' })
if ($flattened.Count -gt 0) {
    Write-Host ""
    Write-Host (" 该备份是旧格式（文件名 = 下划线压扁的路径）: backup\" + $stamp) -ForegroundColor Yellow
    Write-Host " 旧格式无法确定原路径，不能自动还原。请手动对照恢复。" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

Say "================================================"
Say " BATTLETECH / RogueTech 简体中文补丁 还原"
Say "================================================"
Say (" 游戏目录: " + $gameRoot)
Say (" 还原自备份: backup\" + $stamp)
Say ""
Say " 将用该备份覆盖游戏目录下对应的文件。"
Say " 汉化之后的改动不会被自动清除，如需彻底还原请先用"
Say " Steam 的\"验证游戏文件完整性\"或重新解压 RogueTech。"
Say ""

# ---------- 执行还原: 按备份内相对路径覆盖回游戏目录 ----------
# 备份结构: backup\<时间戳>\<相对游戏根的路径> (zhbak 除外, 它不属于覆盖范围)
$files = Get-ChildItem $stampDir -Recurse -File -Force |
         Where-Object { $_.FullName -notmatch '\\zhbak\\' }
if ($files.Count -eq 0) {
    Warn "该备份内没有可还原的文件。"
    exit 1
}
$cnt = 0
foreach ($f in $files) {
    $rel = $f.FullName.Substring($stampDir.Length).TrimStart('\')
    $dst = Join-Path $gameRoot $rel
    $dir = Split-Path $dst -Parent
    if (-not [IO.Directory]::Exists($dir)) { [void][IO.Directory]::CreateDirectory($dir) }
    [IO.File]::Copy($f.FullName, $dst, $true)
    $cnt++
}
Ok ("已还原 " + $cnt + " 个文件")

Say ""
Say "================================================"
Say " 还原完成。重新启动游戏即可生效。"
Say "================================================"
