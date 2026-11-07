[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$seasonalRoot = Split-Path -Parent $PSScriptRoot
$seasonalAttempt = Join-Path $seasonalRoot ('defense-evidence\seasonal-planting\attempts\' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $seasonalAttempt -Force | Out-Null
$seasonalPython = Join-Path $seasonalRoot '.tools\python\python.exe'
$seasonalFlutter = (Get-Command flutter -ErrorAction Stop).Source
$seasonalModelFiles = @('backend/crop_model.pkl', 'backend/crop_model_features.pkl', 'backend/crop_model_metadata.json')
$seasonalHashes = @{}
foreach ($seasonalFile in $seasonalModelFiles) {
    $seasonalHashes[$seasonalFile] = (Get-FileHash -LiteralPath (Join-Path $seasonalRoot $seasonalFile) -Algorithm SHA256).Hash
}
$seasonalChecks = [System.Collections.Generic.List[object]]::new()
$seasonalPassed = $false
Push-Location $seasonalRoot
try {
    $seasonalCommands = @(
        @{ Name = 'backend-tests'; Executable = $seasonalPython; Arguments = @('-m', 'pytest', 'backend/tests', 'deployment/test_build_web.py', '-q', '--disable-warnings') },
        @{ Name = 'active-model-and-xai'; Executable = $seasonalPython; Arguments = @('backend/training/verify_annual_prototype.py') },
        @{ Name = 'flutter-pub-offline'; Executable = $seasonalFlutter; Arguments = @('pub', 'get', '--offline') },
        @{ Name = 'flutter-analyze'; Executable = $seasonalFlutter; Arguments = @('analyze', '--no-pub') },
        @{ Name = 'flutter-tests'; Executable = $seasonalFlutter; Arguments = @('test', '--no-pub') },
        @{ Name = 'flutter-web-build'; Executable = $seasonalFlutter; Arguments = @('build', 'web', '--no-pub', '--dart-define=API_BASE_URL=https://geosustain.onrender.com', '--dart-define-from-file=deployment/firebase-web.public.json', '--dart-define=WEB_BUILD_ID=seasonal-planting-v1-20261107') },
        @{ Name = 'flutter-debug-apk'; Executable = $seasonalFlutter; Arguments = @('build', 'apk', '--debug', '--no-pub', '--dart-define-from-file=deployment/firebase-android.public.json', '--dart-define=API_BASE_URL=https://geosustain.onrender.com') }
    )
    foreach ($seasonalCommand in $seasonalCommands) {
        $seasonalLog = Join-Path $seasonalAttempt ($seasonalCommand.Name + '.log')
        $seasonalExecutable = $seasonalCommand.Executable
        $seasonalArguments = $seasonalCommand.Arguments
        $seasonalSavedPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            & $seasonalExecutable @seasonalArguments *> $seasonalLog
            $seasonalExit = $LASTEXITCODE
        } finally { $ErrorActionPreference = $seasonalSavedPreference }
        $seasonalChecks.Add([pscustomobject]@{ check = $seasonalCommand.Name; exit_code = $seasonalExit; log = $seasonalLog })
        if ($seasonalExit -ne 0) {
            Get-Content -LiteralPath $seasonalLog -Tail 65
            throw "$($seasonalCommand.Name) failed. See $seasonalLog"
        }
        Write-Host "PASS: $($seasonalCommand.Name)"
    }
    foreach ($seasonalFile in $seasonalModelFiles) {
        if ((Get-FileHash -LiteralPath (Join-Path $seasonalRoot $seasonalFile) -Algorithm SHA256).Hash -ne $seasonalHashes[$seasonalFile]) {
            throw "Model artifact changed during seasonal checks: $seasonalFile"
        }
    }
    $seasonalPassed = $true
    Write-Host 'PASS: annual model artifacts unchanged'
} finally {
    [ordered]@{
        recorded_at_utc = [DateTime]::UtcNow.ToString('o')
        checks_passed = $seasonalPassed
        checks = @($seasonalChecks.ToArray())
        model_hashes = $seasonalHashes
        limitation = 'Reference-based seasonal moisture advisory, not a trained seasonal model or field-validated planting calendar. Deploy matching backend/client versions, then run a new analysis. Live acceptance is separate.'
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $seasonalAttempt 'validation.json') -Encoding UTF8
    Pop-Location
}
Write-Host 'Seasonal planting checks passed. APK: build\app\outputs\flutter-apk\app-debug.apk. Deploy matching backend/client versions before testing a new seasonal analysis.'
