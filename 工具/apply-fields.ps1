param(
    [string]$mods = "",
    [string]$pairs = "",
    [string]$fields = "words",
    [string]$backupRoot = "",
    [switch]$DryRun
)
<#
  通用"就地改写 JSON 文本字段"工具

  用途: 游戏对部分字段不查 CSV, 直接显示 JSON 里的字符串, 必须就地替换。
  字段通过 -fields 指定(逗号分隔), 如: words,title,description

  对照表格式: 英文原文 <TAB> 中文译文 (UTF-8)
  保护: 已含中文的跳过; JSON 校验失败则跳过; 改前备份
#>
$ErrorActionPreference = 'Stop'
$BS = [string][char]92
$packRoot = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($mods)) {
    $gr = & (Join-Path $PSScriptRoot 'find-game.ps1')
    if ([string]::IsNullOrWhiteSpace($gr)) { Write-Host " 找不到游戏目录" -ForegroundColor Yellow; exit 1 }
    $mods = Join-Path $gr 'Mods'
}
if ([string]::IsNullOrWhiteSpace($backupRoot)) { $backupRoot = Join-Path $packRoot 'backup\Mods-fields' }
if (-not [IO.File]::Exists($pairs)) { Write-Host (" 找不到对照表: " + $pairs) -ForegroundColor Yellow; exit 1 }

$map = New-Object 'System.Collections.Generic.Dictionary[string,string]'
$sr = New-Object IO.StreamReader($pairs, [Text.Encoding]::UTF8)
while (-not $sr.EndOfStream) {
    $l = $sr.ReadLine()
    if ([string]::IsNullOrWhiteSpace($l)) { continue }
    $i = $l.IndexOf("`t"); if ($i -lt 1) { continue }
    $k = $l.Substring(0, $i); $v = $l.Substring($i + 1)
    if (-not $map.ContainsKey($k)) { $map[$k] = $v }
}
$sr.Close()
Write-Host ("对照表: " + $map.Count + " 条  字段: " + $fields)

# 构造字段正则: "(words|title|description)"\s*:\s*"..."
$fldAlt = ($fields -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }) -join '|'
$rx = New-Object System.Text.RegularExpressions.Regex ('"(' + $fldAlt + ')"\s*:\s*"((?:[^"' + $BS + $BS + ']|' + $BS + $BS + '.)*)"')

function Unesc([string]$s) {
    return $s.Replace($BS + '/', '/').Replace($BS + '"', '"').Replace($BS + $BS, $BS)
}

$enc = New-Object Text.UTF8Encoding $false
$stats = @{ files = 0; changed = 0; repl = 0 }
$script:map = $map
$script:stats = $stats

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
    if ($orig -notmatch ('"(' + $fldAlt + ')"')) { continue }
    $new = $rx.Replace($orig, {
        param($m)
        $fld = $m.Groups[1].Value
        $val = Unesc $m.Groups[2].Value
        if ($val -match '[\u4e00-\u9fff]') { return $m.Value }
        if (-not $script:map.ContainsKey($val)) { return $m.Value }
        $zh = $script:map[$val]
        $script:stats.repl++
        $e = $zh.Replace($BS, $BS + $BS).Replace('"', $BS + '"')
        $e = $e.Replace("`n", $BS + 'n').Replace("`r", $BS + 'r').Replace("`t", $BS + 't')
        return '"' + $fld + '": "' + $e + '"'
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
