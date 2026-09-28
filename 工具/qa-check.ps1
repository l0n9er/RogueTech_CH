param(
    [string]$mods = "",
    [string]$csv  = "",
    [string]$out  = "",
    [switch]$Quiet
)
$ErrorActionPreference = 'Stop'
$packRoot = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($mods)) {
    $gr = & (Join-Path $PSScriptRoot 'find-game.ps1')
    if ([string]::IsNullOrWhiteSpace($gr)) { Write-Host " 找不到游戏目录, 请用 -mods 指定。" -ForegroundColor Yellow; exit 1 }
    $mods = Join-Path $gr 'Mods'
}
if ([string]::IsNullOrWhiteSpace($csv)) { $csv = Join-Path $packRoot 'strings_zh-CN.csv' }
if ([string]::IsNullOrWhiteSpace($out)) {
    $rd = Join-Path $packRoot 'backup'
    if (-not (Test-Path $rd)) { [void][IO.Directory]::CreateDirectory($rd) }
    $out = Join-Path $rd 'qa-report.txt'
}
$BS = [string][char]92
$enc = New-Object Text.UTF8Encoding $true

# ---- 正则(单独定义,避免哈希字面量解析歧义) ----
$rxHan        = [regex]::new('[\u4e00-\u9fff]')
# 检测前先剥离占位符/HTML(它们内部的空格是游戏语法, 不算问题)
$stripGuard   = [regex]::new('<[^>]*>|\{[^{}]*\}|\[\[[^\]]*\]\]|\\r|\\n|\\t')
$rxSpacePunct = [regex]::new('\s+' + '[' + '，。、：；！？' + ']')
$rxPunctSpace = [regex]::new('[' + '，。、：；！？“（【《' + ']' + '\s+\S')
$rxDupPunct   = [regex]::new('(' + '[' + '，。、；：？' + ']' + ')\1|' + '！{4,}')
# 繁体字: 只用"简繁不同形"的字
$rxTrad       = [regex]::new('[' + '體屬機門們個這說為與來時實際發現對開關資網路點線東馬鳥龍風飛飯麵書寫讀語學國會員長問間隊階級軍爭勝敗擊殺傷藥醫護鐵鋼銀錢價貴買賣貨財產業務農場廠驗證據標準確認錯誤檢測設計畫圖樣報導聽見覺記憶練習慣態勢麼' + ']')
$rxNote       = [regex]::new('翻译' + '[' + ':：' + ']|译者|待译|nonetheless\?|\(TODO')
$rxEnSent     = [regex]::new('[\u4e00-\u9fff]\s+[a-z]{3,}\s+[a-z]{3,}')
$rxDupChar    = [regex]::new('的的|在在|了了|你你|我我')

$checks = @(
    @{ Name='标点前空格'; Rx=$rxSpacePunct; Sev='低'; Fix='多为占位符/HTML 前排版空格, 改动前先确认' },
    @{ Name='标点后空格'; Rx=$rxPunctSpace; Sev='低'; Fix='多为 HTML 标签前排版空格, 改动前先确认' },
    @{ Name='重复标点';   Rx=$rxDupPunct;   Sev='中'; Fix='运行 apply-norm.ps1' },
    @{ Name='繁体字混入'; Rx=$rxTrad;       Sev='低'; Fix='人工确认后加入 apply-norm.ps1 规则' },
    @{ Name='译者批注';   Rx=$rxNote;       Sev='高'; Fix='删除批注,保留正文' },
    @{ Name='未译英文句'; Rx=$rxEnSent;     Sev='低'; Fix='人工确认(厂名/型号可保留)' },
    @{ Name='重复字';     Rx=$rxDupChar;    Sev='低'; Fix='人工核对,多数是正常中文' }
)

# ---- 收集语料 ----
$fldList = @('Details','YangsThoughts','StockRole','levelName','decription','DisplayName','ErrorMessage','title','description','Text','CULTURE_ZH_CN','UIName')
$flds = [string]::Join('|', $fldList)
$fieldRx = [regex]::new('"(' + $flds + ')"\s*:\s*"((?:[^"' + $BS + $BS + ']|' + $BS + $BS + '.)*)"')

$items = New-Object 'System.Collections.Generic.List[object]'
$excl = @($BS + '.modtek' + $BS, 'ModSaves')
$files = Get-ChildItem $mods -Recurse -File -Filter '*.json' | Where-Object {
    $p = $_.FullName; $bad = $false
    foreach ($e in $excl) { if ($p -like ('*' + $e + '*')) { $bad = $true } }
    -not $bad
}
$jsonCnt = 0
foreach ($f in $files) {
    $rel = $f.FullName.Substring($mods.Length).TrimStart($BS)
    $txt = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
    if (-not $rxHan.IsMatch($txt)) { continue }
    foreach ($m in $fieldRx.Matches($txt)) {
        $v = $m.Groups[2].Value
        $items.Add([pscustomobject]@{ Src=('JSON|' + $rel + '|' + $m.Groups[1].Value); Text=$v })
        $jsonCnt++
    }
}
$csvRows = 0
if (Test-Path $csv) {
    $sr = New-Object IO.StreamReader($csv, [Text.Encoding]::UTF8)
    $first = $true; $rn = 0
    while (-not $sr.EndOfStream) {
        $l = $sr.ReadLine(); $rn++
        if ($first) { $first = $false; continue }
        if ($null -eq $l) { continue }
        $i = $l.IndexOf(','); if ($i -lt 1) { continue }
        $zh = $l.Substring($i + 1)
        if (-not $rxHan.IsMatch($zh)) { continue }
        $csvRows++
        $items.Add([pscustomobject]@{ Src=('CSV|row' + $rn); Text=$zh })
    }
    $sr.Close()
}

# ---- 检查 ----
$sw = New-Object IO.StreamWriter($out, $false, $enc)
$sw.WriteLine('汉化质量校验报告  ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
$sw.WriteLine('语料: JSON 字段 ' + $jsonCnt + ' 条, CSV ' + $csvRows + ' 行, 合计 ' + $items.Count)
$sw.WriteLine('')
$sw.WriteLine(('{0,-12} {1,-4} {2,8}  {3}' -f '检查项', '级别', '命中', '建议'))
$highCount = 0
foreach ($c in $checks) {
    $n = 0
    $samples = New-Object 'System.Collections.Generic.List[string]'
    foreach ($it in $items) {
        # 剥离占位符/HTML/转义序列后再检测(它们内部的空格是游戏语法)
        # 同时把连续的空白压缩成单个空格, 避免剥离后产生假空格
        $probe = $stripGuard.Replace($it.Text, '')
        $probe = [regex]::Replace($probe, '\s+', ' ')
        if ($c.Rx.IsMatch($probe)) {
            $n++
            if ($samples.Count -lt 3) {
                $s = $it.Text -replace '\s+', ' '
                if ($s.Length -gt 80) { $s = $s.Substring(0, 80) }
                $samples.Add('    ' + $it.Src + ' :: ' + $s)
            }
        }
    }
    if ($c.Sev -eq '高' -and $n -gt 0) { $highCount++ }
    $sw.WriteLine(('{0,-12} {1,-4} {2,8}  {3}' -f $c.Name, $c.Sev, $n, $c.Fix))
    foreach ($s in $samples) { $sw.WriteLine($s) }
}
$sw.WriteLine('')
if ($highCount -eq 0) { $sw.WriteLine('结论: 未发现高优先级问题。') }
else { $sw.WriteLine('结论: 存在 ' + $highCount + ' 项高优先级问题，需处理。') }
$sw.Close()

if (-not $Quiet) { Get-Content $out -Encoding UTF8 | ForEach-Object { Write-Host $_ } }
Write-Host ('报告: ' + $out)
if ($highCount -gt 0) { exit 1 } else { exit 0 }
