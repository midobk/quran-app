import 'package:flutter/material.dart';

import '../../core/arabic/arabic_normalizer.dart';
import '../../core/di/service_locator.dart';
import '../../core/logging/app_logger.dart';
import '../../core/navigation/app_routes.dart';
import '../../data/quran/quran_repository.dart';
import '../../services/ads/ads_service.dart';
import '../../services/asr/model_manager.dart';
import '../../services/asr/whisper_cpp_service.dart';
import '../../services/audio/mic_service.dart';
import '../../services/diagnostics/diagnostics_store.dart';
import '../../services/search/quran_search_engine.dart';
import '../../ui/widgets/ad_banner_slot.dart';
import '../../ui/widgets/ayah_highlight_text.dart';
import 'live_screen_controller.dart';

class LiveScreen extends StatefulWidget {
  const LiveScreen({
    required this.initialLockedAyahId,
    super.key,
    this.controller,
    this.initialSurahNameAr,
    this.initialAyahNo,
  });

  final int initialLockedAyahId;
  final LiveScreenController? controller;
  final String? initialSurahNameAr;
  final int? initialAyahNo;

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  final ArabicNormalizer _normalizer = const ArabicNormalizer();
  late final LiveScreenController _controller;
  bool _showDebug = false;
  int _manualJumpCount = 0;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ??
        LiveScreenController(
          initialPointerAyahId: widget.initialLockedAyahId,
          micService: serviceLocator<MicService>(),
          whisperService: serviceLocator<WhisperCppService>(),
          modelManager: serviceLocator<ModelManager>(),
          searchEngine: serviceLocator<QuranSearchEngine>(),
          repository: serviceLocator<QuranRepository>(),
          logger: serviceLocator<AppLogger>(),
          diagnosticsStore: serviceLocator<DiagnosticsStore>(),
        );
    _controller.init();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _recalibrate() async {
    await _maybeShowInterstitial('recalibrate');
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushReplacementNamed(AppRoutes.listeningWarmup);
  }

  Future<void> _onManualJump(Future<void> Function() jumpAction) async {
    await jumpAction();
    _manualJumpCount++;
    if (_manualJumpCount >= 4) {
      _manualJumpCount = 0;
      await _maybeShowInterstitial('manual_jump');
    }
  }

  Future<void> _maybeShowInterstitial(String trigger) async {
    if (!serviceLocator.isRegistered<AdsService>()) {
      return;
    }

    try {
      await serviceLocator<AdsService>().maybeShowInterstitial(trigger);
    } on Object {
      // Keep user action responsive even when ad service is unavailable.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Display'),
        actions: <Widget>[
          IconButton(
            onPressed: () {
              setState(() {
                _showDebug = !_showDebug;
              });
            },
            icon: Icon(_showDebug ? Icons.bug_report : Icons.bug_report_outlined),
            tooltip: 'Toggle debug details',
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, _) {
          if (_controller.isInitializing) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_controller.errorMessage != null) {
            return Center(child: Text('Live mode error: ${_controller.errorMessage}'));
          }

          final ayah = _controller.currentAyah;
          if (ayah == null) {
            final String fallbackLabel =
                widget.initialSurahNameAr != null && widget.initialAyahNo != null
                ? 'سورة ${widget.initialSurahNameAr} • آية ${widget.initialAyahNo}'
                : 'Ayah #${widget.initialLockedAyahId}';
            return Center(child: Text('No ayah data found yet for $fallbackLabel'));
          }

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (_controller.isLostTrack)
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('Lost track — tap Recalibrate'),
                  ),
                Text(
                  'سورة ${ayah.surahNameAr} • آية ${ayah.ayahNo}',
                  textDirection: TextDirection.rtl,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                AyahHighlightText(
                  uthmaniText: ayah.textUthmani,
                  ayahNormalizedTokens: _normalizer.tokenize(ayah.textNorm),
                  matchStartTokenIndex: _controller.matchStartTokenIndex,
                  matchEndTokenIndex: _controller.matchEndTokenIndex,
                  matchedTokens: _controller.matchedTokens,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 2),
                ),
                if (ayah.translationEn.trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    ayah.translationEn,
                    style: Theme.of(context).textTheme.bodyMedium,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.start,
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  'Confidence: ${_controller.lastConfidence.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text('Live transcript', style: Theme.of(context).textTheme.labelMedium),
                      const SizedBox(height: 4),
                      Text(
                        _controller.currentTranscriptSnippet.trim().isEmpty
                            ? '(listening...)'
                            : _controller.currentTranscriptSnippet,
                        textDirection: TextDirection.rtl,
                        style: Theme.of(context).textTheme.bodyMedium,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                if (_showDebug)
                  Text(
                    'Snippet: ${_truncateSnippet(_controller.currentTranscriptSnippet)}'
                    ' • score ${_controller.lastConfidence.toStringAsFixed(2)}'
                    ' • n=${_controller.lastNUsed}'
                    ' • win ${_controller.lastWindowBack}/${_controller.lastWindowForward}'
                    ' • whisper ${_controller.lastWhisperLatencyMs}ms'
                    ' • search ${_controller.lastSearchLatencyMs}ms'
                    ' • tick ${_controller.lastTickDurationMs}ms',
                    style: Theme.of(context).textTheme.bodySmall,
                    textDirection: TextDirection.rtl,
                  ),
                const SizedBox(height: 6),
                Text(
                  'Speech: ${_controller.isSpeechDetected} • RMS: ${_controller.currentRms.toStringAsFixed(4)}'
                  ' • interval ${_controller.effectiveTickIntervalMs}ms'
                  ' • chunk ${_controller.effectiveChunkSeconds}s',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _onManualJump(_controller.goToPreviousAyah),
                        child: const Text('Prev Ayah'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _onManualJump(_controller.goToNextAyah),
                        child: const Text('Next Ayah'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _controller.toggleTrackingPaused,
                  child: Text(_controller.isTrackingPaused ? 'Resume Tracking' : 'Pause Tracking'),
                ),
                const SizedBox(height: 12),
                ElevatedButton(onPressed: _recalibrate, child: const Text('Recalibrate')),
                const SizedBox(height: 8),
                const AdBannerSlot(),
              ],
            ),
          );
        },
      ),
    );
  }

  String _truncateSnippet(String value) {
    final String trimmed = value.trim();
    if (trimmed.length <= 80) {
      return trimmed;
    }
    return '${trimmed.substring(0, 80)}…';
  }
}
