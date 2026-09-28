param(
    [string]$gameRoot = "",
    [string]$mapFile = "",
    [string]$backupRoot = ""
)
$ErrorActionPreference = 'Stop'

# 包根目录 = 本脚本所在目录(工具\)的上一级
$packRoot = Split-Path $PSScriptRoot -Parent

if ([string]::IsNullOrWhiteSpace($gameRoot)) {
    $gameRoot = & (Join-Path $PSScriptRoot 'find-game.ps1')
    if ([string]::IsNullOrWhiteSpace($gameRoot)) {
        Write-Host " 找不到游戏目录, 请用 -gameRoot 指定。" -ForegroundColor Yellow
        exit 1
    }
}
if ([string]::IsNullOrWhiteSpace($mapFile))    { $mapFile = Join-Path $PSScriptRoot 'category-zh.tsv' }
if ([string]::IsNullOrWhiteSpace($backupRoot)) { $backupRoot = Join-Path $packRoot 'backup\Mods-defs' }

$dir = Join-Path $gameRoot 'Mods\Core\RogueTechCore\categories'
$bakDir = Join-Path $backupRoot 'Core\RogueTechCore\categories'
$enc = New-Object Text.UTF8Encoding $false
$map = New-Object 'System.Collections.Generic.Dictionary[string,string]'
$sr = New-Object IO.StreamReader($mapFile, [Text.Encoding]::UTF8)
while (-not $sr.EndOfStream) {
    $l = $sr.ReadLine(); if ([string]::IsNullOrWhiteSpace($l)) { continue }
    $p = $l.Split("`t"); if ($p.Length -lt 2) { continue }
    $map[$p[0]] = $p[1]
}
$sr.Close()
Write-Host ("映射条目: " + $map.Count)
if (-not (Test-Path $bakDir)) { [void][IO.Directory]::CreateDirectory($bakDir) }
$repl = 0; $bad = 0
foreach ($f in [IO.Directory]::GetFiles($dir, '*.json')) {
    $orig = [IO.File]::ReadAllText($f, [Text.Encoding]::UTF8)
    $t = $orig
    foreach ($k in $map.Keys) {
        $needle = '"DisplayName": "' + $k + '"'
        if ($t.Contains($needle)) { $t = $t.Replace($needle, '"DisplayName": "' + $map[$k] + '"'); $repl++ }
    }
    if ($t -ne $orig) {
        $bak = Join-Path $bakDir ([IO.Path]::GetFileName($f))
        if (-not (Test-Path $bak)) { [IO.File]::WriteAllText($bak, $orig, $enc) }
        Add-Type -AssemblyName System.Web.Extensions
        $ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
        $ser.MaxJsonLength = [int]::MaxValue
        try { [void]$ser.DeserializeObject($t) } catch { $bad++; Write-Host ("JSON 校验失败，跳过: " + $f); continue }
        [IO.File]::WriteAllText($f, $t, $enc)
    }
}
Write-Host ("替换: " + $repl + "   校验失败: " + $bad)
# 复核剩余英文
$left = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($f in [IO.Directory]::GetFiles($dir, '*.json')) {
    $t = [IO.File]::ReadAllText($f, [Text.Encoding]::UTF8)
    foreach ($m in [regex]::Matches($t, '"DisplayName": "([^"]*)"')) {
        $v = $m.Groups[1].Value
        if ($v -and $v -notmatch '[\u4e00-\u9fff]') { [void]$left.Add($v) }
    }
}
Write-Host ("剩余纯英文分类名: " + $left.Count)
$left | Sort-Object | ForEach-Object { Write-Host ("  " + $_) }
