# Translate the Description.Name display field of Quirk_*.json definitions.
#
# Quirk records carry their human-readable name in Description.Name (the "Name"
# at the top level of other files is an internal identifier that must never be
# translated), so this script only walks files under a \Quirks\ directory and
# only rewrites that one field. Already-Chinese values and unknown keys are left
# untouched, and every file is backed up before writing.
#
# The match is done line by line inside the Description block rather than with a
# single cross-object regex: the Description object contains nested braces, so a
# "[^{}]*?" window stops matching on those files and silently translates nothing.
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
# One "Name" line with its value, used only while inside the Description block.
$nameLine = New-Object System.Text.RegularExpressions.Regex ('^(\s*"Name"\s*:\s*")((?:[^"' + $BS + $BS + ']|' + $BS + $BS + '.)*)(")(\s*,?\s*)$')

$files = Get-ChildItem $mods -Recurse -File -Filter 'Quirk_*.json' | Where-Object {
    $p = $_.FullName
    ($p -notlike ('*' + $BS + '.modtek' + $BS + '*')) -and
    ($p -notlike '*ModSaves*') -and
    ($p -like ('*' + $BS + 'Quirks' + $BS + '*'))
}

foreach ($f in $files) {
    $stats.files++
    $lines = [IO.File]::ReadAllLines($f.FullName, [Text.Encoding]::UTF8)
    $inDesc = $false; $depth = 0; $hit = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $ln = $lines[$i]
        if (-not $inDesc) {
            # only the top-level Description block (indented 2 spaces) holds the
            # display name; nested ones belong to sub-components
            if ($ln -match '^  "Description"\s*:\s*\{') { $inDesc = $true; $depth = 1 }
            continue
        }
        # close of the Description object
        $depth += ([regex]::Matches($ln, '\{')).Count - ([regex]::Matches($ln, '\}')).Count
        $m = $nameLine.Match($ln)
        if ($m.Success) {
            $val = $m.Groups[2].Value
            if ($val -notmatch '[\u4e00-\u9fff]' -and $script:map.ContainsKey($val)) {
                $zh = $script:map[$val]
                # a key that maps to itself carries no translation (C.A.S.E. III
                # and other abbreviations); rewriting it would only churn files
                if ($zh -ne $val) {
                    $zh = $zh.Replace('"', '\"')
                    $lines[$i] = $m.Groups[1].Value + $zh + $m.Groups[3].Value + $m.Groups[4].Value
                    $hit++
                }
            }
        }
        if ($depth -le 0) { $inDesc = $false }
    }
    if ($hit -eq 0) { continue }
    $new = ($lines -join "`r`n") + "`r`n"
    $orig = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
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
    $stats.repl += $hit
    $stats.changed++
}
Write-Host ("files=" + $stats.files + " changed=" + $stats.changed + " repl=" + $stats.repl)