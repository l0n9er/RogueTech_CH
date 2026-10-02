param(
    [string]$dir = "",
    [string]$pairs = "",
    [string]$backupRoot = "",
    [switch]$DryRun
)
<#
  把 BonusDescriptions_*.json 里漏译的 Short/Long/Full 字段补成中文

  背景: BonusDescriptions 是装备/技能的"特性"条目, 结构为
    { "Bonus": "标识符", "Short": "...", "Long": "...", "Full": "..." }
  其中 Short/Long/Full 是显示文本, 必须汉化(标识符 Bonus 绝不可译)。

  对照表按【英文原文】匹配, 覆盖任意文件里的同名字段;
  已含中文的字段跳过, 改前备份。
#>
$ErrorActionPreference = 'Stop'
$BS = [string][char]92
$packRoot = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($dir)) {
    $gr = & (Join-Path $PSScriptRoot 'find-game.ps1')
    if ([string]::IsNullOrWhiteSpace($gr)) { Write-Host " 找不到游戏目录" -ForegroundColor Yellow; exit 1 }
    $dir = Join-Path $gr 'Mods'
}
if ([string]::IsNullOrWhiteSpace($pairs)) { $pairs = Join-Path $PSScriptRoot 'dict-bonus.tsv' }
if ([string]::IsNullOrWhiteSpace($backupRoot)) { $backupRoot = Join-Path $packRoot 'backup\Mods-bonus' }
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
Write-Host ("对照表: " + $map.Count + " 条")

$enc = New-Object Text.UTF8Encoding $false
$stats = @{ files = 0; changed = 0; repl = 0 }

# 匹配 "Short|Long|Full": "..."  (排除 Bonus 字段)
$rx = New-Object System.Text.RegularExpressions.Regex ('"(Short|Long|Full)"\s*:\s*"((?:[^"' + $BS + $BS + ']|' + $BS + $BS + '.)*)"')

function Unesc([string]$s) {
    $t = $s.Replace($BS + '/', '/').Replace($BS + '"', '"').Replace($BS + $BS, $BS)
    return $t
}

$files = Get-ChildItem $dir -Recurse -File -Filter 'BonusDescriptions_*.json' |
    Where-Object { $_.FullName -notmatch '\\\.modtek\\' }

foreach ($f in $files) {
    $stats.files++
    $orig = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
    if ($orig -notmatch '"Bonus"') { continue }
    $new = $rx.Replace($orig, {
        param($m)
        $fld = $m.Groups[1].Value
        $val = Unesc $m.Groups[2].Value
        if ($val -match '[\u4e00-\u9fff]') { return $m.Value }
        if (-not $map.ContainsKey($val)) { return $m.Value }
        $zh = $map[$val]
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
        $rel = $f.FullName.Substring($dir.Length).TrimStart($BS)
        $bak = Join-Path $backupRoot $rel
        $d = Split-Path $bak -Parent
        if (-not [IO.Directory]::Exists($d)) { [void][IO.Directory]::CreateDirectory($d) }
        if (-not [IO.File]::Exists($bak)) { [IO.File]::WriteAllText($bak, $orig, $enc) }
        [IO.File]::WriteAllText($f.FullName, $new, $enc)
    }
    $stats.changed++
}
Write-Host ("files=" + $stats.files + " changed=" + $stats.changed + " repl=" + $stats.repl)
