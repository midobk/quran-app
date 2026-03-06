import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/di/service_locator.dart';
import '../../core/logging/app_logger.dart';
import '../../core/navigation/app_routes.dart';
import '../../data/quran/quran_repository.dart';
import '../../services/asr/model_manager.dart';
import '../../services/asr/whisper_cpp_service.dart';
import '../../services/audio/mic_service.dart';
import '../../services/diagnostics/diagnostics_store.dart';
import '../../services/search/quran_search_engine.dart';
import '../../services/settings/app_settings_behavior.dart';
import '../../services/settings/app_settings_service.dart';
import '../../ui/theme/quran_listener_design.dart';
import '../live/live_screen.dart';
import '../results/results_screen.dart';
import 'listening_warmup_controller.dart';

class ListeningWarmupScreen extends StatefulWidget {
  const ListeningWarmupScreen({
    super.key,
    this.controller,
    this.warmupDuration = const Duration(seconds: 10),
    this.resultsScreenBuilder,
    this.liveScreenBuilder,
    this.autoLockConfig,
    this.settingsService,
  });

  final ListeningWarmupController? controller;
  final Duration warmupDuration;
  final Widget Function(WarmupOutcome outcome)? resultsScreenBuilder;
  final Widget Function(SearchResult result)? liveScreenBuilder;
  final SearchConfig? autoLockConfig;
  final AppSettingsService? settingsService;

  @override
  State<ListeningWarmupScreen> createState() => _ListeningWarmupScreenState();
}

class _ListeningWarmupScreenState extends State<ListeningWarmupScreen> {
  late final AppSettingsService _settingsService;
  late final ListeningWarmupController _controller;
  Future<void>? _prepareWhisperFuture;

  @override
  void initState() {
    super.initState();
    _settingsService =
        widget.settingsService ??
        (serviceLocator.isRegistered<AppSettingsService>()
            ? serviceLocator<AppSettingsService>()
            : AppSettingsService());
    _controller =
        widget.controller ??
        ListeningWarmupController(
          startMic: serviceLocator<MicService>().start,
          stopMic: serviceLocator<MicService>().stop,
          getLastSecondsPcm16k: serviceLocator<MicService>().getLastSecondsPcm16k,
          previewTranscribe: _transcribeWithWhisper,
          prepareForTranscription: _prepareWhisper,
          transcribe: _transcribeWithWhisper,
          searchGlobal: serviceLocator<QuranSearchEngine>().searchGlobal,
          ensureSeedData: serviceLocator<QuranRepository>().ensureDevSeedDataIfEmpty,
          warmupDuration: widget.warmupDuration,
          previewChunkSeconds: 1.2,
          previewTimeout: const Duration(seconds: 6),
          transcribeTimeout: const Duration(seconds: 35),
          logger: serviceLocator<AppLogger>(),
          diagnosticsStore: serviceLocator<DiagnosticsStore>(),
        );

    _runWarmup();
  }

  Future<void> _prepareWhisper() {
    final Future<void>? existing = _prepareWhisperFuture;
    if (existing != null) {
      return existing;
    }

    final Future<void> created = _prepareWhisperInternal();
    _prepareWhisperFuture = created;
    return created;
  }

  Future<void> _prepareWhisperInternal() async {
    final ModelManager modelManager = serviceLocator<ModelManager>();
    final WhisperCppService whisperService = serviceLocator<WhisperCppService>();

    final ModelStatus modelStatus = await modelManager.ensureBundledModelCopied();
    if (!modelStatus.exists) {
      throw const WarmupFailure(ListeningWarmupController.couldNotDetectRecitationMessage);
    }

    if (!whisperService.isInitialized || whisperService.modelPath != modelStatus.modelPath) {
      await whisperService.init(modelPath: modelStatus.modelPath);
    }
  }

  Future<String> _transcribeWithWhisper(Float32List pcm16k) async {
    final WhisperCppService whisperService = serviceLocator<WhisperCppService>();
    await _prepareWhisper();
    return whisperService.transcribe(pcm16k, lang: 'ar');
  }

  SearchResult? _resolveAutoLockCandidate(List<SearchResult> results, SearchConfig config) {
    if (!_settingsService.settings.autoDetectAyah || results.isEmpty) {
      return null;
    }

    final SearchResult top = results.first;
    if (results.length == 1) {
      return top.score >= config.autoLockMinScore ? top : null;
    }

    final SearchResult second = results[1];
    final double margin = top.score - second.score;
    if (top.score >= config.autoLockMinScore && margin >= config.autoLockMinMargin) {
      return top;
    }

    return null;
  }

  Future<void> _runWarmup() async {
    try {
      final WarmupOutcome outcome = await _controller.start();
      if (!mounted) {
        return;
      }

      final SearchConfig effectiveAutoLockConfig =
          widget.autoLockConfig ?? searchConfigFromSettings(_settingsService.settings);
      final SearchResult? autoLockCandidate = _resolveAutoLockCandidate(
        outcome.results,
        effectiveAutoLockConfig,
      );
      final Widget destination;
      if (autoLockCandidate != null) {
        destination =
            widget.liveScreenBuilder?.call(autoLockCandidate) ??
            LiveScreen(
              initialLockedAyahId: autoLockCandidate.ayah.id,
              initialSurahNameAr: autoLockCandidate.ayah.surahNameAr,
              initialAyahNo: autoLockCandidate.ayah.ayahNo,
              settingsService: _settingsService,
            );
      } else {
        destination =
            widget.resultsScreenBuilder?.call(outcome) ??
            ResultsScreen(
              transcript: outcome.transcript,
              results: outcome.results,
              autoLockConfig: effectiveAutoLockConfig,
              settingsService: _settingsService,
            );
      }
      await Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute<void>(builder: (_) => destination));
    } catch (_) {
      // The controller exposes errorMessage; UI updates through AnimatedBuilder.
    }
  }

  void _cancelAndReturnHome() {
    Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.home, (Route<dynamic> route) => false);
  }

  void _retryWarmup() {
    if (_controller.isRunning) {
      return;
    }
    _runWarmup();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: QuranListenerBackground(
        patternOpacity: 0.06,
        child: SafeArea(
          bottom: false,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (BuildContext context, _) {
              final bool hasError = _controller.errorMessage != null;
              final bool isProcessing = _controller.isProcessing;
              final bool isListening = _controller.isRunning && !isProcessing;
              final QuranListenerPalette colors = context.quranPalette;
              final ThemeData theme = Theme.of(context);
              final String title = hasError
                  ? 'Warmup failed'
                  : isProcessing
                  ? 'Processing recitation...'
                  : 'Listening to recitation...';
              final String subtitle = hasError
                  ? _controller.errorMessage!
                  : isProcessing
                  ? 'Running offline transcription and Quran search.'
                  : 'Hold device near the speaker';

              return Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                    child: Row(
                      children: <Widget>[
                        const SizedBox(width: 40),
                        Expanded(
                          child: Text(
                            'Listening',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        QuranListenerIconButton(
                          size: 40,
                          icon: const Icon(Icons.close_rounded),
                          onPressed: _cancelAndReturnHome,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: hasError ? QuranListenerColors.statusLow : theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          _WaveformStrip(isActive: isListening),
                          const SizedBox(height: 24),
                          if (isProcessing)
                            const CircularProgressIndicator()
                          else
                            Stack(
                              alignment: Alignment.center,
                              children: <Widget>[
                                SizedBox(
                                  width: 140,
                                  height: 140,
                                  child: CircularProgressIndicator(
                                    value: _controller.progress.clamp(0, 1),
                                    strokeWidth: 6,
                                  ),
                                ),
                                Container(
                                  width: 92,
                                  height: 92,
                                  decoration: BoxDecoration(
                                    color: colors.bgSurface,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: colors.strokeDefault),
                                  ),
                                  child: Icon(
                                    hasError ? Icons.refresh_rounded : Icons.mic_rounded,
                                    size: 40,
                                    color: hasError
                                        ? QuranListenerColors.statusLow
                                        : theme.colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          const SizedBox(height: 22),
                          Text(
                            hasError
                                ? 'Retry warmup'
                                : isProcessing
                                ? 'Finalizing transcript'
                                : 'Listening… (${_controller.remainingSeconds}s)',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          const SizedBox(height: 10),
                          if (_controller.liveTranscriptPreview.trim().isNotEmpty &&
                              !hasError &&
                              !isProcessing)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: colors.bgSurface,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: colors.strokeDefault),
                              ),
                              child: Text(
                                _controller.liveTranscriptPreview,
                                textDirection: TextDirection.rtl,
                                textAlign: TextAlign.center,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            )
                          else
                            Text(
                              hasError
                                  ? 'Could not detect a reliable recitation sample.'
                                  : isProcessing
                                  ? 'Searching Quran matches from the captured sample.'
                                  : 'Speak clearly for the next ${math.max(1, _controller.remainingSeconds)} seconds.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: hasError ? _retryWarmup : _cancelAndReturnHome,
                            child: Text(hasError ? 'Retry' : 'Cancel'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _WaveformStrip extends StatefulWidget {
  const _WaveformStrip({required this.isActive});

  final bool isActive;

  @override
  State<_WaveformStrip> createState() => _WaveformStripState();
}

class _WaveformStripState extends State<_WaveformStrip> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    if (widget.isActive) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _WaveformStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive == oldWidget.isActive) {
      return;
    }
    if (widget.isActive) {
      _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List<Widget>.generate(12, (int index) {
              final double phase = (_controller.value + (index * 0.08)) % 1.0;
              final double heightFactor = widget.isActive
                  ? 0.35 + (math.sin(phase * math.pi * 2) + 1) * 0.28
                  : 0.25;
              return Container(
                width: 8,
                height: 40 * heightFactor,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: widget.isActive ? 0.95 : 0.35),
                  borderRadius: BorderRadius.circular(999),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
