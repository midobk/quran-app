import 'dart:math' as math;

import 'package:flutter/material.dart';

class QuranListenerColors {
  static const Color brandAccent = Color(0xFFC9A227);
  static const Color brandAccentDeep = Color(0xFFA88520);
  static const Color brandPrimary = Color(0xFF0F3D2E);
  static const Color brandPrimaryLight = Color(0xFF1B5A45);
  static const Color statusHigh = Color(0xFF22C55E);
  static const Color statusMedium = Color(0xFFEAB308);
  static const Color statusLow = Color(0xFFEF4444);
}

@immutable
class QuranListenerPalette extends ThemeExtension<QuranListenerPalette> {
  const QuranListenerPalette({
    required this.bgDefault,
    required this.bgSurface,
    required this.textPrimary,
    required this.textSecondary,
    required this.brandAccent,
    required this.brandPrimary,
    required this.statusHigh,
    required this.statusMedium,
    required this.statusLow,
    required this.strokeDefault,
  });

  final Color bgDefault;
  final Color bgSurface;
  final Color textPrimary;
  final Color textSecondary;
  final Color brandAccent;
  final Color brandPrimary;
  final Color statusHigh;
  final Color statusMedium;
  final Color statusLow;
  final Color strokeDefault;

  static const QuranListenerPalette dark = QuranListenerPalette(
    bgDefault: Color(0xFF0A0A0A),
    bgSurface: Color(0xFF141414),
    textPrimary: Color(0xFFF5F5F5),
    textSecondary: Color(0xFF9CA3AF),
    brandAccent: QuranListenerColors.brandAccent,
    brandPrimary: QuranListenerColors.brandPrimary,
    statusHigh: QuranListenerColors.statusHigh,
    statusMedium: QuranListenerColors.statusMedium,
    statusLow: QuranListenerColors.statusLow,
    strokeDefault: Color(0xFF1F1F1F),
  );

  static const QuranListenerPalette light = QuranListenerPalette(
    bgDefault: Color(0xFFF6F1E4),
    bgSurface: Color(0xFFFFFBF2),
    textPrimary: Color(0xFF1D1A14),
    textSecondary: Color(0xFF6C655A),
    brandAccent: QuranListenerColors.brandAccent,
    brandPrimary: QuranListenerColors.brandPrimaryLight,
    statusHigh: QuranListenerColors.statusHigh,
    statusMedium: QuranListenerColors.statusMedium,
    statusLow: QuranListenerColors.statusLow,
    strokeDefault: Color(0xFFD9D0BE),
  );

  static QuranListenerPalette fallback(Brightness brightness) {
    return brightness == Brightness.dark ? dark : light;
  }

  @override
  QuranListenerPalette copyWith({
    Color? bgDefault,
    Color? bgSurface,
    Color? textPrimary,
    Color? textSecondary,
    Color? brandAccent,
    Color? brandPrimary,
    Color? statusHigh,
    Color? statusMedium,
    Color? statusLow,
    Color? strokeDefault,
  }) {
    return QuranListenerPalette(
      bgDefault: bgDefault ?? this.bgDefault,
      bgSurface: bgSurface ?? this.bgSurface,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      brandAccent: brandAccent ?? this.brandAccent,
      brandPrimary: brandPrimary ?? this.brandPrimary,
      statusHigh: statusHigh ?? this.statusHigh,
      statusMedium: statusMedium ?? this.statusMedium,
      statusLow: statusLow ?? this.statusLow,
      strokeDefault: strokeDefault ?? this.strokeDefault,
    );
  }

  @override
  QuranListenerPalette lerp(covariant ThemeExtension<QuranListenerPalette>? other, double t) {
    if (other is! QuranListenerPalette) {
      return this;
    }

    return QuranListenerPalette(
      bgDefault: Color.lerp(bgDefault, other.bgDefault, t) ?? bgDefault,
      bgSurface: Color.lerp(bgSurface, other.bgSurface, t) ?? bgSurface,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t) ?? textPrimary,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t) ?? textSecondary,
      brandAccent: Color.lerp(brandAccent, other.brandAccent, t) ?? brandAccent,
      brandPrimary: Color.lerp(brandPrimary, other.brandPrimary, t) ?? brandPrimary,
      statusHigh: Color.lerp(statusHigh, other.statusHigh, t) ?? statusHigh,
      statusMedium: Color.lerp(statusMedium, other.statusMedium, t) ?? statusMedium,
      statusLow: Color.lerp(statusLow, other.statusLow, t) ?? statusLow,
      strokeDefault: Color.lerp(strokeDefault, other.strokeDefault, t) ?? strokeDefault,
    );
  }
}

QuranListenerPalette quranListenerPaletteOf(BuildContext context) {
  final ThemeData theme = Theme.of(context);
  return theme.extension<QuranListenerPalette>() ?? QuranListenerPalette.fallback(theme.brightness);
}

extension QuranListenerThemeX on BuildContext {
  QuranListenerPalette get quranPalette => quranListenerPaletteOf(this);
}

ThemeData buildQuranListenerTheme({Brightness brightness = Brightness.dark}) {
  final bool isDark = brightness == Brightness.dark;
  final QuranListenerPalette palette = QuranListenerPalette.fallback(brightness);
  final ColorScheme colorScheme = isDark
      ? ColorScheme.dark(
          primary: palette.brandAccent,
          onPrimary: palette.bgDefault,
          secondary: palette.brandPrimary,
          onSecondary: palette.textPrimary,
          error: palette.statusLow,
          onError: palette.textPrimary,
          surface: palette.bgSurface,
          onSurface: palette.textPrimary,
          outline: palette.strokeDefault,
        )
      : ColorScheme.light(
          primary: palette.brandAccent,
          onPrimary: palette.textPrimary,
          secondary: palette.brandPrimary,
          onSecondary: Colors.white,
          error: palette.statusLow,
          onError: Colors.white,
          surface: palette.bgSurface,
          onSurface: palette.textPrimary,
          outline: palette.strokeDefault,
        );

  final TextTheme baseTextTheme = isDark
      ? Typography.whiteMountainView
      : Typography.blackMountainView;
  final TextTheme textTheme = baseTextTheme.copyWith(
    headlineSmall: TextStyle(
      color: palette.textPrimary,
      fontSize: 28,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.2,
    ),
    titleLarge: TextStyle(color: palette.textPrimary, fontSize: 22, fontWeight: FontWeight.w500),
    titleMedium: TextStyle(color: palette.textPrimary, fontSize: 18, fontWeight: FontWeight.w500),
    bodyLarge: TextStyle(color: palette.textPrimary, fontSize: 16, fontWeight: FontWeight.w400),
    bodyMedium: TextStyle(color: palette.textSecondary, fontSize: 14, fontWeight: FontWeight.w400),
    bodySmall: TextStyle(color: palette.textSecondary, fontSize: 12, fontWeight: FontWeight.w400),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: palette.bgDefault,
    canvasColor: palette.bgSurface,
    cardColor: palette.bgSurface,
    colorScheme: colorScheme,
    dividerColor: palette.strokeDefault,
    dividerTheme: DividerThemeData(color: palette.strokeDefault, thickness: 1),
    textTheme: textTheme,
    extensions: <ThemeExtension<dynamic>>[palette],
    appBarTheme: AppBarTheme(
      backgroundColor: palette.bgDefault,
      foregroundColor: palette.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      color: palette.bgSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: EdgeInsets.zero,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: palette.bgSurface,
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: palette.textPrimary),
      behavior: SnackBarBehavior.floating,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        minimumSize: const Size.fromHeight(48),
        elevation: 0,
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        foregroundColor: palette.textPrimary,
        side: BorderSide(color: palette.strokeDefault),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colorScheme.primary,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.bgSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: palette.strokeDefault),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: palette.strokeDefault),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.primary),
      ),
      hintStyle: TextStyle(color: palette.textSecondary),
      labelStyle: TextStyle(color: palette.textSecondary),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith<Color>((Set<WidgetState> states) {
        if (states.contains(WidgetState.selected)) {
          return Colors.white;
        }
        return palette.bgSurface;
      }),
      trackColor: WidgetStateProperty.resolveWith<Color>((Set<WidgetState> states) {
        if (states.contains(WidgetState.selected)) {
          return colorScheme.primary;
        }
        return palette.strokeDefault;
      }),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: colorScheme.primary,
      inactiveTrackColor: palette.strokeDefault,
      thumbColor: colorScheme.primary,
      overlayColor: colorScheme.primary.withValues(alpha: 0.22),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colorScheme.primary,
      linearTrackColor: palette.strokeDefault,
      circularTrackColor: palette.strokeDefault,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: palette.bgSurface,
      surfaceTintColor: Colors.transparent,
      textStyle: textTheme.bodyMedium?.copyWith(color: palette.textPrimary),
    ),
  );
}

class QuranListenerBackground extends StatelessWidget {
  const QuranListenerBackground({required this.child, super.key, this.patternOpacity = 0});

  final Widget child;
  final double patternOpacity;

  @override
  Widget build(BuildContext context) {
    final QuranListenerPalette colors = context.quranPalette;
    final ThemeData theme = Theme.of(context);

    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: DecoratedBox(decoration: BoxDecoration(color: colors.bgDefault)),
        ),
        Positioned(
          top: -120,
          right: -80,
          child: Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: <Color>[
                  theme.colorScheme.secondary.withValues(alpha: 0.32),
                  theme.colorScheme.secondary.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -140,
          left: -100,
          child: Container(
            width: 300,
            height: 300,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: <Color>[
                  theme.colorScheme.primary.withValues(alpha: 0.16),
                  theme.colorScheme.primary.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
        if (patternOpacity > 0)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _IslamicPatternPainter(
                  color: theme.colorScheme.primary.withValues(alpha: patternOpacity),
                ),
              ),
            ),
          ),
        Positioned.fill(child: child),
      ],
    );
  }
}

class QuranListenerIconButton extends StatelessWidget {
  const QuranListenerIconButton({
    required this.icon,
    required this.onPressed,
    this.size = 48,
    super.key,
    this.backgroundColor,
    this.foregroundColor,
  });

  final Widget icon;
  final VoidCallback? onPressed;
  final double size;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final QuranListenerPalette colors = context.quranPalette;

    return Material(
      color: backgroundColor ?? colors.bgSurface,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: size,
          height: size,
          child: IconTheme(
            data: IconThemeData(color: foregroundColor ?? colors.textSecondary, size: size * 0.45),
            child: Center(child: icon),
          ),
        ),
      ),
    );
  }
}

class QuranListenerMicHeroButton extends StatelessWidget {
  const QuranListenerMicHeroButton({required this.onPressed, super.key, this.isActive = false});

  final VoidCallback? onPressed;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final QuranListenerPalette colors = context.quranPalette;
    final ThemeData theme = Theme.of(context);

    return GestureDetector(
      onTap: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: theme.colorScheme.primary, width: 2),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: theme.colorScheme.primary.withValues(alpha: isActive ? 0.42 : 0.22),
              blurRadius: isActive ? 30 : 18,
            ),
          ],
        ),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: isActive
                  ? LinearGradient(
                      colors: <Color>[
                        theme.colorScheme.primary,
                        QuranListenerColors.brandAccentDeep,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: isActive ? null : colors.bgSurface,
            ),
            child: Icon(
              Icons.mic_rounded,
              size: 36,
              color: isActive ? theme.colorScheme.onPrimary : theme.colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}

enum QuranListenerConfidenceLevel { high, medium, low }

QuranListenerConfidenceLevel confidenceLevelFromScore(double score) {
  if (score >= 0.75) {
    return QuranListenerConfidenceLevel.high;
  }
  if (score >= 0.55) {
    return QuranListenerConfidenceLevel.medium;
  }
  return QuranListenerConfidenceLevel.low;
}

Color confidenceColor(QuranListenerConfidenceLevel level) {
  switch (level) {
    case QuranListenerConfidenceLevel.high:
      return QuranListenerColors.statusHigh;
    case QuranListenerConfidenceLevel.medium:
      return QuranListenerColors.statusMedium;
    case QuranListenerConfidenceLevel.low:
      return QuranListenerColors.statusLow;
  }
}

String confidenceLabel(QuranListenerConfidenceLevel level) {
  switch (level) {
    case QuranListenerConfidenceLevel.high:
      return 'High';
    case QuranListenerConfidenceLevel.medium:
      return 'Medium';
    case QuranListenerConfidenceLevel.low:
      return 'Low';
  }
}

class _IslamicPatternPainter extends CustomPainter {
  const _IslamicPatternPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const double spacing = 80;
    final Paint strokePaint = Paint()
      ..color = color
      ..strokeWidth = 0.6
      ..style = PaintingStyle.stroke;

    for (double y = 0; y <= size.height + spacing; y += spacing) {
      for (double x = 0; x <= size.width + spacing; x += spacing) {
        final Offset center = Offset(x, y);
        _drawStar(canvas, center, strokePaint);
      }
    }
  }

  void _drawStar(Canvas canvas, Offset center, Paint paint) {
    final Path path = Path();
    const int points = 8;
    const double outerR = 16;
    const double innerR = 7.4;
    for (int i = 0; i < points * 2; i++) {
      final double angle = (math.pi / points) * i;
      final double radius = i.isEven ? outerR : innerR;
      final Offset p = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
    canvas.drawCircle(center, 3.6, paint);
  }

  @override
  bool shouldRepaint(covariant _IslamicPatternPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
