# 重新打包发布 zip（排除 .git / backup / 自身）
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$packRoot = Split-Path $PSScriptRoot -Parent
# 文件名带日期+时间后缀(精确到分), 便于区分版本; 旧包一并清掉, 只保留最新一个
$stamp = (Get-Date).ToString('yyyyMMdd-HHmm')
$zip = Join-Path $packRoot ('RT汉化包_' + $stamp + '.zip')

# 需要排除的目录（相对包根）
$excludeDirs = @('.git', 'backup')

# 清掉所有历史包(含无后缀的旧命名), 避免目录里堆积
Get-ChildItem $packRoot -Filter 'RT汉化包*.zip' -File -ErrorAction SilentlyContinue | Remove-Item -Force

$files = Get-ChildItem $packRoot -Recurse -File -Force | Where-Object {
    $rel = $_.FullName.Substring($packRoot.Length).TrimStart('\')
    if ($rel -like 'RT汉化包*.zip') { return $false }
    foreach ($d in $excludeDirs) {
        if ($rel -eq $d -or $rel.StartsWith($d + '\')) { return $false }
    }
    # 排除 .zhbak / 临时产物
    if ($_.Name -like '*.zhbak*') { return $false }
    return $true
}

Write-Host ("待打包文件数: " + $files.Count)
$total = ($files | Measure-Object -Property Length -Sum).Sum
Write-Host ("原始大小: " + [Math]::Round($total/1MB,1) + " MB")

$archive = [System.IO.Compression.ZipFile]::Open($zip, 'Create')
try {
    $n = 0
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($packRoot.Length).TrimStart('\')
        $entryName = $rel -replace '\\', '/'
        $entry = $archive.CreateEntry($entryName, [System.IO.Compression.CompressionLevel]::Optimal)
        $es = $entry.Open()
        $fs = [IO.File]::OpenRead($f.FullName)
        try { $fs.CopyTo($es) } finally { $fs.Close(); $es.Close() }
        $n++
        if ($n % 100 -eq 0) { Write-Host ("  " + $n + " ...") }
    }
} finally { $archive.Dispose() }

$zi = Get-Item $zip
Write-Host ("完成: " + $zi.Name + "  " + [Math]::Round($zi.Length/1MB,1) + " MB  " + $n + " 个文件")
