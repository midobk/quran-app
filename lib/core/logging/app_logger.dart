import 'package:flutter/foundation.dart';

class AppLogger {
  const AppLogger();

  void info(String message) {
    debugPrint('[INFO] $message');
  }

  void debug(String message) {
    debugPrint('[DEBUG] $message');
  }

  void warning(String message) {
    debugPrint('[WARN] $message');
  }
}
