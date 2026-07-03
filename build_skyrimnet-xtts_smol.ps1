param(
    [switch]$test,
    [switch]$nobuild,
    [switch]$noarchive,
    [switch]$noclean,
    [switch]$deepspeed,       # Force include DeepSpeed (error if CUDA toolkit missing)
    [switch]$nodeepspeed,     # Force skip DeepSpeed
    [switch]$installcuda      # Auto-install CUDA 12.1 if missing
)

$PACKAGE_NAME = "SkyrimNet_XTTS_smol"

# ============================================================================
# CUDA Toolkit Detection
# ============================================================================
function Test-CudaToolkit {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $false }
    $nvcc = Join-Path $Path "bin\nvcc.exe"
    return (Test-Path $nvcc)
}

function Find-CudaToolkit {
    $candidates = @(
        "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.1",
        "E:\Tools\CUDA\12.1",
        "E:\Tools\CUDA\v12.1",
        "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.9",
        "E:\Tools\CUDA\12.9"
    )
    foreach ($path in $candidates) {
        if (Test-CudaToolkit -Path $path) {
            Write-Host "[CUDA] Found CUDA Toolkit at: $path" -ForegroundColor Green
            return $path
        }
    }
    return $null
}

function Install-Cuda121Minimal {
    Write-Host "[CUDA] Downloading CUDA 12.1.1 network installer..." -ForegroundColor Cyan
    $urls = @(
        "https://developer.download.nvidia.com/compute/cuda/12.1.1/network_installers/cuda_12.1.1_windows_network.exe",
        "https://developer.download.nvidia.com/compute/cuda/12.1.1/local_installers/cuda_12.1.1_531.14_windows.exe"
    )
    $installer = "$env:TEMP\cuda_12.1.1_installer.exe"

    $downloaded = $false
    foreach ($url in $urls) {
        try {
            Write-Host "[CUDA] Trying: $url" -ForegroundColor Gray
            Invoke-WebRequest -Uri $url -OutFile $installer -UseBasicParsing -TimeoutSec 300
            if ((Get-Item $installer).Length -gt 1MB) {
                $downloaded = $true
                break
            }
        } catch {
            Write-Host "[CUDA] Failed: $_" -ForegroundColor Gray
        }
    }

    if (-not $downloaded) {
        Write-Host "[CUDA] Could not download CUDA installer." -ForegroundColor Red
        Write-Host "[CUDA] Please install CUDA 12.1 manually from:" -ForegroundColor Yellow
        Write-Host "[CUDA] https://developer.nvidia.com/cuda-12-1-1-download-archive" -ForegroundColor Yellow
        return $false
    }

    $installDir = "E:\Tools\CUDA\12.1"
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null

    Write-Host "[CUDA] Installing CUDA 12.1.1 (minimal: toolkit only, no driver)..." -ForegroundColor Cyan
    Write-Host "[CUDA] Target: $installDir" -ForegroundColor Cyan

    $proc = Start-Process -FilePath $installer -ArgumentList @(
        "-s", "-noreboot", "-toolkit", "-noopengl", "-nomanifests"
    ) -Wait -PassThru -NoNewWindow

    if ($proc.ExitCode -eq 0) {
        Write-Host "[CUDA] Installation complete!" -ForegroundColor Green
        return (Test-CudaToolkit -Path $installDir)
    } else {
        Write-Host "[CUDA] Installation failed (code: $($proc.ExitCode))." -ForegroundColor Red
        Write-Host "[CUDA] Try installing CUDA 12.1 manually from:" -ForegroundColor Yellow
        Write-Host "[CUDA] https://developer.nvidia.com/cuda-12-1-1-download-archive" -ForegroundColor Yellow
        return $false
    }
}

# ============================================================================
# Detect CUDA Toolkit
# ============================================================================
$cudaPath = Find-CudaToolkit
$foundCuda = ($null -ne $cudaPath)

# ============================================================================
# Handle -installcuda flag (install CUDA if missing)
# ============================================================================
if ($installcuda -and -not $foundCuda) {
    Write-Host "[CUDA] CUDA 12.1 Toolkit not found. Installing..." -ForegroundColor Yellow
    if (Install-Cuda121Minimal) {
        $cudaPath = Find-CudaToolkit
        $foundCuda = ($null -ne $cudaPath)
    }
}

# ============================================================================
# DeepSpeed Mode Selection
# ============================================================================
if ($deepspeed -and $nodeepspeed) {
    Write-Host "[ERROR] Cannot specify both -deepspeed and -nodeepspeed" -ForegroundColor Red
    exit 1
}

$includeDeepSpeed = $false
if ($deepspeed) {
    if (-not $foundCuda) {
        Write-Host "[ERROR] DeepSpeed requires CUDA 12.1 Toolkit with nvcc.exe" -ForegroundColor Red
        Write-Host "[ERROR] Use -installcuda to auto-install, or omit -deepspeed for auto-detection" -ForegroundColor Yellow
        exit 1
    }
    $includeDeepSpeed = $true
    Write-Host "[DEEPSPEED] Force enabled by -deepspeed flag" -ForegroundColor Green

} elseif ($nodeepspeed) {
    $includeDeepSpeed = $false
    Write-Host "[DEEPSPEED] Force disabled by -nodeepspeed flag" -ForegroundColor Yellow

} else {
    $includeDeepSpeed = $foundCuda
    if ($foundCuda) {
        Write-Host "[DEEPSPEED] Auto-enabled (CUDA Toolkit found at: $cudaPath)" -ForegroundColor Green
    } else {
        Write-Host "[DEEPSPEED] Auto-disabled (CUDA 12.1 Toolkit not found)" -ForegroundColor Yellow
    }
}

# ============================================================================
# Set environment for spec file
# ============================================================================
$env:INCLUDE_DEEPSPEED = if ($includeDeepSpeed) { "1" } else { "0" }
if ($foundCuda) {
    $env:CUDA_PATH = $cudaPath
    $env:CUDA_PATH_V12_1 = $cudaPath
    Write-Host "[BUILD] CUDA_PATH = $cudaPath" -ForegroundColor Gray
}
Write-Host "[BUILD] INCLUDE_DEEPSPEED = $($env:INCLUDE_DEEPSPEED)" -ForegroundColor Gray

# ============================================================================
# Strip CUDA from PATH to avoid DLL version conflicts during build
# (torch bundles its own CUDA 12.1 DLLs, but system CUDA 12.9 in PATH
#  causes cufft/cublas version mismatch at import time)
# ============================================================================
$originalPath = $env:PATH
$env:PATH = ($env:PATH -split ';' | Where-Object { $_ -notmatch '\\\\CUDA\\\\' }) -join ';'
Write-Host "[BUILD] Stripped CUDA paths from PATH to avoid DLL conflicts" -ForegroundColor Gray

# ============================================================================
# Build Process
# ============================================================================
if (-not $nobuild) {
    if (-not (Test-Path ".venv_smol\Scripts\Activate.ps1")) {
        Write-Host "[ERROR] Virtual environment '.venv_smol' not found." -ForegroundColor Red
        Write-Host "[ERROR] Run: py -3.12 -m venv .venv_smol && .venv_smol\Scripts\pip install -r requirements_smol.txt" -ForegroundColor Yellow
        exit 1
    }

    . .venv_smol\Scripts\Activate.ps1

    if (-not (Test-Path env:VIRTUAL_ENV)) {
        Write-Host "[ERROR] Failed to activate virtual environment." -ForegroundColor Red
        exit 1
    }
    Write-Host "[BUILD] Virtual environment: $env:VIRTUAL_ENV" -ForegroundColor Gray

    # Install DeepSpeed in venv if needed
    if ($includeDeepSpeed) {
        Write-Host "[DEEPSPEED] Installing deepspeed in virtual environment..." -ForegroundColor Cyan
        $dsWheel = "https://github.com/langfod/DeepSpeed/releases/download/v0.18.0w/deepspeed-0.18.0+361a4043-cp312-cp312-win_amd64.whl"
        & .venv_smol\Scripts\pip install $dsWheel 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[DEEPSPEED] DeepSpeed installed successfully" -ForegroundColor Green
        } else {
            Write-Host "[DEEPSPEED] Installation failed. Continuing without deepspeed." -ForegroundColor Red
            $env:INCLUDE_DEEPSPEED = "0"
            $includeDeepSpeed = $false
        }
    }

    # Install PyInstaller if needed
    if (-not (Get-Command pyinstaller -ErrorAction SilentlyContinue)) {
        & .venv_smol\Scripts\pip install pyinstaller
    }

    Write-Host "[BUILD] Starting PyInstaller build..." -ForegroundColor Cyan
    if ($noclean) {
        & pyinstaller --noconfirm --log-level=INFO "skyrimnet-xtts_smol.spec"
    } else {
        if (Test-Path "build") { Remove-Item -Path "build" -Recurse -Force }
        if (Test-Path "dist")  { Remove-Item -Path "dist" -Recurse -Force }
        if (Test-Path "__pycache__") { Remove-Item -Path "__pycache__" -Recurse -Force }
        Get-ChildItem -Path "skyrimnet-xtts" -Recurse -Directory | Where-Object { $_.Name -eq "__pycache__" } | Remove-Item -Recurse -Force
        & pyinstaller --clean --noconfirm --log-level=INFO "skyrimnet-xtts_smol.spec"
    }

    $env:PATH = $originalPath

    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] PyInstaller build failed with code $LASTEXITCODE" -ForegroundColor Red
        Deactivate
        exit $LASTEXITCODE
    }
    Write-Host "[BUILD] PyInstaller build completed successfully!" -ForegroundColor Green

    Deactivate
}

# ============================================================================
# Test Mode
# ============================================================================
if ($test) {
    Write-Host "[TEST] Test mode: running built executable..." -ForegroundColor Cyan
    if (-not (Test-Path "dist\skyrimnet-xtts\skyrimnet-xtts.exe")) {
        Write-Host "[ERROR] Executable not found. Build first or use -nobuild to skip build." -ForegroundColor Red
        exit 1
    }

    Copy-Item -Path "models" -Destination "dist\$PACKAGE_NAME\" -Force -Recurse
    Copy-Item -Path "speakers" -Destination "dist\$PACKAGE_NAME\" -Force -Recurse
    Copy-Item -Path "assets" -Destination "dist\$PACKAGE_NAME\" -Force -Recurse
    Copy-Item -Path "skyrimnet_config.txt" -Destination "dist\$PACKAGE_NAME\" -Force
    Copy-Item -Path "examples\Start.bat" -Destination "dist\$PACKAGE_NAME\" -Force
    Copy-Item -Path "examples\Start_XTTS.ps1" -Destination "dist\$PACKAGE_NAME\" -Force

    Push-Location "dist/$PACKAGE_NAME"
    Start-Process -FilePath "./Start.bat" -ArgumentList "-server", "localhost", "-port", "7860" -Wait -NoNewWindow
    Pop-Location
}

# ============================================================================
# Archive Creation
# ============================================================================
if (-not $test -and -not $noarchive -and -not $nobuild) {
    Write-Host "[ARCHIVE] Creating deployment archive..." -ForegroundColor Cyan
    if (-not (Test-Path "dist\skyrimnet-xtts\skyrimnet-xtts.exe")) {
        Write-Host "[ERROR] Executable not found. Build first." -ForegroundColor Red
        exit 1
    }

    if (Test-Path "archive") { Remove-Item -Path "archive" -Recurse -Force }
    New-Item -ItemType Directory -Path "archive/$PACKAGE_NAME" -Force | Out-Null
    New-Item -ItemType Directory -Path "archive/$PACKAGE_NAME/assets" -Force | Out-Null

    Get-ChildItem -Path "speakers" -Directory | Copy-Item -Destination "archive/$PACKAGE_NAME/speakers"
    Copy-Item -Path "speakers\en\malebrute.wav" -Destination "archive/$PACKAGE_NAME/speakers/en\" -Force
    Copy-Item -Path "speakers\en\malecommoner.wav" -Destination "archive/$PACKAGE_NAME/speakers/en\" -Force
    Copy-Item -Path "assets\silence_100ms.wav" -Destination "archive/$PACKAGE_NAME/assets\" -Force
    Copy-Item -Path "skyrimnet_config.txt" -Destination "archive/$PACKAGE_NAME\" -Force
    Copy-Item -Path "README.md" -Destination "archive/$PACKAGE_NAME\" -Force
    Copy-Item -Path "README_smol.md" -Destination "archive/$PACKAGE_NAME\" -Force
    Copy-Item -Path "examples\Start.bat" -Destination "archive/$PACKAGE_NAME\" -Force
    Copy-Item -Path "examples\Start_XTTS.ps1" -Destination "archive/$PACKAGE_NAME\" -Force
    Copy-Item -Path "dist\skyrimnet-xtts\skyrimnet-xtts.exe" -Destination "archive/$PACKAGE_NAME\" -Force
    Copy-Item -Path "dist\skyrimnet-xtts\_internal" -Destination "archive/$PACKAGE_NAME\" -Force -Recurse

    $archiveName = "$PACKAGE_NAME"
    $version = Select-String -Path "pyproject.toml" -Pattern 'version = "(.*)"' | ForEach-Object { $_.Matches.Groups[1].Value }
    if ($version) { $archiveName += "_$version" }
    if (-not $includeDeepSpeed) { $archiveName += "_nodeepspeed" }

    Write-Host "[ARCHIVE] Creating: $archiveName.7z" -ForegroundColor Cyan
    Push-Location archive
    Start-Process -FilePath "C:\Program Files\7-Zip\7z.exe" -ArgumentList "a", "-t7z", "$archiveName.7z", "$PACKAGE_NAME", "-mx=9" -Wait -NoNewWindow
    Pop-Location
    Write-Host "[ARCHIVE] Done!" -ForegroundColor Green
}

Write-Host "[DONE] Build complete!" -ForegroundColor Green
Write-Host "[DONE] DeepSpeed: $(if ($includeDeepSpeed) { 'INCLUDED' } else { 'NOT included' })" -ForegroundColor $(if ($includeDeepSpeed) { 'Green' } else { 'Yellow' })
