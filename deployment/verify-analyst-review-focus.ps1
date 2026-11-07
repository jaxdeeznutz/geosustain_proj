[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$reviewRoot = Split-Path -Parent $PSScriptRoot
$reviewAttempt = Join-Path $reviewRoot ('defense-evidence\analyst-review-focus\attempts\' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $reviewAttempt -Force | Out-Null
$reviewPython = Join-Path $reviewRoot '.tools\python\python.exe'
$reviewFlutter = (Get-Command flutter -ErrorAction Stop).Source
$reviewPreviousFlutter = $env:FLUTTER_BIN
$reviewChecks = [System.Collections.Generic.List[object]]::new()
$reviewPassed = $false
Push-Location $reviewRoot
try {
    $env:FLUTTER_BIN = $reviewFlutter
    $reviewCommands = @(
        @{ Name = 'backend-tests'; Executable = $reviewPython; Arguments = @('-m', 'pytest', 'backend/tests', 'deployment/test_build_web.py', '-q', '--disable-warnings') },
        @{ Name = 'active-model-and-xai'; Executable = $reviewPython; Arguments = @('backend/training/verify_annual_prototype.py') },
        @{ Name = 'flutter-pub-offline'; Executable = $reviewFlutter; Arguments = @('pub', 'get', '--offline') },
        @{ Name = 'flutter-analyze'; Executable = $reviewFlutter; Arguments = @('analyze', '--no-pub') },
        @{ Name = 'flutter-tests'; Executable = $reviewFlutter; Arguments = @('test', '--no-pub') },
        @{ Name = 'flutter-web-build'; Executable = $reviewPython; Arguments = @('deployment/build_web.py') },
        @{ Name = 'flutter-debug-apk'; Executable = $reviewFlutter; Arguments = @('build', 'apk', '--debug', '--no-pub', '--dart-define-from-file=deployment/firebase-android.public.json', '--dart-define=API_BASE_URL=https://geosustain.onrender.com') }
    )
    foreach ($reviewCommand in $reviewCommands) {
        $reviewLog = Join-Path $reviewAttempt ($reviewCommand.Name + '.log')
        $reviewExecutable = $reviewCommand.Executable
        $reviewArguments = $reviewCommand.Arguments
        $reviewPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            & $reviewExecutable @reviewArguments *> $reviewLog
            $reviewExit = $LASTEXITCODE
        } finally { $ErrorActionPreference = $reviewPreference }
        $reviewChecks.Add([pscustomobject]@{ check = $reviewCommand.Name; exit_code = $reviewExit; log = $reviewLog })
        if ($reviewExit -ne 0) {
            Get-Content -LiteralPath $reviewLog -Tail 50
            throw "$($reviewCommand.Name) failed. See $reviewLog"
        }
        Write-Host "PASS: $($reviewCommand.Name)"
    }
    $reviewPassed = $true
} finally {
    [ordered]@{
        recorded_at_utc = [DateTime]::UtcNow.ToString('o')
        checks_passed = $reviewPassed
        checks = @($reviewChecks.ToArray())
        live_acceptance = 'Deploy matching backend and web builds. Sign in again, confirm Overview, then open a submitted case from the map. Timeouts offer an explicit retry; server availability is a separate live check.'
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $reviewAttempt 'validation.json') -Encoding UTF8
    $env:FLUTTER_BIN = $reviewPreviousFlutter
    Pop-Location
}
Write-Host 'Analyst review checks passed. Web: build\web. APK: build\app\outputs\flutter-apk\app-debug.apk. Deploy Render and Vercel, then check the live review flow.'
