<#
.SYNOPSIS
    PowerShell HTTP Smoke Testing - Version 5.0

.DESCRIPTION
    Parallel HTTP monitoring with retry logic, latency measurement,
    historical uptime tracking and automated reporting.

.NOTES
    Requirements: PowerShell 7+
    Input: targets.config
#>

# ==========================================
# CONFIGURATION
# ==========================================

$RootDirectory = $PSScriptRoot
$TargetFilePath = Join-Path $RootDirectory "targets.config"

$ReportDirectory = Join-Path $RootDirectory "reports"
$ExecutionDirectory = Join-Path $ReportDirectory "executions"
$DashboardDirectory = Join-Path $RootDirectory "dashboard"

$HistoryFilePath = Join-Path $ReportDirectory "history.json"
$LatestCsvPath = Join-Path $ReportDirectory "latest-results.csv"
$DashboardFilePath = Join-Path $DashboardDirectory "index.html"

$RequestTimeout = 5
$MaxRetries = 2
$MaxConcurrency = 5
$LatencyThreshold = 2000

$ErrorActionPreference = "Stop"

# ==========================================
# INITIALIZATION
# ==========================================

$StartTime = Get-Date
$Timestamp = $StartTime.ToString("yyyyMMdd_HHmmss")

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "PowerShell 7 or later is required."
}

if (-not (Test-Path $TargetFilePath -PathType Leaf)) {
    throw "Target file not found: $TargetFilePath"
}

foreach ($Directory in @(
    $ReportDirectory,
    $ExecutionDirectory,
    $DashboardDirectory
)) {
    New-Item -Path $Directory -ItemType Directory -Force |
        Out-Null
}

$UrlList = @(
    Get-Content $TargetFilePath |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { $_.Trim() } |
        Select-Object -Unique
)

if ($UrlList.Count -eq 0) {
    throw "No monitoring targets configured."
}

# ==========================================
# LOAD HISTORICAL DATA
# ==========================================

$History = @()

if (Test-Path $HistoryFilePath) {
    try {
        $History = @(
            Get-Content $HistoryFilePath -Raw |
                ConvertFrom-Json
        )
    }
    catch {
        Write-Warning "Invalid history file. Starting new history."
        $History = @()
    }
}

# ==========================================
# PARALLEL HTTP MONITORING
# ==========================================

Write-Host "Starting HTTP smoke tests..." -ForegroundColor Cyan

$TestResults = @(
    $UrlList | ForEach-Object -Parallel {

        $Url = $_
        $Timeout = $using:RequestTimeout
        $Retries = $using:MaxRetries
        $LatencyLimit = $using:LatencyThreshold

        $StatusCode = $null
        $ResponseTime = $null
        $ErrorMessage = $null
        $Result = "FAILED"
        $Attempts = 0

        # Validate URL format
        $ParsedUri = $null

        if (-not [System.Uri]::TryCreate(
            $Url,
            [System.UriKind]::Absolute,
            [ref]$ParsedUri
        ) -or $ParsedUri.Scheme -notin @("http", "https")) {

            $ErrorMessage = "Invalid URL format."
        }
        else {

            # Execute HTTP requests with retry support
            for ($Attempt = 1; $Attempt -le ($Retries + 1); $Attempt++) {

                $Attempts = $Attempt
                $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

                try {
                    $Response = Invoke-WebRequest `
                        -Uri $Url `
                        -Method GET `
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

                    if ($null -ne $_.Exception.Response) {
                        try {
                            $StatusCode = [int]$_.Exception.Response.StatusCode
                        }
                        catch {
                            $StatusCode = $null
                        }
                    }
                }

                # Wait before retrying
                if ($Attempt -le $Retries) {
                    Start-Sleep -Seconds 1
                }
            }
        }

        # Evaluate response latency
        $LatencyStatus = if (
            $null -ne $ResponseTime -and
            $ResponseTime -gt $LatencyLimit
        ) {
            "SLOW"
        }
        else {
            "NORMAL"
        }

        # Return structured monitoring result
        [PSCustomObject]@{
            Timestamp      = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            URL            = $Url
            StatusCode     = $StatusCode
            ResponseTimeMs = $ResponseTime
            Attempts       = $Attempts
            Result         = $Result
            LatencyStatus  = $LatencyStatus
            ErrorMessage   = $ErrorMessage
        }

    } -ThrottleLimit $MaxConcurrency
)

# ==========================================
# DISPLAY TEST RESULTS
# ==========================================

foreach ($Test in $TestResults) {

    $Message = "HTTP $($Test.StatusCode) | $($Test.ResponseTimeMs) ms | $($Test.URL)"

    if ($Test.Result -eq "FAILED") {
        Write-Host "[FAILED] $Message" -ForegroundColor Red
    }
    elseif ($Test.LatencyStatus -eq "SLOW") {
        Write-Host "[SLOW] $Message" -ForegroundColor Yellow
    }
    else {
        Write-Host "[SUCCESS] $Message" -ForegroundColor Green
    }
}

# ==========================================
# SAVE EXECUTION HISTORY
# ==========================================

$CurrentRun = [PSCustomObject]@{
    Timestamp = $StartTime.ToString("yyyy-MM-dd HH:mm:ss")
    Results   = @($TestResults)
}

$History = @($History) + @($CurrentRun)

ConvertTo-Json -InputObject @($History) -Depth 8 | Set-Content -Path $HistoryFilePath -Encoding utf8


# ==========================================
# GENERATE HISTORICAL METRICS
# ==========================================

$TargetMetrics = foreach ($Target in $UrlList) {

    # Collect historical results for this endpoint
    $TargetHistory = @(
        $History |
            ForEach-Object { $_.Results } |
            Where-Object { $_.URL -eq $Target }
    )

    $TotalChecks = $TargetHistory.Count

    $SuccessfulChecks = @(
        $TargetHistory |
            Where-Object { $_.Result -eq "SUCCESS" }
    ).Count

    $FailedChecks = $TotalChecks - $SuccessfulChecks

    # Calculate historical uptime percentage
    $Uptime = if ($TotalChecks -gt 0) {
        [math]::Round(
            ($SuccessfulChecks / $TotalChecks) * 100, 2
        )
    }
    else {
        0
    }

    # Calculate average response time
    $ValidResponseTimes = @(
        $TargetHistory |
            Where-Object { $null -ne $_.ResponseTimeMs }
    )

    $AverageLatency = if ($ValidResponseTimes.Count -gt 0) {
        [math]::Round(
            ($ValidResponseTimes |
                Measure-Object -Property ResponseTimeMs -Average).Average,
            2
        )
    }
    else {
        0
    }

    # Retrieve latest endpoint result
    $LatestResult = $TestResults |
        Where-Object { $_.URL -eq $Target } |
        Select-Object -First 1

    # Determine endpoint health status
    $HealthStatus = if ($LatestResult.Result -ne "SUCCESS") {
        "CRITICAL"
    }
    elseif ($LatestResult.LatencyStatus -eq "SLOW") {
        "DEGRADED"
    }
    else {
        "HEALTHY"
    }

    [PSCustomObject]@{
        URL              = $Target
        HealthStatus     = $HealthStatus
        UptimePercentage = $Uptime
        TotalChecks      = $TotalChecks
        SuccessfulChecks = $SuccessfulChecks
        FailedChecks     = $FailedChecks
        AverageLatencyMs = $AverageLatency
        LatestLatencyMs  = $LatestResult.ResponseTimeMs
    }
}

# ==========================================
# EXPORT CSV REPORTS
# ==========================================

$ExecutionCsvPath = Join-Path `
    $ExecutionDirectory "execution_$Timestamp.csv"

# Save individual execution report
$TestResults | Export-Csv `
    -Path $ExecutionCsvPath `
    -NoTypeInformation `
    -Encoding utf8

# Update latest execution report
$TestResults | Export-Csv `
    -Path $LatestCsvPath `
    -NoTypeInformation `
    -Encoding utf8

Write-Host "[INFO] CSV reports generated." -ForegroundColor Cyan

# ==========================================
# GENERATE SUMMARY METRICS
# ==========================================

$TotalTargets = $TestResults.Count

$SuccessfulTargets = @(
    $TestResults |
        Where-Object { $_.Result -eq "SUCCESS" }
).Count

$FailedTargets = $TotalTargets - $SuccessfulTargets

$SlowTargets = @(
    $TestResults |
        Where-Object { $_.LatencyStatus -eq "SLOW" }
).Count

# Calculate average response time
$AverageResponse = $TestResults |
    Where-Object { $null -ne $_.ResponseTimeMs } |
    Measure-Object -Property ResponseTimeMs -Average

$AverageLatency = if ($AverageResponse.Count -gt 0) {
    [math]::Round($AverageResponse.Average, 2)
}
else {
    0
}

# Calculate overall success rate
$SuccessRate = if ($TotalTargets -gt 0) {
    [math]::Round(
        ($SuccessfulTargets / $TotalTargets) * 100, 2
    )
}
else {
    0
}

# ==========================================
# PREPARE DASHBOARD DATA
# ==========================================

$DashboardData = [PSCustomObject]@{

    GeneratedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    Summary = [PSCustomObject]@{
        TotalTargets      = $TotalTargets
        SuccessfulTargets = $SuccessfulTargets
        FailedTargets     = $FailedTargets
        SlowTargets       = $SlowTargets
        SuccessRate       = $SuccessRate
        AverageLatency    = $AverageLatency
        TotalExecutions   = $History.Count
    }

    TargetMetrics = @($TargetMetrics)
    LatestResults = @($TestResults)
}

# Convert dashboard data to JSON
$DashboardJson = ConvertTo-Json `
    -InputObject $DashboardData `
    -Depth 10 `
    -Compress

# Escape HTML-sensitive characters
$DashboardJson = $DashboardJson.
    Replace("<", "\u003c").
    Replace(">", "\u003e").
    Replace("&", "\u0026")

Write-Host "[INFO] Dashboard data prepared." -ForegroundColor Cyan


# ==========================================
# HTML DASHBOARD TEMPLATE
# ==========================================

$HtmlTemplate = @'
<!DOCTYPE html>
<html lang="en">

<head>

<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">

<title>HTTP Monitoring Dashboard</title>

<style>

:root {
    --background: #101827;
    --panel: #1c293b;
    --text: #f1f5f9;
    --muted: #9caec2;
    --green: #22c55e;
    --red: #ef4444;
    --yellow: #eab308;
    --blue: #38bdf8;
}

* {
    box-sizing: border-box;
}

body {
    margin: 0;
    padding: 30px;
    font-family: Arial, sans-serif;
    background: var(--background);
    color: var(--text);
}

.container {
    max-width: 1400px;
    margin: auto;
}

header {
    margin-bottom: 30px;
}

.subtitle {
    color: var(--muted);
}

.cards {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
    gap: 16px;
    margin-bottom: 25px;
}

.card, .panel {
    background: var(--panel);
    border-radius: 12px;
    padding: 22px;
}

.card h3 {
    color: var(--muted);
    font-size: 13px;
}

.metric {
    font-size: 30px;
    font-weight: bold;
}

.green { color: var(--green); }
.red { color: var(--red); }
.yellow { color: var(--yellow); }
.blue { color: var(--blue); }

.panel {
    margin-bottom: 25px;
    overflow-x: auto;
}

table {
    width: 100%;
    border-collapse: collapse;
    min-width: 650px;
}

th, td {
    text-align: left;
    padding: 13px;
    border-bottom: 1px solid #344256;
}

th {
    color: var(--muted);
}

td {
    overflow-wrap: anywhere;
}

.status {
    font-weight: bold;
}

.HEALTHY, .SUCCESS {
    color: var(--green);
}

.DEGRADED, .SLOW {
    color: var(--yellow);
}

.CRITICAL, .FAILED {
    color: var(--red);
}

canvas {
    width: 100%;
    max-height: 300px;
}

footer {
    color: var(--muted);
    font-size: 12px;
    text-align: center;
    padding: 20px;
}

@media (max-width: 600px) {
    body {
        padding: 15px;
    }

    .metric {
        font-size: 24px;
    }
}

</style>

</head>

<body>

<div class="container">

<header>
    <h1>HTTP Monitoring Dashboard</h1>
    <div class="subtitle" id="generatedAt"></div>
</header>

<!-- Summary metric cards -->

<section class="cards">

    <div class="card">
        <h3>Total Endpoints</h3>
        <div class="metric blue" id="totalTargets">0</div>
    </div>

    <div class="card">
        <h3>Successful</h3>
        <div class="metric green" id="successful">0</div>
    </div>

    <div class="card">
        <h3>Failed</h3>
        <div class="metric red" id="failed">0</div>
    </div>

    <div class="card">
        <h3>Slow Endpoints</h3>
        <div class="metric yellow" id="slow">0</div>
    </div>

    <div class="card">
        <h3>Success Rate</h3>
        <div class="metric blue" id="successRate">0%</div>
    </div>

    <div class="card">
        <h3>Average Latency</h3>
        <div class="metric blue" id="averageLatency">0 ms</div>
    </div>

</section>

<!-- Historical endpoint health -->

<section class="panel">

    <h2>Endpoint Health Status</h2>

    <table>

        <thead>
            <tr>
                <th>Endpoint</th>
                <th>Health</th>
                <th>Uptime</th>
                <th>Checks</th>
                <th>Average Latency</th>
            </tr>
        </thead>

        <tbody id="healthTable"></tbody>

    </table>

</section>

<!-- Response time visualization -->

<section class="panel">

    <h2>Latest Response Times</h2>

    <canvas id="latencyChart" height="100"></canvas>

</section>

<!-- Latest HTTP test results -->

<section class="panel">

    <h2>Latest Test Results</h2>

    <table>

        <thead>
            <tr>
                <th>Endpoint</th>
                <th>HTTP Status</th>
                <th>Response Time</th>
                <th>Result</th>
                <th>Attempts</th>
            </tr>
        </thead>

        <tbody id="resultsTable"></tbody>

    </table>

</section>

<footer>
    PowerShell HTTP Smoke Testing v5.0
    | Automatically generated monitoring report
</footer>

</div>

<script>

const dashboardData = __DASHBOARD_DATA__;

const summary = dashboardData.Summary;

// ==========================================
// POPULATE SUMMARY METRICS
// ==========================================

document.getElementById("generatedAt").textContent =
    "Last updated: " + dashboardData.GeneratedAt;

document.getElementById("totalTargets").textContent =
    summary.TotalTargets;

document.getElementById("successful").textContent =
    summary.SuccessfulTargets;

document.getElementById("failed").textContent =
    summary.FailedTargets;

document.getElementById("slow").textContent =
    summary.SlowTargets;

document.getElementById("successRate").textContent =
    summary.SuccessRate + "%";

document.getElementById("averageLatency").textContent =
    summary.AverageLatency + " ms";

// ==========================================
// POPULATE ENDPOINT HEALTH TABLE
// ==========================================

const healthTable = document.getElementById("healthTable");

dashboardData.TargetMetrics.forEach(item => {

    const row = document.createElement("tr");

    const values = [
        item.URL,
        item.HealthStatus,
        item.UptimePercentage + "%",
        item.TotalChecks,
        item.AverageLatencyMs + " ms"
    ];

    values.forEach((value, index) => {

        const cell = document.createElement("td");

        cell.textContent = value;

        if (index === 1) {
            cell.className = "status " + item.HealthStatus;
        }

        row.appendChild(cell);
    });

    healthTable.appendChild(row);
});

// ==========================================
// POPULATE LATEST RESULTS TABLE
// ==========================================

const resultsTable = document.getElementById("resultsTable");

dashboardData.LatestResults.forEach(item => {

    const row = document.createElement("tr");

    const values = [
        item.URL,
        item.StatusCode ?? "N/A",
        item.ResponseTimeMs === null
            ? "N/A"
            : item.ResponseTimeMs + " ms",
        item.Result,
        item.Attempts
    ];

    values.forEach((value, index) => {

        const cell = document.createElement("td");

        cell.textContent = value;

        if (index === 3) {
            cell.className = "status " + item.Result;
        }

        row.appendChild(cell);
    });

    resultsTable.appendChild(row);
});

// ==========================================
// RESPONSE TIME CHART
// ==========================================

const canvas = document.getElementById("latencyChart");
const context = canvas.getContext("2d");

const chartData = dashboardData.LatestResults.filter(
    item => item.ResponseTimeMs !== null
);

function drawChart() {

    const width = canvas.clientWidth;
    const height = 300;
    const ratio = window.devicePixelRatio || 1;

    canvas.width = width * ratio;
    canvas.height = height * ratio;

    context.setTransform(ratio, 0, 0, ratio, 0, 0);
    context.clearRect(0, 0, width, height);

    if (chartData.length === 0) {
        context.fillStyle = "#9caec2";
        context.fillText("No latency data available", 15, 30);
        return;
    }

    const maxValue = Math.max(
        1,
        ...chartData.map(item => item.ResponseTimeMs)
    );

    const chartWidth = width - 40;
    const chartHeight = 220;
    const barGap = 10;

    const barWidth = Math.max(
        4,
        (chartWidth - barGap * chartData.length) / chartData.length
    );

    chartData.forEach((item, index) => {

        const barHeight =
            (item.ResponseTimeMs / maxValue) * chartHeight;

        const x = 20 + index * (barWidth + barGap);
        const y = chartHeight - barHeight + 20;

        context.fillStyle =
            item.LatencyStatus === "SLOW"
                ? "#eab308"
                : "#38bdf8";

        context.fillRect(x, y, barWidth, barHeight);

        context.fillStyle = "#9caec2";
        context.font = "10px Arial";

        context.save();

        context.translate(x + barWidth / 2, 260);
        context.rotate(-Math.PI / 4);

        context.fillText(
            item.URL.length > 25
                ? item.URL.substring(0, 25) + "..."
                : item.URL,
            0,
            0
        );

        context.restore();
    });
}

// Initial chart rendering
drawChart();

// Redraw chart when browser window changes size
window.addEventListener("resize", drawChart);

</script>

</body>
</html>
'@


# ==========================================
# GENERATE HTML DASHBOARD
# ==========================================

# Replace dashboard data placeholder with JSON
$HtmlContent = $HtmlTemplate.Replace(
    "__DASHBOARD_DATA__",
    $DashboardJson
)

# Save dashboard HTML file
Set-Content `
    -Path $DashboardFilePath `
    -Value $HtmlContent `
    -Encoding utf8

Write-Host "[INFO] HTML dashboard generated." -ForegroundColor Cyan

# ==========================================
# EXECUTION SUMMARY
# ==========================================

$EndTime = Get-Date

$ExecutionTime = [math]::Round(
    ($EndTime - $StartTime).TotalSeconds,
    2
)

Write-Host "`n==========================================" -ForegroundColor Cyan
Write-Host "       POWERSHELL HTTP MONITORING" -ForegroundColor Cyan
Write-Host "             VERSION 5.0" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

Write-Host ""
Write-Host "MONITORING SUMMARY" -ForegroundColor Yellow

Write-Host "Total Targets:       $TotalTargets"
Write-Host "Successful:          $SuccessfulTargets" -ForegroundColor Green
Write-Host "Failed:              $FailedTargets" -ForegroundColor Red
Write-Host "Slow Endpoints:      $SlowTargets" -ForegroundColor Yellow

Write-Host ""
Write-Host "PERFORMANCE METRICS" -ForegroundColor Yellow

Write-Host "Success Rate:        $SuccessRate%"
Write-Host "Average Latency:     $AverageLatency ms"
Write-Host "Historical Runs:     $($History.Count)"
Write-Host "Execution Time:      $ExecutionTime seconds"

Write-Host ""
Write-Host "GENERATED REPORTS" -ForegroundColor Yellow

Write-Host "CSV Report:          $LatestCsvPath"
Write-Host "History:             $HistoryFilePath"
Write-Host "Dashboard:           $DashboardFilePath"

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan

# ==========================================
# FINAL EXECUTION STATUS
# ==========================================

if ($FailedTargets -gt 0) {

    Write-Host ""
    Write-Host "[WARNING] Some endpoints failed." -ForegroundColor Red

    exit 1
}

Write-Host ""
Write-Host "[SUCCESS] All endpoints passed." -ForegroundColor Green

exit 0

