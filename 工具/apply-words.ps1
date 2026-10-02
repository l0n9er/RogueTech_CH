# 直接把 JSON 里 dialogueContent[].words 的英文替换为中文
#
# 背景: 游戏对 words(对话字幕) 不查 CSV, 也不支持 [[...]] 插值查表,
#       而是直接显示 JSON 里的字符串。月光石头的本地化表(CULTURE_ZH_CN)
#       虽有译文, 但对应的源文件从未被改写成 __/Name/__ 占位符,
#       所以译文用不上。这里直接在源文件上替换。
#
# 保护: HTML 标签、{占位符}、\\\\n 转义序列原样保留
param(
    [string]$mods = "",
    [string]$pairs = "",
    [string]$backupRoot = "",
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$BS = [string][char]92
$packRoot = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($mods)) {
    $gr = & (Join-Path $PSScriptRoot 'find-game.ps1')
    if ([string]::IsNullOrWhiteSpace($gr)) { Write-Host " 找不到游戏目录" -ForegroundColor Yellow; exit 1 }
    $mods = Join-Path $gr 'Mods'
}
if ([string]::IsNullOrWhiteSpace($pairs)) { $pairs = Join-Path $PSScriptRoot 'dict-words.tsv' }
if ([string]::IsNullOrWhiteSpace($backupRoot)) { $backupRoot = Join-Path $packRoot 'backup\Mods-words' }
if (-not [IO.File]::Exists($pairs)) { Write-Host (" 找不到对照表: " + $pairs) -ForegroundColor Yellow; exit 1 }

# ---- 读对照表 ----
$map = New-Object 'System.Collections.Generic.Dictionary[string,string]'
$sr = New-Object IO.StreamReader($pairs, [Text.Encoding]::UTF8)
while (-not $sr.EndOfStream) {
    $l = $sr.ReadLine()
    if ([string]::IsNullOrWhiteSpace($l)) { continue }
    $i = $l.IndexOf("`t"); if ($i -lt 1) { continue }
    $k = $l.Substring(0, $i)
    $v = $l.Substring($i + 1)
    if (-not $map.ContainsKey($k)) { $map[$k] = $v }
}
$sr.Close()
Write-Host ("对照表: " + $map.Count + " 条")

$enc = New-Object Text.UTF8Encoding $false
$stats = @{ files = 0; changed = 0; repl = 0 }
$script:map = $map
$script:stats = $stats

# 匹配 "words": "..."  (处理转义)
$rx = [regex]('"words"\s*:\s*"((?:[^"' + $BS + $BS + ']|' + $BS + $BS + '.)*)"')

function Unesc([string]$s) {
    $t = $s.Replace($BS + '/', '/').Replace($BS + '"', '"').Replace($BS + $BS, $BS)
    return $t
}

$excl = @($BS + '.modtek' + $BS, 'ModSaves')
$files = Get-ChildItem $mods -Recurse -File -Filter '*.json' | Where-Object {
    $p = $_.FullName; $bad = $false
    foreach ($e in $excl) { if ($p -like ('*' + $e + '*')) { $bad = $true } }
    if ($_.Name -in @('mod.json', 'modstate.json')) { $bad = $true }
    -not $bad
}

foreach ($f in $files) {
    $stats.files++
    $orig = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
    if ($orig -notmatch '"words"') { continue }
    $new = $rx.Replace($orig, {
        param($m)
        $val = Unesc $m.Groups[1].Value
        if ($val -match '[\u4e00-\u9fff]') { return $m.Value }   # 已译
        if (-not $script:map.ContainsKey($val)) { return $m.Value }
        $zh = $script:map[$val]
        $script:stats.repl++
        # 重新转义
        $e = $zh.Replace($BS, $BS + $BS).Replace('"', $BS + '"')
        $e = $e.Replace("`n", $BS + 'n').Replace("`r", $BS + 'r').Replace("`t", $BS + 't')
        return '"words": "' + $e + '"'
    })
    if ($new -eq $orig) { continue }
    if (-not $DryRun) {
        Add-Type -AssemblyName System.Web.Extensions
        $ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
        $ser.MaxJsonLength = [int]::MaxValue
        try { [void]$ser.DeserializeObject($new) } catch { Write-Host ("跳过(JSON 无效): " + $f.Name); continue }
        $rel = $f.FullName.Substring($mods.Length).TrimStart($BS)
        $bak = Join-Path $backupRoot $rel
        $d = Split-Path $bak -Parent
        if (-not [IO.Directory]::Exists($d)) { [void][IO.Directory]::CreateDirectory($d) }
        if (-not [IO.File]::Exists($bak)) { [IO.File]::WriteAllText($bak, $orig, $enc) }
        [IO.File]::WriteAllText($f.FullName, $new, $enc)
    }
    $stats.changed++
}
Write-Host ("files=" + $stats.files + " changed=" + $stats.changed + " repl=" + $stats.repl)
