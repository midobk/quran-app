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

## Assumptions

- DI uses [`get_it`](https://pub.dev/packages/get_it)
- Default ad behavior is `NoAdsService` (no network, no SDK)
- `StubAdsService` is available for local debug flows only

## Prerequisites

- Flutter SDK (stable channel)
- Dart SDK (bundled with Flutter)
- Android Studio + Android SDK / emulator
- Xcode + iOS Simulator (macOS only)

## Commands

```bash
flutter doctor
flutter pub get
flutter analyze
flutter test
flutter run # Android
flutter run -d ios # iOS
```

## Formatting

Use a single formatting style across the project:

```bash
dart format .
```

## Notes

- The app is designed to be **offline-first**: no runtime network calls are implemented.
- Ads are **stubbed for later** through `AdsService` abstraction and can be swapped when you decide to add an ad SDK.
