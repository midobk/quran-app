import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/logging/app_logger.dart';
import '../device/screen_awake_service.dart';

class AppSettings {
  const AppSettings({
    this.autoDetectAyah = true,
    this.confidenceThreshold = 70,
    this.keepScreenAwake = true,
    this.showTranslation = true,
    this.arabicFontSize = 58,
    this.hapticFeedback = true,
    this.debugMode = false,
  });

  final bool autoDetectAyah;
  final double confidenceThreshold;
  final bool keepScreenAwake;
  final bool showTranslation;
  final double arabicFontSize;
  final bool hapticFeedback;
  final bool debugMode;

  AppSettings copyWith({
    bool? autoDetectAyah,
    double? confidenceThreshold,
    bool? keepScreenAwake,
    bool? showTranslation,
    double? arabicFontSize,
    bool? hapticFeedback,
    bool? debugMode,
  }) {
    return AppSettings(
      autoDetectAyah: autoDetectAyah ?? this.autoDetectAyah,
      confidenceThreshold: confidenceThreshold ?? this.confidenceThreshold,
      keepScreenAwake: keepScreenAwake ?? this.keepScreenAwake,
      showTranslation: showTranslation ?? this.showTranslation,
      arabicFontSize: arabicFontSize ?? this.arabicFontSize,
      hapticFeedback: hapticFeedback ?? this.hapticFeedback,
      debugMode: debugMode ?? this.debugMode,
    );
  }

  Map<String, Object> toJson() {
    return <String, Object>{
      'autoDetectAyah': autoDetectAyah,
      'confidenceThreshold': confidenceThreshold,
      'keepScreenAwake': keepScreenAwake,
      'showTranslation': showTranslation,
      'arabicFontSize': arabicFontSize,
      'hapticFeedback': hapticFeedback,
      'debugMode': debugMode,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      autoDetectAyah: _readBool(json['autoDetectAyah'], fallback: true),
      confidenceThreshold: _clampDouble(
        _readDouble(json['confidenceThreshold'], fallback: 70),
        min: 30,
        max: 100,
      ),
      keepScreenAwake: _readBool(json['keepScreenAwake'], fallback: true),
      showTranslation: _readBool(json['showTranslation'], fallback: true),
      arabicFontSize: _clampDouble(
        _readDouble(json['arabicFontSize'], fallback: 58),
        min: 32,
        max: 72,
      ),
      hapticFeedback: _readBool(json['hapticFeedback'], fallback: true),
      debugMode: _readBool(json['debugMode'], fallback: false),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AppSettings &&
        other.autoDetectAyah == autoDetectAyah &&
        other.confidenceThreshold == confidenceThreshold &&
        other.keepScreenAwake == keepScreenAwake &&
        other.showTranslation == showTranslation &&
        other.arabicFontSize == arabicFontSize &&
        other.hapticFeedback == hapticFeedback &&
        other.debugMode == debugMode;
  }

  @override
  int get hashCode => Object.hash(
    autoDetectAyah,
    confidenceThreshold,
    keepScreenAwake,
    showTranslation,
    arabicFontSize,
    hapticFeedback,
    debugMode,
  );

  static bool _readBool(Object? value, {required bool fallback}) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final String normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1') {
        return true;
      }
      if (normalized == 'false' || normalized == '0') {
        return false;
      }
    }
    return fallback;
  }

  static double _readDouble(Object? value, {required double fallback}) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value) ?? fallback;
    }
    return fallback;
  }

  static double _clampDouble(double value, {required double min, required double max}) {
    if (value < min) {
      return min;
    }
    if (value > max) {
      return max;
    }
    return value;
  }
}

class AppSettingsService extends ChangeNotifier {
  AppSettingsService({
    Future<Directory> Function()? appDirectoryProvider,
    ScreenAwakeService? screenAwakeService,
    AppLogger? logger,
  }) : _appDirectoryProvider = appDirectoryProvider ?? getApplicationSupportDirectory,
       _usesDefaultDirectoryProvider = appDirectoryProvider == null,
       _screenAwakeService = screenAwakeService,
       _logger = logger ?? const AppLogger();

  final Future<Directory> Function() _appDirectoryProvider;
  final bool _usesDefaultDirectoryProvider;
  final ScreenAwakeService? _screenAwakeService;
  final AppLogger _logger;

  AppSettings _settings = const AppSettings();
  bool _isInitialized = false;

  AppSettings get settings => _settings;
  bool get isInitialized => _isInitialized;

  Future<void> init() async {
    if (_isInitialized) {
      return;
    }

    if (_canUsePlatformStorage()) {
      try {
        final File file = await _settingsFile();
        if (await file.exists()) {
          final Object? decoded = jsonDecode(await file.readAsString());
          if (decoded is Map<String, dynamic>) {
            _settings = AppSettings.fromJson(decoded);
          }
        }
      } on MissingPluginException {
        _settings = const AppSettings();
      } catch (error) {
        _logger.warning('AppSettingsService init failed, using defaults: $error');
        _settings = const AppSettings();
      }
    }

    _isInitialized = true;
    await _applyKeepScreenAwake();
  }

  Future<void> setAutoDetectAyah(bool value) => _update(_settings.copyWith(autoDetectAyah: value));

  Future<void> setConfidenceThreshold(double value) =>
      _update(_settings.copyWith(confidenceThreshold: value));

  Future<void> setKeepScreenAwake(bool value) =>
      _update(_settings.copyWith(keepScreenAwake: value));

  Future<void> setShowTranslation(bool value) =>
      _update(_settings.copyWith(showTranslation: value));

  Future<void> setArabicFontSize(double value) =>
      _update(_settings.copyWith(arabicFontSize: value));

  Future<void> setHapticFeedback(bool value) => _update(_settings.copyWith(hapticFeedback: value));

  Future<void> setDebugMode(bool value) => _update(_settings.copyWith(debugMode: value));

  Future<void> _update(AppSettings next) async {
    if (_settings == next) {
      return;
    }

    _settings = next;
    notifyListeners();

    await _applyKeepScreenAwake();

    if (!_canUsePlatformStorage()) {
      return;
    }

    try {
      final File file = await _settingsFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(_settings.toJson()), flush: true);
    } catch (error) {
      _logger.warning('Failed to persist app settings: $error');
    }
  }

  Future<void> _applyKeepScreenAwake() async {
    final ScreenAwakeService? service = _screenAwakeService;
    if (service == null) {
      return;
    }
    await service.setEnabled(_settings.keepScreenAwake);
  }

  Future<File> _settingsFile() async {
    final Directory appDir = await _appDirectoryProvider();
    return File(p.join(appDir.path, 'settings', 'app_settings.json'));
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
