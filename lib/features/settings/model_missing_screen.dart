import 'package:flutter/material.dart';

class ModelMissingScreen extends StatelessWidget {
  const ModelMissingScreen({required this.expectedModelPath, super.key});

  final String expectedModelPath;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Model Missing')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Model missing. Please import model file into the app storage.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            const Text(
              'Expected bundled asset: assets/models/whisper.gguf (or assets/models/whisper.bin)',
            ),
            const SizedBox(height: 8),
            SelectableText('App storage target: $expectedModelPath'),
            const SizedBox(height: 12),
            const Text(
              'This app stays 100% offline. No model download is performed automatically.',
            ),
          ],
        ),
      ),
    );
  }
}
