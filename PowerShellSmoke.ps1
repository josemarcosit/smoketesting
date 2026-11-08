
<#
.SYNOPSIS
    PowerShell HTTP Smoke Testing

.DESCRIPTION
    Reads a list of URLs from a text file and performs HTTP requests
    to verify whether the target endpoints are responding successfully.

.NOTES
    Author: PowerShell Smoke Testing
    Version: 2.0
    Input File: targets.config
#>

# Configuration
$TargetFilePath = ".\targets.config"
$RequestTimeout = 5

# Initialize test counters
$TotalTargets = 0
$SuccessfulTargets = 0
$FailedTargets = 0

# Display script header
Write-Host "`n======================================" -ForegroundColor Cyan
Write-Host "       POWERSHELL SMOKE TESTING" -ForegroundColor Cyan
Write-Host "======================================`n" -ForegroundColor Cyan

# Validate input file
if (-not (Test-Path -Path $TargetFilePath -PathType Leaf)) {
    Write-Host "[ERROR] Target file not found: $TargetFilePath" -ForegroundColor Red
    exit 1
}

# Load URLs from the input file
$UrlList = Get-Content -Path $TargetFilePath |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    ForEach-Object { $_.Trim() }

if (-not $UrlList) {
    Write-Host "[WARNING] No URLs found in the target file." -ForegroundColor Yellow
    exit 0
}

# Process each URL
foreach ($Url in $UrlList) {

    $TotalTargets++

    # Validate URL format
    $ParsedUri = $null

    if (-not [System.Uri]::TryCreate(
        $Url,
        [System.UriKind]::Absolute,
        [ref]$ParsedUri
    ) -or $ParsedUri.Scheme -notin @("http", "https")) {

        Write-Host "[INVALID] $Url" -ForegroundColor Yellow
        $FailedTargets++
        continue
    }

    try {
        # Send HTTP GET request
        $Response = Invoke-WebRequest `
            -Uri $Url `
            -Method Get `
            -TimeoutSec $RequestTimeout `
            -UseBasicParsing `
            -ErrorAction Stop

        # Check HTTP response status
        if ($Response.StatusCode -ge 200 -and $Response.StatusCode -lt 300) {

            Write-Host "[SUCCESS] HTTP $($Response.StatusCode) - $Url" `
                -ForegroundColor Green

            $SuccessfulTargets++
        }
        else {

            Write-Host "[FAILED] HTTP $($Response.StatusCode) - $Url" `
                -ForegroundColor Red

            $FailedTargets++
        }
    }
    catch {
        # Handle HTTP errors, connection failures and timeouts
        $ErrorMessage = $_.Exception.Message

        Write-Host "[ERROR] $Url - $ErrorMessage" -ForegroundColor Red

        $FailedTargets++
    }
}

# Display execution summary
Write-Host "`n======================================" -ForegroundColor Cyan
Write-Host "              TEST SUMMARY" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan

Write-Host "Total Targets:    $TotalTargets"
Write-Host "Successful:       $SuccessfulTargets" -ForegroundColor Green
Write-Host "Failed:            $FailedTargets" -ForegroundColor Red

Write-Host "======================================`n" -ForegroundColor Cyan

# Return an appropriate exit code
if ($FailedTargets -gt 0) {
    exit 1
}

exit 0
