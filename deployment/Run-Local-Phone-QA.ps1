param([Parameter(Mandatory=$true)][string]$Device)
$ErrorActionPreference='Stop'
$projectRoot=(Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$adb=Join-Path $env:LOCALAPPDATA 'Android/Sdk/platform-tools/adb.exe'
$python=Join-Path $projectRoot '.tools/python/python.exe'
$apk=Join-Path $env:USERPROFILE 'Downloads/GeoSustain-QA-Readiness-2026-10-24.apk'
$qaWork='D:/GeoSustain-defense-temp-2026-10-23'
foreach ($path in @($adb,$python,$apk,$qaWork)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Required local QA path is unavailable: $path" }
}
if ($Device -notmatch '^([0-9]{1,3}\.){3}[0-9]{1,3}:[0-9]{2,5}$') {
    throw 'Use the current Wireless debugging main-screen IPv4 address:port. Do not use its pairing port/code.'
}
$ready=$false
try { $ready=(Invoke-WebRequest -UseBasicParsing 'http://127.0.0.1:18000/ready' -TimeoutSec 5).StatusCode -eq 200 } catch {}
if (-not $ready) {
    if (Get-NetTCPConnection -LocalPort 18000 -State Listen -ErrorAction SilentlyContinue) {
        throw 'A local service is already running but not ready. Check its logs; no process or data was changed.'
    }
    $launcher=Join-Path $projectRoot 'defense-evidence/2026-10-23/android-wireless-acceptance/local_qa_server.py'
    Start-Process -FilePath $python -ArgumentList ('"'+$launcher+'"') -WorkingDirectory $projectRoot -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $qaWork 'manual-local-backend.out.log') `
        -RedirectStandardError (Join-Path $qaWork 'manual-local-backend.err.log')
    for ($attempt=0;$attempt -lt 15;$attempt++) {
        Start-Sleep -Milliseconds 500
        try { $ready=(Invoke-WebRequest -UseBasicParsing 'http://127.0.0.1:18000/ready' -TimeoutSec 2).StatusCode -eq 200 } catch {}
        if ($ready) { break }
    }
    if (-not $ready) { throw 'The isolated local backend is not ready. Inspect the local QA logs; do not change the production database.' }
}
& $adb connect $Device
if ($LASTEXITCODE -ne 0) { throw 'Wireless connection failed. Unlock the phone and check its current debugging address.' }
& $adb -s $Device reverse tcp:18000 tcp:18000
if ($LASTEXITCODE -ne 0) { throw 'Port forwarding failed; no app installation attempted.' }
$env:GEOSUSTAIN_QA_DEVICE=$Device
& $python (Join-Path $projectRoot 'defense-evidence/2026-10-23/grouped-fixes/restore_logging.py')
if ($LASTEXITCODE -ne 0) { throw 'Original test logging state could not be confirmed. Inspect the restoration receipt before continuing.' }
& $adb -s $Device install -r $apk
if ($LASTEXITCODE -ne 0) { throw 'Update failed. Keep the existing app/data; do not uninstall to bypass a signing error.' }
Write-Output 'GeoSustain QA 1.0.1 installed over the separate phoneqa app. Open GeoSustain QA on the phone.'
Write-Output 'API: http://127.0.0.1:18000 through ADB. Keep the PC/backend and debugging connection running.'
