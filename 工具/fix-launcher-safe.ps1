param(
    [string]$backupRoot = "",
    [switch]$DryRun
)
<#
  把 RogueTech 启动器配置里的 <SafeLaunchDisabled> 置为 true

  为什么需要:
    RogueLauncher 在启动游戏前会做哈希校验 (bkprocessor._hashCheck)。它把
    被汉化改过的文件判为 "file tamper detected ... re-writing source",
    用缓存里的英文原版覆盖回 <游戏>\Mods。日志实测一次启动有 7400+ 条
    tamper 记录, 汉化因此大面积失效。
    把 SafeLaunchDisabled 设为 true 后, 启动器打印
    "Safety Checks Disabled!!!!" 并跳过该覆盖逻辑。

  说明:
    · 只改这一个标签, 其余配置原样保留
    · 改前备份到 backup\<时间戳>\launcher\
    · 配置文件不存在 / 无写权限时只警告, 不中断安装

  搜索顺序:
    1) 环境变量/常见目录下的 RtLauncherSettings.xml
    2) 各固定盘符根目录的 RT / RogueTech 目录
    3) 汉化包所在盘
    4) 递归找 RogueLauncher.exe 所在目录 (浅层)
#>
$ErrorActionPreference = 'Stop'
$BS = [string][char]92

function Ok($m)   { Write-Host ("      " + $m) }
function Warn($m) { Write-Host ("      警告: " + $m) -ForegroundColor Yellow }

$packRoot = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($backupRoot)) { $backupRoot = Join-Path $packRoot "backup" }

# ---------- 定位配置文件 ----------
$cands = New-Object System.Collections.ArrayList
foreach ($base in @($env:USERPROFILE, $env:LOCALAPPDATA, $env:APPDATA, $packRoot, (Split-Path $packRoot -Parent))) {
    if ([string]::IsNullOrWhiteSpace($base)) { continue }
    foreach ($sub in @('', 'RT', 'RogueTech')) {
        $p = if ($sub -eq '') { Join-Path $base 'RtLauncherSettings.xml' } else { Join-Path $base ($sub + "\RtLauncherSettings.xml") }
        [void]$cands.Add($p)
    }
}
foreach ($drive in [IO.DriveInfo]::GetDrives()) {
    if ($drive.DriveType -ne 'Fixed') { continue }
    $r = $drive.RootDirectory.FullName
    foreach ($sub in @('RT', 'RogueTech', 'Games\RT', 'Games\RogueTech')) {
        [void]$cands.Add((Join-Path $r ($sub + "\RtLauncherSettings.xml")))
    }
}
# 找 RogueLauncher.exe 所在目录(限制深度, 避免全盘扫描)
foreach ($drive in [IO.DriveInfo]::GetDrives()) {
    if ($drive.DriveType -ne 'Fixed') { continue }
    $r = $drive.RootDirectory.FullName
    foreach ($sub in @('RT', 'RogueTech', 'Games', 'Games\RT', 'Games\RogueTech')) {
        $d = Join-Path $r $sub
        if (-not [IO.Directory]::Exists($d)) { continue }
        $exe = Join-Path $d 'RogueLauncher.exe'
        if ([IO.File]::Exists($exe)) { [void]$cands.Add((Join-Path $d 'RtLauncherSettings.xml')) }
    }
}

$cfg = ""
foreach ($c in $cands) {
    if ([IO.File]::Exists($c)) { $cfg = $c; break }
}
if ($cfg -eq "") {
    Warn "未找到 RtLauncherSettings.xml（可能未安装 RogueTech 启动器），已跳过"
    exit 0
}

# ---------- 读取与判断 ----------
$text = [IO.File]::ReadAllText($cfg, [Text.Encoding]::UTF8)
$rx = [regex]'<SafeLaunchDisabled>\s*(true|false)\s*</SafeLaunchDisabled>'
$m = $rx.Match($text)
if (-not $m.Success) {
    Warn ("配置里没有 SafeLaunchDisabled 标签，已跳过: " + $cfg)
    exit 0
}
$cur = $m.Groups[1].Value
if ($cur -eq 'true') {
    Ok "启动器安全检查已禁用（SafeLaunchDisabled=true）"
    exit 0
}

Write-Host ("      检测到启动器安全检查处于开启状态（会覆盖汉化）")
Write-Host ("        " + $cfg)

# ---------- 备份并改写 ----------
$stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$bakDir = Join-Path $backupRoot ($stamp + "\launcher")
if (-not $DryRun) {
    if (-not [IO.Directory]::Exists($bakDir)) { [void][IO.Directory]::CreateDirectory($bakDir) }
    [IO.File]::Copy($cfg, (Join-Path $bakDir 'RtLauncherSettings.xml'), $true)
}
$new = $rx.Replace($text, '<SafeLaunchDisabled>true</SafeLaunchDisabled>', 1)
if ($DryRun) {
    Ok "[DryRun] 将把 SafeLaunchDisabled 改为 true"
    exit 0
}
try {
    [IO.File]::WriteAllText($cfg, $new, (New-Object Text.UTF8Encoding $false))
    Ok "已禁用启动器安全检查（SafeLaunchDisabled=true），汉化不会被覆盖"
} catch {
    Warn ("写入失败（可能无权限，或启动器正在运行）: " + $_.Exception.Message)
    Warn ("请手动把 " + $cfg + " 中的 SafeLaunchDisabled 改为 true")
    exit 0
}
