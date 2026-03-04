import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app/services/theme/theme_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('theme_service_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('defaults to system mode when no saved setting exists', () async {
    final ThemeService service = ThemeService(appDirectoryProvider: () async => tempDir);

    await service.init();

    expect(service.themeMode, AppThemeMode.system);
    expect(service.materialThemeMode, ThemeMode.system);
  });

  test('persists selected theme mode and restores it on next init', () async {
    final ThemeService service = ThemeService(appDirectoryProvider: () async => tempDir);
    await service.init();
    await service.setThemeMode(AppThemeMode.dark);

    final ThemeService reloaded = ThemeService(appDirectoryProvider: () async => tempDir);
    await reloaded.init();

    expect(reloaded.themeMode, AppThemeMode.dark);
    expect(reloaded.materialThemeMode, ThemeMode.dark);
  });
}
