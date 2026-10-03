param(
    [string]$gameRoot = ""
)
$ErrorActionPreference = 'Stop'
$CTL = [char]31
$CTLstr = [string][char]31
$enc = New-Object Text.UTF8Encoding $false

if ([string]::IsNullOrWhiteSpace($gameRoot)) {
    $gameRoot = & (Join-Path $PSScriptRoot 'find-game.ps1')
    if ([string]::IsNullOrWhiteSpace($gameRoot)) {
        Write-Host " 找不到游戏目录, 请用 -gameRoot 指定。" -ForegroundColor Yellow
        exit 1
    }
}

# U+001F 是误写的分隔符, 原意是全角逗号
#
# 性能: 原先分两趟扫全树、且用 ToCharArray() 逐字符数控制字符, 25k 文件要走
# 167 秒。这里合并成一趟(每个文件只读一次), 计数与扫描都交给 .NET 正则,
# 实测降到 10 秒以内。
$gameTargets = @()
$gameTargets += Get-ChildItem (Join-Path $gameRoot 'Mods') -Recurse -File -Filter '*.json' -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -notlike '*\.modtek\*' -and $_.Name -notlike '*.zhbak*' }
$gameTargets += Get-Item (Join-Path $gameRoot 'BattleTech_Data\StreamingAssets\data\localization\strings_zh-CN.csv')

$otherRx = New-Object System.Text.RegularExpressions.Regex ('[\x00-\x08\x0B\x0C\x0E-\x1F]')
$total2 = 0; $files2 = 0
$other = @{}
foreach ($f in $gameTargets) {
    $t = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)

    if ($t.IndexOf($CTL) -ge 0) {
        # 单字符替换的计数用长度差, 比逐字符循环快两个数量级
        $total2 += $t.Length - $t.Replace($CTLstr, '').Length
        $files2++
        $t = $t.Replace($CTLstr, '，')
        [IO.File]::WriteAllText($f.FullName, $t, $enc)
    }

    # 复查其它异常控制字符(基于修复后的内容, 与原两趟语义一致)
    foreach ($m in $otherRx.Matches($t)) {
        $k = 'U+' + ([int]$m.Value[0]).ToString('X4')
        if (-not $other.ContainsKey($k)) { $other[$k] = 0 }
        $other[$k]++
    }
}

Write-Host '=== 修复游戏内数据 ==='
Write-Host ("  修复文件 " + $files2 + " 个，替换 " + $total2 + " 处")
Write-Host ''
Write-Host '=== 3) 复查其它异常控制字符 ==='
if ($other.Count -eq 0) { Write-Host '  无其它异常控制字符' }
foreach ($k in $other.Keys) { Write-Host ("  " + $k + " : " + $other[$k]) }