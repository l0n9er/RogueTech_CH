param(
    [string]$csv = "",
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$packRoot = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($csv)) { $csv = Join-Path $packRoot 'strings_zh-CN.csv' }

# CSV 侧的标点空格规范化(与 apply-norm.ps1 同规则; 术语替换已在总表内完成,
# 此处只做格式清理, 避免重复替换造成二次改写)
$rules = @(
    @{ n='空格+标点'; rx=[regex]'\s+([，。、：；！？”》）】《])'; to='$1' },
    @{ n='标点+空格'; rx=[regex]'([，。、：；！？“（【《])\s+(?=\S)'; to='$1' },
    @{ n='重复标点';  rx=[regex]'([，。、；：？])\1+|！{4,}'; to='$1' }
)
# 保护: HTML 标签、[[...]] 占位符(内部可含 {...})、{...} 占位符、转义序列
$guard = [regex]'(<[^>]*>|\[\[.*?\]\]|\{[^{}]*\}|\\r|\\n|\\t)'
$encNoBom = New-Object Text.UTF8Encoding $false

function Fix-Text([string]$text) {
    if ($text -notmatch '[\u4e00-\u9fff]') { return $text }
    $parts = @(); $last = 0
    foreach ($m in $guard.Matches($text)) {
        if ($m.Index -gt $last) { $parts += ,@('T', $text.Substring($last, $m.Index - $last)) }
        $parts += ,@('G', $m.Value)
        $last = $m.Index + $m.Length
    }
    if ($last -lt $text.Length) { $parts += ,@('T', $text.Substring($last)) }
    $out = New-Object System.Text.StringBuilder
    foreach ($p in $parts) {
        if ($p[0] -eq 'G') { [void]$out.Append($p[1]); continue }
        $seg = $p[1]
        foreach ($r in $rules) { if ($r.rx.IsMatch($seg)) { $seg = $r.rx.Replace($seg, $r.to) } }
        [void]$out.Append($seg)
    }
    return $out.ToString()
}

if (-not (Test-Path $csv)) { Write-Host ("CSV 不存在: " + $csv); exit 1 }
$tmp = $csv + '.nctmp'
$sr = New-Object IO.StreamReader($csv, [Text.Encoding]::UTF8)
$sw = New-Object IO.StreamWriter($tmp, $false, $encNoBom)
$sw.NewLine = "`r`n"
$row = 0; $ch = 0; $first = $true
while (-not $sr.EndOfStream) {
    $l = $sr.ReadLine(); $row++
    if ($first) { $first = $false; $sw.WriteLine($l); continue }
    if ($null -eq $l) { $l = '' }
    $i = $l.IndexOf(','); if ($i -lt 1) { $sw.WriteLine($l); continue }
    $zh = $l.Substring($i + 1)
    if ($zh -notmatch '[\u4e00-\u9fff]') { $sw.WriteLine($l); continue }
    $new = Fix-Text $zh
    if ($new -eq $zh) { $sw.WriteLine($l); continue }
    $ch++; $sw.WriteLine($l.Substring(0, $i + 1) + $new)
}
$sr.Close(); $sw.Close()
if ($ch -gt 0 -and -not $DryRun) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    # 备份放到 CSV 同级的 backup 子目录(避免污染包根目录)
    $bakDir = Join-Path (Split-Path $csv -Parent) 'backup\csv-baks'
    if (-not (Test-Path $bakDir)) { [void][IO.Directory]::CreateDirectory($bakDir) }
    [IO.File]::Copy($csv, (Join-Path $bakDir ((Split-Path $csv -Leaf) + '.ncbak-' + $stamp)), $false)
    [IO.File]::Delete($csv); [IO.File]::Move($tmp, $csv)
} else { [IO.File]::Delete($tmp) }
Write-Host ("CSV 行数=" + $row + " 修正=" + $ch + " mode=" + $(if ($DryRun) { 'DRY' } else { 'WRITTEN' }))
