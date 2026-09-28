param(
    [string]$gameRoot = ""
)
$ErrorActionPreference = 'Stop'
$CTL = [char]31
$enc = New-Object Text.UTF8Encoding $false
$report = New-Object 'System.Collections.Generic.List[string]'

if ([string]::IsNullOrWhiteSpace($gameRoot)) {
    $gameRoot = & (Join-Path $PSScriptRoot 'find-game.ps1')
    if ([string]::IsNullOrWhiteSpace($gameRoot)) {
        Write-Host " 找不到游戏目录, 请用 -gameRoot 指定。" -ForegroundColor Yellow
        exit 1
    }
}

function Fix-File([string]$path, [switch]$DryRun) {
    $t = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
    if ($t.IndexOf($CTL) -lt 0) { return 0 }
    $n = 0
    foreach ($c in $t.ToCharArray()) { if ($c -eq $CTL) { $n++ } }
    if (-not $DryRun) {
        # U+001F 是误写的分隔符, 原意是全角逗号
        $new = $t.Replace($CTL, '，')
        [IO.File]::WriteAllText($path, $new, $enc)
    }
    return $n
}

# 修复游戏内已写入的数据
Write-Host '=== 修复游戏内数据 ==='
$game = $gameRoot
$gameTargets = @()
$gameTargets += Get-ChildItem (Join-Path $game 'Mods') -Recurse -File -Filter '*.json' -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -notlike '*\.modtek\*' -and $_.Name -notlike '*.zhbak*' }
$gameTargets += Get-Item (Join-Path $game 'BattleTech_Data\StreamingAssets\data\localization\strings_zh-CN.csv')
$total2 = 0; $files2 = 0
foreach ($f in $gameTargets) {
    $n = Fix-File $f.FullName
    if ($n -gt 0) { $files2++; $total2 += $n }
}
Write-Host ("  修复文件 " + $files2 + " 个，替换 " + $total2 + " 处")

# 3) 扫其余控制字符
Write-Host ''
Write-Host '=== 3) 复查其它异常控制字符 ==='
$other = @{}
foreach ($f in $gameTargets) {
    $t = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
    foreach ($c in $t.ToCharArray()) {
        $cp = [int]$c
        if ($cp -lt 32 -and $cp -ne 9 -and $cp -ne 10 -and $cp -ne 13) {
            $k = "U+{0:X4}" -f $cp
            if (-not $other.ContainsKey($k)) { $other[$k] = 0 }
            $other[$k]++
        }
    }
}
if ($other.Count -eq 0) { Write-Host '  无其它异常控制字符' }
foreach ($k in $other.Keys) { Write-Host ("  " + $k + " : " + $other[$k]) }
