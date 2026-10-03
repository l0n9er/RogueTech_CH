# Apply Chinese translations to the base-game simGameStatDesc templates.
#
# Background: simGameStatDesc/*.json stores Result templates directly in JSON;
# the game does not route them through strings_zh-CN.csv, so the only way to
# localise them is to rewrite the JSON.
#
# Note on the interpolation separator: the shipped English JSON writes these
# placeholders as "[[Def, Label]]" with an ASCII comma, so the JSON files keep
# that form. The 0x1F (ASCII 31) separator only exists inside the localization
# CSVs, where a literal comma would collide with the CSV delimiter.
param(
    [string]$game = "",
    [string]$pairs = "",
    [string]$backupRoot = "",
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$packRoot = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($game)) {
    $gr = & (Join-Path $PSScriptRoot 'find-game.ps1')
    if ([string]::IsNullOrWhiteSpace($gr)) { Write-Host " game dir not found" -ForegroundColor Yellow; exit 1 }
    $game = $gr
}
if ([string]::IsNullOrWhiteSpace($pairs)) { $pairs = Join-Path $PSScriptRoot 'dict-statdesc.tsv' }
if ([string]::IsNullOrWhiteSpace($backupRoot)) { $backupRoot = Join-Path $packRoot 'backup\simGameStatDesc' }
if (-not [IO.File]::Exists($pairs)) { Write-Host (" pairs not found: " + $pairs) -ForegroundColor Yellow; exit 1 }

$dir = Join-Path $game 'BattleTech_Data\StreamingAssets\data\simGameStatDesc'
if (-not [IO.Directory]::Exists($dir)) { Write-Host (" simGameStatDesc not found: " + $dir) -ForegroundColor Yellow; exit 1 }

# Read pairs. Keys are the English template strings, values the Chinese ones.
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
Write-Host ("statdesc pairs: " + $map.Count)

$enc = New-Object Text.UTF8Encoding $false
$stats = @{ files = 0; changed = 0; repl = 0 }
$fields = @('setResult','positiveResult','negativeResult','temporalSetResult','temporalPositiveResult','temporalNegativeResult','infinitiveSetResult','infinitivePositiveResult','infinitiveNegativeResult')
$rx = [regex]('("(?:' + ($fields -join '|') + ')"\s*:\s*")((?:[^"\\]|\\.)*)(")')

foreach ($f in Get-ChildItem $dir -Filter '*.json') {
    $stats.files++
    $orig = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
    $new = $rx.Replace($orig, {
        param($m)
        $val = $m.Groups[2].Value
        if ($val -match '[\u4e00-\u9fff]') { return $m.Value }
        if (-not $script:map.ContainsKey($val)) { return $m.Value }
        $script:stats.repl++
        $zh = $script:map[$val]
        # The dictionary already stores JSON-escaped text (\n, \u00A2), so only
        # quotes need escaping; a blanket backslash pass would double them.
        $e = $zh.Replace('"', '\"')
        return $m.Groups[1].Value + $e + $m.Groups[3].Value
    })
    if ($new -eq $orig) { continue }
    if (-not $DryRun) {
        Add-Type -AssemblyName System.Web.Extensions
        $ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
        $ser.MaxJsonLength = [int]::MaxValue
        try { [void]$ser.DeserializeObject($new) } catch { Write-Host (" skip(invalid JSON): " + $f.Name); continue }
        if (-not [IO.Directory]::Exists($backupRoot)) { [void][IO.Directory]::CreateDirectory($backupRoot) }
        $bak = Join-Path $backupRoot $f.Name
        if (-not [IO.File]::Exists($bak)) { [IO.File]::WriteAllText($bak, $orig, $enc) }
        [IO.File]::WriteAllText($f.FullName, $new, $enc)
    }
    $stats.changed++
}
Write-Host ("files=" + $stats.files + " changed=" + $stats.changed + " repl=" + $stats.repl)
