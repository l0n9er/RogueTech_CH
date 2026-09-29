param(
    [string]$mods = "",
    [string]$out  = ""
)
<#
  注册表标识符校验 —— 防止"内部标识符被汉化"导致游戏逻辑失灵
  背景: UnitTypes_*.json 的 Name 是单位类型标识符, 被 Categories_*.json 的 "UnitType" 字段引用.
        若被翻译成中文(如 Quad -> 四足), 四足机甲的槽位限制会失效, 表现为:
        "~过量 足部驱动器: 该单位在 左臂 中最多只能安装 0 个 / QuadIncompatible 无法与 四足机甲 搭配使用"

  校验项:
   1) Mods/**/unitTypes/UnitTypes_*.json 的 Name 必须是纯 ASCII (绝不可含 CJK)
   2) Categories_*.json / defaults / locations 里 "UnitType": "X" 的 X 必须能在 unitTypes 里找到定义
   3) 引用完整性: 每个 "UnitType" 值都能匹配到某个 UnitTypes 条目的 Name
#>
$ErrorActionPreference = 'Stop'
$BS = [string][char]92
if ([string]::IsNullOrWhiteSpace($mods)) {
    $gr = & (Join-Path $PSScriptRoot 'find-game.ps1')
    if ([string]::IsNullOrWhiteSpace($gr)) { Write-Host " 找不到游戏目录, 请用 -mods 指定。" -ForegroundColor Yellow; exit 1 }
    $mods = Join-Path $gr 'Mods'
}
if ([string]::IsNullOrWhiteSpace($out)) {
    $packRoot = Split-Path $PSScriptRoot -Parent
    $rd = Join-Path $packRoot 'backup'
    if (-not (Test-Path $rd)) { [void][IO.Directory]::CreateDirectory($rd) }
    $out = Join-Path $rd 'registry-check.txt'
}
$enc = New-Object Text.UTF8Encoding $true
$rxHan = New-Object System.Text.RegularExpressions.Regex ('[\u4e00-\u9fff]')
$rxName = New-Object System.Text.RegularExpressions.Regex ('"Name"\s*:\s*"([^"]*)"')
$rxUnitType = New-Object System.Text.RegularExpressions.Regex ('"UnitType"\s*:\s*"([^"]*)"')

$problems = New-Object 'System.Collections.Generic.List[string]'
$defined = New-Object 'System.Collections.Generic.HashSet[string]'

# ---- 1) 扫 unitTypes 注册表 ----
# 单位类型名是内部标识符, 一经汉化必须还原。优先从 RtCache 基线恢复;
# 若无基线, 则用内建对照表把中文名回译为英文标识符。
$builtinBack = @{
    '机甲'         = 'Mech'
    '四足'         = 'Quad'
    '车辆'         = 'Vehicle'
    '工业机甲'     = 'IndustrialMech'
    '原始机甲'     = 'PrimitiveMech'
    '陆空两用机甲' = 'LandAirMech'
    '万能机甲'     = 'OmniMech'
    '多人机甲'     = 'MechSquad'
    '原型机甲'     = 'ProtoMech'
    '战斗装甲'     = 'BattleArmor'
    '超重型机甲'   = 'SuperheavyMech'
}
$rtCache = 'D:\RT\RtlCache\RtCache'
$repaired = 0
$utDirs = Get-ChildItem $mods -Recurse -Directory -Filter 'unitTypes' -ErrorAction SilentlyContinue |
          Where-Object { $_.FullName -notmatch '\\\.modtek\\' }
if ($utDirs.Count -eq 0) { $problems.Add('[警告] 未找到任何 unitTypes 目录, 请确认游戏/模组结构') }
foreach ($d in $utDirs) {
    foreach ($f in Get-ChildItem $d.FullName -File -Filter '*.json') {
        $rel = $f.FullName.Substring($mods.Length).TrimStart($BS)
        $txt = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
        $dirty = $false
        foreach ($m in $rxName.Matches($txt)) {
            if ($rxHan.IsMatch($m.Groups[1].Value)) { $dirty = $true; break }
        }
        if ($dirty) {
            $fixed = $null
            $base = Join-Path $rtCache $rel
            if (Test-Path $base) {
                $bt = [IO.File]::ReadAllText($base, [Text.Encoding]::UTF8)
                if (-not $rxHan.IsMatch(($rxName.Matches($bt) | ForEach-Object { $_.Groups[1].Value }) -join '')) { $fixed = $bt }
            }
            if ($null -eq $fixed) {
                $fixed = $rxName.Replace($txt, {
                    param($mm)
                    $v = $mm.Groups[1].Value
                    if ($builtinBack.ContainsKey($v)) { return '"Name": "' + $builtinBack[$v] + '"' }
                    return $mm.Value
                })
            }
            [IO.File]::WriteAllText($f.FullName, $fixed, (New-Object Text.UTF8Encoding $false))
            $repaired++
            Write-Host ('  已还原: ' + $rel) -ForegroundColor Yellow
        }
        $txt2 = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
        foreach ($m in $rxName.Matches($txt2)) {
            $v = $m.Groups[1].Value
            if ($rxHan.IsMatch($v)) {
                $problems.Add('[严重] 单位类型标识符被汉化: ' + $rel + '  Name="' + $v + '"  (必须为 ASCII)')
            } else {
                [void]$defined.Add($v)
            }
        }
    }
}
Write-Host ('unitTypes 已定义 ' + $defined.Count + ' 个单位类型: ' + (($defined | Sort-Object) -join ', '))

# ---- 2) 扫引用方 ----
# 已知白名单: 这些值在原始 RogueTech 数据里就作为 UnitType 出现(实为 tag 名), 非注册表项, 不算问题
$knownExtra = @('QuadMech', 'TribeMech')
$refFiles = Get-ChildItem $mods -Recurse -File -Filter '*.json' -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '\\\.modtek\\' -and $_.Name -match 'Categories|Defaults|EquipLocation|UnitTypes' }
$refCnt = 0
foreach ($f in $refFiles) {
    $txt = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
    if ($txt -notmatch '"UnitType"') { continue }
    $rel = $f.FullName.Substring($mods.Length).TrimStart($BS)
    foreach ($m in $rxUnitType.Matches($txt)) {
        $v = $m.Groups[1].Value
        $refCnt++
        if ($rxHan.IsMatch($v)) {
            $problems.Add('[严重] UnitType 引用值是中文: ' + $rel + '  UnitType="' + $v + '"')
        } elseif (-not $defined.Contains($v) -and $knownExtra -notcontains $v) {
            $problems.Add('[警告] UnitType 引用了未定义的类型: ' + $rel + '  UnitType="' + $v + '"')
        }
    }
}

# ---- 输出 ----
$sw = New-Object IO.StreamWriter($out, $false, $enc)
$sw.WriteLine('注册表标识符校验报告  ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
$sw.WriteLine('unitTypes 目录: ' + $utDirs.Count + '   定义类型: ' + $defined.Count + '   UnitType 引用: ' + $refCnt)
$sw.WriteLine('')
if ($problems.Count -eq 0) {
    $sw.WriteLine('结论: 通过 — 未发现标识符被汉化或引用断裂。')
} else {
    $sw.WriteLine('发现 ' + $problems.Count + ' 个问题:')
    foreach ($p in $problems) { $sw.WriteLine('  ' + $p) }
}
$sw.Close()
Get-Content $out -Encoding UTF8 | ForEach-Object { Write-Host $_ }
Write-Host ('报告: ' + $out)
$severe = @($problems | Where-Object { $_ -like '[[]严重]*' })
if ($severe.Count -gt 0) { exit 1 } else { exit 0 }
