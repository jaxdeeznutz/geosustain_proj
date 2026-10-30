[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$phaseRoot = Split-Path -Parent $PSScriptRoot
$phaseEvidence = Join-Path $phaseRoot 'defense-evidence\capstone-fix-execution\phase-05'
New-Item -ItemType Directory -Path $phaseEvidence -Force | Out-Null
$phaseRunEvidence = Join-Path $phaseEvidence ('attempts\' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $phaseRunEvidence -Force | Out-Null
$phaseResults = [System.Collections.Generic.List[object]]::new()
$phaseSucceeded = $false

Push-Location $phaseRoot
try {
    $phaseFlutter = (Get-Command flutter -ErrorAction Stop).Source
    $phaseCommands = @(
        @{ Name = 'flutter-pub-offline'; Arguments = @('pub', 'get', '--offline') },
        @{ Name = 'flutter-analyze'; Arguments = @('analyze', '--no-pub') },
        @{ Name = 'flutter-tests'; Arguments = @('test', '--no-pub') },
        @{ Name = 'flutter-web-build'; Arguments = @('build', 'web', '--no-pub', '--dart-define=API_BASE_URL=https://geosustain.onrender.com') }
    )
    foreach ($phaseCommand in $phaseCommands) {
        $phaseStarted = [DateTime]::UtcNow
        $phaseLog = Join-Path $phaseRunEvidence ($phaseCommand.Name + '.log')
        $phaseArguments = $phaseCommand.Arguments
        $phaseSavedPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            & $phaseFlutter @phaseArguments *> $phaseLog
            $phaseExit = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $phaseSavedPreference
        }
        $phaseResults.Add([pscustomobject]@{
            check = $phaseCommand.Name
            arguments = $phaseArguments
            started_utc = $phaseStarted.ToString('o')
            ended_utc = [DateTime]::UtcNow.ToString('o')
            exit_code = $phaseExit
            log = $phaseLog
        })
        if ($phaseExit -ne 0) {
            Get-Content -LiteralPath $phaseLog -Tail 60
            throw "$($phaseCommand.Name) failed. The phase remains pending; see $phaseLog"
        }
        Write-Host "PASS: $($phaseCommand.Name)"
    }
    $phaseSucceeded = $true
}
finally {
    $phaseSourceRevision = (& git rev-parse HEAD) -join ''
    $phaseChanges = @(& git status --short)
    $phaseSummary = [ordered]@{
        recorded_at_utc = [DateTime]::UtcNow.ToString('o')
        source_commit = $phaseSourceRevision
        working_tree_status = $phaseChanges
        checks = @($phaseResults.ToArray())
        checks_passed = $phaseSucceeded
        limitation = 'Automated client checks only; no deployed/installed-device or human acceptance is implied.'
        run_evidence = $phaseRunEvidence
    }
    $phaseSummary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $phaseRunEvidence 'client-validation.json') -Encoding UTF8
    $phaseSummary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $phaseEvidence 'client-validation.json') -Encoding UTF8
    Pop-Location
}

Write-Host 'Client checks passed. Record the separate manual journey before closing Phase 5.'
