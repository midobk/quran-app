# Quran App (Offline-First Skeleton)

This repository contains a Flutter skeleton for an **offline Quran live ayah display app** targeting **iOS and Android** from one codebase.

## What is included

- Flutter project bootstrapped from scratch
- Layered `lib/` structure:
  - `core/`
  - `data/`
  - `domain/`
  - `features/`
  - `services/`
  - `ui/`
- Offline-safe app routing and placeholder screens
- Ads abstraction ready for later integration (no ad SDK installed)
- Basic dependency injection and logging
- Minimal tests for DI and HomeScreen rendering
- Vendored `whisper.cpp` native source at `native/whispercpp/` (MIT)

## Assumptions

- DI uses [`get_it`](https://pub.dev/packages/get_it)
- Default ad behavior is `NoAdsService` (no network, no SDK)
- `StubAdsService` is available for local debug flows only

## Prerequisites

- Flutter SDK (stable channel)
- Dart SDK (bundled with Flutter)
- Android Studio + Android SDK / emulator
- Xcode + iOS Simulator (macOS only)
- Android NDK `27.0.12077973` + CMake (install from Android Studio SDK Manager)
- CocoaPods (for iOS native dependency integration)

## Developer Setup

Setup scripts are available under `scripts/` and are intentionally non-destructive. They only check your environment and print guidance.

### macOS (iOS + Android)

1. Install required tools manually:
   - Xcode (App Store)
   - Android Studio (includes Android SDK Manager)
   - Flutter SDK
2. Run the environment check script:

   ```bash
   bash scripts/setup_macos.sh
   ```

3. Follow any warnings printed by the script (PATH, Xcode, CocoaPods, Android SDK variables, SDK tools, NDK notes).
4. Verify the project:

   ```bash
   flutter doctor
   flutter pub get
   flutter analyze
   flutter test
   flutter run
   ```

5. For iOS device/simulator run:

   ```bash
   flutter run -d ios
   ```

6. Install iOS pods before first iOS run (and whenever native iOS dependencies change):

   ```bash
   cd ios
   pod install
   cd ..
   ```

7. If `flutter run -d ios` fails, run this quick iOS preflight:
   - Open Xcode once and accept license prompts
   - Ensure full Xcode app exists at `/Applications/Xcode.app`
   - Ensure CocoaPods is installed (`pod --version`)
   - Ensure at least ~15 GB free disk space (iOS artifacts can fail with `No space left on device`)

### Windows (Android)

1. Install required tools manually:
   - Android Studio (includes Android SDK Manager)
   - Flutter SDK
2. Run the environment check script from PowerShell:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\scripts\setup_windows.ps1
   ```

3. Follow any warnings printed by the script (PATH, execution policy, long paths, Android SDK variables, SDK tools, NDK notes).
4. Verify the project:

   ```bash
   flutter doctor
   flutter pub get
   flutter analyze
   flutter test
   flutter run
   ```

## Commands

```bash
flutter doctor
flutter pub get
flutter analyze
flutter test
flutter run # Android
flutter run -d ios # iOS
```

## Offline Whisper.cpp ASR

This project includes on-device Whisper integration through Flutter FFI.

- Native source: `native/whispercpp/` (vendored copy, not submodule)
- Android bridge/CMake:
  - `android/app/src/main/cpp/wcpp_bridge.cpp`
  - `android/app/src/main/cpp/CMakeLists.txt`
- iOS local pod bridge:
  - `native/whispercpp_ios/WhisperCppBridge.podspec`
  - `native/whispercpp_ios/src/wcpp_bridge.cpp`
- Dart FFI/service:
  - `lib/services/asr/whisper_bindings.dart`
  - `lib/services/asr/whisper_cpp_service.dart`
  - `lib/services/asr/model_manager.dart`

### Model placement (offline only)

- Bundled model asset path expected by default:
  - `assets/models/whisper.gguf`
- On first use, `ModelManager` copies the bundled model into app storage:
  - `<app-support-dir>/models/whisper.gguf`
- If the bundled model is missing, the app shows an in-app **Model Missing** screen with import instructions.
- No model download is performed. No network calls are used.

### Debug actions

In **Settings**:

- `Re-copy bundled model to storage (Dev)`
- `Run Whisper Test` (runs a 2-second dummy 16kHz mono f32 buffer through Whisper and shows result + timing)
- `DB Health Check (Dev)` (DB path/count/search diagnostics)

### iOS notes

- `ios/Podfile` includes a local pod:
  - `pod 'WhisperCppBridge', :path => '../native/whispercpp_ios'`
- After pulling native changes, run:

  ```bash
  cd ios && pod install && cd ..
  ```

### Android notes

- `android/app/build.gradle.kts` configures:
  - NDK version `27.0.12077973`
  - externalNativeBuild with CMake at `android/app/src/main/cpp/CMakeLists.txt`

## Formatting

Use a single formatting style across the project:

```bash
dart format .
```

## Offline Database Initialization

- The app uses a local SQLite file: `quran.db` in the app documents directory.
- On first initialization:
  1. If `assets/db/quran.db` exists, it is copied into documents storage and opened.
  2. If no prebuilt DB asset exists yet, the app creates an empty database and applies schema tables/indexes so the app still runs offline.
- The debug search screen handles an empty DB and shows:
  - `DB has 0 ayahs — add dataset later.`

### Translation support

- The `ayah` table stores:
  - `surah_name_en` (English surah name)
  - `translation_en` (English ayah translation)
  - `text_en` (legacy compatibility column)
  - `text_plain` (MASAQ reconstructed plain Arabic)
  - `text_plain_norm` (normalized plain Arabic used for indexing/search)
- Results, live display, and debug search screens render translation under Arabic text when `translation_en` is present.
- Database schema init is migration-safe:
  - If an existing local DB was created before translation support, `surah_name_en` and `translation_en` are added automatically on startup.
  - Existing `text_en` values are backfilled into `translation_en`.

### Add prebuilt Quran DB later

1. Build or obtain a SQLite file named `quran.db`.
2. Place it at: `assets/db/quran.db`.
3. Confirm `pubspec.yaml` includes:
   - `assets/db/`
4. Run:

   ```bash
   flutter pub get
   ```

5. Reinstall app or clear app data if a previous `quran.db` already exists in documents storage (first-run copy is non-destructive and will not overwrite an existing DB file).

### Build `quran.db` from CSV/ZIP

Use the included script to convert a Quran CSV (or zipped CSV) into `assets/db/quran.db`:

```bash
python3 scripts/build_quran_db_from_csv.py \
  --input "/absolute/path/to/The Quran Dataset.csv.zip" \
  --output assets/db/quran.db
```

CSV mapping used by the importer:
- `ayah_no_quran` -> `id`
- `surah_no` -> `surah_no`
- `ayah_no_surah` -> `ayah_no`
- `surah_name_ar` -> `surah_name_ar`
- `surah_name_en` / `sura_name_en` / `surah_en` -> `surah_name_en`
- `ayah_ar` -> `text_uthmani`
- `ayah_ar` -> normalized + stored as `text_norm`
- `ayah_en` / `translation_en` / `text_en` -> `translation_en`

Expected output includes ayah row count and token index row count.

After rebuilding:

1. `flutter pub get`
2. Reinstall app or clear app data (to force first-run asset copy into app documents directory)

### Rebuild `quran.db` with MASAQ plain Arabic

The project includes `assets/data/MASAQ.csv` (word-level data). Use this to populate plain Arabic per ayah and rebuild search index/token vocab from `text_plain_norm`.

```bash
python3 tools/build_quran_db_with_masaq.py \
  --source-db assets/db/quran.db \
  --masaq-csv assets/data/MASAQ.csv \
  --output-db assets/db/quran.db
```

What this script does:
- Adds `ayah.text_plain` and `ayah.text_plain_norm` if missing.
- Reconstructs plain ayah text by grouping MASAQ rows by `(Sura_No, Verse_No, Column5)` and taking the first non-empty `Without_Diacritics` per word slot.
- Updates each ayah using `(surah_no, ayah_no)`.
- Rebuilds `token_index` from `text_plain_norm` (not Uthmani text).
- Rebuilds `vocab(token,freq)` from `token_index`.

After running the script:
1. `flutter pub get`
2. Reinstall app or clear app data so the updated asset DB is copied into app documents.

## Notes

- The app is designed to be **offline-first**: no runtime network calls are implemented.
- Ads are **stubbed for later** through `AdsService` abstraction and can be swapped when you decide to add an ad SDK.
- In `Settings`, `Ads Mode (Dev)` can switch between:
  - `Off (NoAdsService)` (default)
  - `Stub (StubAdsService)` (logs ad triggers, still offline)
- Ads mode applies immediately for the current app session and resets to `Off` on restart.
- Third-party licensing: see `THIRD_PARTY_NOTICES.md`.

## Troubleshooting

- `Undefined symbol: wcpp_*` (iOS):
  - Run `cd ios && pod install`
  - Clean and rebuild (`flutter clean`, then `flutter run -d ios`)
- `No space left on device` while downloading/building iOS artifacts:
  - Free disk space (target at least 15 GB)
  - Retry `flutter build ios --simulator --no-codesign` or `flutter run -d ios`
- Android CMake/NDK errors:
  - Confirm NDK `27.0.12077973` is installed in Android Studio SDK Manager
  - Confirm CMake is installed in SDK Manager
- Whisper test says model missing:
  - Place model at `assets/models/whisper.gguf`
  - Run `flutter pub get`
  - Use Settings -> `Re-copy bundled model to storage (Dev)`
