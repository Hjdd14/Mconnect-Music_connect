# Mconnect release helper.
#
# This script exists because the release steps in AGENTS.md §1/§2 were entirely
# manual, and the two mistakes they guard against both shipped at least once:
#   * a universal APK was produced and handed out (80.5 MB, 76 MB of it three
#     architectures' lib/ for a phone that needs one), and
#   * the seven version numbers drifted apart, so the app, the installer, the
#     exe resources and the docs disagreed.
#
# Usage:
#   pwsh scripts/release.ps1                 # full release (APKs + installer)
#   pwsh scripts/release.ps1 -SkipWindows    # Android only
#   pwsh scripts/release.ps1 -SkipTests      # skip gates (use only to re-package)
#
# Exit code is 0 only when every gate passed and every expected artifact exists.

[CmdletBinding()]
param(
  [switch]$SkipTests,
  [switch]$SkipWindows,
  [switch]$SkipInstaller
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

function Write-Step([string]$text) {
  Write-Host ''
  Write-Host "=== $text" -ForegroundColor Cyan
}

function Assert-ExitCode([string]$what) {
  if ($LASTEXITCODE -ne 0) {
    throw "$what failed with exit code $LASTEXITCODE"
  }
}

# --- 1. Version sync ---------------------------------------------------------
# `test/version_sync_test.dart` checks all seven points from AGENTS.md §2
# (pubspec, app constant, settings test literal, Inno Setup, Runner.rc x2, and
# the two gitignored docs when they are on disk).
Write-Step 'version sync points'
$pubspec = Get-Content 'pubspec.yaml' -Raw
if ($pubspec -notmatch 'version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)') {
  throw 'pubspec.yaml has no parseable `version: X.Y.Z+N`'
}
$versionName = $Matches[1]
$versionBuild = $Matches[2]
Write-Host "version: $versionName+$versionBuild"

# --- 2. Gates ----------------------------------------------------------------
if (-not $SkipTests) {
  Write-Step 'flutter analyze --no-pub (must be 0 issues)'
  flutter analyze --no-pub
  Assert-ExitCode 'flutter analyze'

  Write-Step 'flutter test --no-pub -j 1 (must be all green)'
  flutter test --no-pub -j 1
  Assert-ExitCode 'flutter test'
} else {
  Write-Host 'gates skipped (-SkipTests)' -ForegroundColor Yellow
}

# --- 3. Android: split per ABI, never universal -------------------------------
# AGENTS.md §1. The three products are reported individually; a stale universal
# APK from an older run is deleted so it can never be sent by mistake.
Write-Step 'flutter build apk --release --split-per-abi'
flutter build apk --release --split-per-abi
Assert-ExitCode 'flutter build apk'

$apkDir = 'build/app/outputs/flutter-apk'
$expected = @(
  'app-arm64-v8a-release.apk',
  'app-armeabi-v7a-release.apk',
  'app-x86_64-release.apk'
)

$universal = Join-Path $apkDir 'app-release.apk'
if (Test-Path $universal) {
  Write-Host "removing stale universal APK (AGENTS.md §1 forbids shipping it): $universal" -ForegroundColor Yellow
  Remove-Item $universal -Force
}

$missing = @($expected | Where-Object { -not (Test-Path (Join-Path $apkDir $_)) })
if ($missing.Count -gt 0) {
  throw "expected split APKs are missing: $($missing -join ', ')"
}

# --- 4. Windows build + installer -------------------------------------------
if (-not $SkipWindows) {
  Write-Step 'flutter build windows --release'
  flutter build windows --release
  Assert-ExitCode 'flutter build windows'
}

$installerPath = $null
if (-not $SkipWindows -and -not $SkipInstaller) {
  Write-Step 'Inno Setup'
  # Look in the machine-wide install dirs AND the user-level one. Inno Setup's
  # per-user installer puts ISCC.exe under %LOCALAPPDATA%\Programs, which is NOT on
  # PATH and NOT under Program Files - checking only the two paths below silently
  # skipped a build on a machine where Inno Setup 6.7.3 was in fact installed.
  $isccCandidates = @(
    'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
    'C:\Program Files\Inno Setup 6\ISCC.exe',
    (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe')
  )
  # Registry as a last resort, for an install placed somewhere unusual.
  foreach ($root in @(
      'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
      'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
      'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')) {
    Get-ChildItem $root -ErrorAction SilentlyContinue | ForEach-Object {
      $props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
      if ($props.DisplayName -like '*Inno Setup*' -and $props.InstallLocation) {
        $isccCandidates += (Join-Path $props.InstallLocation 'ISCC.exe')
      }
    }
  }
  $iscc = $isccCandidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

  if ($null -eq $iscc) {
    Write-Host 'ISCC.exe not found: skipping the installer (install Inno Setup 6 to include it).' -ForegroundColor Yellow
  } else {
    Write-Host "using $iscc"
    & $iscc 'installer/mconnect.iss'
    Assert-ExitCode 'ISCC'
    # mconnect.iss writes next to the Windows build output, not into installer/.
    $installerPath = Join-Path $repo "build/windows/x64/Mconnect-Setup-$versionName.exe"
    if (-not (Test-Path $installerPath)) {
      # Fall back to wherever it actually landed, rather than reporting nothing.
      $found = Get-ChildItem (Join-Path $repo 'build') -Filter "Mconnect-Setup-$versionName.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($found) {
        $installerPath = $found.FullName
      } else {
        Write-Host "installer not found under build/ - check [Setup] OutputDir in mconnect.iss" -ForegroundColor Yellow
        $installerPath = $null
      }
    }
  }
}

# --- 5. Report what to hand out ---------------------------------------------
Write-Step "artifacts for v$versionName+$versionBuild"
Write-Host 'Android (AGENTS.md §1: ship the split APKs; arm64 covers almost every phone since 2016)'
foreach ($name in $expected) {
  $path = Join-Path $apkDir $name
  $mb = [math]::Round((Get-Item $path).Length / 1MB, 1)
  Write-Host ("  {0,-38} {1,6} MB" -f $path, $mb)
}
if (-not $SkipWindows) {
  Write-Host "Windows: build/windows/x64/runner/Release/mconnect.exe"
}
if ($installerPath) {
  $mb = [math]::Round((Get-Item $installerPath).Length / 1MB, 1)
  Write-Host ("  {0,-38} {1,6} MB" -f $installerPath, $mb)
}

Write-Host ''
Write-Host 'Reminders:' -ForegroundColor Cyan
Write-Host '  * release is still signed with the debug keystore (AGENTS.md §3) - do not change it without asking the user'
Write-Host '  * the Android build number is ABI-weighted: arm64 is build*2+10 (AGENTS.md §1)'
Write-Host '  * CHANGELOG.md needs a "版本与产物" section for this version'
Write-Host ''
Write-Host "release packaging complete for v$versionName+$versionBuild" -ForegroundColor Green
