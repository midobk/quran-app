import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app/services/settings/app_settings_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('app_settings_service_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('defaults are used when no saved settings exist', () async {
    final AppSettingsService service = AppSettingsService(
      appDirectoryProvider: () async => tempDir,
    );

    await service.init();

    expect(service.settings, const AppSettings());
  });

  test('persists updated settings and restores them on next init', () async {
    final AppSettingsService service = AppSettingsService(
      appDirectoryProvider: () async => tempDir,
    );
    await service.init();

    await service.setAutoDetectAyah(false);
    await service.setConfidenceThreshold(82);
    await service.setKeepScreenAwake(false);
    await service.setShowTranslation(false);
    await service.setArabicFontSize(40);
    await service.setHapticFeedback(false);
    await service.setDebugMode(true);

    final AppSettingsService reloaded = AppSettingsService(
      appDirectoryProvider: () async => tempDir,
    );
    await reloaded.init();

    expect(
      reloaded.settings,
      const AppSettings(
        autoDetectAyah: false,
        confidenceThreshold: 82,
        keepScreenAwake: false,
        showTranslation: false,
        arabicFontSize: 40,
        hapticFeedback: false,
        debugMode: true,
      ),
    );
  });
}
