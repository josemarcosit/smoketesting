
<#
.SYNOPSIS
    PowerShell HTTP Smoke Testing - Version 3.0

.DESCRIPTION
    Performs HTTP smoke tests against a list of URLs.
    Measures response time and exports the results to a CSV report.

.NOTES
    Version: 3.0
    Input File: targets.config
    Output File: reports/smoke-test-results.csv
#>

# Configuration
$TargetFilePath = ".\targets.config"
$ReportDirectory = ".\reports"
$ReportFilePath = Join-Path $ReportDirectory "smoke-test-results.csv"
$RequestTimeout = 5

# Initialize counters and results
$TotalTargets = 0
$SuccessfulTargets = 0
$FailedTargets = 0
$TestResults = [System.Collections.Generic.List[PSObject]]::new()

# Display script header
Write-Host "`n======================================" -ForegroundColor Cyan
Write-Host "       POWERHELL SMOKE TESTING" -ForegroundColor Cyan
Write-Host "                VERSION 3.0" -ForegroundColor Cyan
Write-Host "======================================`n" -ForegroundColor Cyan

# Validate input file
if (-not (Test-Path -Path $TargetFilePath -PathType Leaf)) {
    Write-Host "[ERROR] Target file not found: $TargetFilePath" -ForegroundColor Red
    exit 1
}

# Create report directory if necessary
if (-not (Test-Path -Path $ReportDirectory)) {
    New-Item -Path $ReportDirectory -ItemType Directory -Force | Out-Null
}

# Load and clean target URLs
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

    $StatusCode = $null
    $ResponseTime = $null
    $Result = "FAILED"
    $ErrorMessage = $null

    # Validate URL format
    $ParsedUri = $null

    if (-not [System.Uri]::TryCreate(
        $Url,
        [System.UriKind]::Absolute,
        [ref]$ParsedUri
    ) -or $ParsedUri.Scheme -notin @("http", "https")) {

        $ErrorMessage = "Invalid URL format"
        Write-Host "[INVALID] $Url" -ForegroundColor Yellow
    }
    else {

        # Start response time measurement
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        try {
            # Send HTTP GET request
            $Response = Invoke-WebRequest `
                -Uri $Url `
                -Method Get `
                -TimeoutSec $RequestTimeout `
                -UseBasicParsing `
                -ErrorAction Stop

            $StatusCode = [int]$Response.StatusCode

            # Stop response time measurement
            $Stopwatch.Stop()
            $ResponseTime = [math]::Round($Stopwatch.Elapsed.TotalMilliseconds, 2)

            # Evaluate HTTP response
            if ($StatusCode -ge 200 -and $StatusCode -lt 300) {

                $Result = "SUCCESS"
                $SuccessfulTargets++

                Write-Host "[SUCCESS] HTTP $StatusCode | ${ResponseTime}ms | $Url" `
                    -ForegroundColor Green
            }
            else {

                $FailedTargets++

                Write-Host "[FAILED] HTTP $StatusCode | ${ResponseTime}ms | $Url" `
                    -ForegroundColor Red
            }
        }
        catch {
            $Stopwatch.Stop()

            $ResponseTime = [math]::Round($Stopwatch.Elapsed.TotalMilliseconds, 2)
            $ErrorMessage = $_.Exception.Message

            # Extract HTTP status code when available
            if ($_.Exception.Response) {
                $StatusCode = [int]$_.Exception.Response.StatusCode
            }

            $FailedTargets++

            Write-Host "[ERROR] ${ResponseTime}ms | $Url | $ErrorMessage" `
                -ForegroundColor Red
        }
    }

    # Store test result
    $TestResults.Add([PSCustomObject]@{
        Timestamp     = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        URL           = $Url
        StatusCode    = $StatusCode
        ResponseTimeMs = $ResponseTime
        Result        = $Result
        ErrorMessage  = $ErrorMessage
    })
}

# Export results to CSV
try {
    $TestResults | Export-Csv `
        -Path $ReportFilePath `
        -NoTypeInformation `
        -Encoding UTF8 `
        -Delimiter ";"

    Write-Host "`n[INFO] Report successfully exported: $ReportFilePath" `
        -ForegroundColor Cyan
}
catch {
    Write-Host "[ERROR] Failed to export CSV report: $($_.Exception.Message)" `
        -ForegroundColor Red
    exit 1
}

# Display execution summary
Write-Host "`n======================================" -ForegroundColor Cyan
Write-Host "              TEST SUMMARY" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan

Write-Host "Total Targets:     $TotalTargets"
Write-Host "Successful:        $SuccessfulTargets" -ForegroundColor Green
Write-Host "Failed:            $FailedTargets" -ForegroundColor Red

if ($ResponseTimes = @($TestResults | Where-Object { $null -ne $_.ResponseTimeMs })) {
    $AverageResponseTime = ($ResponseTimes | Measure-Object -Property ResponseTimeMs -Average).Average
    Write-Host "Average Response:  $([math]::Round($AverageResponseTime, 2)) ms"
}

Write-Host "CSV Report:        $ReportFilePath"
Write-Host "======================================`n" -ForegroundColor Cyan

# Return an appropriate exit code
if ($FailedTargets -gt 0) {
    exit 1
}

exit 0
