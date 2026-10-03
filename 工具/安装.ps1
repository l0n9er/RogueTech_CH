param(
    [string]$gameRoot = ""
)
$ErrorActionPreference = 'Stop'
$enc = New-Object Text.UTF8Encoding $false

# 控制台输出编码: PS 5.1 默认按控制台当前代码页输出中文, 若与窗口代码页
# 不一致会乱码。这里显式采用系统默认(GBK/936), 与 安装.bat 的 chcp 936 一致。
try {
    $cp = [Console]::OutputEncoding.CodePage
    if ($cp -ne 936 -and $cp -ne 65001) {
        [Console]::OutputEncoding = [Text.Encoding]::GetEncoding(936)
    }
} catch { }

function Say($m)  { Write-Host $m }
function Step($n, $m) { Write-Host ""; Write-Host ("[" + $n + "/20] " + $m) }
function Ok($m)   { Write-Host ("      " + $m) }
function Warn($m) { Write-Host ("      警告: " + $m) -ForegroundColor Yellow }

# ---------- 定位游戏目录 ----------
$userSpecified = -not [string]::IsNullOrWhiteSpace($gameRoot)
if (-not $userSpecified) {
    # 未指定时: 自动探测(启动器配置 / Steam 注册表 / 常见安装位置)
    $gameRoot = & (Join-Path $PSScriptRoot 'find-game.ps1')
    if ([string]::IsNullOrWhiteSpace($gameRoot)) {
        Write-Host ""
        Write-Host " 找不到游戏目录（未找到 BattleTech.exe）。" -ForegroundColor Yellow
        Write-Host " 请用 -gameRoot 参数指定游戏安装路径，例如：" -ForegroundColor Yellow
        Write-Host '   powershell -File "工具\安装.ps1" -gameRoot "E:\Steam\steamapps\common\BATTLETECH"' -ForegroundColor Yellow
        Write-Host ""
        exit 1
    }
} else {
    # 用户明确指定: 校验不通过就直接报错, 不回退(避免静默装到别处)
    if (-not [IO.File]::Exists((Join-Path $gameRoot "BattleTech.exe"))) {
        Write-Host ""
        Write-Host (" 指定的游戏目录无效（未找到 BattleTech.exe）: " + $gameRoot) -ForegroundColor Yellow
        Write-Host ""
        exit 1
    }
}

Say "================================================"
Say " BATTLETECH / RogueTech 简体中文补丁 安装"
Say "================================================"
Say (" 游戏目录: " + $gameRoot)

# ---------- 游戏运行中则拒绝 ----------
$proc = Get-Process -Name BattleTech -ErrorAction SilentlyContinue
if ($proc) {
    Write-Host ""
    Write-Host (" 检测到游戏正在运行（PID " + $proc.Id + "）。") -ForegroundColor Yellow
    Write-Host " 请先完全退出游戏，再重新运行本安装。" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

$packRoot = Split-Path $PSScriptRoot -Parent
$stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$backupDir = Join-Path $packRoot ("backup\" + $stamp)
[void][IO.Directory]::CreateDirectory($backupDir)
Say (" 备份目录: backup\" + $stamp)

function BackupAndCopy($src, $dst, $label) {
    if (-not [IO.File]::Exists($src)) { Warn ("包内缺少文件，已跳过: " + $label); return $false }
    if ([IO.File]::Exists($dst)) {
        # 备份保留原目录结构(相对游戏根), 一键还原时直接按相对路径覆盖回去
        $rel = $dst.Substring($gameRoot.Length).TrimStart('\')
        $bak = Join-Path $backupDir $rel
        $bakParent = Split-Path $bak -Parent
        if (-not [IO.Directory]::Exists($bakParent)) { [void][IO.Directory]::CreateDirectory($bakParent) }
        [IO.File]::Copy($dst, $bak, $true)
    }
    $dir = Split-Path $dst -Parent
    if (-not [IO.Directory]::Exists($dir)) { [void][IO.Directory]::CreateDirectory($dir) }
    [IO.File]::Copy($src, $dst, $true)
    return $true
}

# 工具脚本统一调用方式(带失败提示，不中断整体安装)
function RunTool($script, $extraArgs) {
    $sp = Join-Path $PSScriptRoot $script
    if (-not (Test-Path $sp)) { Warn ($script + " 不存在，已跳过"); return }
    $arg = @('-NoProfile','-ExecutionPolicy','Bypass','-File', $sp) + $extraArgs
    & powershell @arg
    if ($LASTEXITCODE -ne 0) { Warn ($script + " 返回码 " + $LASTEXITCODE) }
}

# ---------- 1) 翻译总表 ----------
Step 1 "写入翻译总表"
$csvName = "strings_zh-CN.csv"
$csvDst = Join-Path $gameRoot "BattleTech_Data\StreamingAssets\data\localization\$csvName"
if (BackupAndCopy (Join-Path $packRoot $csvName) $csvDst "翻译总表") {
    $n = ([IO.File]::ReadAllText($csvDst, [Text.Encoding]::UTF8) -split "`r`n").Count
    Ok ("已写入，" + $n + " 行")
}

# ---------- 2) 亲和数据 ----------
Step 2 "写入 MechAffinity 亲和数据"
$affSrc = Join-Path $packRoot "Mods\Core\MechAffinity\AffinityDefs"
if ([IO.Directory]::Exists($affSrc)) {
    $cnt = 0
    foreach ($f in [IO.Directory]::GetFiles($affSrc, "*.json")) {
        $dst = Join-Path $gameRoot ("Mods\Core\MechAffinity\AffinityDefs\" + [IO.Path]::GetFileName($f))
        if (BackupAndCopy $f $dst "亲和数据") { $cnt++ }
    }
    Ok ("" + $cnt + " 个文件")
} else { Warn "包内缺少亲和数据目录，已跳过" }

# ---------- 3) 本地化表与其余模组数据 ----------
# 包内 Mods\ 下还有各模组的 Localization.json（CULTURE_ZH_CN 译文）与
# CustomLocalization 的 mod.json 等数据文件。这些译文只存在于包内 ——
# 安装脚本的词典（dict-all.tsv）不带它们：fold-apply 只处理
# Details/YangsThoughts/StockRole 三种字段，且显式排除 Localization 目录。
# 若不复制，界面里的一大批装备、技能、背景说明仍会是英文。
# DLL 由下一步按固定清单处理，这里跳过 *.dll 避免重复写入。
Step 3 "写入模组本地化表与数据文件"
$dataSrc = Join-Path $packRoot "Mods"
$dataCnt = 0
$dataSkip = 0
if ([IO.Directory]::Exists($dataSrc)) {
    foreach ($f in [IO.Directory]::GetFiles($dataSrc, "*", [IO.SearchOption]::AllDirectories)) {
        $rel = $f.Substring($dataSrc.Length).TrimStart('\')
        if ($rel -like "*.dll") { continue }
        $dst = Join-Path $gameRoot ("Mods\" + $rel)
        if (BackupAndCopy $f $dst $rel) { $dataCnt++ } else { $dataSkip++ }
    }
    if ($dataSkip -gt 0) { Warn ("有 " + $dataSkip + " 个数据文件写入失败，已跳过") }
    Ok ("" + $dataCnt + " 个文件")
} else { Warn "包内缺少 Mods 目录，已跳过" }

# ---------- 4) 汉化 DLL ----------
# 这些 DLL 出自月光石头的《BATTLETECH 汉化工具》，通过反编译修改硬编码
# 字符串实现界面汉化。包内按原始相对路径存放，逐个体替换。
Step 4 "写入汉化 DLL（界面文字）"
$dllList = @(
    'BattleTech_Data\Managed\Assembly-CSharp.dll',
    'BattleTech_Data\Managed\battletech_core.dll',
    'Mods\Core\Abilifier\Abilifier.dll',
    'Mods\Core\CustomAmmoCategories\AttackImprovementMod.dll',
    'Mods\Core\CustomAmmoCategories\CustomAmmoCategories.dll',
    'Mods\Core\CustomAmmoCategories\CustomAmmoCategoriesHelper.dll',
    'Mods\Core\CustomAmmoCategories\CustomAmmoCategoriesPrivate.dll',
    'Mods\Core\CustomComponents\CustomComponents.dll',
    'Mods\Core\CustomFilters\CustomFilters.dll',
    'Mods\Core\CustomSalvage\CustomSalvage.dll',
    'Mods\Core\CustomUnits\CustomDeploy.dll',
    'Mods\Core\CustomUnits\CustomUnits.dll',
    'Mods\Core\CustomUnits\CustomUnitsHelper.dll',
    'Mods\Core\CustomUnits\NAudio.dll',
    'Mods\Core\DropCostsEnhanced\DropCostsEnhanced.dll',
    'Mods\Core\IRTweaks\IRTweaks.dll',
    'Mods\Core\IttyBittyLivingSpace\IttyBittyLivingSpace.dll',
    'Mods\Core\LootMagnet\LootMagnet.dll',
    'Mods\Core\MechAffinity\MechAffinity.dll',
    'Mods\Core\MechEngineer\MechEngineer.dll',
    'Mods\Core\PilotHealthPopup\PilotHealthPopup.dll',
    'Mods\Core\Pilot_Fatigue\Pilot_Fatigue.dll',
    'Mods\Core\StrategicOperations\StrategicOperations.dll',
    'Mods\Core\TisButAScratch\TisButAScratch.dll',
    'Mods\WarTechIIC\WarTechIIC.dll'
)
# 非 DLL 的汉化必需资源（不在 Mods\ 下，第 3 步覆盖不到）：
#   font                  —— Unity 资源包，中文字形字体，缺了中文会显示成方框
#   VersionManifest.csv   —— 游戏资源清单，登记资源加载
$assetList = @(
    'BattleTech_Data\StreamingAssets\font',
    'BattleTech_Data\StreamingAssets\data\VersionManifest.csv'
)
$dllCnt = 0
$dllSkip = 0
foreach ($rel in $dllList) {
    $s = Join-Path $packRoot $rel
    $d = Join-Path $gameRoot $rel
    if (BackupAndCopy $s $d $rel) { $dllCnt++ } else { $dllSkip++ }
}
if ($dllSkip -gt 0) { Warn ("有 " + $dllSkip + " 个 DLL 包内缺失，已跳过") }
Ok ("已写入 " + $dllCnt + " 个 DLL")

$assetCnt = 0
foreach ($rel in $assetList) {
    $s = Join-Path $packRoot $rel
    $d = Join-Path $gameRoot $rel
    if (BackupAndCopy $s $d $rel) { $assetCnt++ } else { Warn ("包内缺少资源，已跳过: " + $rel) }
}
Ok ("已写入 " + $assetCnt + " 个汉化资源（字体 / 资源清单）")

# ---------- 5) 清理遗留备份 ----------
# MechAffinity 会把自己目录下的所有文件都当作定义加载，.zhbak 会导致
# 定义重复、键冲突，进而读档失败，必须移出游戏目录。
Step 5 "清理遗留的 .zhbak 备份"
$zhs = @(Get-ChildItem (Join-Path $gameRoot "Mods") -Recurse -File -Force -ErrorAction SilentlyContinue |
         Where-Object { $_.Name -like "*.zhbak*" })
if ($zhs.Count -eq 0) { Ok "无遗留备份" }
else {
    foreach ($z in $zhs) {
        $rel = $z.FullName.Substring($gameRoot.Length).TrimStart("\")
        # 保留目录结构, 放到 backup\<时间戳>\zhbak\<相对路径> 下, 便于追溯
        $bak = Join-Path $backupDir ("zhbak\" + $rel)
        $bakParent = Split-Path $bak -Parent
        if (-not [IO.Directory]::Exists($bakParent)) { [void][IO.Directory]::CreateDirectory($bakParent) }
        [IO.File]::Move($z.FullName, $bak)
    }
    Ok ("已移出 " + $zhs.Count + " 个文件")
}

# ---------- 6) 禁用启动器安全检查 ----------
# RogueLauncher 启动游戏前会做哈希校验，把汉化过的文件判为 "file tamper
# detected" 并用缓存里的英文原版覆盖回 Mods（实测一次启动 7400+ 条），
# 汉化因此大面积失效。把 SafeLaunchDisabled 设为 true 可跳过该覆盖。
Step 6 "禁用 RogueTech 启动器的文件校验（防止汉化被覆盖）"
RunTool 'fix-launcher-safe.ps1' @('-backupRoot', $backupDir)
Ok "完成"

# ---------- 7) 数据字段汉化 ----------
Step 7 "汉化数据字段（Details / YangsThoughts / StockRole）"
RunTool 'fold-apply.ps1' @('-mods', (Join-Path $gameRoot 'Mods'),
                           '-pairs', (Join-Path $PSScriptRoot 'dict-all.tsv'),
                           '-csv', (Join-Path $packRoot 'strings_zh-CN.csv'),
                           '-backupRoot', (Join-Path $packRoot 'backup\Mods-defs'))
Ok "完成"

# ---------- 8) 装备特性说明汉化 ----------
# BonusDescriptions_*.json 的 Short/Long/Full 是装备"特性"栏的显示文本
Step 8 "补译装备特性说明（BonusDescriptions）"
RunTool 'apply-bonus.ps1' @('-dir', (Join-Path $gameRoot 'Mods'),
                            '-pairs', (Join-Path $PSScriptRoot 'dict-bonus.tsv'),
                            '-backupRoot', (Join-Path $packRoot 'backup\Mods-bonus'))
Ok "完成"

# ---------- 8b) 游戏本体 stat 说明模板汉化 ----------
# BattleTech_Data\StreamingAssets\data\simGameStatDesc\*.json 的 Result 模板
# 不查 CSV, 直接在 JSON 里显示, 必须就地替换
Step 9 "汉化游戏本体状态说明模板（simGameStatDesc）"
RunTool 'apply-statdesc.ps1' @('-game', $gameRoot,
                               '-pairs', (Join-Path $PSScriptRoot 'dict-statdesc.tsv'),
                               '-backupRoot', (Join-Path $packRoot 'backup\simGameStatDesc'))
# 模组自带的 SimGameStatDesc(Aircademy/IRTweaks/IttyBittyLivingSpace/
# MissionControl/RogueTechCore 等 40 余个) 同样不查 CSV, 里面的合约报酬、
# 声望变化、维护费用等结果模板同样是玩家可见文本。
$modStatDict = Join-Path $PSScriptRoot 'dict-statdesc-mod.tsv'
if ([IO.File]::Exists($modStatDict)) {
    RunTool 'apply-statdesc.ps1' @('-game', $gameRoot,
                                   '-pairs', $modStatDict,
                                   '-ModsOnly',
                                   '-backupRoot', (Join-Path $packRoot 'backup\simGameStatDesc-mod'))
}
Ok "完成"

# ---------- 9) 对话/字幕汉化 ----------
# 游戏对 dialogueContent[].words 不查 CSV, 直接显示 JSON 里的字符串,
# 必须就地替换(月光石头的本地化表虽有译文, 但源文件未被改写, 用不上)
Step 10 "汉化对话与字幕（words）"
RunTool 'apply-words.ps1' @('-mods', (Join-Path $gameRoot 'Mods'),
                            '-pairs', (Join-Path $PSScriptRoot 'dict-words.tsv'),
                            '-backupRoot', (Join-Path $packRoot 'backup\Mods-words'))
Ok "完成"

# ---------- 9b) 任务标题/描述/物品界面名/合约简报 ----------
# 这些字段同样不查 CSV(或查询优先级低), 一并就地补译
# shortDescription/longDescription 是合约简报正文, ShortDesc 是技能/AI 能力简述;
# 这三个字段曾被完全遗漏, 玩家在合约界面看到的是整段英文
Step 11 "补译任务标题、目标描述、物品界面名与合约简报"
foreach ($pair in @(
    @{ f = 'title';       d = 'dict-title.tsv' },
    @{ f = 'description'; d = 'dict-desc.tsv' },
    @{ f = 'UIName';      d = 'dict-uiname.tsv' },
    @{ f = 'shortDescription,longDescription,ShortDesc'; d = 'dict-brief.tsv' }
    @{ f = 'ErrorMessage'; d = 'dict-errmsg.tsv' }
)) {
    $dict = Join-Path $PSScriptRoot $pair.d
    if ([IO.File]::Exists($dict)) {
        RunTool 'apply-fields.ps1' @('-mods', (Join-Path $gameRoot 'Mods'),
                                     '-pairs', $dict,
                                     '-fields', $pair.f,
                                     '-backupRoot', (Join-Path $packRoot 'backup\Mods-fields'))
    }
}
# 个别模组 mod.json 的 description 是玩家可见的设置说明, 需 -IncludeModJson 放行
$descExtra = Join-Path $PSScriptRoot 'dict-desc-extra.tsv'
if ([IO.File]::Exists($descExtra)) {
    RunTool 'apply-fields.ps1' @('-mods', (Join-Path $gameRoot 'Mods'),
                                 '-pairs', $descExtra,
                                 '-fields', 'description',
                                 '-IncludeModJson',
                                 '-backupRoot', (Join-Path $packRoot 'backup\Mods-fields'))
}
Ok "完成"

# ---------- 9d) 模组本地化覆盖表（mod_localized_text.json） ----------
# 8 个模组用这个文件覆盖引擎文本(战斗浮动提示、菜单按钮、台词、光照面板)。
# 游戏先按英文原文查 CSV 挤兑键, 查不到就退回文件里的英文原值 —— 所以
# 既要补 CSV 缺的键, 也要把文件里的值就地改成中文(CodeWords 已全员中文,
# 证明这条通道有效)。数组项(战斗台词)一并处理。
Step 12 "汉化模组本地化覆盖表（mod_localized_text）"
$mtDict = Join-Path $PSScriptRoot 'dict-modtext.tsv'
if ([IO.File]::Exists($mtDict)) {
    RunTool 'apply-modtext.ps1' @('-mods', (Join-Path $gameRoot 'Mods'),
                                  '-pairs', $mtDict,
                                  '-backupRoot', (Join-Path $packRoot 'backup\Mods-modtext'))
}
Ok "完成"

# ---------- 9e) IRTweaks / CustomFilters 菜单 ----------
# IRTweaks 的难度设置菜单与 CustomFilters 的库存页签: 这些文件的
# Name/Tooltip/Text/Caption 直接显示。字段名在别处可能是内部标识符或
# 匹配键, 所以用 -pathLike 把处理范围压到这两个模组的菜单文件。
Step 13 "汉化难度设置菜单与库存页签"
$menuDict = Join-Path $PSScriptRoot 'dict-menus.tsv'
if ([IO.File]::Exists($menuDict)) {
    RunTool 'apply-fields.ps1' @('-mods', (Join-Path $gameRoot 'Mods'),
                                 '-pairs', $menuDict,
                                 '-fields', 'Name,Tooltip,Text,Caption',
                                 '-pathLike', 'IRTweaks\Menus,CustomFilters\RogueTechTabs.json',
                                 '-backupRoot', (Join-Path $packRoot 'backup\Mods-menus'))
}
Ok "完成"
# ---------- 9f) MechEngineer 部位命名模板 ----------
# Settings.json 的 MechLocationNamingTemplates 决定步兵/原型机甲/机甲小队/
# VTOL/四足机甲等特殊单位在机甲实验室里各部位的显示名(如 "Trooper 5")。
Step 14 "汉化特殊单位部位显示名"
$locDict = Join-Path $PSScriptRoot 'dict-locnames.tsv'
if ([IO.File]::Exists($locDict)) {
    RunTool 'apply-fields.ps1' @('-mods', (Join-Path $gameRoot 'Mods'),
                                 '-pairs', $locDict,
                                 '-fields', 'Label',
                                 '-pathLike', 'MechEngineer\Settings.json',
                                 '-backupRoot', (Join-Path $packRoot 'backup\Mods-locnames'))
}
# 战斗中"臂装精度加成"在提示里的显示名(WEAPON MOUNT)
$mechFixDict = Join-Path $PSScriptRoot 'dict-mechfix.tsv'
if ([IO.File]::Exists($mechFixDict)) {
    RunTool 'apply-fields.ps1' @('-mods', (Join-Path $gameRoot 'Mods'),
                                 '-pairs', $mechFixDict,
                                 '-fields', 'CombatHUDTooltipName',
                                 '-pathLike', 'MechEngineer\Settings.json',
                                 '-backupRoot', (Join-Path $packRoot 'backup\Mods-mechfix'))
}
# CustomFilters 的库存筛选标签: 只有 DLC / +Blacklisted 两条英文
$cfDict = Join-Path $PSScriptRoot 'dict-cf.tsv'
if ([IO.File]::Exists($cfDict)) {
    RunTool 'apply-fields.ps1' @('-mods', (Join-Path $gameRoot 'Mods'),
                                 '-pairs', $cfDict,
                                 '-fields', 'Label',
                                 '-pathLike', 'CustomFilters\Settings.json',
                                 '-backupRoot', (Join-Path $packRoot 'backup\Mods-cf'))
}
Ok "完成"

# ---------- 9g) 角色创建背景与合约结束评价 ----------
# RogueBackgrounds 的 OptionName/OptionDescription/Intro 是角色创建界面里
# 背景选项的标题与说明; 各派系 faction_*.json 的 MissionSuccessStatement /
# GoodFaithFailureStatement / BadFaithFailureStatement 是任务结束时雇主对
# 你的评价。两类都是直接显示 JSON 里的字符串。
# 译文取自各模组 Localization/ZH 表(已是 JSON 转义形式, 含 0x1F 占位符),
# 所以用 -JsonValue 避免二次转义。
Step 15 "汉化角色背景与合约评价"
$bgDict = Join-Path $PSScriptRoot 'dict-bg.tsv'
if ([IO.File]::Exists($bgDict)) {
    RunTool 'apply-fields.ps1' @('-mods', (Join-Path $gameRoot 'Mods'),
                                 '-pairs', $bgDict,
                                 '-fields', 'OptionName,OptionDescription,Intro,MissionSuccessStatement,GoodFaithFailureStatement,BadFaithFailureStatement',
                                 '-pathLike', 'RogueBackgrounds,RogueTechCore\Factions',
                                 '-JsonValue',
                                 '-backupRoot', (Join-Path $packRoot 'backup\Mods-bg'))
}
Ok "完成"
# Quirk_*.json 的 Description.Name 是显示名(装备特性栏), 包内不含这些定义
# 文件, 只能靠词典在目标机应用。Name 字段在别处可能是内部标识符, 所以
# 限定只处理 Quirks 目录下的文件。
Step 16 "补译 Quirk 特性显示名"
$quirkDict = Join-Path $PSScriptRoot 'dict-quirk.tsv'
if ([IO.File]::Exists($quirkDict)) {
    RunTool 'apply-quirk.ps1' @('-mods', (Join-Path $gameRoot 'Mods'),
                                '-pairs', $quirkDict,
                                '-backupRoot', (Join-Path $packRoot 'backup\Mods-quirk'))
}
Ok "完成"

# ---------- 10) 装备分类显示名 ----------
Step 17 "汉化装备分类显示名"
RunTool 'apply-category-zh.ps1' @('-gameRoot', $gameRoot)
Ok "完成"

# ---------- 11) 控制字符与标点空格 ----------
Step 18 "清理控制字符、标点空格与插值占位符"
RunTool 'fix-ctl.ps1' @('-gameRoot', $gameRoot) | Out-Null
RunTool 'cleanup.ps1' @('-gameRoot', $gameRoot) | Out-Null
# [[OBJ ， {OBJ.Field}]] 里的全角逗号会让游戏报 INVALID ALIAS 并显示"错误"
RunTool 'fix-interp-punct.ps1' @('-csv', $csvDst)
Ok "完成"

# ---------- 11) 术语归一化与格式修复 ----------
Step 19 "术语归一化与格式修复"
RunTool 'apply-norm.ps1' @('-mods', (Join-Path $gameRoot 'Mods'),
                           '-backupRoot', (Join-Path $packRoot 'backup\Mods-norm'))
RunTool 'norm-csv.ps1' @('-csv', $csvDst)
Ok "完成"

# ---------- 12) 校验 ----------
Step 20 "校验"
$zhs2 = @(Get-ChildItem (Join-Path $gameRoot "Mods") -Recurse -File -Force -ErrorAction SilentlyContinue |
          Where-Object { $_.Name -like "*.zhbak*" })
if ($zhs2.Count -gt 0) { Warn ("仍有 " + $zhs2.Count + " 个 .zhbak 留在 Mods 下") }
else { Ok "Mods 下无遗留备份文件" }
$csvLine = ([IO.File]::ReadAllText($csvDst, [Text.Encoding]::UTF8) -split "`r`n").Count
Ok ("翻译总表: " + $csvLine + " 行")

# 注册表标识符校验: 单位类型名(UnitTypes_*.json 的 Name)是内部标识符, 绝不能被汉化
# 一旦被译成中文(如 Quad -> 四足), 四足机甲的槽位限制会失效, 报
# "过量 足部驱动器: 该单位在 左臂 中最多只能安装 0 个 / QuadIncompatible 无法与 四足机甲 搭配使用"
# check-registry 发现问题会自动按基线还原(所以这里只提示, 不中断)
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'check-registry.ps1') -mods (Join-Path $gameRoot 'Mods')
if ($LASTEXITCODE -ne 0) {
    Warn "检测到标识符被汉化（已自动还原），详见 backup\registry-check.txt"
} else { Ok "注册表标识符正常" }

Say ""
Say "================================================"
Say " 安装完成，请重新启动游戏。"
Say (" 如需回滚，备份在: backup\" + $stamp)
Say "================================================"
