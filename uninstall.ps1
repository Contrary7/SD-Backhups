# SteamDaddy Uninstaller — github.com/Contrary7/SteamDaddy-Backup
# Safely removes SteamDaddy activation DLLs from the Steam directory.
$ErrorActionPreference = "Stop"

# Ensure Administrator privileges so system DLL locks can be released
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "[SteamDaddy Uninstaller] Requesting Administrator privileges for file cleanup..." -ForegroundColor Yellow
    try {
        if ($PSCommandPath) {
            Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs -ErrorAction Stop
            exit
        } else {
            $tmpScript = Join-Path $env:TEMP "SteamDaddy_Uninstall.ps1"
            (New-Object System.Net.WebClient).DownloadFile(
                "https://raw.githubusercontent.com/Contrary7/SteamDaddy-Backup/main/uninstall.ps1",
                $tmpScript
            )
            Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$tmpScript`"" -Verb RunAs -ErrorAction Stop
            exit
        }
    } catch {
        Write-Host "[SteamDaddy Uninstaller] Continuing without elevated permissions..." -ForegroundColor Yellow
    }
}

Write-Host "[SteamDaddy Uninstaller] Locating Steam installation directory..." -ForegroundColor Cyan

# Locate Steam root directory from Windows Registry
$steamPath = (Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" -Name "InstallPath" -ErrorAction SilentlyContinue).InstallPath
if (-not $steamPath) {
    $steamPath = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Valve\Steam" -Name "InstallPath" -ErrorAction SilentlyContinue).InstallPath
}
if (-not $steamPath) {
    $steamPath = (Get-ItemProperty -Path "HKCU:\SOFTWARE\Valve\Steam" -Name "InstallPath" -ErrorAction SilentlyContinue).InstallPath
}
if (-not $steamPath) {
    $steamPath = (Get-ItemProperty -Path "HKCU:\SOFTWARE\Valve\Steam" -Name "SteamPath" -ErrorAction SilentlyContinue).SteamPath
}

# Fallback default locations if registry key is missing
if (-not $steamPath -or -not (Test-Path $steamPath)) {
    $fallbackPaths = @(
        "C:\Program Files (x86)\Steam",
        "C:\Program Files\Steam",
        "C:\Steam"
    )
    foreach ($fb in $fallbackPaths) {
        if (Test-Path $fb) {
            $steamPath = $fb
            break
        }
    }
}

if (-not $steamPath -or -not (Test-Path $steamPath)) {
    Write-Host "[SteamDaddy Uninstaller] Error: Steam installation directory could not be found." -ForegroundColor Red
    exit 1
}

Write-Host "[SteamDaddy Uninstaller] Found Steam installation at: $steamPath" -ForegroundColor Green

# Close Steam process if running to release DLL file handles
$steamProc = Get-Process -Name "steam" -ErrorAction SilentlyContinue
if ($steamProc) {
    Write-Host "[SteamDaddy Uninstaller] Stopping Steam process to unlock DLL files..." -ForegroundColor Yellow
    Stop-Process -Name "steam" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

$sdProc = Get-Process -Name "SteamDaddy" -ErrorAction SilentlyContinue
if ($sdProc) {
    Stop-Process -Name "SteamDaddy" -Force -ErrorAction SilentlyContinue
}

# List of DLL files to uninstall from Steam root directory
$targetDlls = @(
    "SteamDaddy.dll",
    "dwmapi.dll",
    "xinput1_4.dll"
)

$removedCount = 0

foreach ($dll in $targetDlls) {
    $dllPath = Join-Path $steamPath $dll
    if (Test-Path $dllPath) {
        try {
            Remove-Item -Path $dllPath -Force -ErrorAction Stop
            Write-Host "[SteamDaddy Uninstaller] Successfully deleted: $dll" -ForegroundColor Green
            $removedCount++
        } catch {
            Write-Host "[SteamDaddy Uninstaller] Failed to delete $dll : $_" -ForegroundColor Red
        }
    } else {
        Write-Host "[SteamDaddy Uninstaller] File not found (already uninstalled): $dll" -ForegroundColor DarkGray
    }
}

Write-Host ""
if ($removedCount -gt 0) {
    Write-Host "[SteamDaddy Uninstaller] Uninstall complete! Removed $removedCount DLL file(s) from Steam." -ForegroundColor Magenta
} else {
    Write-Host "[SteamDaddy Uninstaller] Clean! No SteamDaddy DLL files were found in Steam directory." -ForegroundColor Green
}
