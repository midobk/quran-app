import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/logging/app_logger.dart';
import '../../data/quran/ayah_row.dart';
import '../../data/quran/quran_repository.dart';
import '../../services/asr/model_manager.dart';
import '../../services/asr/whisper_cpp_service.dart';
import '../../services/audio/mic_service.dart';
import '../../services/diagnostics/diagnostics_store.dart';
import '../../services/search/quran_search_engine.dart';
import 'live_guardrail.dart';
import 'live_tracking_logic.dart';

class LiveScreenController extends ChangeNotifier {
  LiveScreenController({
    required int initialPointerAyahId,
    required MicService micService,
    required WhisperCppService whisperService,
    required ModelManager modelManager,
    required QuranSearchEngine searchEngine,
    required QuranRepository repository,
    AppLogger? logger,
    DiagnosticsStore? diagnosticsStore,
    LiveGuardrailConfig guardrailConfig = const LiveGuardrailConfig(),
    LiveTrackingTuning trackingTuning = const LiveTrackingTuning(),
    this.autoAdvanceEnabled = true,
    this.tickInterval = const Duration(milliseconds: 1200),
    this.chunkSeconds = 7,
    this.transcribeTimeout = const Duration(seconds: 20),
    this.normalRadiusBack = 2,
    this.normalRadiusForward = 10,
    this.recoveryRadiusBack = 5,
    this.recoveryRadiusForward = 25,
  }) : assert(chunkSeconds > 0),
       _pointerAyahId = initialPointerAyahId,
       _micService = micService,
       _whisperService = whisperService,
       _modelManager = modelManager,
       _searchEngine = searchEngine,
       _repository = repository,
       _logger = logger ?? const AppLogger(),
       _diagnosticsStore = diagnosticsStore,
       _guardrailConfig = guardrailConfig,
       _trackingTuning = trackingTuning {
    _effectiveTickInterval = tickInterval;
    _effectiveChunkSeconds = chunkSeconds;
  }

  final MicService _micService;
  final WhisperCppService _whisperService;
  final ModelManager _modelManager;
  final QuranSearchEngine _searchEngine;
  final QuranRepository _repository;
  final AppLogger _logger;
  final DiagnosticsStore? _diagnosticsStore;
  final LiveGuardrailConfig _guardrailConfig;
  final LiveTrackingTuning _trackingTuning;

  final bool autoAdvanceEnabled;
  final Duration tickInterval;
  final int chunkSeconds;
  final Duration transcribeTimeout;
  final int normalRadiusBack;
  final int normalRadiusForward;
  final int recoveryRadiusBack;
  final int recoveryRadiusForward;
  late Duration _effectiveTickInterval;
  late int _effectiveChunkSeconds;
  int _highLatencyStreak = 0;

  int _pointerAyahId;
  AyahRow? _currentAyah;
  bool _isInitializing = true;
  String? _errorMessage;
  bool _isDisposed = false;

  Timer? _tickTimer;
  bool _isTickRunning = false;
  bool _isTrackingPaused = false;

  String _currentTranscriptSnippet = '';
  double _lastConfidence = 0;
  int _lastNUsed = 0;
  int _lastResultCount = 0;
  int _lastWhisperLatencyMs = 0;
  int _lastSearchLatencyMs = 0;
  int _lastTickDurationMs = 0;
  int _lastWindowBack = 2;
  int _lastWindowForward = 10;

  int _consecutiveLowConfidence = 0;
  int _consecutiveNoResults = 0;
  bool _isRecoveryMode = false;
  int _recoveryTicks = 0;

  int? _matchStartTokenIndex;
  int? _matchEndTokenIndex;
  List<String> _matchedTokens = const <String>[];

  int get pointerAyahId => _pointerAyahId;
  AyahRow? get currentAyah => _currentAyah;
  bool get isInitializing => _isInitializing;
  String? get errorMessage => _errorMessage;
  String get currentTranscriptSnippet => _currentTranscriptSnippet;
  double get lastConfidence => _lastConfidence;
  int get lastNUsed => _lastNUsed;
  int get lastResultCount => _lastResultCount;
  int get lastWhisperLatencyMs => _lastWhisperLatencyMs;
  int get lastSearchLatencyMs => _lastSearchLatencyMs;
  int get lastTickDurationMs => _lastTickDurationMs;
  int get lastWindowBack => _lastWindowBack;
  int get lastWindowForward => _lastWindowForward;
  int get effectiveTickIntervalMs => _effectiveTickInterval.inMilliseconds;
  int get effectiveChunkSeconds => _effectiveChunkSeconds;
  int get highLatencyStreak => _highLatencyStreak;
  bool get isTrackingPaused => _isTrackingPaused;
  bool get isTrackingActive => !_isTrackingPaused;
  bool get isTickRunning => _isTickRunning;
  bool get isRecoveryMode => _isRecoveryMode;
  int get recoveryTicks => _recoveryTicks;
  int get consecutiveLowConfidence => _consecutiveLowConfidence;
  int get consecutiveNoResults => _consecutiveNoResults;
  int? get matchStartTokenIndex => _matchStartTokenIndex;
  int? get matchEndTokenIndex => _matchEndTokenIndex;
  List<String> get matchedTokens => _matchedTokens;
  bool get isSpeechDetected => _micService.isSpeech;
  double get currentRms => _micService.currentRms;
  bool get isLostTrack => LiveTrackingLogic.shouldShowLostTrackBanner(
    isRecoveryMode: _isRecoveryMode,
    recoveryTicks: _recoveryTicks,
  );

  Future<void> init() async {
    _isInitializing = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _repository.ensureDevSeedDataIfEmpty();
      _currentAyah = await _repository.getAyahById(_pointerAyahId);
      await _micService.init();

      final ModelStatus modelStatus = await _modelManager.ensureBundledModelCopied();
      if (!modelStatus.exists) {
        throw StateError('Whisper model missing. Open Settings and re-copy the bundled model.');
      }
      if (!_whisperService.isInitialized || _whisperService.modelPath != modelStatus.modelPath) {
        await _whisperService.init(modelPath: modelStatus.modelPath);
      }

      _isInitializing = false;
      notifyListeners();
      _startScheduler();
    } catch (error) {
      _isInitializing = false;
      _errorMessage = '$error';
      notifyListeners();
    }
  }

  void toggleTrackingPaused() {
    _isTrackingPaused = !_isTrackingPaused;
    notifyListeners();
    if (!_isTrackingPaused && !_isTickRunning) {
      unawaited(_runTick());
    }
  }

  Future<void> goToPreviousAyah() async {
    final AyahRow? currentAyah = _currentAyah;
    if (currentAyah == null) {
      return;
    }
    final AyahRow? previousAyah = await _repository.getPreviousAyah(currentAyah);
    if (previousAyah != null) {
      await _setPointerAyah(previousAyah.id);
    }
  }

  Future<void> goToNextAyah() async {
    final AyahRow? currentAyah = _currentAyah;
    if (currentAyah == null) {
      return;
    }
    final AyahRow? nextAyah = await _repository.getNextAyah(currentAyah);
    if (nextAyah != null) {
      await _setPointerAyah(nextAyah.id);
    }
  }

  Future<void> _setPointerAyah(int ayahId) async {
    if (ayahId < 1) {
      return;
    }
    final AyahRow? ayah = await _repository.getAyahById(ayahId);
    if (ayah == null) {
      return;
    }
    _pointerAyahId = ayah.id;
    _currentAyah = ayah;
    _clearTrackingPenaltyState();
    _clearMatch();
    notifyListeners();
  }

  void _startScheduler() {
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(_effectiveTickInterval, (_) {
      if (_isDisposed || _isTrackingPaused || _isTickRunning) {
        return;
      }
      unawaited(_runTick());
    });

    if (!_isTrackingPaused && !_isTickRunning) {
      unawaited(_runTick());
    }
  }

  Future<void> _runTick() async {
    if (_isDisposed || _isTrackingPaused || _isTickRunning) {
      return;
    }
    _isTickRunning = true;
    final Stopwatch tickWatch = Stopwatch()..start();
    bool tickVadSkipped = false;
    bool tickLowConfidence = false;
    int? tickWhisperLatencyMs;
    int? tickSearchLatencyMs;

    try {
      if (!_micService.isRunning) {
        await _micService.start();
      }

      if (!_micService.isSpeech) {
        _currentTranscriptSnippet = '';
        _lastResultCount = 0;
        _lastNUsed = 0;
        tickVadSkipped = true;
        _applyGuardrail(null);
        _recordDiagnosticsTick(
          vadSkipped: tickVadSkipped,
          lowConfidence: tickLowConfidence,
          whisperLatencyMs: tickWhisperLatencyMs,
          searchLatencyMs: tickSearchLatencyMs,
        );
        return;
      }

      final Float32List pcm = _micService.getLastSecondsPcm16k(_effectiveChunkSeconds.toDouble());
      if (pcm.isEmpty) {
        _onNoResultsTick();
        _recordDiagnosticsTick(
          vadSkipped: tickVadSkipped,
          lowConfidence: autoAdvanceEnabled,
          whisperLatencyMs: tickWhisperLatencyMs,
          searchLatencyMs: tickSearchLatencyMs,
        );
        return;
      }

      final Stopwatch whisperWatch = Stopwatch()..start();
      String transcript = '';
      try {
        transcript = await _whisperService
            .transcribe(pcm, lang: 'ar')
            .timeout(
              transcribeTimeout,
              onTimeout: () => throw TimeoutException(
                'Whisper timed out after ${transcribeTimeout.inSeconds}s.',
              ),
            );
      } on TimeoutException catch (error) {
        whisperWatch.stop();
        _lastWhisperLatencyMs = transcribeTimeout.inMilliseconds;
        tickWhisperLatencyMs = _lastWhisperLatencyMs;
        _logger.warning('Live whisper timeout: $error');
        _onNoResultsTick();
        _applyGuardrail(_lastWhisperLatencyMs);
        _recordDiagnosticsTick(
          vadSkipped: tickVadSkipped,
          lowConfidence: autoAdvanceEnabled,
          whisperLatencyMs: tickWhisperLatencyMs,
          searchLatencyMs: tickSearchLatencyMs,
        );
        return;
      }
      whisperWatch.stop();
      _lastWhisperLatencyMs = whisperWatch.elapsedMilliseconds;
      tickWhisperLatencyMs = _lastWhisperLatencyMs;
      _applyGuardrail(_lastWhisperLatencyMs);

      _currentTranscriptSnippet = transcript.trim();
      _logger.debug('Live transcript: $_currentTranscriptSnippet');
      if (_currentTranscriptSnippet.isEmpty) {
        _onNoResultsTick();
        _recordDiagnosticsTick(
          vadSkipped: tickVadSkipped,
          lowConfidence: autoAdvanceEnabled,
          whisperLatencyMs: tickWhisperLatencyMs,
          searchLatencyMs: tickSearchLatencyMs,
        );
        return;
      }

      if (!autoAdvanceEnabled) {
        _lastConfidence = 0;
        _lastNUsed = 0;
        _lastResultCount = 0;
        _clearTrackingPenaltyState();
        _clearMatch();
        _recordDiagnosticsTick(
          vadSkipped: tickVadSkipped,
          lowConfidence: false,
          whisperLatencyMs: tickWhisperLatencyMs,
          searchLatencyMs: tickSearchLatencyMs,
        );
        return;
      }

      final int radiusBack = _isRecoveryMode ? recoveryRadiusBack : normalRadiusBack;
      final int radiusForward = _isRecoveryMode ? recoveryRadiusForward : normalRadiusForward;
      _lastWindowBack = radiusBack;
      _lastWindowForward = radiusForward;

      final Stopwatch searchWatch = Stopwatch()..start();
      final List<SearchResult> results = await _searchEngine.searchNear(
        _pointerAyahId,
        _currentTranscriptSnippet,
        radiusBack: radiusBack,
        radiusForward: radiusForward,
      );
      searchWatch.stop();
      _lastSearchLatencyMs = searchWatch.elapsedMilliseconds;
      tickSearchLatencyMs = _lastSearchLatencyMs;
      _lastResultCount = results.length;
      _logger.debug('Live search results: ${results.length}');

      if (results.isEmpty) {
        _onNoResultsTick();
        _recordDiagnosticsTick(
          vadSkipped: tickVadSkipped,
          lowConfidence: true,
          whisperLatencyMs: tickWhisperLatencyMs,
          searchLatencyMs: tickSearchLatencyMs,
        );
        return;
      }

      final SearchResult best = results.first;
      final SearchResult? second = results.length > 1 ? results[1] : null;
      _lastConfidence = best.score;
      _lastNUsed = best.nUsed;

      final bool confident = LiveTrackingLogic.isConfidentCandidate(
        topScore: best.score,
        secondScore: second?.score,
        tuning: _trackingTuning,
      );
      tickLowConfidence = !confident;

      final bool shouldAdvance = LiveTrackingLogic.shouldAdvancePointer(
        currentAyahId: _pointerAyahId,
        candidateAyahId: best.ayah.id,
        topScore: best.score,
        secondScore: second?.score,
        isRecoveryMode: _isRecoveryMode,
        recoveryTicks: _recoveryTicks,
        tuning: _trackingTuning,
      );

      if (confident) {
        _consecutiveLowConfidence = 0;
        _consecutiveNoResults = 0;

        final bool recovered = shouldAdvance || best.ayah.id == _pointerAyahId;
        if (recovered) {
          _isRecoveryMode = false;
          _recoveryTicks = 0;
        } else if (_isRecoveryMode) {
          _recoveryTicks++;
        }
      } else {
        _consecutiveLowConfidence++;
        _consecutiveNoResults = 0;
        _updateRecoveryModeForPenaltyTick();
      }

      if (shouldAdvance) {
        _pointerAyahId = best.ayah.id;
        _currentAyah = best.ayah;
        _setMatchFromResult(best);
      } else if (best.ayah.id == _pointerAyahId) {
        _currentAyah = best.ayah;
        _setMatchFromResult(best);
      } else {
        _clearMatch();
      }

      _recordDiagnosticsTick(
        vadSkipped: tickVadSkipped,
        lowConfidence: tickLowConfidence,
        whisperLatencyMs: tickWhisperLatencyMs,
        searchLatencyMs: tickSearchLatencyMs,
      );
    } catch (error) {
      _logger.warning('Live tracking tick failed: $error');
      _errorMessage = 'Live tracking error: $error';
      _recordDiagnosticsTick(
        vadSkipped: tickVadSkipped,
        lowConfidence: autoAdvanceEnabled,
        whisperLatencyMs: tickWhisperLatencyMs,
        searchLatencyMs: tickSearchLatencyMs,
      );
    } finally {
      tickWatch.stop();
      _lastTickDurationMs = tickWatch.elapsedMilliseconds;
      _isTickRunning = false;
      if (!_isDisposed) {
        notifyListeners();
      }
    }
  }

  void _onNoResultsTick() {
    _lastConfidence = 0;
    _lastNUsed = 0;
    _lastResultCount = 0;
    _clearMatch();

    if (!autoAdvanceEnabled) {
      return;
    }

    _consecutiveNoResults++;
    _consecutiveLowConfidence = 0;
    _updateRecoveryModeForPenaltyTick();
  }

  void _applyGuardrail(int? whisperLatencyMs) {
    final LiveGuardrailDecision decision = LiveGuardrailLogic.evaluate(
      state: LiveGuardrailState(
        tickIntervalMs: _effectiveTickInterval.inMilliseconds,
        chunkSeconds: _effectiveChunkSeconds,
        highLatencyStreak: _highLatencyStreak,
      ),
      config: _guardrailConfig,
      lastWhisperLatencyMs: whisperLatencyMs,
    );

    _highLatencyStreak = decision.highLatencyStreak;
    final bool intervalChanged = decision.tickIntervalMs != _effectiveTickInterval.inMilliseconds;
    _effectiveTickInterval = Duration(milliseconds: decision.tickIntervalMs);
    _effectiveChunkSeconds = decision.chunkSeconds;

    if (intervalChanged && !_isDisposed) {
      _startScheduler();
    }
  }

  void _recordDiagnosticsTick({
    required bool vadSkipped,
    required bool lowConfidence,
    int? whisperLatencyMs,
    int? searchLatencyMs,
  }) {
    final AyahRow? current = _currentAyah;
    final DiagnosticsStore? store = _diagnosticsStore;
    if (store == null || current == null) {
      return;
    }

    store.recordLiveTick(
      vadSkipped: vadSkipped,
      lowConfidence: lowConfidence,
      whisperLatencyMs: whisperLatencyMs,
      searchLatencyMs: searchLatencyMs,
      windowBack: _lastWindowBack,
      windowForward: _lastWindowForward,
      pointerAyahId: _pointerAyahId,
      pointerSurahNameAr: current.surahNameAr,
      pointerAyahNo: current.ayahNo,
    );
  }

  void _updateRecoveryModeForPenaltyTick() {
    if (LiveTrackingLogic.shouldEnterRecovery(
      consecutiveLowConfidence: _consecutiveLowConfidence,
      consecutiveNoResults: _consecutiveNoResults,
    )) {
      if (!_isRecoveryMode) {
        _isRecoveryMode = true;
        _recoveryTicks = 1;
      } else {
        _recoveryTicks++;
      }
      return;
    }

    if (_isRecoveryMode) {
      _recoveryTicks++;
    }
  }

  void _clearTrackingPenaltyState() {
    _consecutiveLowConfidence = 0;
    _consecutiveNoResults = 0;
    _isRecoveryMode = false;
    _recoveryTicks = 0;
  }

  void _setMatchFromResult(SearchResult result) {
    _matchStartTokenIndex = result.matchStartTokenIndex;
    _matchEndTokenIndex = result.matchEndTokenIndex;
    _matchedTokens = List<String>.from(result.matchedTokens);
  }

  void _clearMatch() {
    _matchStartTokenIndex = null;
    _matchEndTokenIndex = null;
    _matchedTokens = const <String>[];
  }

  @override
  void dispose() {
    _isDisposed = true;
    _tickTimer?.cancel();
    unawaited(_micService.stop());
    super.dispose();
  }
}
