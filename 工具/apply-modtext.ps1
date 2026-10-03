param(
    [string]$mods = "",
    [string]$pairs = "",
    [string]$backupRoot = "",
    [switch]$DryRun
)
<#
  汉化各模组的 mod_localized_text.json

  这类文件是 HBS 引擎支持的"模组本地化覆盖表"：游戏先按英文原文查
  strings_zh-CN.csv 的挤兑键(squash key), 查不到就退回文件里的英文原值。
  所以只要把值就地改成中文(或补上 CSV 缺的键), 界面就会显示中文。
  先例: CodeWords 的 mod_localized_text.json 已是全员中文且工作正常。

  对照表格式: 英文原值 <TAB> 中文译文 (值级精确匹配, 不做字段名匹配)
  数组项(如战斗台词)同样处理: 逐行扫描 "..." 独占一行的条目。
  保护: 已含中文的跳过; JSON 校验失败则跳过; 改前备份。
#>
$ErrorActionPreference = 'Stop'
$BS = [string][char]92
$packRoot = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($mods)) {
    $gr = & (Join-Path $PSScriptRoot 'find-game.ps1')
    if ([string]::IsNullOrWhiteSpace($gr)) { Write-Host " 找不到游戏目录" -ForegroundColor Yellow; exit 1 }
    $mods = Join-Path $gr 'Mods'
}
if ([string]::IsNullOrWhiteSpace($pairs)) { $pairs = Join-Path $PSScriptRoot 'dict-modtext.tsv' }
if ([string]::IsNullOrWhiteSpace($backupRoot)) { $backupRoot = Join-Path $packRoot 'backup\Mods-modtext' }
if (-not [IO.File]::Exists($pairs)) { Write-Host (" 找不到对照表: " + $pairs) -ForegroundColor Yellow; exit 1 }

$map = New-Object 'System.Collections.Generic.Dictionary[string,string]'
$sr = New-Object IO.StreamReader($pairs, [Text.Encoding]::UTF8)
while (-not $sr.EndOfStream) {
    $l = $sr.ReadLine()
    if ([string]::IsNullOrWhiteSpace($l)) { continue }
    $i = $l.IndexOf("`t"); if ($i -lt 1) { continue }
    $k = $l.Substring(0, $i); $v = $l.Substring($i + 1)
    # 字典里的多行文本写作字面 \n(便于人工维护), 但文件里的值是 JSON
    # 转义形式, 反转义后比对用的键必须是真实换行 —— 因此把字面形式与
    # 反转义形式都登记为键(两者指向同一译文)。
    if (-not $map.ContainsKey($k)) { $map[$k] = $v }
    $ku = $k.Replace('\n', "`n").Replace('\r', "`r").Replace('\t', "`t")
    if ($ku -ne $k -and -not $map.ContainsKey($ku)) { $map[$ku] = $v }
}
$sr.Close()
Write-Host ("对照表: " + $map.Count + " 条(含多行键展开)")

function Unesc([string]$s) {
    $sb = New-Object Text.StringBuilder
    $i = 0
    while ($i -lt $s.Length) {
        $c = $s[$i]
        if ($c -eq $BS -and ($i + 1) -lt $s.Length) {
            $n = $s[$i + 1]
            if ($n -eq 'n') { [void]$sb.Append("`n"); $i += 2; continue }
            if ($n -eq 'r') { [void]$sb.Append("`r"); $i += 2; continue }
            if ($n -eq 't') { [void]$sb.Append("`t"); $i += 2; continue }
            if ($n -eq '"') { [void]$sb.Append('"'); $i += 2; continue }
            if ($n -eq $BS) { [void]$sb.Append($BS); $i += 2; continue }
            if ($n -eq '/') { [void]$sb.Append('/'); $i += 2; continue }
        }
        [void]$sb.Append($c); $i++
    }
    return $sb.ToString()
}
function Esc([string]$s) {
    return $s.Replace($BS, $BS + $BS).Replace('"', $BS + '"').Replace("`r", $BS + 'r').Replace("`n", $BS + 'n').Replace("`t", $BS + 't')
}

$enc = New-Object Text.UTF8Encoding $false
$stats = @{ files = 0; changed = 0; repl = 0 }
$script:map = $map
$script:stats = $stats
$script:BS = $BS

$rxPair = New-Object System.Text.RegularExpressions.Regex ('("(?:[A-Za-z_][A-Za-z0-9_]*)"\s*:\s*")((?:[^"' + $BS + $BS + ']|' + $BS + $BS + '.)*)(")')

$files = Get-ChildItem $mods -Recurse -File -Filter 'mod_localized_text.json' | Where-Object {
    ($_.FullName -notlike ('*' + $BS + '.modtek' + $BS + '*')) -and ($_.FullName -notlike '*ModSaves*')
}
Write-Host ("目标文件: " + $files.Count)

foreach ($f in $files) {
    $stats.files++
    $orig = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
    $lines = [IO.File]::ReadAllLines($f.FullName, [Text.Encoding]::UTF8)
    $hit = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $ln = $lines[$i]
        # key: value 形式(值可能跨行, 这里逐行; 多行值由下面的整块正则兜底)
        $m = $rxPair.Match($ln)
        if ($m.Success) {
            $val = Unesc $m.Groups[2].Value
            if ($val -notmatch '[\u4e00-\u9fff]' -and $script:map.ContainsKey($val)) {
                # 译文里的 \n 已是 JSON 转义写法(与英文原文一致), 不能交给
                # Esc 再次转义, 否则会变成 \\n 而在游戏里显示成字面反斜杠n
                $zh = $script:map[$val]
                $zh = $zh.Replace('"', $BS + '"')
                $lines[$i] = $m.Groups[1].Value + $zh + $m.Groups[3].Value + $ln.Substring($m.Index + $m.Length)
                $hit++
                continue
            }
        }
        # 数组项: 值独占一行
        $t2 = $ln.Trim()
        if ($t2.Length -lt 3 -or $t2[0] -ne '"') { continue }
        if ($t2 -match '"\s*:\s*"') { continue }
        $end = $t2.LastIndexOf('"')
        if ($end -le 0) { continue }
        $rest = $t2.Substring($end + 1).Trim().TrimEnd(',')
        if ($rest.Length -gt 0) { continue }
        $raw = $t2.Substring(1, $end - 1)
        if ($raw -match '^[A-Za-z_]+$' -and $raw -cmatch '^[A-Z_]+$') { continue }
        $val = Unesc $raw
        if ($val -match '[\u4e00-\u9fff]') { continue }
        if (-not $script:map.ContainsKey($val)) { continue }
        $indent = $ln.Substring(0, $ln.Length - $ln.TrimStart().Length)
        $tail = $ln.Substring($ln.LastIndexOf('"') + 1)
        $lines[$i] = $indent + '"' + ($script:map[$val].Replace('"', $BS + '"')) + '"' + $tail
        $hit++
    }
    if ($hit -eq 0) { continue }
    $new = ($lines -join "`r`n") + "`r`n"
    if ($new -eq $orig) { continue }
    if (-not $DryRun) {
        # MonsterMashup/SizeMatters/SkillBasedInit 三个文件带尾逗号, 游戏
        # 自带的解析器容忍, .NET 严格解析器不容忍。校验前先去掉尾逗号,
        # 只验证"我们改写的内容"没有破坏结构。
        $probe = [regex]::Replace($new, ',(\s*[}\]])', '$1')
        Add-Type -AssemblyName System.Web.Extensions
        $ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
        $ser.MaxJsonLength = [int]::MaxValue
        try { [void]$ser.DeserializeObject($probe) } catch { Write-Host (" 跳过(JSON 无效): " + $f.Name + " @ " + (Split-Path $f.DirectoryName -Leaf)); continue }
        $rel = $f.FullName.Substring($mods.Length).TrimStart($BS)
        $bak = Join-Path $backupRoot $rel
        $d = Split-Path $bak -Parent
        if (-not [IO.Directory]::Exists($d)) { [void][IO.Directory]::CreateDirectory($d) }
        if (-not [IO.File]::Exists($bak)) { [IO.File]::WriteAllText($bak, $orig, $enc) }
        [IO.File]::WriteAllText($f.FullName, $new, $enc)
    }
    $stats.repl += $hit
    $stats.changed++
}
Write-Host ("files=" + $stats.files + " changed=" + $stats.changed + " repl=" + $stats.repl)
