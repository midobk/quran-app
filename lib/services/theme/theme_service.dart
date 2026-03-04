import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/logging/app_logger.dart';

enum AppThemeMode { system, light, dark }

extension AppThemeModeX on AppThemeMode {
  ThemeMode get materialThemeMode {
    switch (this) {
      case AppThemeMode.system:
        return ThemeMode.system;
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
    }
  }

  String get storageValue {
    switch (this) {
      case AppThemeMode.system:
        return 'system';
      case AppThemeMode.light:
        return 'light';
      case AppThemeMode.dark:
        return 'dark';
    }
  }

  static AppThemeMode fromStorage(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'light':
        return AppThemeMode.light;
      case 'dark':
        return AppThemeMode.dark;
      default:
        return AppThemeMode.system;
    }
  }
}

class ThemeService extends ChangeNotifier {
  ThemeService({Future<Directory> Function()? appDirectoryProvider, AppLogger? logger})
    : _appDirectoryProvider = appDirectoryProvider ?? getApplicationSupportDirectory,
      _usesDefaultDirectoryProvider = appDirectoryProvider == null,
      _logger = logger ?? const AppLogger();

  final Future<Directory> Function() _appDirectoryProvider;
  final bool _usesDefaultDirectoryProvider;
  final AppLogger _logger;

  AppThemeMode _themeMode = AppThemeMode.system;
  bool _isInitialized = false;

  AppThemeMode get themeMode => _themeMode;
  ThemeMode get materialThemeMode => _themeMode.materialThemeMode;
  bool get isInitialized => _isInitialized;

  Future<void> init() async {
    if (_isInitialized) {
      return;
    }

    if (!_canUsePlatformStorage()) {
      _isInitialized = true;
      return;
    }

    try {
      final File file = await _settingsFile();
      if (await file.exists()) {
        final String value = await file.readAsString();
        _themeMode = AppThemeModeX.fromStorage(value);
      }
    } on MissingPluginException {
      _themeMode = AppThemeMode.system;
    } catch (error) {
      _logger.warning('ThemeService init failed, defaulting to system mode: $error');
      _themeMode = AppThemeMode.system;
    } finally {
      _isInitialized = true;
    }
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    if (_themeMode == mode) {
      return;
    }

    _themeMode = mode;
    notifyListeners();

    try {
      final File file = await _settingsFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(mode.storageValue, flush: true);
    } catch (error) {
      _logger.warning('Failed to persist theme mode: $error');
    }
  }

  Future<File> _settingsFile() async {
    final Directory appDir = await _appDirectoryProvider();
    return File(p.join(appDir.path, 'settings', 'theme_mode.txt'));
  }

  bool _canUsePlatformStorage() {
    if (!_usesDefaultDirectoryProvider) {
      return true;
    }

    try {
      WidgetsBinding.instance;
      return true;
    } catch (_) {
      return false;
    }
  }
}
