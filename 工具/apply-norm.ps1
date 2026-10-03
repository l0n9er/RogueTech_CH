param(
    [string]$mods = "",
    [string]$backupRoot = "",
    [string]$audit = "",
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$packRoot = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($mods)) {
    $gr = & (Join-Path $PSScriptRoot 'find-game.ps1')
    if ([string]::IsNullOrWhiteSpace($gr)) { Write-Host " 找不到游戏目录, 请用 -mods 指定。" -ForegroundColor Yellow; exit 1 }
    $mods = Join-Path $gr 'Mods'
}
if ([string]::IsNullOrWhiteSpace($backupRoot)) { $backupRoot = Join-Path $packRoot 'backup\Mods-norm' }
$BS = [string][char]92

# 与 qa-fix.ps1 相同的规则(标点空格 + 术语变体 + 繁体 + 精确错字)
$rules = @(
    @{ n='空格+标点';   rx=[regex]'\s+([，。、：；！？”》）】《])'; to='$1' },
    @{ n='标点+空格';   rx=[regex]'([，。、：；！？“（【《])\s+(?=\S)'; to='$1' },
    @{ n='重复标点';    rx=[regex]'([，。、；：？])\1+|！{4,}'; to='$1' },
    @{ n='作动器';      rx=[regex]'作动器'; to='驱动器' },
    @{ n='执行机构';    rx=[regex]'执行机构'; to='驱动器' },
    @{ n='内天體';      rx=[regex]'内天體'; to='内天体' },
    @{ n='屬于';        rx=[regex]'屬于'; to='属于' },
    @{ n='战斗機甲';    rx=[regex]'战斗機甲'; to='战斗机甲' },
    @{ n='一門';        rx=[regex]'一門'; to='一门' },
    @{ n='的的-边境';   rx=[regex]'境内外域边境的的伍德拜恩'; to='境内外域边境的伍德拜恩' },
    @{ n='你你';        rx=[regex]'我会给你你该得的'; to='我会给你该得的' },
    @{ n='旨在在';      rx=[regex]'旨在在不增加引擎吨位'; to='旨在不增加引擎吨位' },
    @{ n='寻的的';      rx=[regex]'四个各自寻的的弹丸'; to='四个各自寻的弹丸' },
    @{ n='次要的的';    rx=[regex]'较为次要的的跳跃能力'; to='较为次要的跳跃能力' },
    @{ n='所看到的的';  rx=[regex]'我们所看到的的一切'; to='我们所看到的一切' },
    @{ n='撇清关系的的';rx=[regex]'一支可以撇清关系的的'; to='一支可以撇清关系的' },
    @{ n='内骨骼钢复合';rx=[regex]'内骨骼钢复合结构'; to='钢内骨复合结构' },
    @{ n='内骨骼钢结构';rx=[regex]'内骨骼钢结构'; to='钢内骨结构' },
    @{ n='内骨骼钢';    rx=[regex]'内骨骼钢'; to='钢内骨结构' },
    @{ n='运输舰';      rx=[regex]'运输舰'; to='空投艇' },
    @{ n='空降舰';      rx=[regex]'空降舰'; to='空投艇' },
    @{ n='载具';        rx=[regex]'载具'; to='车辆' },
    @{ n='混战';        rx=[regex]'混战'; to='近战' },
    @{ n='长程导弹';    rx=[regex]'长程导弹'; to='远程导弹' },
    @{ n='短程导弹';    rx=[regex]'短程导弹'; to='短程火箭' },
    @{ n='跳跃喷射器';  rx=[regex]'跳跃喷射器'; to='跳跃推进器' },
    @{ n='跳跃舰';      rx=[regex]'跳跃舰'; to='跃迁舰' },
    @{ n='跃迁船';      rx=[regex]'跃迁船'; to='跃迁舰' },
    @{ n='执行器';      rx=[regex]'执行器'; to='驱动器' },
    @{ n='驾驶员';      rx=[regex]'驾驶员'; to='机师' },
    @{ n='格斗者';      rx=[regex]'格斗者'; to='近战者' },
    @{ n='格斗';        rx=[regex]'(?<!精英)格斗(?!家)'; to='近战' },
    @{ n='亲和';        rx=[regex]'亲和(?![兄弟姑姨母叔姐哥])'; to='偏好' },
    @{ n='TODO-Default';rx=[regex]'\s*\(TODO-?\s*Default Mission Start dialogue.*?\)'; to='' },
    @{ n='TODO-Finailize';rx=[regex]'\s*\(TODO\s*-\s*Finailize default failure\)'; to='' },
    @{ n='TODO-最终';   rx=[regex]'\s*\(TODO-最终设置成功\)'; to='' },
    @{ n='译者批注-草稿';rx=[regex]'\s*[^"，。]{0,12}nonetheless\?\s*不对\.\s*翻译:\s*'; to='' },
    @{ n='半译-and Keep';rx=[regex]'消灭敌方小队 and Keep Test Drive Mech Alive'; to='消灭敌方小队并保住试驾机甲' }
)

# 保护: HTML 标签、[[...]] 占位符(内部可含 {...})、{...} 占位符、转义序列
$guard = [regex]'(<[^>]*>|\[\[.*?\]\]|\{[^{}]*\}|\\r|\\n|\\t)'
# 快筛: 由全部规则自身拼成一个交替正则(保留各规则原有的元字符),
# 先问一次"这段文本有没有可能命中任何规则", 没有就直接返回,
# 省掉逐条 IsMatch 的开销(原先每段文本要跑 28 次匹配)。
# 注意: 不能用 [regex]::Escape 处理字面量规则, 否则会丢掉 \s \1 等语义。
$ruleHint = [regex](($rules | ForEach-Object { '(?:' + $_.rx.ToString() + ')' }) -join '|')

# 文件级预筛用的字面量清单: 覆盖 $rules 里所有"固定串"规则(变体写法取最短的
# 覆盖串, 如"内骨骼钢"已涵盖"内骨骼钢复合结构"/"内骨骼钢结构"; "格斗"涵盖
# "格斗者")。String.Contains 是 SIMD 加速的, 比在 193MB 上跑正则快得多。
$needles = @(
    '作动器','执行机构','内天體','屬於','战斗機甲','一門',
    '境内外域边境的的伍德拜恩','我会给你你该得的','旨在在不增加引擎吨位',
    '四个各自寻的的弹丸','较为次要的的跳跃能力','我们所看到的的一切',
    '一支可以撇清关系的的','内骨骼钢','运输舰','空降舰','载具','混战',
    '长程导弹','短程导弹','跳跃喷射器','跳跃舰','跃迁船','执行器','驾驶员',
    '格斗','亲和','TODO','nonetheless','and Keep Test Drive Mech Alive'
)
# 标点类规则(空格+标点 / 标点+空格 / 重复标点)无法用 Contains, 单独用轻量正则
$filePunctRx = [regex]'(\s+[，。、：；！？”》）】《]|[，。、：；！？“（【《]\s+(?=\S)|([，。、；：？])\1|！{4,})'
$encNoBom = New-Object Text.UTF8Encoding $false
$auditEnc = New-Object Text.UTF8Encoding $true
if ([string]::IsNullOrWhiteSpace($audit)) {
    $ad = Join-Path $packRoot 'backup'
    if (-not (Test-Path $ad)) { [void][IO.Directory]::CreateDirectory($ad) }
    $audit = Join-Path $ad 'norm-audit.tsv'
}
$aw = New-Object IO.StreamWriter($audit, $false, $auditEnc)
$script:n = 0

function Fix-Text([string]$text, [string]$src) {
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
        # 快筛: 未命中则任何规则都不可能改动它, 直接原样输出
        if (-not $ruleHint.IsMatch($seg)) { [void]$out.Append($seg); continue }
        # 命中快筛说明"可能有规则生效", 但多数情况只是一两个词。逐条 Replace 并
        # 用返回值是否变化判断, 省掉原先多跑一遍的 IsMatch($seg)。
        foreach ($r in $rules) {
            $b = $seg
            $seg = $r.rx.Replace($seg, $r.to)
            if ($seg -ne $b) {
                $script:n++
                $s = ($b -replace "`r", ' ' -replace "`n", ' ')
                if ($s.Length -gt 70) { $s = $s.Substring(0, 70) }
                $aw.WriteLine($src + "`t" + $r.n + "`t" + $s)
            }
        }
        [void]$out.Append($seg)
    }
    return $out.ToString()
}

# 覆盖全部已知文本字段(含之前遗漏的 CULTURE_ZH_CN 与 words)
# words 曾长期缺席, 导致对话/字幕里的"运输舰""载具""混战"等术语始终没被
# 归一化(实测残留 228/31/11 处), 而脚本每次都报 hits=0 看不出问题。
$fldList = @('words','Details','YangsThoughts','StockRole','levelName','decription','DisplayName','ErrorMessage','title','description','Text','CULTURE_ZH_CN','UIName','Name','Original','Commentary','Short','Long','Full','BonusValueA','BonusValueB','shortDescription','longDescription','ShortDesc')
$flds = [string]::Join('|', $fldList)
$fieldRx = [regex]('"(' + $flds + ')"\s*:\s*"((?:[^"' + $BS + $BS + ']|' + $BS + $BS + '.)*)"')
$excl = @($BS + '.modtek' + $BS, 'ModSaves', $BS + 'unitTypes' + $BS)
$files = Get-ChildItem $mods -Recurse -File -Filter '*.json' | Where-Object {
    $p = $_.FullName; $bad = $false
    foreach ($e in $excl) { if ($p -like ('*' + $e + '*')) { $bad = $true } }
    -not $bad
}
$stats = @{ files=0; changed=0; skip=0 }
$script:rel = ''
$eval = [System.Text.RegularExpressions.MatchEvaluator]{
    param($m)
    $fld = $m.Groups[1].Value
    $raw = $m.Groups[2].Value
    if ($raw -notmatch '[\u4e00-\u9fff]') { return $m.Value }
    $new = Fix-Text $raw ('JSON|' + $script:rel + '|' + $fld)
    if ($new -eq $raw) { return $m.Value }
    return '"' + $fld + '": "' + $new + '"'
}
foreach ($f in $files) {
    $stats.files++
    $script:rel = $f.FullName.Substring($mods.Length).TrimStart($BS)
    $orig = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
    # 廉价预筛: 全部规则只作用于含中文的文本, 无中文的文件不必跑大正则。
    # (更激进的"关键词预筛"实测反而更慢 —— 在 193MB 上跑交替正则比重跑
    #  字段正则还贵, 故只保留这一级。)
    if ($orig -notmatch '[\u4e00-\u9fff]') { continue }
    # 文件级预筛: 用 Contains 找规则字面量(极快), 标点类规则再补一次轻量正则。
    # 两者都不命中时, $fieldRx 无论如何都不会改动任何内容, 可安全跳过。
    $hit = $false
    foreach ($nd in $needles) { if ($orig.Contains($nd)) { $hit = $true; break } }
    if (-not $hit) { if (-not $filePunctRx.IsMatch($orig)) { continue } }
    $new = $fieldRx.Replace($orig, $eval)
    if ($new -eq $orig) { continue }
    if (-not $DryRun) {
        Add-Type -AssemblyName System.Web.Extensions
        $ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
        $ser.MaxJsonLength = [int]::MaxValue
        try { [void]$ser.DeserializeObject($new) } catch { Write-Host ('跳过(JSON 无效): ' + $script:rel); $stats.skip++; continue }
        $bak = Join-Path $backupRoot $script:rel
        $d = Split-Path $bak -Parent
        if (-not (Test-Path $d)) { [void][IO.Directory]::CreateDirectory($d) }
        if (-not (Test-Path $bak)) { [IO.File]::WriteAllText($bak, $orig, $encNoBom) }
        [IO.File]::WriteAllText($f.FullName, $new, $encNoBom)
    }
    $stats.changed++
    if ($stats.changed % 1000 -eq 0) { Write-Host ("  progress: " + $stats.changed + " files, " + $script:n + " hits") }
}
$aw.Close()
Write-Host ("JSON files=" + $stats.files + " changed=" + $stats.changed + " skipped=" + $stats.skip + " hits=" + $script:n)
Write-Host ("mode: " + $(if ($DryRun) { 'DRY-RUN' } else { 'WRITTEN' }))
