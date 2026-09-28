# 探测 BATTLETECH 安装目录 —— 输出目录路径, 找不到则输出空串。
# 查找顺序:
#   1) RogueTech / RogueLauncher 的配置文件 (installTarget / BattleTechExe)
#   2) Steam 注册表登记的库目录
#   3) Steam 默认安装位置
#   4) 常见手动安装位置
# 不依赖任何固定盘符。

function Test-GameRoot([string]$p) {
    if ([string]::IsNullOrWhiteSpace($p)) { return $false }
    return [IO.File]::Exists((Join-Path $p 'BattleTech.exe'))
}

$found = ""

# ---- 1) RogueTech 启动器配置 ----
# 配置文件可能出现在: 启动器安装目录、用户目录、游戏目录
$cfgCandidates = New-Object System.Collections.ArrayList
foreach ($base in @($env:USERPROFILE, $env:LOCALAPPDATA, $(if ($PSScriptRoot) { Split-Path $PSScriptRoot -Parent } else { '' }))) {
    if ([string]::IsNullOrWhiteSpace($base)) { continue }
    [void]$cfgCandidates.Add((Join-Path $base 'RtLauncherSettings.xml'))
    [void]$cfgCandidates.Add((Join-Path $base 'RogueTech\RtLauncherSettings.xml'))
    [void]$cfgCandidates.Add((Join-Path $base 'RT\RtLauncherSettings.xml'))
}
# 也搜一下根目录常见位置 (C:\RT 等), 但不假设盘符
foreach ($drive in [IO.DriveInfo]::GetDrives()) {
    if ($drive.DriveType -ne 'Fixed') { continue }
    $r = $drive.RootDirectory.FullName
    [void]$cfgCandidates.Add((Join-Path $r 'RT\RtLauncherSettings.xml'))
    [void]$cfgCandidates.Add((Join-Path $r 'RogueTech\RtLauncherSettings.xml'))
}
foreach ($cfg in $cfgCandidates) {
    if (-not [IO.File]::Exists($cfg)) { continue }
    try {
        $xml = [IO.File]::ReadAllText($cfg, [Text.Encoding]::UTF8)
        $m = [regex]::Match($xml, '<BattleTechExe>\s*([^<]+?)\s*</BattleTechExe>')
        if ($m.Success) {
            $p = $m.Groups[1].Value.Trim()
            $d = Split-Path $p -Parent
            if (Test-GameRoot $d) { $found = $d; break }
        }
        $m2 = [regex]::Match($xml, '<installTarget>\s*([^<]+?)\s*</installTarget>')
        if ($m2.Success) {
            $p2 = $m2.Groups[1].Value.Trim()
            $d2 = Split-Path $p2 -Parent       # installTarget 指向 <游戏>\Mods
            if (Test-GameRoot $d2) { $found = $d2; break }
        }
    } catch { }
}
if ($found) { $found; return }

# ---- 2) Steam 注册表 -> 库目录 -> common\BATTLETECH ----
$steamPaths = New-Object System.Collections.ArrayList
foreach ($k in @('HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam')) {
    try {
        $v = Get-ItemProperty -Path $k -ErrorAction SilentlyContinue
        if ($v) {
            if ($v.SteamPath) { [void]$steamPaths.Add($v.SteamPath) }
            if ($v.InstallPath) { [void]$steamPaths.Add($v.InstallPath) }
        }
    } catch { }
}
foreach ($sp in $steamPaths) {
    foreach ($rel in @('steamapps\common\BATTLETECH', 'SteamApps\common\BATTLETECH')) {
        $d = Join-Path $sp $rel
        if (Test-GameRoot $d) { $found = $d; break }
    }
    if ($found) { break }
    # 额外库: steamapps\libraryfolders.vdf
    $lf = Join-Path $sp 'steamapps\libraryfolders.vdf'
    if ([IO.File]::Exists($lf)) {
        try {
            $vdf = [IO.File]::ReadAllText($lf, [Text.Encoding]::UTF8)
            foreach ($mm in [regex]::Matches($vdf, '"path"\s*"([^"]+)"')) {
                $lib = $mm.Groups[1].Value -replace '\\\\', '\'
                $d = Join-Path $lib 'steamapps\common\BATTLETECH'
                if (Test-GameRoot $d) { $found = $d; break }
            }
        } catch { }
    }
    if ($found) { break }
}
if ($found) { $found; return }

# ---- 3) 常见位置 (所有固定盘符下逐个试) ----
$subs = @(
    'Program Files (x86)\Steam\steamapps\common\BATTLETECH',
    'Program Files\Steam\steamapps\common\BATTLETECH',
    'Steam\steamapps\common\BATTLETECH',
    'SteamLibrary\steamapps\common\BATTLETECH',
    'Games\Steam\steamapps\common\BATTLETECH',
    'Games\steamapps\common\BATTLETECH',
    'steamapps\common\BATTLETECH',
    'BATTLETECH',
    'Games\BATTLETECH'
)
foreach ($drive in [IO.DriveInfo]::GetDrives()) {
    if ($drive.DriveType -ne 'Fixed') { continue }
    $root = $drive.RootDirectory.FullName
    foreach ($s in $subs) {
        $d = Join-Path $root $s
        if (Test-GameRoot $d) { $found = $d; break }
    }
    if ($found) { break }
}

$found
