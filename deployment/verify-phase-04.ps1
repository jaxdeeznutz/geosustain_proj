[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$phaseRoot = Split-Path -Parent $PSScriptRoot
$phasePython = Join-Path $phaseRoot '.tools\python\python.exe'
if (-not (Test-Path -LiteralPath $phasePython)) {
    throw 'The project test Python is missing: .tools\python\python.exe. Phase 4 verification was not run.'
}
Push-Location $phaseRoot
try {
    $phaseSavedPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $phasePython 'backend\tests\verify_phase04_tooling.py'
        $phaseExit = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $phaseSavedPreference
    }
    if ($phaseExit -ne 0) {
        throw 'Phase 4 tooling verification failed; see defense-evidence\capstone-fix-execution\phase-04\tooling-validation.json.'
    }
    Write-Host 'Phase 4 local audit/tooling checks passed. Scientific model acceptance remains a separate Phase 8 gate.'
}
finally {
    Pop-Location
}
