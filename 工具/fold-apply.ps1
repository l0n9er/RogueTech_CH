param(
    [string]$dict = "",
    [string]$mods = "",
    [string]$backupRoot = "",
    [string]$csv = "",
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$packRoot = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($dict)) { $dict = Join-Path $PSScriptRoot 'dict-all.tsv' }
if ([string]::IsNullOrWhiteSpace($mods)) {
    $gr = & (Join-Path $PSScriptRoot 'find-game.ps1')
    if ([string]::IsNullOrWhiteSpace($gr)) { Write-Host " 找不到游戏目录, 请用 -mods 指定。" -ForegroundColor Yellow; exit 1 }
    $mods = Join-Path $gr 'Mods'
}
if ([string]::IsNullOrWhiteSpace($backupRoot)) { $backupRoot = Join-Path $packRoot 'backup\Mods-defs' }
if ([string]::IsNullOrWhiteSpace($csv)) { $csv = Join-Path $packRoot 'strings_zh-CN.csv' }
$BS = [string][char]92

# --- 字典：精确键 + 空白折叠键 两套 ---
$exact = New-Object 'System.Collections.Generic.Dictionary[string,string]'
function Fold([string]$s) { return ([regex]::Replace(($s -replace "`r`n", "`n"), '[\s]+', ' ')).Trim() }
$fold = New-Object 'System.Collections.Generic.Dictionary[string,string]'
$sr = New-Object IO.StreamReader($dict, [Text.Encoding]::UTF8)
while (-not $sr.EndOfStream) {
    $l = $sr.ReadLine(); if ([string]::IsNullOrWhiteSpace($l)) { continue }
    $i = $l.IndexOf("`t"); if ($i -lt 1) { continue }
    $k = ($l.Substring(0, $i) -replace (($BS + $BS) + 'n'), "`r`n")
    $v = ($l.Substring($i + 1) -replace (($BS + $BS) + 'n'), "`r`n")
    if (-not $exact.ContainsKey($k)) { $exact[$k] = $v }
    $fk = Fold $k
    if ($fk.Length -gt 12 -and -not $fold.ContainsKey($fk)) { $fold[$fk] = $v }
}
$sr.Close()
Write-Host ("dict exact: " + $exact.Count + "   folded: " + $fold.Count)

function Unesc([string]$s) {
    $t = [regex]::Replace($s, ($BS + $BS + 'u([0-9a-fA-F]{4})'), [System.Text.RegularExpressions.MatchEvaluator]{ param($mm) [char][int]("0x" + $mm.Groups[1].Value) })
    $t = $t.Replace($BS + '/', '/').Replace($BS + '"', '"').Replace($BS + $BS, $BS)
    $t = $t.Replace($BS + 'n', "`n").Replace($BS + 'r', "`r").Replace($BS + 't', "`t")
    return $t
}
function Esc([string]$s) {
    $t = $s.Replace($BS, $BS + $BS).Replace('"', $BS + '"')
    return $t.Replace("`n", $BS + 'n').Replace("`r", $BS + 'r').Replace("`t", $BS + 't')
}

$script:exact = $exact; $script:fold = $fold
$stats = @{ files = 0; changed = 0; repl = 0; miss = 0; viaFold = 0 }
$missList = New-Object 'System.Collections.Generic.List[string]'
$eval = [System.Text.RegularExpressions.MatchEvaluator]{
    param($m)
    $fld = $m.Groups[1].Value
    $val = Unesc $m.Groups[2].Value
    if ([string]::IsNullOrWhiteSpace($val)) { return $m.Value }
    if ($val -match '[\u4e00-\u9fff]') { return $m.Value }
    $zh = $null
    if ($script:exact.ContainsKey($val)) { $zh = $script:exact[$val] }
    if ($null -eq $zh) {
        $fk = Fold $val
        if ($script:fold.ContainsKey($fk)) { $zh = $script:fold[$fk]; $stats.viaFold++ }
    }
    if ($null -eq $zh -or [string]::IsNullOrWhiteSpace($zh)) {
        $stats.miss++
        if ($missList.Count -lt 20000) { $missList.Add($fld + "`t" + ($val -replace "`r?`n", ($BS + 'n'))) }
        return $m.Value
    }
    $m2 = '"' + $fld + '": "' + (Esc $zh) + '"'
    if ($m2 -eq $m.Value) { return $m.Value }
    $stats.repl++
    return $m2
}
$rx = [regex]('"(Details|YangsThoughts|StockRole)"\s*:\s*"((?:[^"' + $BS + $BS + ']|' + $BS + $BS + '.)*)"')
$excl = @($BS + '.modtek' + $BS, 'ModSaves', 'Localization', 'localization')
$files = Get-ChildItem $mods -Recurse -File -Filter '*.json' | Where-Object {
    $p = $_.FullName; $bad = $false
    foreach ($e in $excl) { if ($p -like ('*' + $e + '*')) { $bad = $true } }
    if ($_.Name -in @('mod.json', 'modstate.json')) { $bad = $true }
    -not $bad
}
$enc = New-Object Text.UTF8Encoding $false
foreach ($f in $files) {
    $stats.files++
    $orig = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
    $new = $rx.Replace($orig, $eval)
    if ($new -eq $orig) { continue }
    if (-not $DryRun) {
        Add-Type -AssemblyName System.Web.Extensions
        $ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
        $ser.MaxJsonLength = [int]::MaxValue
        [void]$ser.DeserializeObject($new)
        $rel = $f.FullName.Substring($mods.Length).TrimStart($BS)
        $bak = Join-Path $backupRoot $rel
        $d = Split-Path $bak -Parent
        if (-not (Test-Path $d)) { [void][IO.Directory]::CreateDirectory($d) }
        if (-not (Test-Path $bak)) { [IO.File]::WriteAllText($bak, $orig, $enc) }
        [IO.File]::WriteAllText($f.FullName, $new, $enc)
        $stats.changed++
    }
}
$line = "mode=" + $(if ($DryRun) { 'dry' } else { 'written' }) + " files=" + $stats.files + " changed=" + $stats.changed + " repl=" + $stats.repl + " viaFold=" + $stats.viaFold + " miss=" + $stats.miss
Write-Host $line
# 报告写到包内 backup 目录(不污染游戏目录, 便于排查)
$reportDir = Join-Path $packRoot 'backup'
if (-not (Test-Path $reportDir)) { [void][IO.Directory]::CreateDirectory($reportDir) }
[IO.File]::WriteAllText((Join-Path $reportDir 'coverage-summary.txt'), $line, (New-Object Text.UTF8Encoding $false))
if ($missList.Count -gt 0) {
    [IO.File]::WriteAllLines((Join-Path $reportDir 'still-missing-raw.tsv'), $missList, (New-Object Text.UTF8Encoding $true))
    Write-Host ("missing samples -> backup\still-missing-raw.tsv (" + $missList.Count + ")")
}
