import 'package:flutter/services.dart';

import '../../core/logging/app_logger.dart';

class ScreenAwakeService {
  ScreenAwakeService({MethodChannel? channel, AppLogger? logger})
    : _channel = channel ?? const MethodChannel(_channelName),
      _logger = logger ?? const AppLogger();

  static const String _channelName = 'quran_app/screen_awake';

  final MethodChannel _channel;
  final AppLogger _logger;

  bool _isEnabled = false;

  bool get isEnabled => _isEnabled;

  Future<void> setEnabled(bool enabled) async {
    if (_isEnabled == enabled) {
      return;
    }

    _isEnabled = enabled;

    try {
      await _channel.invokeMethod<void>('setEnabled', <String, bool>{'enabled': enabled});
    } on MissingPluginException {
      // Widget tests and unsupported platforms can safely ignore this.
    } on Error {
      // Non-widget tests can hit this before the Flutter bindings are initialized.
    } catch (error) {
      _logger.warning('Failed to update screen-awake state: $error');
    }
  }
}
