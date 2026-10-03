param(
    [string]$gameRoot = ""
)
$ErrorActionPreference = 'Stop'
$FS = [string][char]31        # 0x1F 单元分隔符 —— 游戏 [[对象<0x1F>字段]] 语法的正确分隔符
$enc = New-Object Text.UTF8Encoding $false

if ([string]::IsNullOrWhiteSpace($gameRoot)) {
    $gameRoot = & (Join-Path $PSScriptRoot 'find-game.ps1')
    if ([string]::IsNullOrWhiteSpace($gameRoot)) {
        Write-Host " 找不到游戏目录, 请用 -gameRoot 指定。" -ForegroundColor Yellow
        exit 1
    }
}

# ============================================================================
# 插值占位符分隔符修复
#
# 游戏语法: [[对象<0x1F>{对象.字段}]] 与 [[前缀[目标]<0x1F>显示名]]
#   - 0x1F (ASCII 31) 是必须的分隔符
#   - 依据: 英文原版 CSV / 德文 CSV / 月光石头中文表 该位置都是 20 1F 20
#   - 缺分隔符或误用全角逗号 -> 游戏解析失败 -> 界面显示 "错误" 兜底
#
# 历史教训: 早期版本误以为 0x1F 是"误写", 把它替换成全角逗号(，),
# 导致大量界面回退 error。本版纠正为: 把错误的逗号/裸空格形态恢复成 0x1F。
# ============================================================================
$SP = [string][char]32
$FW = [string][char]0xFF0C   # 全角逗号

# 形态 1: [[OBJ ， {...}]] 或 [[OBJ , {...}]]  ->  [[OBJ 0x1F {...}]]
$rx1 = New-Object System.Text.RegularExpressions.Regex ('(\[\[[A-Za-z_][A-Za-z0-9_.]*)\s*[，,]\s*(\{[^}]+\}\])')
# 形态 2: [[前缀[目标] ， 显示]]  ->  [[前缀[目标] 0x1F 显示]]
$rx2 = New-Object System.Text.RegularExpressions.Regex ('(\[\[[A-Za-z_][A-Za-z0-9_.]*\[[^\]]+\])\s*[，,]\s*([^\r\n\]])')
# 形态 3: [[OBJ{...}]] 无分隔  ->  [[OBJ 0x1F {...}]]
$rx3 = New-Object System.Text.RegularExpressions.Regex ('(\[\[[A-Za-z_][A-Za-z0-9_.]*)(\{[^}]+\}\])')
# 形态 4: [[前缀[目标] 显示]] 仅空格无0x1F -> 补 0x1F
$rx4 = New-Object System.Text.RegularExpressions.Regex ('(\[\[DM\.[^\[\r\n]+\[[^\]]+\])' + $SP + '(?=[^' + $FS + '\r\n\[])')

$targets = New-Object System.Collections.ArrayList
foreach ($f in (Get-ChildItem (Join-Path $gameRoot 'Mods') -Recurse -File -Filter '*.json' -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -notlike '*\.modtek\*' -and $_.Name -notlike '*.zhbak*' })) {
    [void]$targets.Add($f.FullName)
}
[void]$targets.Add((Join-Path $gameRoot 'BattleTech_Data\StreamingAssets\data\localization\strings_zh-CN.csv'))

$stat = @{ files = 0; n1 = 0; n2 = 0; n3 = 0; n4 = 0 }
foreach ($path in $targets) {
    if (-not [IO.File]::Exists($path)) { continue }
    $t = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
    if ($t.IndexOf('[[') -lt 0) { continue }
    $stat.files++
    $orig = $t
    $c1 = $rx1.Matches($t).Count
    if ($c1 -gt 0) { $t = $rx1.Replace($t, ('$1' + $SP + $FS + $SP + '$2')) }
    $c2 = $rx2.Matches($t).Count
    if ($c2 -gt 0) { $t = $rx2.Replace($t, ('$1' + $SP + $FS + $SP + '$2')) }
    $c3 = $rx3.Matches($t).Count
    if ($c3 -gt 0) { $t = $rx3.Replace($t, ('$1' + $SP + $FS + $SP + '$2')) }
    $c4 = $rx4.Matches($t).Count
    if ($c4 -gt 0) { $t = $rx4.Replace($t, ('$1' + $SP + $FS + $SP)) }
    if ($t -ne $orig) {
        [IO.File]::WriteAllText($path, $t, $enc)
        $stat.n1 += $c1; $stat.n2 += $c2; $stat.n3 += $c3; $stat.n4 += $c4
    }
}

Write-Host '=== 插值占位符分隔符修复 ==='
Write-Host ("  扫描文件 " + $stat.files + " 个")
Write-Host ("  全角/半角逗号 -> 0x1F : " + $stat.n1 + " 处")
Write-Host ("  目标段逗号     -> 0x1F : " + $stat.n2 + " 处")
Write-Host ("  无分隔补 0x1F         : " + $stat.n3 + " 处")
Write-Host ("  裸空格补 0x1F         : " + $stat.n4 + " 处")

# 复核: CSV 中 [[...]] 内是否还有逗号形态残留
$csv = Join-Path $gameRoot 'BattleTech_Data\StreamingAssets\data\localization\strings_zh-CN.csv'
if ([IO.File]::Exists($csv)) {
    $ct = [IO.File]::ReadAllText($csv, [Text.Encoding]::UTF8)
    $leftBad = ([regex]::Matches($ct, '\[\[[A-Za-z_][A-Za-z0-9_.]*[，,]\s*\{')).Count
    $leftNoSep = ([regex]::Matches($ct, '\[\[[A-Za-z_][A-Za-z0-9_.]*\{\{?')).Count
    $hasFs = ([regex]::Matches($ct, '\x1f')).Count
    Write-Host '=== 复核(翻译总表) ==='
    Write-Host ("  逗号形态残留: " + $leftBad)
    Write-Host ("  无分隔残留  : " + $leftNoSep)
    Write-Host ("  0x1F 总数   : " + $hasFs)
}
