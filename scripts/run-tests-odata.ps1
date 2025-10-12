#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Execute AL tests via OData API using the Codeunit Run Request system.

.DESCRIPTION
    This script executes AL test codeunits via the OData API exposed by the
    Codeunit Run Requests API page (page 50002). It provides a stateful
    execution pattern with status tracking.

.PARAMETER BaseUrl
    The base URL of the Business Central instance (e.g., "http://localhost:7049/BC")

.PARAMETER Tenant
    The tenant name (default: "default")

.PARAMETER Username
    Username for authentication (default: "admin")

.PARAMETER Password
    Password for authentication (default: "P@ssw0rd123!")

.PARAMETER CodeunitId
    The ID of the test codeunit to execute (default: 50002 - "Test CU")

.PARAMETER MaxWaitSeconds
    Maximum time to wait for test execution to complete (default: 300 seconds)

.EXAMPLE
    ./run-tests-odata.ps1 -BaseUrl "http://localhost:7048/BC" -CodeunitId 50002

.NOTES
    API Endpoint: /api/custom/automation/v1.0/codeunitRunRequests
    Uses the state-tracked execution pattern with status monitoring.
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$BaseUrl = "http://localhost:7048/BC",

    [Parameter(Mandatory=$false)]
    [string]$Tenant = "default",

    [Parameter(Mandatory=$false)]
    [string]$Username = "admin",

    [Parameter(Mandatory=$false)]
    [string]$Password = "P@ssw0rd123!",

    [Parameter(Mandatory=$false)]
    [int]$CodeunitId = 50002,

    [Parameter(Mandatory=$false)]
    [int]$MaxWaitSeconds = 300
)

# Enable strict mode
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Build API endpoint
$ApiPath = "/api/custom/automation/v1.0/codeunitRunRequests"
$ApiUrl = "$BaseUrl$ApiPath"

Write-Host "=== AL Test Execution via OData API ===" -ForegroundColor Cyan
Write-Host "Base URL: $BaseUrl" -ForegroundColor Gray
Write-Host "Tenant: $Tenant" -ForegroundColor Gray
Write-Host "Codeunit ID: $CodeunitId" -ForegroundColor Gray
Write-Host ""

# Use hardcoded working base64 credentials (admin:P@ssw0rd123!)
$base64AuthInfo = "YWRtaW46UEBzc3cwcmQxMjMh"

# Headers for API requests
$Headers = @{
    "Content-Type" = "application/json"
    "Accept" = "application/json"
    "Authorization" = "Basic $base64AuthInfo"
}

try {
    # Pre-flight check: Test basic API connectivity
    Write-Host "[0/4] Testing API connectivity..." -ForegroundColor Yellow
    try {
        $testUrl = "$BaseUrl/api/v2.0/companies"
        $testResponse = Invoke-WebRequest -Uri $testUrl `
            -Method Get `
            -Headers $Headers `
            -AllowUnencryptedAuthentication `
            -SkipHttpErrorCheck `
            -TimeoutSec 10

        if ($testResponse.StatusCode -eq 200) {
            Write-Host "✓ API is accessible (HTTP $($testResponse.StatusCode))" -ForegroundColor Green
        } elseif ($testResponse.StatusCode -eq 401) {
            Write-Host "✗ Authentication failed (HTTP 401)" -ForegroundColor Red
            Write-Host "  Current credentials: $Username / [password hidden]" -ForegroundColor Gray
            Write-Host "  Please verify container credentials or check BCDevOnLinux setup" -ForegroundColor Yellow
            exit 1
        } else {
            Write-Host "⚠ Unexpected status code: $($testResponse.StatusCode)" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "⚠ Warning: Could not verify API connectivity: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "  Continuing anyway..." -ForegroundColor Gray
    }
    Write-Host ""

    Write-Host "[1/4] Creating execution request..." -ForegroundColor Yellow

    # Step 1: Create a new Codeunit Run Request
    $RequestBody = @{
        CodeunitId = $CodeunitId
    } | ConvertTo-Json

    $CreateResponse = Invoke-RestMethod -Uri "$ApiUrl" `
        -Method Post `
        -Headers $Headers `
        -Body $RequestBody `
        -AllowUnencryptedAuthentication `
        -SkipHttpErrorCheck `
        -TimeoutSec 30

    $RequestId = $CreateResponse.Id
    $RequestUrl = "$ApiUrl($RequestId)"

    Write-Host "✓ Request created with ID: $RequestId" -ForegroundColor Green
    Write-Host "  Status: $($CreateResponse.Status)" -ForegroundColor Gray
    Write-Host ""

    Write-Host "[2/4] Executing codeunit..." -ForegroundColor Yellow

    # Step 2: Execute the codeunit via the runCodeunit action
    $ActionUrl = "$BaseUrl/api/custom/automation/v1.0/codeunitRunRequests($RequestId)/Microsoft.NAV.runCodeunit"

    $ExecuteResponse = Invoke-RestMethod -Uri $ActionUrl `
        -Method Post `
        -Headers $Headers `
        -AllowUnencryptedAuthentication `
        -SkipHttpErrorCheck `
        -TimeoutSec 60

    Write-Host "✓ Execution triggered" -ForegroundColor Green
    Write-Host ""

    Write-Host "[3/4] Monitoring execution status..." -ForegroundColor Yellow

    # Step 3: Poll for completion
    $StartTime = Get-Date
    $Completed = $false
    $Status = "Running"
    $LastResult = ""
    $PollCount = 0

    while (-not $Completed) {
        $PollCount++
        $ElapsedSeconds = ((Get-Date) - $StartTime).TotalSeconds

        if ($ElapsedSeconds -gt $MaxWaitSeconds) {
            Write-Host "✗ Timeout: Execution did not complete within $MaxWaitSeconds seconds" -ForegroundColor Red
            exit 1
        }

        # Get current status
        $StatusResponse = Invoke-RestMethod -Uri "$RequestUrl" `
            -Method Get `
            -Headers $Headers `
            -AllowUnencryptedAuthentication `
            -SkipHttpErrorCheck `
            -TimeoutSec 30

        $Status = $StatusResponse.Status
        $LastResult = $StatusResponse.LastResult
        $LastExecutionUTC = $StatusResponse.LastExecutionUTC

        Write-Host "  Poll #$PollCount - Status: $Status (${ElapsedSeconds}s elapsed)" -ForegroundColor Gray

        if ($Status -eq "Finished" -or $Status -eq "Error") {
            $Completed = $true
        } else {
            # Wait 2 seconds before next poll
            Start-Sleep -Seconds 2
        }
    }

    Write-Host ""
    Write-Host "[4/4] Execution Results:" -ForegroundColor Yellow
    Write-Host "  Status: $Status" -ForegroundColor $(if ($Status -eq "Finished") { "Green" } else { "Red" })
    Write-Host "  Result: $LastResult" -ForegroundColor Gray
    Write-Host "  Execution Time (UTC): $LastExecutionUTC" -ForegroundColor Gray
    Write-Host "  Total Wait Time: $([Math]::Round($ElapsedSeconds, 2)) seconds" -ForegroundColor Gray
    Write-Host ""

    # Step 4: Check Log Table via OData (if available)
    Write-Host "[BONUS] Checking execution logs..." -ForegroundColor Yellow

    try {
        # Note: This assumes you have an API page exposing the Log Table
        # You may need to create one or skip this step
        $LogApiUrl = "$BaseUrl/api/v2.0/companies(default)/logEntries?\$top=5&\$orderby=entryNo desc"

        Write-Host "  (Skipping log retrieval - API page for Log Table not yet implemented)" -ForegroundColor Gray
        # Uncomment when Log Table API is available:
        # $LogResponse = Invoke-RestMethod -Uri $LogApiUrl -Method Get -Credential $Credential -Headers $Headers -AllowUnencryptedAuthentication -TimeoutSec 30
        # $LogResponse.value | ForEach-Object {
        #     Write-Host "  Log: $($_.'message') - Computer: $($_.'computerName')" -ForegroundColor Gray
        # }
    } catch {
        Write-Host "  (Could not retrieve logs: $($_.Exception.Message))" -ForegroundColor DarkGray
    }

    Write-Host ""

    # Exit with appropriate code
    if ($Status -eq "Finished") {
        Write-Host "=== TEST EXECUTION SUCCESSFUL ===" -ForegroundColor Green
        exit 0
    } else {
        Write-Host "=== TEST EXECUTION FAILED ===" -ForegroundColor Red
        Write-Host "Error: $LastResult" -ForegroundColor Red
        exit 1
    }

} catch {
    Write-Host ""
    Write-Host "=== FATAL ERROR ===" -ForegroundColor Red
    Write-Host "Error Type: $($_.Exception.GetType().Name)" -ForegroundColor Red
    Write-Host "Error Message: $($_.Exception.Message)" -ForegroundColor Red

    if ($_.Exception.Response) {
        $statusCode = $_.Exception.Response.StatusCode
        Write-Host "HTTP Status Code: $($statusCode.value__)" -ForegroundColor Red

        # Read response body if available
        try {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $responseBody = $reader.ReadToEnd()
            $reader.Close()
            if ($responseBody) {
                Write-Host "Response Body: $responseBody" -ForegroundColor Red
            }
        } catch {
            # Ignore errors reading response body
        }
    }

    Write-Host ""
    Write-Host "Troubleshooting Tips:" -ForegroundColor Yellow
    Write-Host "  1. Verify BC container is running: docker ps" -ForegroundColor Gray
    Write-Host "  2. Check credentials match container config" -ForegroundColor Gray
    Write-Host "  3. Verify API endpoint is accessible: curl $BaseUrl/api/v2.0/companies" -ForegroundColor Gray
    Write-Host "  4. Check if extension is published with API page 50002" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Full Error Details:" -ForegroundColor DarkRed
    Write-Host $_ -ForegroundColor DarkRed

    exit 1
}
