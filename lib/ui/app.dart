import 'package:flutter/material.dart';

import '../core/di/service_locator.dart';
import '../core/navigation/app_router.dart';
import '../core/navigation/app_routes.dart';

class QuranApp extends StatelessWidget {
  const QuranApp({super.key});

  @override
  Widget build(BuildContext context) {
    final AppRouter router = serviceLocator<AppRouter>();

    return MaterialApp(
      title: 'Quran Live Ayah',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF17624D))),
      initialRoute: AppRoutes.home,
      onGenerateRoute: router.onGenerateRoute,
    );
  }
}
