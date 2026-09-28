param(
    [string]$gameRoot = ""
)
$ErrorActionPreference='Stop'
$enc = New-Object Text.UTF8Encoding $false
if ([string]::IsNullOrWhiteSpace($gameRoot)) {
    $gameRoot = & (Join-Path $PSScriptRoot 'find-game.ps1')
    if ([string]::IsNullOrWhiteSpace($gameRoot)) {
        Write-Host " 找不到游戏目录, 请用 -gameRoot 指定。" -ForegroundColor Yellow
        exit 1
    }
}
$game=$gameRoot
$CTL=[char]31

# 说明: JSON 侧的标点空格与术语统一由 apply-norm.ps1 负责(它一次遍历即完成
#       全部字段的规范化)。本脚本只处理 CSV 与可疑字符排查, 避免重复遍历
#       25,000 个 JSON 造成安装耗时过长。
#
# 保护策略: 先把受保护区(占位符/HTML/转义)整体替换为哨兵字符, 做完整串 Replace,
#           再把哨兵还原。这样只走两次正则扫描 + 几次 O(n) 字符串替换,
#           比"逐个匹配分段再拼接"快一个数量级(CSV 有数万个占位符, 分段法会卡住)。
$guardRx = [regex]'(<[^>]*>|\[\[.*?\]\]|\{[^{}]*\}|\\r|\\n|\\t)'
$SENT = [char]0xE000   # 私用区哨兵, 正文不会出现

function Fix-Spaces([string]$t) {
    if ($t -notmatch '[\u4e00-\u9fff]') { return $t }
    if ($t.IndexOf(" ，") -lt 0 -and $t.IndexOf("， ") -lt 0 -and $t.IndexOf(" 。") -lt 0) { return $t }
    # 1) 占位符等 -> 哨兵, 同时记录原文
    $saved = New-Object 'System.Collections.Generic.List[string]'
    $marks = [regex]::Replace($t, $guardRx, {
        param($m)
        $saved.Add($m.Value)
        return $SENT.ToString()
    }.GetNewClosure())
    # 2) 标点空格规范化(此时串内已无占位符, 可安全整串替换)
    $marks = $marks.Replace(" ， ", '，').Replace("， ", '，').Replace(" ，", '，').Replace(" 。", '。')
    # 3) 还原哨兵(按哨兵切分后依次插回原文, 避免逐字符循环)
    if ($saved.Count -eq 0) { return $marks }
    $segs = $marks.Split($SENT)
    $out = New-Object System.Text.StringBuilder
    for ($k = 0; $k -lt $segs.Count; $k++) {
        [void]$out.Append($segs[$k])
        if ($k -lt $saved.Count) { [void]$out.Append($saved[$k]) }
    }
    return $out.ToString()
}

Write-Host '=== A) 清理翻译总表的标点多余空格(占位符受保护) ==='
$csv = Join-Path $game 'BattleTech_Data\StreamingAssets\data\localization\strings_zh-CN.csv'
$nf = 0
if (Test-Path $csv) {
    $t = [IO.File]::ReadAllText($csv, [Text.Encoding]::UTF8)
    $new = Fix-Spaces $t
    if ($new -ne $t) { [IO.File]::WriteAllText($csv, $new, $enc); $nf = 1 }
}
Write-Host ("  清理文件数: " + $nf)

Write-Host ''
Write-Host '=== B) 排查控制字符 ==='
# 用正则一次性匹配可疑码位, 比逐字符循环快得多
$suspectRx = [regex]'[\u0000-\u0008\u000B\u000C\u000E-\u001F\uE000-\uF8FF\uFFFD]'
$suspect = @{}
if (Test-Path $csv) {
    $t = [IO.File]::ReadAllText($csv, [Text.Encoding]::UTF8)
    foreach ($m in $suspectRx.Matches($t)) {
        $k = "U+{0:X4}" -f [int][char]$m.Value
        if (-not $suspect.ContainsKey($k)) { $suspect[$k]=0 }
        $suspect[$k]++
    }
}
if ($suspect.Count -eq 0) { Write-Host '  翻译总表未发现控制字符/私用区/替换字符' }
foreach ($k in $suspect.Keys) { Write-Host ("  " + $k + " : " + $suspect[$k]) }
Write-Host '  (JSON 侧同类检查由 apply-norm.ps1 与 qa-check.ps1 覆盖)'
