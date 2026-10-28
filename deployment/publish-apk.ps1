[CmdletBinding()]
param(
    [string]$RepositoryUrl = 'https://github.com/jaxdeeznutz/geosustain_proj.git',
    [string]$BuildName = '1.0.2',
    [ValidateRange(3, 2147483647)][int]$BuildNumber = 3,
    [string]$ApiBaseUrl = 'https://geosustain.onrender.com'
)

# Run in the owner's normal PowerShell session, with Flutter/Android SDK access
# and GitHub Git authentication. Signing keys/passwords are never published.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$expectedPackage = 'com.example.geosustain_clean_arranged'

function Invoke-Checked {
    param([string]$Executable, [string[]]$CommandArguments)
    & $Executable @CommandArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed ($LASTEXITCODE): $Executable $($CommandArguments -join ' ')"
    }
}

if (([uri]$ApiBaseUrl).Scheme -ne 'https') {
    throw 'A release requires an HTTPS backend URL.'
}
$flutter = (Get-Command flutter -ErrorAction Stop).Source
$git = (Get-Command git -ErrorAction Stop).Source
if (!(Test-Path -LiteralPath (Join-Path $projectRoot 'android\key.properties'))) {
    throw 'Configure the existing private android/key.properties before release. No new signing key will be generated.'
}
$sdkLine = Get-Content -LiteralPath (Join-Path $projectRoot 'android\local.properties') |
    Where-Object { $_ -match '^sdk\.dir=' } | Select-Object -First 1
if (!$sdkLine) { throw 'Android SDK path is missing from android/local.properties.' }
$androidSdk = $sdkLine.Substring($sdkLine.IndexOf('=') + 1).Replace('\\', '\').Replace('\:', ':')
$buildTools = Get-ChildItem -LiteralPath (Join-Path $androidSdk 'build-tools') -Directory |
    Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
    Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
if (!$buildTools) { throw 'Install Android SDK Build Tools before release.' }
$apkSigner = Join-Path $buildTools.FullName 'apksigner.bat'
$aapt = Join-Path $buildTools.FullName 'aapt.exe'
if (!(Test-Path -LiteralPath $apkSigner) -or !(Test-Path -LiteralPath $aapt)) {
    throw 'Android APK signature/package verification tools are unavailable.'
}

Push-Location $projectRoot
try {
    $authorName = & $git config user.name
    $authorEmail = & $git config user.email
    if (!$authorName -or !$authorEmail) {
        throw 'Configure your Git user.name and user.email before publishing.'
    }
    $checkout = Join-Path $projectRoot ('.tools\apk-publish-' + [guid]::NewGuid().ToString('N'))
    Invoke-Checked $git @('clone', '--', $RepositoryUrl, $checkout)
    Invoke-Checked $git @('-C', $checkout, 'config', 'user.name', $authorName)
    Invoke-Checked $git @('-C', $checkout, 'config', 'user.email', $authorEmail)
    & $git -C $checkout rev-parse --verify --quiet HEAD | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Invoke-Checked $git @('-C', $checkout, 'symbolic-ref', 'HEAD', 'refs/heads/main')
    }
    $branch = & $git -C $checkout symbolic-ref --short HEAD
    if ($LASTEXITCODE -ne 0) { throw 'Could not determine the APK repository branch.' }
    $previousMetadata = Join-Path $checkout 'GeoSustain-release.json'
    if (Test-Path -LiteralPath $previousMetadata) {
        $previous = Get-Content -LiteralPath $previousMetadata -Raw | ConvertFrom-Json
        if ($previous.build_number -and $BuildNumber -le [int]$previous.build_number) {
            $BuildNumber = [int]$previous.build_number + 1
        }
    }

    Invoke-Checked $flutter @('pub', 'get')
    Invoke-Checked $flutter @('analyze', '--no-pub')
    Invoke-Checked $flutter @('test', '--no-pub')
    $buildStarted = Get-Date
    Invoke-Checked $flutter @('build', 'apk', '--release', '--no-pub',
        "--build-name=$BuildName", "--build-number=$BuildNumber", "--dart-define=API_BASE_URL=$ApiBaseUrl")
    $apk = Get-Item -LiteralPath (Join-Path $projectRoot 'build\app\outputs\flutter-apk\app-release.apk')
    if ($apk.LastWriteTime -lt $buildStarted) { throw 'APK output is stale; publication canceled.' }
    if ($apk.Length -ge 100MB) {
        throw 'APK exceeds the GitHub Git file limit. Publish it as a GitHub Release asset instead.'
    }
    $signature = & $apkSigner verify --verbose --print-certs $apk.FullName 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'APK signature verification failed.' }
    $certificateLine = $signature | Where-Object { "$_" -match 'certificate SHA-256 digest:' } | Select-Object -First 1
    if (!$certificateLine) { throw 'Could not read the APK signer fingerprint.' }
    $certificateHash = ("$certificateLine" -split 'certificate SHA-256 digest:', 2)[1].Trim()
    if ($previous -and $previous.signer_certificate_sha256 -and
        $previous.signer_certificate_sha256 -ne $certificateHash) {
        throw 'APK signing identity differs from the previous release; publication canceled.'
    }
    $packageInfo = & $aapt dump badging $apk.FullName
    if ($LASTEXITCODE -ne 0) { throw 'APK package inspection failed.' }
    $packageLine = $packageInfo | Where-Object { $_ -match '^package:' } | Select-Object -First 1
    if ($packageLine -notmatch "name='([^']+)' versionCode='([^']+)' versionName='([^']+)'") {
        throw 'Could not read APK package/version metadata.'
    }
    if ($Matches[1] -ne $expectedPackage -or [int]$Matches[2] -ne $BuildNumber -or $Matches[3] -ne $BuildName) {
        throw 'APK application ID or version does not match the requested release.'
    }

    $sourceCommit = & $git rev-parse HEAD
    if ($LASTEXITCODE -ne 0) { throw 'Could not record the source revision.' }
    $sourceDirty = [bool](& $git status --porcelain --untracked-files=normal)
    $sourceFiles = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'lib') -Recurse -File -Filter '*.dart') +
        @(Get-Item -LiteralPath (Join-Path $projectRoot 'pubspec.yaml'), (Join-Path $projectRoot 'pubspec.lock'))
    $fingerprintText = ($sourceFiles | Sort-Object FullName | ForEach-Object {
        $_.FullName.Substring($projectRoot.Length) + ':' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    }) -join "`n"
    $hashAlgorithm = [Security.Cryptography.SHA256]::Create()
    try {
        $sourceFingerprint = [BitConverter]::ToString($hashAlgorithm.ComputeHash([Text.Encoding]::UTF8.GetBytes($fingerprintText))).Replace('-', '').ToLowerInvariant()
    } finally { $hashAlgorithm.Dispose() }
    $publishedApk = Join-Path $checkout 'GeoSustain.apk'
    Copy-Item -LiteralPath $apk.FullName -Destination $publishedApk
    $apkHash = (Get-FileHash -LiteralPath $publishedApk -Algorithm SHA256).Hash.ToLowerInvariant()
    [ordered]@{
        application_id = $expectedPackage
        version = $BuildName
        build_number = $BuildNumber
        built_at_utc = [DateTime]::UtcNow.ToString('o')
        source_commit = $sourceCommit
        source_has_local_changes = $sourceDirty
        dart_and_pubspec_fingerprint_sha256 = $sourceFingerprint
        apk_sha256 = $apkHash
        signer_certificate_sha256 = $certificateHash
        api_origin = $ApiBaseUrl
        backend_deployment = 'Separate deployment required for restored estimated NPK behavior'
    } | ConvertTo-Json | Set-Content -LiteralPath $previousMetadata -Encoding UTF8
    "$apkHash  GeoSustain.apk" | Set-Content -LiteralPath (Join-Path $checkout 'GeoSustain.apk.sha256') -Encoding ASCII
    $downloadUrl = $RepositoryUrl -replace '\.git$', ''
    $downloadUrl += "/raw/refs/heads/$branch/GeoSustain.apk"
    $notes = @"
# GeoSustain Android $BuildName (build $BuildNumber)

[Download the signed farmer APK]($downloadUrl)

This build includes the current farmer interface and estimated-NPK display.
The matching backend changes must be deployed separately to $ApiBaseUrl for new
analyses to use the restored pre-CAGRO NPK path. Historical CAGRO records remain
separate, and saved analyses are unchanged.

APK SHA-256: $apkHash

The release metadata records the source revision, local changes, client source
fingerprint, and signing certificate fingerprint. No signing keys, passwords,
backend source, account data, or environment files are included in this repository.
"@
    $notes | Set-Content -LiteralPath (Join-Path $checkout 'RELEASE_NOTES.md') -Encoding UTF8
    if (!(Test-Path -LiteralPath (Join-Path $checkout 'README.md'))) {
        $notes | Set-Content -LiteralPath (Join-Path $checkout 'README.md') -Encoding UTF8
    }
    $publishFiles = @('GeoSustain.apk', 'GeoSustain.apk.sha256', 'GeoSustain-release.json', 'RELEASE_NOTES.md')
    $trackedReadme = & $git -C $checkout ls-files -- README.md
    if ($LASTEXITCODE -ne 0) { throw 'Could not inspect repository files.' }
    if (!$trackedReadme) { $publishFiles += 'README.md' }
    Invoke-Checked $git (@('-C', $checkout, 'add', '--') + $publishFiles)
    Invoke-Checked $git @('-C', $checkout, 'commit', '-m', "Publish GeoSustain Android $BuildName ($BuildNumber)")
    Invoke-Checked $git @('-C', $checkout, 'push', '-u', 'origin', 'HEAD')
    $localCommit = & $git -C $checkout rev-parse HEAD
    $remoteHead = & $git -C $checkout ls-remote origin "refs/heads/$branch"
    if ($LASTEXITCODE -ne 0 -or !$remoteHead -or ($remoteHead -split '\s+')[0] -ne $localCommit) {
        throw 'Push returned, but the remote revision could not be verified.'
    }
    Write-Output "Published and verified: $downloadUrl"
    Write-Output "Local signed APK: $($apk.FullName)"
} finally { Pop-Location }
