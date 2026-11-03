[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$designRoot = Split-Path -Parent $PSScriptRoot
$designEvidence = Join-Path $designRoot 'defense-evidence\review-case-redesign'
$designAttempt = Join-Path $designEvidence ('attempts\' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $designAttempt -Force | Out-Null
$designResults = [System.Collections.Generic.List[object]]::new()
$designPassed = $false
$designManifest = Get-Content -LiteralPath (Join-Path $designEvidence 'backend-before.json') -Raw | ConvertFrom-Json

function Test-DesignBackendUnchanged {
    foreach ($designFile in $designManifest.files.PSObject.Properties) {
        $designPath = Join-Path $designRoot $designFile.Name
        if (!(Test-Path -LiteralPath $designPath -PathType Leaf)) {
            throw "Backend file missing: $($designFile.Name)"
        }
        $designHash = (Get-FileHash -LiteralPath $designPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($designHash -ne $designFile.Value) {
            throw "Backend changed since the design baseline: $($designFile.Name)"
        }
    }
}

Push-Location $designRoot
try {
    Test-DesignBackendUnchanged
    Write-Host 'PASS: backend unchanged'
    $designFlutter = (Get-Command flutter -ErrorAction Stop).Source
    $designCommands = @(
        @{ Name = 'flutter-pub-offline'; Arguments = @('pub', 'get', '--offline') },
        @{ Name = 'flutter-analyze'; Arguments = @('analyze', '--no-pub') },
        @{ Name = 'flutter-tests'; Arguments = @('test', '--no-pub') },
        @{ Name = 'flutter-web-build'; Arguments = @('build', 'web', '--no-pub', '--dart-define=API_BASE_URL=https://geosustain.onrender.com', '--dart-define-from-file=deployment/firebase-web.public.json', '--dart-define=WEB_BUILD_ID=review-case-redesign-20261103') }
    )
    foreach ($designCommand in $designCommands) {
        $designLog = Join-Path $designAttempt ($designCommand.Name + '.log')
        $designArguments = $designCommand.Arguments
        $designSavedPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            & $designFlutter @designArguments *> $designLog
            $designExit = $LASTEXITCODE
        }
        finally { $ErrorActionPreference = $designSavedPreference }
        $designResults.Add([pscustomobject]@{ check = $designCommand.Name; exit_code = $designExit; log = $designLog })
        if ($designExit -ne 0) {
            Get-Content -LiteralPath $designLog -Tail 65
            throw "$($designCommand.Name) failed. See $designLog"
        }
        Write-Host "PASS: $($designCommand.Name)"
    }
    Test-DesignBackendUnchanged
    $designPassed = $true
}
finally {
    [ordered]@{
        recorded_at_utc = [DateTime]::UtcNow.ToString('o')
        source_commit = ((& git rev-parse HEAD) -join '')
        checks_passed = $designPassed
        checks = @($designResults.ToArray())
        backend_baseline = 'backend-before.json'
        limitation = 'Frontend checks and backend file integrity only. Browser visual acceptance remains separate; Phases 8-9 remain paused.'
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $designAttempt 'validation.json') -Encoding UTF8
    Pop-Location
}
Write-Host 'Review case redesign checks passed. Preview PNGs: build\review-case-previews. Restart only the Flutter web client to review.'
