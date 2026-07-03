<#
.SYNOPSIS
Starts SkyrimNet XTTS Smol version (lightweight, no DeepSpeed by default).

.DESCRIPTION
Designed to run on Windows 10 (PowerShell 5.1).
Uses .venv_smol virtual environment.

.PARAMETER cpu
Use CPU only (no GPU)

.PARAMETER bfloat16
Enable bfloat16 precision

.EXAMPLE
.\2_Start_XTTS_smol.ps1
Start XTTS Smol in standard mode

.EXAMPLE
.\2_Start_XTTS_smol.ps1 -cpu
Start XTTS Smol using CPU only
#>

param(
    [switch]$cpu,
    [switch]$bfloat16,
    [string]$server = "0.0.0.0",
    [int]$port = 7860
)

function Show-Banner {
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

function Any_Key_Wait {
    param (
        [string]$msg = "Press any key to continue...",
        [int]$wait_sec = 5
    )
    if ([Console]::KeyAvailable) {[Console]::ReadKey($true) }
    $secondsRunning = $wait_sec;
    Write-Host "$msg" -NoNewline
    While ( !([Console]::KeyAvailable) -And ($secondsRunning -gt 0)) {
        Start-Sleep -Seconds 1;
        Write-Host "$secondsRunning.." -NoNewLine; $secondsRunning--
    }
}

Clear-Host
Show-Banner

Write-Host "`nAttempting to start SkyrimNet XTTS Smol..." -ForegroundColor Green

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$venvPython = Join-Path $scriptRoot '.venv_smol\Scripts\python.exe'

if (Test-Path $venvPython) {
    $pythonPath = $venvPython
    Write-Host "Using virtualenv python: $pythonPath"
} else {
    $pyCmd = Get-Command python -ErrorAction SilentlyContinue
    if ($pyCmd) {
        $pythonPath = $pyCmd.Source
        Write-Host "Using system python: $pythonPath"
    } else {
        Write-Host "No python executable found. Please run 1_Install_smol.ps1 first." -ForegroundColor Red
        Read-Host -Prompt "Press Enter to exit"
        exit 1
    }
}

$moduleToRun = Join-Path $scriptRoot 'skyrimnet-xtts'
if (-not (Test-Path $moduleToRun)) {
    Write-Host "Could not find module: $moduleToRun" -ForegroundColor Red
    Read-Host -Prompt "Press Enter to exit"
    exit 1
}

$pythonArgs = "--server $server --port $port"
if ($cpu) {
    $pythonArgs = "$pythonArgs --use_cpu"
    Write-Host "CPU mode enabled" -ForegroundColor Cyan
}

if ($bfloat16) {
    $pythonArgs = "$pythonArgs --use_bfloat16"
    Write-Host "BF16 mode enabled" -ForegroundColor Cyan
}

Write-Host "Starting new PowerShell window to run: $pythonPath -m skyrimnet-xtts $pythonArgs"

$psCommand = "`$Host.UI.RawUI.WindowTitle = 'SkyrimNet XTTS Smol'; & '$pythonPath' -m skyrimnet-xtts $pythonArgs"

$proc = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoExit','-Command',$psCommand) -WorkingDirectory $scriptRoot -PassThru
try {
    $proc.PriorityClass = 'High'
    Write-Host "Set PowerShell window process priority to High (Id=$($proc.Id))."
} catch {
    Write-Host "Warning: failed to set process priority: $_" -ForegroundColor Yellow
}

Write-Host "`nSkyrimNet XTTS Smol should start in another window. Default web server is http://localhost:7860" -ForegroundColor Green
Write-Host "If that window closes immediately, run '.venv_smol\Scripts\python -m skyrimnet-xtts' to capture errors." -ForegroundColor Yellow
Any_Key_Wait -msg "Otherwise, you may close this window if it does not close itself.`n" -wait_sec 20
