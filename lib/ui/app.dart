import 'package:flutter/material.dart';

import '../core/di/service_locator.dart';
import '../core/navigation/app_router.dart';
import '../core/navigation/app_routes.dart';
import '../services/theme/theme_service.dart';

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
          title: 'Quran Live Ayah',
          debugShowCheckedModeBanner: false,
          themeMode: themeService.materialThemeMode,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF17624D)),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF17624D),
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          initialRoute: AppRoutes.home,
          onGenerateRoute: router.onGenerateRoute,
        );
      },
    );
  }
}
