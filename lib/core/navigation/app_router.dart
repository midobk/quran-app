import 'package:flutter/material.dart';

import '../../features/home/home_screen.dart';
import '../../features/listening/listening_warmup_screen.dart';
import '../../features/search/quran_search_debug_screen.dart';
import '../../features/settings/settings_screen.dart';
import 'app_routes.dart';

class AppRouter {
  Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.home:
        return MaterialPageRoute<HomeScreen>(
          builder: (_) => const HomeScreen(),
          settings: settings,
        );
      case AppRoutes.listeningWarmup:
        return MaterialPageRoute<ListeningWarmupScreen>(
          builder: (_) => const ListeningWarmupScreen(),
          settings: settings,
        );
      case AppRoutes.quranSearchDebug:
        return MaterialPageRoute<QuranSearchDebugScreen>(
          builder: (_) => const QuranSearchDebugScreen(),
          settings: settings,
        );
      case AppRoutes.settings:
        return MaterialPageRoute<SettingsScreen>(
          builder: (_) => const SettingsScreen(),
          settings: settings,
        );
      default:
        return MaterialPageRoute<UnknownRouteScreen>(
          builder: (_) => UnknownRouteScreen(routeName: settings.name),
          settings: settings,
        );
    }
  }
}

class UnknownRouteScreen extends StatelessWidget {
  const UnknownRouteScreen({required this.routeName, super.key});

  final String? routeName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Unknown Route')),
      body: Center(child: Text('No route found for: ${routeName ?? 'null'}')),
    );
  }
}
