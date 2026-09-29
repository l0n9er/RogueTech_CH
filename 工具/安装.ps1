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
function Step($n, $m) { Write-Host ""; Write-Host ("[" + $n + "/9] " + $m) }
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

# ---------- 3) 汉化 DLL ----------
# 这些 DLL 出自月光石头的《BATTLETECH 汉化工具》，通过反编译修改硬编码
# 字符串实现界面汉化。包内按原始相对路径存放，逐个体替换。
Step 3 "写入汉化 DLL（界面文字）"
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
$dllCnt = 0
$dllSkip = 0
foreach ($rel in $dllList) {
    $s = Join-Path $packRoot $rel
    $d = Join-Path $gameRoot $rel
    if (BackupAndCopy $s $d $rel) { $dllCnt++ } else { $dllSkip++ }
}
if ($dllSkip -gt 0) { Warn ("有 " + $dllSkip + " 个 DLL 包内缺失，已跳过") }
Ok ("已写入 " + $dllCnt + " 个 DLL")

# ---------- 4) 清理遗留备份 ----------
# MechAffinity 会把自己目录下的所有文件都当作定义加载，.zhbak 会导致
# 定义重复、键冲突，进而读档失败，必须移出游戏目录。
Step 4 "清理遗留的 .zhbak 备份"
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

# ---------- 5) 数据字段汉化 ----------
Step 5 "汉化数据字段（Details / YangsThoughts / StockRole）"
RunTool 'fold-apply.ps1' @('-mods', (Join-Path $gameRoot 'Mods'),
                           '-pairs', (Join-Path $PSScriptRoot 'dict-all.tsv'),
                           '-csv', (Join-Path $packRoot 'strings_zh-CN.csv'),
                           '-backupRoot', (Join-Path $packRoot 'backup\Mods-defs'))
Ok "完成"

# ---------- 6) 装备分类显示名 ----------
Step 6 "汉化装备分类显示名"
RunTool 'apply-category-zh.ps1' @('-gameRoot', $gameRoot)
Ok "完成"

# ---------- 7) 控制字符与标点空格 ----------
Step 7 "清理控制字符、标点空格与插值占位符"
RunTool 'fix-ctl.ps1' @('-gameRoot', $gameRoot) | Out-Null
RunTool 'cleanup.ps1' @('-gameRoot', $gameRoot) | Out-Null
# [[OBJ ， {OBJ.Field}]] 里的全角逗号会让游戏报 INVALID ALIAS 并显示"错误"
RunTool 'fix-interp-punct.ps1' @('-csv', $csvDst)
Ok "完成"

# ---------- 8) 术语归一化与格式修复 ----------
Step 8 "术语归一化与格式修复"
RunTool 'apply-norm.ps1' @('-mods', (Join-Path $gameRoot 'Mods'),
                           '-backupRoot', (Join-Path $packRoot 'backup\Mods-norm'))
RunTool 'norm-csv.ps1' @('-csv', $csvDst)
Ok "完成"

# ---------- 9) 校验 ----------
Step 9 "校验"
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
