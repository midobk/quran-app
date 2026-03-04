$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$problems = 0

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "== $Title =="
}

function Write-Ok {
    param([string]$Message)
    Write-Host "[OK] $Message"
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[WARN] $Message"
    $script:problems++
}

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message"
}

Write-Section "Flutter"
$flutter = Get-Command flutter -ErrorAction SilentlyContinue
if ($null -ne $flutter) {
    Write-Ok "Flutter found on PATH."
    try {
        flutter --version
    }
    catch {
        Write-Warn "Unable to run 'flutter --version'. Check your Flutter installation."
    }
    Write-Info "Running flutter doctor for detailed guidance:"
    try {
        flutter doctor
    }
    catch {
        Write-Warn "Unable to run 'flutter doctor'."
    }
}
else {
    Write-Warn "Flutter is not on PATH."
    Write-Info "Install Flutter SDK: https://docs.flutter.dev/get-started/install/windows/mobile"
    Write-Info "Add Flutter to PATH (example): C:\src\flutter\bin"
    Write-Info "Optional: FVM can help pin Flutter versions per project: https://fvm.app/"
}

Write-Section "Android Tooling"
$androidStudioPaths = @(
    "$Env:ProgramFiles\Android\Android Studio\bin\studio64.exe",
    "${Env:ProgramFiles(x86)}\Android\Android Studio\bin\studio64.exe"
)

$androidStudioFound = $false
foreach ($path in $androidStudioPaths) {
    if ($path -and (Test-Path $path)) {
        Write-Ok "Android Studio detected: $path"
        $androidStudioFound = $true
        break
    }
}
if (-not $androidStudioFound) {
    Write-Warn "Android Studio not detected in common install locations."
    Write-Info "Install Android Studio manually: https://developer.android.com/studio"
}

$androidSdk = if ($Env:ANDROID_SDK_ROOT) { $Env:ANDROID_SDK_ROOT } elseif ($Env:ANDROID_HOME) { $Env:ANDROID_HOME } else { "" }
if ($androidSdk) {
    Write-Ok "ANDROID_SDK_ROOT/ANDROID_HOME is set to: $androidSdk"
}
else {
    Write-Warn "ANDROID_SDK_ROOT or ANDROID_HOME is not set."
    Write-Info "Set one variable (example):"
    Write-Info "  setx ANDROID_SDK_ROOT %LOCALAPPDATA%\Android\Sdk"
}

$sdkManager = Get-Command sdkmanager -ErrorAction SilentlyContinue
if ($null -ne $sdkManager) {
    Write-Ok "sdkmanager found on PATH."
    try {
        sdkmanager --version
    }
    catch {
        Write-Warn "Unable to run 'sdkmanager --version'."
    }
}
else {
    Write-Warn "sdkmanager is not on PATH."
    Write-Info "Install Android command-line tools via Android Studio SDK Manager."
    Write-Info "Then add to PATH (example): %ANDROID_SDK_ROOT%\cmdline-tools\latest\bin"
}

if ($androidSdk) {
    $adbPath = Join-Path $androidSdk "platform-tools\adb.exe"
    if (Test-Path $adbPath) {
        Write-Ok "Android platform-tools detected (adb.exe present)."
    }
    else {
        Write-Warn "platform-tools not detected in Android SDK."
        Write-Info "Install 'Android SDK Platform-Tools' from SDK Manager."
    }

    $ndkPath = Join-Path $androidSdk "ndk"
    if (Test-Path $ndkPath) {
        Write-Ok "NDK directory detected (useful later for whisper.cpp/native builds)."
    }
    else {
        Write-Warn "NDK directory not found."
        Write-Info "For future whisper.cpp/native work, install Android NDK from SDK Manager."
    }
}
else {
    Write-Info "Skipping platform-tools/NDK path checks because Android SDK path is unknown."
}

Write-Section "Common Environment Hints"
$pathEntries = $Env:Path -split ";"
if (-not ($pathEntries -contains "C:\src\flutter\bin")) {
    Write-Info "Ensure your Flutter bin directory is in PATH for new terminals."
}

try {
    $longPaths = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -ErrorAction Stop).LongPathsEnabled
    if ($longPaths -eq 1) {
        Write-Ok "Windows long paths are enabled."
    }
    else {
        Write-Warn "Windows long paths are disabled."
        Write-Info "Enable long paths in Local Group Policy or registry for smoother builds."
    }
}
catch {
    Write-Warn "Unable to read LongPathsEnabled registry value."
    Write-Info "If builds fail on path length, enable Windows long paths."
}

try {
    $executionPolicy = Get-ExecutionPolicy -Scope CurrentUser
    Write-Info "CurrentUser execution policy: $executionPolicy"
    if ($executionPolicy -eq "Restricted") {
        Write-Warn "Execution policy is Restricted."
        Write-Info "Set a safer policy for local scripts (example):"
        Write-Info "  Set-ExecutionPolicy -Scope CurrentUser RemoteSigned"
    }
}
catch {
    Write-Warn "Unable to read PowerShell execution policy."
}

Write-Section "Verification Commands"
Write-Info "Run these from the project root:"
Write-Info "  flutter doctor"
Write-Info "  flutter pub get"
Write-Info "  flutter analyze"
Write-Info "  flutter test"
Write-Info "  flutter run"

if ($problems -gt 0) {
    Write-Host ""
    Write-Host "Setup checks completed with $problems issue(s). Follow the guidance above and rerun this script."
    exit 1
}

Write-Host ""
Write-Host "Setup checks completed successfully."
exit 0

