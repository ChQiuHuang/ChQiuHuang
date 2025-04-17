# uBlock Origin 安裝腳本 - 兼容 IEX 調用
# 解決中文編碼問題


Write-Host "正在安裝 uBlock Origin..." -ForegroundColor Cyan

# 設定常數
$version = "1.63.3b16"
$extensionFolder = "$env:LOCALAPPDATA\uBlock0.chromium"
$downloadUrl = "https://github.com/gorhill/uBlock/releases/download/$version/uBlock0_$version.chromium.zip"
$zipPath = "$env:TEMP\uBlock0.zip"

# 下載並解壓 uBlock Origin
Write-Host "正在下載 uBlock Origin..." -ForegroundColor Yellow
if (-not (Test-Path $extensionFolder)) {
    Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing
    Write-Host "正在解壓..." -ForegroundColor Yellow
    Expand-Archive -LiteralPath $zipPath -DestinationPath $env:LOCALAPPDATA -Force
    Remove-Item $zipPath -Force
}

# 獲取擴充功能 ID
$manifestPath = "$extensionFolder\manifest.json"
if (-not (Test-Path $manifestPath)) {
    Write-Host "無法找到 manifest.json" -ForegroundColor Red
    exit
}
$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
$extensionId = if ($manifest.id) { $manifest.id } else { $manifest.version }

# 設定 Chrome 的擴充功能強制安裝政策
$regPath = "HKLM:\Software\Policies\Google\Chrome\ExtensionInstallForcelist"
if (-not (Test-Path $regPath)) {
    New-Item -Path $regPath -Force | Out-Null
    Write-Host "已建立 Chrome 政策註冊表項目" -ForegroundColor Green
}

# 在註冊表中加入強制安裝的擴充功能
Set-ItemProperty -Path $regPath -Name "1" -Value "$extensionId;file:///$($extensionFolder.Replace('\','/'))" -Force
Write-Host "已設定強制安裝擴充功能政策" -ForegroundColor Green

# 設定 Chrome 實驗性功能旗標
$localStatePath = "$env:LOCALAPPDATA\Google\Chrome\User Data\Local State"
if (Test-Path $localStatePath) {
    Write-Host "更新 Chrome 實驗性功能旗標..." -ForegroundColor Yellow
    
    try {
        # 讀取 Local State 檔案
        $json = Get-Content $localStatePath -Raw | ConvertFrom-Json
        
        # 確保必要的屬性存在
        if (-not $json.browser) {
            $json | Add-Member -MemberType NoteProperty -Name "browser" -Value @{}
        }
        if (-not $json.browser.enabled_labs_experiments) {
            $json.browser | Add-Member -MemberType NoteProperty -Name "enabled_labs_experiments" -Value @()
        }
        
        # 要啟用的旗標
        $flagsToEnable = @(
            "allow-legacy-mv2-extensions"   # 啟用舊版 Manifest V2 擴充
        )
        
        # 要禁用的旗標
        $flagsToDisable = @(
            "extension-manifest-v2-deprecation-warning@2",
            "extension-manifest-v2-deprecation-disabled@2",
            "extension-manifest-v2-deprecation-unsupported@2"
        )
        
        # 更新旗標列表
        $existingFlags = $json.browser.enabled_labs_experiments
        
        # 移除可能存在的衝突旗標
        foreach ($flag in $flagsToEnable) {
            $existingFlags = $existingFlags | Where-Object { $_ -notmatch "^$flag(@.*)?$" }
        }
        foreach ($flag in $flagsToDisable) {
            $baseFlag = $flag.Split("@")[0]
            $existingFlags = $existingFlags | Where-Object { $_ -notmatch "^$baseFlag(@.*)?$" }
        }
        
        # 添加新旗標
        $existingFlags += $flagsToEnable
        $existingFlags += $flagsToDisable
        $json.browser.enabled_labs_experiments = $existingFlags | Sort-Object -Unique
        
        # 儲存更新後的 Local State 檔案
        $json | ConvertTo-Json -Depth 100 | Set-Content -Path $localStatePath
        Write-Host "Chrome 實驗旗標設定完成" -ForegroundColor Green
    }
    catch {
        Write-Host "處理 Local State 文件時發生錯誤: $_" -ForegroundColor Red
    }
}

# 設定 Chrome 快捷方式的啟動參數
$possibleShortcutPaths = @(
    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Google Chrome.lnk",
    "$env:PUBLIC\Desktop\Google Chrome.lnk",
    "$env:USERPROFILE\Desktop\Google Chrome.lnk"
)

$shortcutUpdated = $false
foreach ($chromeShortcutPath in $possibleShortcutPaths) {
    if (Test-Path $chromeShortcutPath) {
        Write-Host "更新 Chrome 快捷方式..." -ForegroundColor Yellow
        $chromeFlags = "--enable-features=AllowLegacyExtensionManifestV2 --disable-features=ExtensionManifestV2DeprecationWarning,ExtensionManifestV2DeprecationDisabled,ExtensionManifestV2DeprecationUnsupported"
        
        try {
            $wsh = New-Object -ComObject WScript.Shell
            $shortcut = $wsh.CreateShortcut($chromeShortcutPath)
            $originalArgs = $shortcut.Arguments
            
            # 保留原有參數並添加新的參數
            if ($originalArgs -notmatch "AllowLegacyExtensionManifestV2") {
                $shortcut.Arguments = "$originalArgs $chromeFlags".Trim()
                $shortcut.Save()
                $shortcutUpdated = $true
                Write-Host "已更新快捷方式" -ForegroundColor Green
            }
        }
        catch {
            Write-Host "更新快捷方式時發生錯誤: $_" -ForegroundColor Red
        }
    }
}

# 找出 Chrome 安裝路徑
$chromePaths = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe"
)

$chromePath = $null
foreach ($path in $chromePaths) {
    if (Test-Path $path) {
        $chromePath = $path
        break
    }
}

if ($null -eq $chromePath) {
    $chromePath = (Get-Command "chrome.exe" -ErrorAction SilentlyContinue).Source
}

# 重啟 Chrome
Write-Host "正在關閉所有 Chrome 程序..." -ForegroundColor Yellow
Stop-Process -Name chrome -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

if ($chromePath) {
    Write-Host "啟動 Chrome 與 uBlock Origin..." -ForegroundColor Green
    $launchArgs = "--load-extension=`"$extensionFolder`" --enable-features=AllowLegacyExtensionManifestV2 --disable-features=ExtensionManifestV2DeprecationWarning,ExtensionManifestV2DeprecationDisabled,ExtensionManifestV2DeprecationUnsupported"
    Start-Process $chromePath -ArgumentList $launchArgs
} else {
    Write-Host "無法找到 Chrome 執行檔，請手動啟動 Chrome" -ForegroundColor Red
}

Write-Host "`nuBlock Origin 安裝完成！" -ForegroundColor Green
Write-Host "若 Chrome 有更新，可能需要重新執行此腳本" -ForegroundColor Yellow
pause
