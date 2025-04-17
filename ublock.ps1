# 確保使用者是以管理員身份執行
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "正在以管理員身份重新啟動..." -ForegroundColor Yellow
    Start-Process powershell "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# 設定常數
$version = "1.63.3b16"
$extensionFolder = "$env:LOCALAPPDATA\uBlock0.chromium"
$downloadUrl = "https://github.com/gorhill/uBlock/releases/download/$version/uBlock0_$version.chromium.zip"
$zipPath = "$env:TEMP\uBlock0.zip"

# 下載並解壓 uBlock Origin
Write-Host "正在下載 uBlock Origin..." -ForegroundColor Yellow
if (-not (Test-Path $extensionFolder)) {
    Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath
    Write-Host "正在解壓..." -ForegroundColor Yellow
    Expand-Archive -LiteralPath $zipPath -DestinationPath $env:LOCALAPPDATA -Force
    Remove-Item $zipPath -Force
}

# 獲取擴充功能 ID (從 manifest.json)
$manifestPath = "$extensionFolder\manifest.json"
if (-not (Test-Path $manifestPath)) {
    Write-Host "無法找到 manifest.json，請確認擴充功能是否正確解壓。" -ForegroundColor Red
    exit
}
$manifest = Get-Content $manifestPath -Encoding UTF8 | ConvertFrom-Json
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

# 找出所有 Chrome 配置目錄
Write-Host "尋找 Chrome 用戶配置..." -ForegroundColor Yellow
$chromeUserDataPath = "$env:LOCALAPPDATA\Google\Chrome\User Data"
$defaultProfiles = @("Default", "Profile 1", "Profile 2", "Profile 3")
$profileDirs = @()

# 檢查默認配置文件
foreach ($profile in $defaultProfiles) {
    $profilePath = Join-Path -Path $chromeUserDataPath -ChildPath $profile
    if (Test-Path $profilePath) {
        $profileDirs += $profilePath
    }
}

# 檢查所有自定義配置文件
if (Test-Path $chromeUserDataPath) {
    Get-ChildItem -Path $chromeUserDataPath -Directory | ForEach-Object {
        if ($_.Name -notmatch '^(Default|Profile \d+|System Profile|Guest Profile|.+Cache.*)$' -and 
            $_.Name -notmatch '^(Crashpad|GrShaderCache|ShaderCache)$') {
            $profileDirs += $_.FullName
        }
    }
}

# 設定每個配置文件的 Local State 檔案
foreach ($profileDir in $profileDirs) {
    $localStatePath = "$chromeUserDataPath\Local State"
    
    if (Test-Path $localStatePath) {
        Write-Host "更新 Chrome 實驗性功能旗標 (適用於所有配置)..." -ForegroundColor Yellow
        
        try {
            # 讀取 Local State 檔案
            $json = Get-Content $localStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
            
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
            $json | ConvertTo-Json -Depth 100 | Set-Content -Path $localStatePath -Encoding UTF8
            Write-Host "Chrome 全局實驗旗標設定完成！" -ForegroundColor Green
        }
        catch {
            Write-Host "處理 Local State 文件時發生錯誤: $_" -ForegroundColor Red
        }
        break  # 只需要處理一次 Local State 文件，它是全局的
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
        Write-Host "更新 Chrome 快捷方式 ($chromeShortcutPath)..." -ForegroundColor Yellow
        $chromeFlags = "--enable-features=AllowLegacyExtensionManifestV2 --disable-features=ExtensionManifestV2DeprecationWarning,ExtensionManifestV2DeprecationDisabled,ExtensionManifestV2DeprecationUnsupported"
        
        try {
            $wsh = New-Object -ComObject WScript.Shell
            $shortcut = $wsh.CreateShortcut($chromeShortcutPath)
            $targetPath = $shortcut.TargetPath
            $originalArgs = $shortcut.Arguments
            
            # 保留原有參數並添加新的參數
            if ($originalArgs -notmatch "AllowLegacyExtensionManifestV2") {
                $shortcut.Arguments = "$originalArgs $chromeFlags".Trim()
                $shortcut.Save()
                $shortcutUpdated = $true
                Write-Host "已更新快捷方式: $chromeShortcutPath" -ForegroundColor Green
            }
            else {
                Write-Host "快捷方式已包含需要的參數，無需更新" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "更新快捷方式 $chromeShortcutPath 時發生錯誤: $_" -ForegroundColor Red
        }
    }
}

if (-not $shortcutUpdated) {
    Write-Host "未找到 Chrome 快捷方式，請手動設置啟動參數" -ForegroundColor Yellow
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
    Write-Host "無法找到 Chrome 執行檔，請手動啟動 Chrome。" -ForegroundColor Red
}

Write-Host "`n安裝完成！uBlock Origin 現已安裝並啟用。" -ForegroundColor Green
pause
