[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$authRoot = Split-Path -Parent $PSScriptRoot
$authEvidence = Join-Path $authRoot 'defense-evidence\annual-climate-analysis'
$authAttempt = Join-Path $authEvidence ('attempts\' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $authAttempt -Force | Out-Null
$authManifest = Get-Content -LiteralPath (Join-Path $authEvidence 'backend-before.json') -Raw | ConvertFrom-Json
$authAllowed = @('backend/environmental_pipeline.py', 'backend/provider_cache.py', 'backend/rainfallDatasets.py', 'backend/fastapi_app.py', 'backend/tests/conftest.py', 'backend/model_artifacts.py', 'backend/training/train_model.py', 'backend/tests/test_model_artifacts.py', 'backend/climate_contract.py', 'backend/model_explainability.py', 'backend/seasonal_assessment.py', 'backend/spatial_analysis.py', 'backend/spatial_provider.py', 'backend/suitability.py', 'backend/training/climate_training_contract.py', 'backend/training/evaluate_models.py', 'backend/tests/test_analysis_optimization_comparison.py', 'backend/tests/test_climate_contract.py', 'backend/tests/test_legacy_npk_restore.py', 'backend/tests/test_model_evaluation.py', 'backend/tests/test_model_ranking.py', 'backend/tests/test_regressions.py', 'backend/tests/test_spatial_provider.py')
$authResults = [System.Collections.Generic.List[object]]::new()
$authPassed = $false

function Test-UnaffectedBackend {
    foreach ($authFile in $authManifest.files.PSObject.Properties) {
        $authPath = Join-Path $authRoot $authFile.Name
        if (!(Test-Path -LiteralPath $authPath -PathType Leaf)) { throw "Backend file missing: $($authFile.Name)" }
        $authHash = (Get-FileHash -LiteralPath $authPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($authHash -ne $authFile.Value -and $authFile.Name -notin $authAllowed) {
            throw "Backend changed outside the approved provider, seven-crop and annual-climate scope: $($authFile.Name)"
        }
    }
}

Push-Location $authRoot
try {
    Test-UnaffectedBackend
    Write-Host 'PASS: backend scope checked; production artifacts unchanged'
    $authPython = Join-Path $authRoot '.tools\python\python.exe'
    if (!(Test-Path -LiteralPath $authPython -PathType Leaf)) { $authPython = (Get-Command python -ErrorAction Stop).Source }
    $authFlutter = (Get-Command flutter -ErrorAction Stop).Source
    $authCommands = @(
        @{ Name = 'backend-tests'; Executable = $authPython; Arguments = @('-m', 'pytest', 'backend/tests', 'deployment/test_build_web.py', '-q', '--disable-warnings') },
        @{ Name = 'candidate-verification'; Executable = $authPython; Arguments = @('backend/training/verify_seven_crop_candidate.py', 'research/seven-crop-candidates/20261103-seven-crops') },
        @{ Name = 'flutter-pub-offline'; Executable = $authFlutter; Arguments = @('pub', 'get', '--offline') },
        @{ Name = 'flutter-analyze'; Executable = $authFlutter; Arguments = @('analyze', '--no-pub') },
        @{ Name = 'flutter-tests'; Executable = $authFlutter; Arguments = @('test', '--no-pub') },
        @{ Name = 'flutter-web-build'; Executable = $authFlutter; Arguments = @('build', 'web', '--no-pub', '--dart-define=API_BASE_URL=https://geosustain.onrender.com', '--dart-define-from-file=deployment/firebase-web.public.json', '--dart-define=WEB_BUILD_ID=annual-climate-20261106') },
        @{ Name = 'flutter-debug-apk'; Executable = $authFlutter; Arguments = @('build', 'apk', '--debug', '--no-pub', '--dart-define-from-file=deployment/firebase-android.public.json', '--dart-define=API_BASE_URL=https://geosustain.onrender.com') }
    )
    foreach ($authCommand in $authCommands) {
        $authLog = Join-Path $authAttempt ($authCommand.Name + '.log')
        $authExecutable = $authCommand.Executable
        $authArguments = $authCommand.Arguments
        $authSavedPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            & $authExecutable @authArguments *> $authLog
            $authExit = $LASTEXITCODE
        }
        finally { $ErrorActionPreference = $authSavedPreference }
        $authResults.Add([pscustomobject]@{ check = $authCommand.Name; exit_code = $authExit; log = $authLog })
        if ($authExit -ne 0) {
            Get-Content -LiteralPath $authLog -Tail 65
            throw "$($authCommand.Name) failed. See $authLog"
        }
        Write-Host "PASS: $($authCommand.Name)"
    }
    Test-UnaffectedBackend
    $authPassed = $true
}
finally {
    [ordered]@{
        recorded_at_utc = [DateTime]::UtcNow.ToString('o')
        checks_passed = $authPassed
        checks = @($authResults.ToArray())
        provider_backend_changes = $authAllowed
        backend_baseline = 'backend-before.json'
        limitation = 'New analyses use five-year annual rainfall and temperature. Unsupported models yield explicit reference-only comparisons. The archived seven-class experiment remains unapproved for annual input. Model/data artifacts are preserved; device acceptance and deployment remain separate.'
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $authAttempt 'validation.json') -Encoding UTF8
    Pop-Location
}
Write-Host 'Annual climate/client checks passed. APK: build\app\outputs\flutter-apk\app-debug.apk. Deploy matching backend/client versions for annual-only analysis. Unsupported crop models remain explicitly unavailable; no model was promoted.'
