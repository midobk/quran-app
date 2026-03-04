import 'package:flutter/material.dart';

import '../../core/di/service_locator.dart';
import '../../core/navigation/app_routes.dart';
import '../../services/ads/ads_service.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _navigateWithTrigger(
    BuildContext context, {
    required String route,
    required String trigger,
  }) async {
    await serviceLocator<AdsService>().maybeShowInterstitial(trigger);
    if (context.mounted) {
      Navigator.of(context).pushNamed(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AdsService adsService = serviceLocator<AdsService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Quran Live Ayah')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Offline Quran live ayah display app skeleton.',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => _navigateWithTrigger(
                  context,
                  route: AppRoutes.listeningWarmup,
                  trigger: 'home_start_listening',
                ),
                child: const Text('Start Listening'),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => _navigateWithTrigger(
                  context,
                  route: AppRoutes.quranSearchDebug,
                  trigger: 'home_quran_search_debug',
                ),
                child: const Text('Quran Search (Debug)'),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => _navigateWithTrigger(
                  context,
                  route: AppRoutes.settings,
                  trigger: 'home_settings',
                ),
                child: const Text('Settings'),
              ),
              const Spacer(),
              adsService.banner(),
            ],
          ),
        ),
      ),
    );
  }
}
