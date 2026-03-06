import 'package:flutter/material.dart';

import '../../core/di/service_locator.dart';
import '../../core/navigation/app_routes.dart';
import '../../services/asr/model_manager.dart';
import '../../ui/theme/quran_listener_design.dart';
import '../settings/diagnostics_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _navigate(BuildContext context, String route) {
    Navigator.of(context).pushNamed(route);
  }

  Future<void> _openDiagnostics(BuildContext context) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const DiagnosticsScreen()));
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
    final QuranListenerPalette colors = context.quranPalette;

    return Scaffold(
      body: QuranListenerBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              const SizedBox(height: 22),
              const _HomeHeader(),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 26),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      QuranListenerMicHeroButton(onPressed: () => _startListening(context)),
                      const SizedBox(height: 30),
                      Text('Start Listening', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 10),
                      Text(
                        'Tap to begin listening to Quran recitation. The app will automatically detect and display the current ayah.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: colors.strokeDefault)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    QuranListenerIconButton(
                      icon: const Icon(Icons.settings_rounded),
                      onPressed: () => _navigate(context, AppRoutes.settings),
                    ),
                    const SizedBox(width: 16),
                    QuranListenerIconButton(
                      icon: const Icon(Icons.monitor_heart_rounded),
                      onPressed: () => _openDiagnostics(context),
                    ),
                    const SizedBox(width: 16),
                    QuranListenerIconButton(
                      icon: const Icon(Icons.search_rounded),
                      onPressed: () => _navigate(context, AppRoutes.quranSearchDebug),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      children: <Widget>[
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: theme.colorScheme.secondary,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(Icons.access_time_rounded, size: 30, color: theme.colorScheme.primary),
        ),
        const SizedBox(height: 14),
        Text('Quran Listener', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          'بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}
