import 'package:flutter/material.dart';

import '../../core/di/service_locator.dart';
import '../../core/navigation/app_routes.dart';
import '../../services/asr/model_manager.dart';
import '../../ui/widgets/ad_banner_slot.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _navigate(BuildContext context, String route) {
    Navigator.of(context).pushNamed(route);
  }

  Future<void> _startListening(BuildContext context) async {
    try {
      final ModelStatus status = await serviceLocator<ModelManager>().ensureBundledModelCopied();
      if (!status.exists) {
        if (!context.mounted) {
          return;
        }
        await showDialog<void>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Model Missing'),
              content: const Text(
                'Whisper model is missing. Open Settings and use Diagnostics / model tools before starting listening.',
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).pushNamed(AppRoutes.settings);
                  },
                  child: const Text('Open Settings'),
                ),
              ],
            );
          },
        );
        return;
      }

      if (!context.mounted) {
        return;
      }
      _navigate(context, AppRoutes.listeningWarmup);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not verify model status: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
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
                onPressed: () => _startListening(context),
                child: const Text('Start Listening'),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => _navigate(context, AppRoutes.quranSearchDebug),
                child: const Text('Quran Search (Debug)'),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => _navigate(context, AppRoutes.settings),
                child: const Text('Settings'),
              ),
              const Spacer(),
              const AdBannerSlot(),
            ],
          ),
        ),
      ),
    );
  }
}
