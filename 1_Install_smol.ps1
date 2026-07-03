<#
.SYNOPSIS
Installation script for the smol version of SkyrimNet XTTS.

.DESCRIPTION
Creates a Python 3.12 venv (.venv_smol), installs requirements_smol.txt.

Differences from main version:
- Uses .venv_smol instead of .venv
- Installs from requirements_smol.txt (lighter deps, no deepspeed by default)
#>

function Print-Banner {
    $banner = @'
  ad88888ba   88                                 88                      888b      88                       
 d8"     "8b  88                                 ""                      8888b     88                ,d     
 Y8,          88                                                         88 `8b    88                88     
 `Y8aaaaa,    88   ,d8  8b       d8  8b,dPPYba,  88  88,dPYba,,adPYba,   88  `8b   88   ,adPPYba,  MM88MMM  
   `""""""8b,  88 ,a8"   `8b     d8'  88P'   "Y8  88  88P'   "88"    "8a  88   `8b  88  a8P_____88    88     
         `8b  8888[      `8b   d8'   88          88  88      88      88  88    `8b 88  8PP"""""""    88     
 Y8a     a8P  88`"Yba,    `8b,d8'    88          88  88      88      88  88     `8888  "8b,   ,aa    88,    
  "Y88888P"   88   `Y8a     Y88'     88          88  88      88      88  88      `888   `"Ybbd8"'    "Y888  
                            d8'                                                  
                           d8'       XTTS Smol (lightweight, no DeepSpeed)                                    

'@
    Write-Host $banner
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Header($text) {
    Write-Host "`n=== $text ===" -ForegroundColor Cyan
}

$tempFile = Join-Path $env:TEMP "winget_output_smol.txt"

function Test-WingetAvailable {
    try {
        Get-Command winget -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    }
}

Clear-Host
Print-Banner

$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

$wingetPresent = Test-WingetAvailable
if (-not $wingetPresent) {
    Write-Warning "winget not found. Skipping winget-based installs. Ensure Python 3.12 is installed manually."
}

Write-Header "Checking if Python 3.12 is installed"
if ($wingetPresent) {
    winget list --id Python.Python.3.12 --accept-source-agreements > $tempFile 2>&1
    $found = Select-String -Path $tempFile -Pattern 'Python.Python.3.12' -SimpleMatch -Quiet
    if (-not $found) {
        Write-Host "Python.Python.3.12 is NOT installed. Installing via winget..."
        Start-Process -FilePath winget -ArgumentList 'install','--id=Python.Python.3.12','-e','--silent','--accept-package-agreements','--accept-source-agreements' -NoNewWindow -Wait
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    } else {
        Write-Host "Python 3.12 is already installed."
    }
    Remove-Item -Path $tempFile -ErrorAction SilentlyContinue
}

Write-Header "Creating Python 3.12 virtual environment (.venv_smol)"
$pyExe = 'py'
$pyArgs = '-3.12'
$usePyLauncher = $false
try {
    & $pyExe $pyArgs -V | Out-Null
    $usePyLauncher = $true
} catch {
    Write-Warning "Python 3.12 launcher not found as 'py -3.12'. Trying 'python'."
    $pyExe = 'python'
    $pyArgs = ''
}

$createVenvArgs = @()
if ($pyArgs -ne '') { $createVenvArgs += $pyArgs }
$createVenvArgs += '-m'; $createVenvArgs += 'venv'; $createVenvArgs += '.venv_smol'; $createVenvArgs += '--clear'
$proc = Start-Process -FilePath $pyExe -ArgumentList $createVenvArgs -NoNewWindow -Wait -PassThru
if ($proc.ExitCode -ne 0) {
    Write-Error "Failed to create virtual environment. ExitCode=$($proc.ExitCode)"
    exit 1
}

Write-Host "Activating virtual environment and installing requirements..."
$activateScript = Join-Path -Path (Get-Location) -ChildPath ".venv_smol\Scripts\Activate.ps1"
if (-not (Test-Path $activateScript)) {
    Write-Error "Activation script not found at $activateScript"
    exit 1
}

. $activateScript

try {
    Write-Host "Upgrading pip and installing packages from requirements_smol.txt"
    python -m pip install --quiet --upgrade pip
    pip install uv
    Write-Host "Installing package (no deps)..."
    uv pip install --link-mode=copy -e . --no-deps
    Write-Host "Installing dependencies from requirements_smol.txt..."
    pip install -r requirements_smol.txt
} catch {
    Write-Error "Package installation failed: $_"
    if (Get-Command -ErrorAction SilentlyContinue Deactivate) { Deactivate }
    exit 1
}

if (Get-Command -ErrorAction SilentlyContinue Deactivate) { Deactivate }

Write-Header "Done"
Write-Host "If all succeeded you can run 2_Start_smol.bat (Nvidia GPU) or 2_Start_smol_CPU.bat (CPU only)" -ForegroundColor Green

exit 0
