[CmdletBinding()]
param([string]$DeviceId, [switch]$Phone, [switch]$BuildApk)

$ErrorActionPreference = 'Stop'
$phaseRoot = Split-Path -Parent $PSScriptRoot
$phaseFlutter = (Get-Command flutter -ErrorAction Stop).Source
$previousPhaseQa = [Environment]::GetEnvironmentVariable('GEOSUSTAIN_PHASE01_QA', 'Process')

function Invoke-PhaseTool {
    param([string]$Executable, [string[]]$Arguments)
    $phasePreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $Executable @Arguments
        $phaseExit = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $phasePreference }
    if ($phaseExit -ne 0) { throw "$Executable failed (exit $phaseExit). Keep the output above for review." }
}

function Get-PhaseAndroidDevices {
    param([object[]]$Devices, [bool]$UsePhone)
    $Devices | Where-Object {
        $_.targetPlatform -like 'android*' -and ($_.emulator -eq (!$UsePhone))
    }
}

Push-Location $phaseRoot
try {
    $phaseDevicesOutput = Invoke-PhaseTool $phaseFlutter @('devices', '--machine')
    # Windows PowerShell can emit a JSON array as one pipeline object.
    # Capture it first so the following pipeline enumerates individual devices.
    $phaseAllDevices = ConvertFrom-Json -InputObject ($phaseDevicesOutput -join "`n")
    $phaseDevices = @(Get-PhaseAndroidDevices -Devices $phaseAllDevices -UsePhone $Phone.IsPresent)
    if (!$DeviceId) {
        if ($phaseDevices.Count -ne 1) {
            $phaseAllDevices | Select-Object id, name, targetPlatform, emulator | Format-Table
            throw 'No unique matching Android device. Run flutter devices; authorize USB debugging or pair/connect Wireless debugging. For multiple matching devices, pass -DeviceId.'
        }
        $DeviceId = $phaseDevices[0].id
    }
    if (!($phaseDevices | Where-Object { $_.id -eq $DeviceId })) { throw 'Choose a matching authorized Android device shown by flutter devices.' }

    $phaseSdkCandidates = @($env:ANDROID_SDK_ROOT, $env:ANDROID_HOME, (Join-Path $env:LOCALAPPDATA 'Android\Sdk'))
    $phaseSdkLine = Get-Content -LiteralPath (Join-Path $phaseRoot 'android\local.properties') -ErrorAction SilentlyContinue | Where-Object { $_ -match '^sdk.dir=' } | Select-Object -First 1
    if ($phaseSdkLine) { $phaseSdkCandidates += $phaseSdkLine.Substring(8).Replace('\\', '\').Replace('\:', ':') }
    $phaseAdb = (Get-Command adb.exe -ErrorAction SilentlyContinue).Source
    if (!$phaseAdb) {
        foreach ($phaseSdkCandidate in $phaseSdkCandidates) {
            if ($phaseSdkCandidate -and (Test-Path -LiteralPath (Join-Path $phaseSdkCandidate 'platform-tools\adb.exe'))) {
                $phaseAdb = Join-Path $phaseSdkCandidate 'platform-tools\adb.exe'
                break
            }
        }
    }
    if (($Phone -or $BuildApk) -and !$phaseAdb) { throw 'Android platform-tools/adb.exe was not found. Keep the output for review.' }
    $phaseApi = 'http://10.0.2.2:18001'
    if ($Phone) {
        Invoke-PhaseTool $phaseAdb @('-s', $DeviceId, 'reverse', 'tcp:18001', 'tcp:18001')
        $phaseApi = 'http://127.0.0.1:18001'
    }
    $env:GEOSUSTAIN_PHASE01_QA = 'true'
    if ($BuildApk) {
        Invoke-PhaseTool $phaseFlutter @('build', 'apk', '--debug', '--no-pub', "--dart-define=API_BASE_URL=$phaseApi")
        $phasePackage = 'com.example.geosustain_clean_arranged.phase01qa'
        $phaseMetadataPath = Join-Path $phaseRoot 'build\app\outputs\apk\debug\output-metadata.json'
        $phaseMetadata = Get-Content -LiteralPath $phaseMetadataPath -Raw | ConvertFrom-Json
        if ($phaseMetadata.applicationId -ne $phasePackage) {
            throw "Refusing installation: build metadata package '$($phaseMetadata.applicationId)' does not match '$phasePackage'. No app was installed."
        }
        $phaseApkDirectory = Join-Path $phaseRoot 'build\phase-01'
        New-Item -ItemType Directory -Path $phaseApkDirectory -Force | Out-Null
        $phaseApk = Join-Path $phaseApkDirectory 'geosustain-phase01-debug.apk'
        Copy-Item -LiteralPath (Join-Path $phaseRoot 'build\app\outputs\flutter-apk\app-debug.apk') -Destination $phaseApk
        Write-Host "Test APK: $phaseApk"
        $phaseSdkCandidates += Split-Path -Parent (Split-Path -Parent $phaseAdb)
        $phaseAapt = $null
        foreach ($phaseSdkCandidate in ($phaseSdkCandidates | Where-Object { $_ } | Select-Object -Unique)) {
            $phaseBuildTools = Join-Path $phaseSdkCandidate 'build-tools'
            if (Test-Path -LiteralPath $phaseBuildTools) {
                $phaseAapt = Get-ChildItem -LiteralPath $phaseBuildTools -Filter aapt.exe -Recurse -File | Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
                if ($phaseAapt) { break }
            }
        }
        if (!$phaseAapt) { throw 'APK built, but aapt.exe is required to verify its test package before installation.' }
        $phaseBadging = Invoke-PhaseTool $phaseAapt @('dump', 'badging', $phaseApk)
        if (!($phaseBadging -match "^package: name='$([regex]::Escape($phasePackage))' ")) {
            $phasePackageLine = @($phaseBadging | Where-Object { $_ -match '^package:' }) -join ' '
            throw "Refusing installation: APK package check failed. Expected '$phasePackage'. Reported: $phasePackageLine. No app was installed."
        }
        Invoke-PhaseTool $phaseAdb @('-s', $DeviceId, 'install', '-r', $phaseApk)
        Invoke-PhaseTool $phaseAdb @('-s', $DeviceId, 'shell', 'am', 'start', '-n', "$phasePackage/com.example.geosustain_clean_arranged.MainActivity")
        Write-Host "Phone test copy installed and opened. Keep the ADB connection active (USB or wireless) while using the local backend. Device: $DeviceId"
    }
    else {
        Invoke-PhaseTool $phaseFlutter @('run', '--debug', '-d', $DeviceId, '--no-pub', "--dart-define=API_BASE_URL=$phaseApi")
    }
}
finally {
    [Environment]::SetEnvironmentVariable('GEOSUSTAIN_PHASE01_QA', $previousPhaseQa, 'Process')
    Pop-Location
}
