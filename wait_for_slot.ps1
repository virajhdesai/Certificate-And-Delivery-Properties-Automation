param (
    [Parameter(Mandatory = $true)]
    [string]$EnrollmentId,

    [string]$ConfigSection = "akamaio",
    [int]$TimeoutMinutes = 150
)

$pythonExe = "C:\Users\videsa\AppData\Local\Programs\Python\Python312\python.exe"
$pythonScript = Join-Path $PSScriptRoot "check_cps_status.py"

Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host "Tracking CPS Deployment for Enrollment: $EnrollmentId" -ForegroundColor Cyan
Write-Host "==========================================================================" -ForegroundColor Cyan

$startTime = Get-Date
$timeoutTime = $startTime.AddMinutes($TimeoutMinutes)

while ((Get-Date) -lt $timeoutTime) {
    # Call external Python script cleanly without inline syntax escaping issues
    $output = & $pythonExe $pythonScript $EnrollmentId $ConfigSection 2>&1 | Out-String

    if (-not [string]::IsNullOrWhiteSpace($output)) {
        try {
            $json = $output | ConvertFrom-Json
            $elapsed = [math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)

            # Check if primaryCertificate or active/deployed status is returned
            $hasStagingCert = $null -ne $json.staging.primaryCertificate
            $hasProdCert = $null -ne $json.production.primaryCertificate

            Write-Host "[$(Get-Date -Format 'HH:mm:ss') | ${elapsed}m] Staging Cert Deployed: $hasStagingCert | Prod Cert Deployed: $hasProdCert" -ForegroundColor Yellow

            if ($hasStagingCert -or $hasProdCert -or $output -match "primaryCertificate" -or $output -match "active") {
                Write-Host "==========================================================================" -ForegroundColor Green
                Write-Host "SUCCESS: CPS Certificate is ACTIVE and deployed!" -ForegroundColor Green
                Write-Host "==========================================================================" -ForegroundColor Green
                exit 0
            }
        }
        catch {
            if ($output -match "ERROR:") {
                Write-Host "Python Exception: $($output.Trim())" -ForegroundColor Red
            }
        }
    }

    $elapsed = [math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)
    Write-Host "[$(Get-Date -Format 'HH:mm:ss') | ${elapsed}m] Polling Akamai CPS deployment status..." -ForegroundColor Yellow

    Start-Sleep -Seconds 20
}

Write-Error "TIMEOUT: Certificate slot failed to deploy within $TimeoutMinutes minutes."
exit 1