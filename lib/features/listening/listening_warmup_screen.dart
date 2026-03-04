import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/di/service_locator.dart';
import '../../core/logging/app_logger.dart';
import '../../data/quran/quran_repository.dart';
import '../../services/asr/model_manager.dart';
import '../../services/asr/whisper_cpp_service.dart';
import '../../services/audio/mic_service.dart';
import '../../services/diagnostics/diagnostics_store.dart';
import '../../services/search/quran_search_engine.dart';
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
    this.autoLockConfig = const SearchConfig(),
  });

  final ListeningWarmupController? controller;
  final Duration warmupDuration;
  final Widget Function(WarmupOutcome outcome)? resultsScreenBuilder;
  final Widget Function(SearchResult result)? liveScreenBuilder;
  final SearchConfig autoLockConfig;

  @override
  State<ListeningWarmupScreen> createState() => _ListeningWarmupScreenState();
}

class _ListeningWarmupScreenState extends State<ListeningWarmupScreen> {
  late final ListeningWarmupController _controller;
  Future<void>? _prepareWhisperFuture;

  @override
  void initState() {
    super.initState();
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

    final modelStatus = await modelManager.ensureBundledModelCopied();
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
    if (results.isEmpty) {
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

      final SearchResult? autoLockCandidate = _resolveAutoLockCandidate(
        outcome.results,
        widget.autoLockConfig,
      );
      final Widget destination;
      if (autoLockCandidate != null) {
        destination =
            widget.liveScreenBuilder?.call(autoLockCandidate) ??
            LiveScreen(
              initialLockedAyahId: autoLockCandidate.ayah.id,
              initialSurahNameAr: autoLockCandidate.ayah.surahNameAr,
              initialAyahNo: autoLockCandidate.ayah.ayahNo,
            );
      } else {
        destination =
            widget.resultsScreenBuilder?.call(outcome) ??
            ResultsScreen(
              transcript: outcome.transcript,
              results: outcome.results,
              autoLockConfig: widget.autoLockConfig,
            );
      }
      await Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute<void>(builder: (_) => destination));
    } catch (_) {
      // The controller exposes errorMessage; UI updates through AnimatedBuilder.
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Listening Warmup')),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, _) {
          final bool hasError = _controller.errorMessage != null;
          final bool isProcessing = _controller.isProcessing;
          final double progress = _controller.progress.clamp(0, 1);
          final String title = hasError
              ? 'Warmup failed'
              : isProcessing
              ? 'Processing recitation...'
              : 'Listening… (${_controller.remainingSeconds}s)';
          final String subtitle = hasError
              ? _controller.errorMessage!
              : isProcessing
              ? 'Running offline transcription and Quran search.'
              : 'Please recite clearly during warmup.';

          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 18),
                  LinearProgressIndicator(value: isProcessing ? null : progress),
                  const SizedBox(height: 18),
                  Text(subtitle, textAlign: TextAlign.center),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(
                          'What app hears (live)',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _controller.liveTranscriptPreview.trim().isEmpty
                              ? '(listening...)'
                              : _controller.liveTranscriptPreview,
                          textDirection: TextDirection.rtl,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
