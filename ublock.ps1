# 確認管理員權限
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
    [Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Start-Process powershell "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# 設定網址與路徑
$downloadUrl = "https://github.com/gorhill/uBlock/releases/download/1.63.3b16/uBlock0_1.63.3b16.chromium.zip"
$tempFolder = "$env:TEMP\uBlock0"
$zipPath = "$tempFolder.zip"
$extensionFolder = Join-Path $tempFolder "uBlock0.chromium"

# 清除舊資料
if (Test-Path $tempFolder) { Remove-Item $tempFolder -Recurse -Force }
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

# 下載 uBlock
Write-Host "正在下載 uBlock Origin..." -ForegroundColor Yellow
Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath

# 解壓縮
Expand-Archive -LiteralPath $zipPath -DestinationPath $tempFolder

# 確認資料夾存在
if (-not (Test-Path $extensionFolder)) {
    Write-Host "找不到 uBlock0.chromium 資料夾！" -ForegroundColor Red
    exit
}

# 關閉 Chrome
Get-Process chrome -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

# 定位 Chrome 執行檔
$chromePath = "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"
$chromePathX86 = "$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe"

if (Test-Path $chromePath) {
    $chromeExe = $chromePath
} elseif (Test-Path $chromePathX86) {
    $chromeExe = $chromePathX86
} else {
    Write-Host "找不到 Chrome！" -ForegroundColor Red
    exit
}

# 啟動 Chrome，套用 flags 與載入 extension
Start-Process $chromeExe -ArgumentList @(
    "--load-extension=`"$extensionFolder`"",
    "--flag-switches-begin",
    "--enable-features=AllowLegacyExtensionManifestV2",
    "--disable-features=ExtensionManifestV2DeprecationWarning,ExtensionManifestV2DeprecationDisabled,ExtensionManifestV2DeprecationUnsupported",
    "--flag-switches-end"
)

Write-Host "✅ Chrome 已啟動，uBlock 已安裝，MV2 已啟用且警告已關閉！" -ForegroundColor Green
