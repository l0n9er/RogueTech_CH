# Translate the Description.Name display field of Quirk_*.json definitions.
#
# Quirk records carry their human-readable name in Description.Name (the "Name"
# at the top level of other files is an internal identifier that must never be
# translated), so this script only walks files under a \Quirks\ directory and
# only rewrites that one field. Already-Chinese values and unknown keys are left
# untouched, and every file is backed up before writing.
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
    if ([string]::IsNullOrWhiteSpace($gr)) { Write-Host " game dir not found" -ForegroundColor Yellow; exit 1 }
    $mods = Join-Path $gr 'Mods'
}
if ([string]::IsNullOrWhiteSpace($pairs)) { $pairs = Join-Path $PSScriptRoot 'dict-quirk.tsv' }
if ([string]::IsNullOrWhiteSpace($backupRoot)) { $backupRoot = Join-Path $packRoot 'backup\Mods-quirk' }
if (-not [IO.File]::Exists($pairs)) { Write-Host (" pairs not found: " + $pairs) -ForegroundColor Yellow; exit 1 }

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
Write-Host ("quirk pairs: " + $map.Count)

$enc = New-Object Text.UTF8Encoding $false
$stats = @{ files = 0; changed = 0; repl = 0 }
$script:map = $map
$script:stats = $stats

# "Name" nested inside a Description block, with the flat indentation used by
# these files; matched per file below rather than by JSON path so that a stray
# top-level "Name" cannot be touched.
$rx = New-Object System.Text.RegularExpressions.Regex ('("Description"\s*:\s*\{[^{}]*?"Name"\s*:\s*")((?:[^"' + $BS + $BS + ']|' + $BS + $BS + '.)*)(")', 'Singleline')

$files = Get-ChildItem $mods -Recurse -File -Filter 'Quirk_*.json' | Where-Object {
    $p = $_.FullName
    ($p -notlike ('*' + $BS + '.modtek' + $BS + '*')) -and
    ($p -notlike '*ModSaves*') -and
    ($p -like ('*' + $BS + 'Quirk' + $BS + '*') -or $p -like ('*' + $BS + 'Quirks' + $BS + '*'))
}

foreach ($f in $files) {
    $stats.files++
    $orig = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
    if ($orig -notmatch '"Description"') { continue }
    $new = $rx.Replace($orig, {
        param($m)
        $val = $m.Groups[2].Value
        if ($val -match '[\u4e00-\u9fff]') { return $m.Value }
        if (-not $script:map.ContainsKey($val)) { return $m.Value }
        $zh = $script:map[$val]
        $script:stats.repl++
        $e = $zh.Replace($BS, $BS + $BS).Replace('"', $BS + '"')
        $e = $e.Replace("`n", $BS + 'n').Replace("`r", $BS + 'r').Replace("`t", $BS + 't')
        return $m.Groups[1].Value + $e + $m.Groups[3].Value
    })
    if ($new -eq $orig) { continue }
    if (-not $DryRun) {
        Add-Type -AssemblyName System.Web.Extensions
        $ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
        $ser.MaxJsonLength = [int]::MaxValue
        try { [void]$ser.DeserializeObject($new) } catch { Write-Host (" skip(invalid JSON): " + $f.Name); continue }
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
