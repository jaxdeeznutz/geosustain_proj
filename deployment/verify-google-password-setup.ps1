[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$authRoot = Split-Path -Parent $PSScriptRoot
$authEvidence = Join-Path $authRoot 'defense-evidence\google-password-setup'
$authAttempt = Join-Path $authEvidence ('attempts\' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $authAttempt -Force | Out-Null
$authManifest = Get-Content -LiteralPath (Join-Path $authEvidence 'backend-before.json') -Raw | ConvertFrom-Json
$authAllowed = @('backend/auth_security.py', 'backend/database.py', 'backend/fastapi_app.py', 'backend/federated_identity.py', 'backend/password_reset.py', 'backend/tests/test_federated_identity.py')
$authResults = [System.Collections.Generic.List[object]]::new()
$authPassed = $false

function Test-UnaffectedBackend {
    foreach ($authFile in $authManifest.files.PSObject.Properties) {
        $authPath = Join-Path $authRoot $authFile.Name
        if (!(Test-Path -LiteralPath $authPath -PathType Leaf)) { throw "Backend file missing: $($authFile.Name)" }
        $authHash = (Get-FileHash -LiteralPath $authPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($authHash -ne $authFile.Value -and $authFile.Name -notin $authAllowed) {
            throw "Backend changed outside the approved authentication scope: $($authFile.Name)"
        }
    }
}

Push-Location $authRoot
try {
    Test-UnaffectedBackend
    Write-Host 'PASS: non-auth backend unchanged'
    $authPython = Join-Path $authRoot '.tools\python\python.exe'
    if (!(Test-Path -LiteralPath $authPython -PathType Leaf)) { $authPython = (Get-Command python -ErrorAction Stop).Source }
    $authFlutter = (Get-Command flutter -ErrorAction Stop).Source
    $authCommands = @(
        @{ Name = 'backend-tests'; Executable = $authPython; Arguments = @('-m', 'pytest', 'backend/tests', '-q', '--disable-warnings') },
        @{ Name = 'flutter-pub-offline'; Executable = $authFlutter; Arguments = @('pub', 'get', '--offline') },
        @{ Name = 'flutter-analyze'; Executable = $authFlutter; Arguments = @('analyze', '--no-pub') },
        @{ Name = 'flutter-tests'; Executable = $authFlutter; Arguments = @('test', '--no-pub') },
        @{ Name = 'flutter-web-build'; Executable = $authFlutter; Arguments = @('build', 'web', '--no-pub', '--dart-define=API_BASE_URL=https://geosustain.onrender.com', '--dart-define=WEB_BUILD_ID=google-password-setup-20261103') }
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
        approved_backend_changes = $authAllowed
        backend_baseline = 'backend-before.json'
        limitation = 'Real Firebase configuration and Google login on the intended Android/web releases remain separate acceptance checks. No deployment is performed.'
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $authAttempt 'validation.json') -Encoding UTF8
    Pop-Location
}
Write-Host 'Google password setup checks passed. Configure Firebase and deploy matching backend/client versions before live acceptance.'
