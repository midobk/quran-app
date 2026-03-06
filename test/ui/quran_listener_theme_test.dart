import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app/ui/theme/quran_listener_design.dart';

void main() {
  test('buildQuranListenerTheme exposes distinct light and dark palettes', () {
    final ThemeData lightTheme = buildQuranListenerTheme(brightness: Brightness.light);
    final ThemeData darkTheme = buildQuranListenerTheme(brightness: Brightness.dark);
    final QuranListenerPalette lightPalette = lightTheme.extension<QuranListenerPalette>()!;
    final QuranListenerPalette darkPalette = darkTheme.extension<QuranListenerPalette>()!;

    expect(lightTheme.brightness, Brightness.light);
    expect(darkTheme.brightness, Brightness.dark);
    expect(lightTheme.scaffoldBackgroundColor, isNot(darkTheme.scaffoldBackgroundColor));
    expect(lightPalette.textPrimary, isNot(darkPalette.textPrimary));
    expect(lightTheme.colorScheme.primary, QuranListenerColors.brandAccent);
    expect(darkTheme.colorScheme.primary, QuranListenerColors.brandAccent);
  });
}
