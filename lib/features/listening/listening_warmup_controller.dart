import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/logging/app_logger.dart';
import '../../services/diagnostics/diagnostics_store.dart';
import '../../services/search/quran_search_engine.dart';

class WarmupOutcome {
  const WarmupOutcome({required this.transcript, required this.results});

  final String transcript;
  final List<SearchResult> results;
}

class ListeningWarmupController extends ChangeNotifier {
  ListeningWarmupController({
    required Future<void> Function() startMic,
    required Future<void> Function() stopMic,
    required Float32List Function(double seconds) getLastSecondsPcm16k,
    required Future<String> Function(Float32List pcm16k) transcribe,
    Future<String> Function(Float32List pcm16k)? previewTranscribe,
    Future<void> Function()? prepareForTranscription,
    required Future<List<SearchResult>> Function(String transcript) searchGlobal,
    required Future<void> Function() ensureSeedData,
    this.warmupDuration = const Duration(seconds: 10),
    this.previewChunkSeconds = 2.5,
    this.previewTimeout = const Duration(seconds: 2),
    this.transcribeTimeout = const Duration(seconds: 20),
    this.searchTimeout = const Duration(seconds: 10),
    AppLogger? logger,
    DiagnosticsStore? diagnosticsStore,
  }) : _startMic = startMic,
       _stopMic = stopMic,
       _getLastSecondsPcm16k = getLastSecondsPcm16k,
       _transcribe = transcribe,
       _previewTranscribe = previewTranscribe,
       _prepareForTranscription = prepareForTranscription,
       _searchGlobal = searchGlobal,
       _ensureSeedData = ensureSeedData,
       _logger = logger ?? const AppLogger(),
       _diagnosticsStore = diagnosticsStore {
    _remainingSeconds = warmupDuration.inSeconds;
  }

  static const String couldNotDetectRecitationMessage = 'Could not detect recitation. Try again.';

  final Future<void> Function() _startMic;
  final Future<void> Function() _stopMic;
  final Float32List Function(double seconds) _getLastSecondsPcm16k;
  final Future<String> Function(Float32List pcm16k) _transcribe;
  final Future<String> Function(Float32List pcm16k)? _previewTranscribe;
  final Future<void> Function()? _prepareForTranscription;
  final Future<List<SearchResult>> Function(String transcript) _searchGlobal;
  final Future<void> Function() _ensureSeedData;
  final AppLogger _logger;
  final DiagnosticsStore? _diagnosticsStore;
  final Duration warmupDuration;
  final double previewChunkSeconds;
  final Duration previewTimeout;
  final Duration transcribeTimeout;
  final Duration searchTimeout;

  late int _remainingSeconds;
  bool _isRunning = false;
  bool _isProcessing = false;
  bool _isPreviewRunning = false;
  String? _errorMessage;
  String _liveTranscriptPreview = '';

  int get remainingSeconds => _remainingSeconds;
  bool get isRunning => _isRunning;
  bool get isProcessing => _isProcessing;
  String? get errorMessage => _errorMessage;
  String get liveTranscriptPreview => _liveTranscriptPreview;
  int get totalSeconds => warmupDuration.inSeconds;
  double get progress => totalSeconds <= 0 ? 1 : (totalSeconds - _remainingSeconds) / totalSeconds;

  Future<WarmupOutcome> start() async {
    if (_isRunning) {
      throw StateError('Warmup is already running.');
    }

    bool micStarted = false;
    _isRunning = true;
    _isProcessing = false;
    _errorMessage = null;
    _remainingSeconds = totalSeconds;
    notifyListeners();

    try {
      await _ensureSeedData();
      final Future<void> prepareFuture = _prepareForTranscription?.call() ?? Future<void>.value();
      await _startMic();
      micStarted = true;

      for (int elapsed = 0; elapsed < totalSeconds; elapsed++) {
        await Future<void>.delayed(const Duration(seconds: 1));
        _remainingSeconds = totalSeconds - elapsed - 1;
        _runPreviewTick();
        notifyListeners();
      }

      final Float32List pcm = _getLastSecondsPcm16k(warmupDuration.inSeconds.toDouble());
      if (pcm.isEmpty) {
        throw const WarmupFailure(couldNotDetectRecitationMessage);
      }

      _isProcessing = true;
      notifyListeners();
      await prepareFuture.timeout(
        transcribeTimeout,
        onTimeout: () => throw const WarmupFailure(couldNotDetectRecitationMessage),
      );
      final Stopwatch whisperStopwatch = Stopwatch()..start();
      final String transcript = await _transcribe(pcm).timeout(
        transcribeTimeout,
        onTimeout: () => throw const WarmupFailure(couldNotDetectRecitationMessage),
      );
      whisperStopwatch.stop();
      _logger.info('Warmup whisper inference: ${whisperStopwatch.elapsedMilliseconds} ms');
      _logger.info('Warmup transcript: $transcript');
      _diagnosticsStore?.recordWhisperLatencyMs(whisperStopwatch.elapsedMilliseconds);

      String trimmedTranscript = transcript.trim();
      if (trimmedTranscript.isEmpty && _liveTranscriptPreview.trim().isNotEmpty) {
        trimmedTranscript = _liveTranscriptPreview.trim();
      }
      if (trimmedTranscript.isEmpty) {
        throw const WarmupFailure(couldNotDetectRecitationMessage);
      }

      final Stopwatch searchStopwatch = Stopwatch()..start();
      final List<SearchResult> results = await _searchGlobal(trimmedTranscript).timeout(
        searchTimeout,
        onTimeout: () => throw const WarmupFailure(couldNotDetectRecitationMessage),
      );
      searchStopwatch.stop();
      _diagnosticsStore?.recordSearchLatencyMs(searchStopwatch.elapsedMilliseconds);
      _logger.info('Warmup search results: ${results.length}');

      _isRunning = false;
      _isProcessing = false;
      notifyListeners();
      return WarmupOutcome(transcript: trimmedTranscript, results: results);
    } catch (error) {
      _logger.warning('Warmup pipeline failed: $error');
      _isRunning = false;
      _isProcessing = false;
      if (error is WarmupFailure) {
        _errorMessage = error.message;
      } else {
        _errorMessage = couldNotDetectRecitationMessage;
      }
      notifyListeners();
      rethrow;
    } finally {
      if (micStarted) {
        try {
          await _stopMic();
        } catch (error) {
          _logger.warning('Failed to stop mic after warmup: $error');
        }
      }
    }
  }

  void _runPreviewTick() {
    if (_isProcessing || _isPreviewRunning || _previewTranscribe == null) {
      return;
    }
    unawaited(_runPreviewTickInternal());
  }

  Future<void> _runPreviewTickInternal() async {
    _isPreviewRunning = true;
    try {
      final Float32List chunk = _getLastSecondsPcm16k(previewChunkSeconds);
      if (chunk.isEmpty) {
        return;
      }

      final String preview = await _previewTranscribe!(
        chunk,
      ).timeout(previewTimeout, onTimeout: () => '');
      final String trimmedPreview = preview.trim();
      if (trimmedPreview.isNotEmpty) {
        _liveTranscriptPreview = trimmedPreview;
        notifyListeners();
      }
    } on Object {
      // Preview is best-effort only; ignore failures.
    } finally {
      _isPreviewRunning = false;
    }
  }
}

class WarmupFailure implements Exception {
  const WarmupFailure(this.message);

  final String message;

  @override
  String toString() {
    return message;
  }
}
