# uBlock Origin 安裝腳本 - 進階版
# 完整修正編碼、保護 Chrome 設定、支援更新
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
{
    Start-Process powershell.exe "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Write-Host "▶️ 開始安裝 uBlock Origin..." -ForegroundColor Cyan

# ===== 設定參數 =====
$version = "1.63.3b16"
$extensionFolder = "$env:LOCALAPPDATA\uBlock0.chromium"
$downloadUrl = "https://github.com/gorhill/uBlock/releases/download/$version/uBlock0_$version.chromium.zip"
$tempZipPath = "$env:TEMP\uBlock0.zip"
$localStatePath = "$env:LOCALAPPDATA\Google\Chrome\User Data\Local State"
$chromeFlags = "--enable-features=AllowLegacyExtensionManifestV2 --disable-features=ExtensionManifestV2DeprecationWarning,ExtensionManifestV2DeprecationDisabled,ExtensionManifestV2DeprecationUnsupported"

# ===== 輔助函式 =====
function Backup-File($filePath) {
    if (Test-Path $filePath) {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        Copy-Item $filePath "$filePath.bak_$timestamp"
        Write-Host "📦 備份完成：$filePath.bak_$timestamp" -ForegroundColor Green
    }
}

function Safe-WriteJson($data, $filePath) {
    $json | ConvertTo-Json -Depth 100 | Set-Content -Path $localStatePath -Encoding UTF8

}

# ===== 安裝擴充功能 =====
if (-not (Test-Path $extensionFolder)) {
    Write-Host "⬇️ 下載 uBlock Origin..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $downloadUrl -OutFile $tempZipPath -UseBasicParsing

    Write-Host "📂 解壓縮中..." -ForegroundColor Yellow
    Expand-Archive -LiteralPath $tempZipPath -DestinationPath $env:LOCALAPPDATA -Force
    Remove-Item $tempZipPath -Force
}

# 確認 manifest.json
$manifestPath = Join-Path $extensionFolder "manifest.json"
if (-not (Test-Path $manifestPath)) {
    Write-Host "❌ 無法找到 manifest.json，安裝失敗" -ForegroundColor Red
    exit
}

$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
$extensionId = if ($manifest.PSObject.Properties.Name -contains 'key' -and $manifest.key) { $manifest.key } else { $manifest.version }


# ===== 更新註冊表強制安裝 =====
$regPath = "HKLM:\Software\Policies\Google\Chrome\ExtensionInstallForcelist"
if (-not (Test-Path $regPath)) {
    New-Item -Path $regPath -Force | Out-Null
}

Set-ItemProperty -Path $regPath -Name "1" -Value "$extensionId;file:///$($extensionFolder.Replace('\','/'))" -Force
Write-Host "🔗 已設定 Chrome 強制安裝擴充功能" -ForegroundColor Green

# ===== 修改 Local State 啟用實驗旗標 =====
if (Test-Path $localStatePath) {
    Write-Host "🛡️ 修改 Chrome Local State..." -ForegroundColor Yellow

    Backup-File $localStatePath

    try {
        $localState = Get-Content $localStatePath -Raw | ConvertFrom-Json

        if (-not $localState.browser) {
            $localState | Add-Member -MemberType NoteProperty -Name "browser" -Value @{}
        }
        if (-not $localState.browser.enabled_labs_experiments) {
            $localState.browser | Add-Member -MemberType NoteProperty -Name "enabled_labs_experiments" -Value @()
        }

        $flagsToEnable = @(
            "allow-legacy-mv2-extensions"
        )
        $flagsToDisable = @(
            "extension-manifest-v2-deprecation-warning@2",
            "extension-manifest-v2-deprecation-disabled@2",
            "extension-manifest-v2-deprecation-unsupported@2"
        )

        # 移除舊旗標
        $localState.browser.enabled_labs_experiments = $localState.browser.enabled_labs_experiments | Where-Object {
            ($_ -notin $flagsToEnable) -and
            ($_ -notmatch '^extension-manifest-v2-deprecation')
        }

        # 新增新旗標
        $localState.browser.enabled_labs_experiments += $flagsToEnable + $flagsToDisable
        $localState.browser.enabled_labs_experiments = $localState.browser.enabled_labs_experiments | Sort-Object -Unique

        # 寫回檔案（使用正確 UTF-8 無 BOM）
        Safe-WriteJson $localState $localStatePath

        Write-Host "✅ Local State 更新完成" -ForegroundColor Green
    }
    catch {
        Write-Host "⚠️ Local State 修改失敗: $_" -ForegroundColor Red
    }
}

# ===== 更新快捷方式加上參數 =====
$shortcutPaths = @(
    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Google Chrome.lnk",
    "$env:PUBLIC\Desktop\Google Chrome.lnk",
    "$env:USERPROFILE\Desktop\Google Chrome.lnk"
)

foreach ($shortcutPath in $shortcutPaths) {
    if (Test-Path $shortcutPath) {
        Write-Host "🖱️ 更新 Chrome 快捷方式..." -ForegroundColor Yellow
        try {
            $wsh = New-Object -ComObject WScript.Shell
            $shortcut = $wsh.CreateShortcut($shortcutPath)

            if ($shortcut.Arguments -notmatch "AllowLegacyExtensionManifestV2") {
                $shortcut.Arguments = "$($shortcut.Arguments) $chromeFlags".Trim()
                $shortcut.Save()
                Write-Host "🛠️ 快捷方式已更新" -ForegroundColor Green
            }
        }
        catch {
            Write-Host "⚠️ 快捷方式更新失敗: $_" -ForegroundColor Red
        }
    }
}

# ===== 重啟 Chrome =====
$chromeExePaths = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe"
)

$chromeExe = $chromeExePaths | Where-Object { Test-Path $_ } | Select-Object -First 1

Write-Host "🚪 關閉 Chrome..." -ForegroundColor Yellow
Stop-Process -Name chrome -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

if ($chromeExe) {
    Write-Host "🚀 啟動 Chrome 和 uBlock Origin..." -ForegroundColor Green
    Start-Process $chromeExe -ArgumentList "--load-extension=`"$extensionFolder`" $chromeFlags"
} else {
    Write-Host "❗ 找不到 Chrome，請手動開啟" -ForegroundColor Red
}

Write-Host "🎉 uBlock Origin 安裝完成！" -ForegroundColor Cyan
pause
