
<#
.SYNOPSIS
    Advanced PowerShell HTTP Smoke Testing - Version 4.0

.DESCRIPTION
    Performs parallel HTTP smoke tests against a list of URLs.
    Includes retry mechanism, response time measurement,
    latency thresholds, and CSV/JSON reporting.

.NOTES
    Version: 4.0
    Requirements: PowerShell 7+
    Input File: targets.config
    Output Directory: reports/
#>

# ==========================================
# CONFIGURATION
# ==========================================

$TargetFilePath = ".\targets.config"
$ReportDirectory = ".\reports"

$RequestTimeout = 5
$MaxRetries = 2
$MaxConcurrency = 5
$LatencyThreshold = 2000

# ==========================================
# INITIALIZATION
# ==========================================

$StartTime = Get-Date

Write-Host "`n==========================================" -ForegroundColor Cyan
Write-Host "       POWERSHELL SMOKE TESTING" -ForegroundColor Cyan
Write-Host "                VERSION 4.0" -ForegroundColor Cyan
Write-Host "==========================================`n" -ForegroundColor Cyan

# Verify PowerShell version
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "[ERROR] PowerShell 7 or higher is required." -ForegroundColor Red
    exit 1
}

# Validate target file
if (-not (Test-Path -Path $TargetFilePath -PathType Leaf)) {
    Write-Host "[ERROR] Target file not found: $TargetFilePath" -ForegroundColor Red
    exit 1
}

# Create report directory
if (-not (Test-Path -Path $ReportDirectory)) {
    New-Item -Path $ReportDirectory -ItemType Directory -Force | Out-Null
}

# Load targets
$UrlList = @(
    Get-Content -Path $TargetFilePath |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { $_.Trim() } |
        Select-Object -Unique
)

if ($UrlList.Count -eq 0) {
    Write-Host "[WARNING] No targets found." -ForegroundColor Yellow
    exit 0
}

# ==========================================
# PARALLEL HTTP TESTING
# ==========================================

Write-Host "[INFO] Starting parallel HTTP tests..." -ForegroundColor Cyan
Write-Host "[INFO] Total targets: $($UrlList.Count)"
Write-Host "[INFO] Max concurrency: $MaxConcurrency"
Write-Host "[INFO] Retry attempts: $MaxRetries`n"

$TestResults = @(
    $UrlList | ForEach-Object -Parallel {

        # Receive configuration from the parent scope
        $Url = $_
        $Timeout = $using:RequestTimeout
        $Retries = $using:MaxRetries
        $LatencyLimit = $using:LatencyThreshold

        $Result = "FAILED"
        $StatusCode = $null
        $ResponseTime = $null
        $ErrorMessage = $null
        $Attempt = 0

        # Validate URL
        $ParsedUri = $null

        if (-not [System.Uri]::TryCreate(
            $Url,
            [System.UriKind]::Absolute,
            [ref]$ParsedUri
        ) -or $ParsedUri.Scheme -notin @("http", "https")) {

            $ErrorMessage = "Invalid URL format"
        }
        else {

            # Retry failed requests
            for ($Attempt = 1; $Attempt -le ($Retries + 1); $Attempt++) {

                $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

                try {

                    # Execute HTTP request
                    $Response = Invoke-WebRequest `
                        -Uri $Url `
                        -Method Get `
                        -TimeoutSec $Timeout `
                        -UseBasicParsing `
                        -ErrorAction Stop

                    $Stopwatch.Stop()

                    $StatusCode = [int]$Response.StatusCode

                    $ResponseTime = [math]::Round(
                        $Stopwatch.Elapsed.TotalMilliseconds, 2
                    )

                    if ($StatusCode -ge 200 -and $StatusCode -lt 300) {
                        $Result = "SUCCESS"
                        $ErrorMessage = $null
                        break
                    }

                    $ErrorMessage = "Unexpected HTTP status: $StatusCode"
                }
                catch {

                    $Stopwatch.Stop()

                    $ResponseTime = [math]::Round(
                        $Stopwatch.Elapsed.TotalMilliseconds, 2
                    )

                    $ErrorMessage = $_.Exception.Message

                    if ($_.Exception.Response) {
                        $StatusCode = [int]$_.Exception.Response.StatusCode
                    }
                }

                # Wait before retrying
                if ($Attempt -le $Retries) {
                    Start-Sleep -Seconds 1
                }
            }
        }

        # Evaluate latency
        $LatencyStatus = "NORMAL"

        if ($null -ne $ResponseTime -and $ResponseTime -gt $LatencyLimit) {
            $LatencyStatus = "SLOW"
        }

        # Return structured result
        [PSCustomObject]@{
            Timestamp      = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            URL            = $Url
            StatusCode     = $StatusCode
            ResponseTimeMs = $ResponseTime
            Attempts       = $Attempt
            Result         = $Result
            LatencyStatus  = $LatencyStatus
            ErrorMessage   = $ErrorMessage
        }

    } -ThrottleLimit $MaxConcurrency
)

# ==========================================
# DISPLAY RESULTS
# ==========================================

foreach ($Test in $TestResults) {

    $Message = "HTTP $($Test.StatusCode) | $($Test.ResponseTimeMs)ms | $($Test.URL)"

    if ($Test.Result -eq "SUCCESS" -and $Test.LatencyStatus -eq "NORMAL") {
        Write-Host "[SUCCESS] $Message" -ForegroundColor Green
    }
    elseif ($Test.Result -eq "SUCCESS") {
        Write-Host "[SLOW] $Message" -ForegroundColor Yellow
    }
    else {
        Write-Host "[FAILED] $Message | $($Test.ErrorMessage)" -ForegroundColor Red
    }
}

# ==========================================
# REPORT GENERATION
# ==========================================

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

$CsvReport = Join-Path $ReportDirectory "smoke-test_$Timestamp.csv"
$JsonReport = Join-Path $ReportDirectory "smoke-test_$Timestamp.json"

try {

    # Export CSV report
    $TestResults | Export-Csv `
        -Path $CsvReport `
        -NoTypeInformation `
        -Encoding utf8

    # Export JSON report
    $TestResults | ConvertTo-Json -Depth 5 |
        Set-Content -Path $JsonReport -Encoding utf8

    Write-Host "`n[INFO] Reports generated successfully." -ForegroundColor Cyan
}
catch {

    Write-Host "[ERROR] Report generation failed: $($_.Exception.Message)" `
        -ForegroundColor Red

    exit 1
}

# ==========================================
# EXECUTION SUMMARY
# ==========================================

$EndTime = Get-Date
$Duration = [math]::Round(($EndTime - $StartTime).TotalSeconds, 2)

$TotalTargets = $TestResults.Count

$SuccessfulTargets = @(
    $TestResults | Where-Object { $_.Result -eq "SUCCESS" }
).Count

$FailedTargets = $TotalTargets - $SuccessfulTargets

$SlowTargets = @(
    $TestResults | Where-Object { $_.LatencyStatus -eq "SLOW" }
).Count

$AverageResponse = $TestResults |
    Where-Object { $null -ne $_.ResponseTimeMs } |
    Measure-Object -Property ResponseTimeMs -Average

$AverageLatency = if ($AverageResponse.Count -gt 0) {
    [math]::Round($AverageResponse.Average, 2)
}
else {
    0
}

$SuccessRate = if ($TotalTargets -gt 0) {
    [math]::Round(($SuccessfulTargets / $TotalTargets) * 100, 2)
}
else {
    0
}

Write-Host "`n==========================================" -ForegroundColor Cyan
Write-Host "              TEST SUMMARY" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

Write-Host "Total Targets:      $TotalTargets"
Write-Host "Successful:         $SuccessfulTargets" -ForegroundColor Green
Write-Host "Failed:             $FailedTargets" -ForegroundColor Red
Write-Host "Slow Endpoints:     $SlowTargets" -ForegroundColor Yellow
Write-Host "Success Rate:       $SuccessRate%"
Write-Host "Average Latency:    $AverageLatency ms"
Write-Host "Execution Time:     $Duration seconds"

Write-Host "`nCSV Report:         $CsvReport"
Write-Host "JSON Report:        $JsonReport"

Write-Host "==========================================`n" -ForegroundColor Cyan

# Return appropriate exit code
if ($FailedTargets -gt 0) {
    exit 1
}

exit 0
