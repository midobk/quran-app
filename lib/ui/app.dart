import 'package:flutter/material.dart';

import '../core/di/service_locator.dart';
import '../core/navigation/app_router.dart';
import '../core/navigation/app_routes.dart';
import '../services/theme/theme_service.dart';
import 'theme/quran_listener_design.dart';

class QuranApp extends StatelessWidget {
  const QuranApp({super.key});

  @override
  Widget build(BuildContext context) {
    final AppRouter router = serviceLocator<AppRouter>();
    final ThemeService themeService = serviceLocator<ThemeService>();

    return AnimatedBuilder(
      animation: themeService,
      builder: (BuildContext context, Widget? child) {
        return MaterialApp(
          title: 'Quran Listener',
          debugShowCheckedModeBanner: false,
          themeMode: themeService.materialThemeMode,
          theme: buildQuranListenerTheme(brightness: Brightness.light),
          darkTheme: buildQuranListenerTheme(brightness: Brightness.dark),
          initialRoute: AppRoutes.home,
          onGenerateRoute: router.onGenerateRoute,
        );
      },
    );
  }
}
