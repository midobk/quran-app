#!/usr/bin/env bash
set -euo pipefail

problems=0

print_section() {
  printf '\n== %s ==\n' "$1"
}

print_ok() {
  printf '[OK] %s\n' "$1"
}

print_warn() {
  printf '[WARN] %s\n' "$1"
  problems=$((problems + 1))
}

print_info() {
  printf '[INFO] %s\n' "$1"
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

print_section 'Flutter'
if has_cmd flutter; then
  print_ok 'Flutter found on PATH.'
  flutter --version || true
  print_info 'Running flutter doctor for detailed guidance:'
  flutter doctor || true
else
  print_warn 'Flutter is not on PATH.'
  print_info 'Install Flutter SDK: https://docs.flutter.dev/get-started/install/macos/mobile-ios'
  print_info "Add Flutter to PATH in your shell profile:"
  print_info "  export PATH=\"\$HOME/flutter/bin:\$PATH\""
  print_info 'Optional: FVM can help pin Flutter versions per project: https://fvm.app/'
fi

print_section 'Android Tooling'
if [[ -d '/Applications/Android Studio.app' ]]; then
  print_ok 'Android Studio detected at /Applications/Android Studio.app'
else
  print_warn 'Android Studio not detected in /Applications.'
  print_info 'Install Android Studio manually: https://developer.android.com/studio'
fi

android_sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
if [[ -n "${android_sdk}" ]]; then
  print_ok "ANDROID_SDK_ROOT/ANDROID_HOME set to: ${android_sdk}"
else
  print_warn 'ANDROID_SDK_ROOT or ANDROID_HOME is not set.'
  print_info 'Set one variable in your shell profile, for example:'
  print_info '  export ANDROID_SDK_ROOT="$HOME/Library/Android/sdk"'
fi

if has_cmd sdkmanager; then
  print_ok 'sdkmanager found on PATH.'
  sdkmanager --version || true
else
  print_warn 'sdkmanager is not on PATH.'
  print_info 'Install Android command-line tools via Android Studio SDK Manager.'
  print_info 'Then add this to PATH (adjust if needed):'
  print_info '  export PATH="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$PATH"'
fi

if [[ -n "${android_sdk}" ]]; then
  if [[ -x "${android_sdk}/platform-tools/adb" ]]; then
    print_ok 'Android platform-tools detected (adb present).'
  else
    print_warn 'platform-tools not detected in Android SDK.'
    print_info 'Install "Android SDK Platform-Tools" from Android Studio SDK Manager.'
  fi

  if [[ -d "${android_sdk}/ndk" ]]; then
    print_ok 'NDK directory detected (useful later for whisper.cpp/native builds).'
  else
    print_warn 'NDK directory not found.'
    print_info 'For future whisper.cpp/native work, install Android NDK from SDK Manager.'
  fi
else
  print_info 'Skipping platform-tools/NDK path checks because Android SDK path is unknown.'
fi

print_section 'iOS Tooling'
if xcode-select -p >/dev/null 2>&1; then
  xcode_path="$(xcode-select -p)"
  print_ok "Xcode command-line tools configured: ${xcode_path}"
  if has_cmd xcodebuild; then
    xcodebuild -version || true
  fi
else
  print_warn 'Xcode is not configured (xcode-select -p failed).'
  print_info 'Install Xcode from the App Store, then run:'
  print_info '  sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer'
  print_info '  sudo xcodebuild -runFirstLaunch'
fi

if [[ -d '/Applications/Xcode.app' ]]; then
  print_ok 'Full Xcode app detected at /Applications/Xcode.app'
else
  print_warn 'Full Xcode.app not found in /Applications.'
  print_info 'Install the full Xcode app from the App Store (CLI tools alone are not enough for iOS builds).'
fi

if has_cmd pod; then
  print_ok 'CocoaPods found on PATH.'
  pod --version || true
else
  print_warn 'CocoaPods not found.'
  print_info 'Install CocoaPods (example): brew install cocoapods'
fi

available_kb="$(df -Pk . | awk 'NR==2 {print $4}')"
if [[ -n "${available_kb}" ]] && [[ "${available_kb}" -lt 15728640 ]]; then
  print_warn 'Less than 15GB free disk space detected.'
  print_info 'Flutter iOS artifacts and Xcode builds can fail with "No space left on device".'
  print_info 'Free up disk space, then retry flutter build/run.'
else
  print_ok 'Disk space check passed for iOS tooling.'
fi

print_section 'Common Environment Hints'
if [[ ":${PATH}:" != *":$HOME/flutter/bin:"* ]]; then
  print_info 'Flutter bin may not be persisted in PATH for new terminals.'
  print_info 'Add this line to ~/.zshrc or ~/.bashrc:'
  print_info '  export PATH="$HOME/flutter/bin:$PATH"'
fi

print_info 'If command execution fails with permissions errors, check directory ownership and executable bits.'
print_info 'If iOS tools fail after updates, open Xcode once and accept license prompts.'

print_section 'Verification Commands'
print_info 'Run these from the project root:'
print_info '  flutter doctor'
print_info '  flutter pub get'
print_info '  flutter analyze'
print_info '  flutter test'
print_info '  flutter run'
print_info '  flutter run -d ios'
print_info '  (first iOS build) cd ios && pod install && cd ..'

if [[ "$problems" -gt 0 ]]; then
  printf '\nSetup checks completed with %d issue(s). Follow the guidance above and rerun this script.\n' "$problems"
  exit 1
fi

printf '\nSetup checks completed successfully.\n'
