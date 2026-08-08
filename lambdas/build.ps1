param (
    [switch]$Clean = $false
)

$lambdas = @("job_dispatcher", "status_updater", "mediaconvert_trigger")
$baseDir = $PSScriptRoot

foreach ($lambda in $lambdas) {
    $lambdaDir = Join-Path $baseDir $lambda
    $zipPath = Join-Path $lambdaDir "function.zip"
    $packageDir = Join-Path $lambdaDir "package"

    Write-Host "Building $lambda..." -ForegroundColor Cyan

    if ($Clean) {
        if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
        if (Test-Path $packageDir) { Remove-Item -Recurse -Force $packageDir }
    }

    # Create package dir
    if (-not (Test-Path $packageDir)) {
        New-Item -ItemType Directory -Path $packageDir | Out-Null
    }

    # Install dependencies into package dir (using python from .venv)
    $reqFile = Join-Path $lambdaDir "requirements.txt"
    if (Test-Path $reqFile) {
        Write-Host "  Installing dependencies..."
        # Use pip to install to target directory
        python -m pip install -r $reqFile -t $packageDir --quiet
    }

    # Copy source files to package dir
    Write-Host "  Copying source files..."
    Get-ChildItem -Path $lambdaDir -File | Where-Object { $_.Name -like "*.py" } | Copy-Item -Destination $packageDir

    # Zip the package dir
    Write-Host "  Zipping to $zipPath..."
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Compress-Archive -Path "$packageDir\*" -DestinationPath $zipPath

    Write-Host "  Done!" -ForegroundColor Green
}

Write-Host "All Lambdas packaged successfully!" -ForegroundColor Green
