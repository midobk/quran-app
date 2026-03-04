import 'package:flutter/foundation.dart';

import 'rolling_stats_buffer.dart';

class DiagnosticsStore extends ChangeNotifier {
  DiagnosticsStore({this.capacity = 30})
    : assert(capacity > 0),
      _whisperLatencyMs = RollingStatsBuffer(capacity: capacity),
      _searchLatencyMs = RollingStatsBuffer(capacity: capacity),
      _vadSkippedFlags = RollingStatsBuffer(capacity: capacity),
      _lowConfidenceFlags = RollingStatsBuffer(capacity: capacity);

  final int capacity;
  final RollingStatsBuffer _whisperLatencyMs;
  final RollingStatsBuffer _searchLatencyMs;
  final RollingStatsBuffer _vadSkippedFlags;
  final RollingStatsBuffer _lowConfidenceFlags;

  int _windowBack = 2;
  int _windowForward = 10;
  int? _pointerAyahId;
  String _pointerSurahNameAr = '-';
  int? _pointerAyahNo;

  int get samplesCount => _vadSkippedFlags.length;
  double get avgWhisperLatencyMs => _whisperLatencyMs.average;
  double get avgSearchLatencyMs => _searchLatencyMs.average;
  double get vadSkipRatePercent => _vadSkippedFlags.average * 100;
  double get lowConfidenceRatePercent => _lowConfidenceFlags.average * 100;

  int get windowBack => _windowBack;
  int get windowForward => _windowForward;
  int? get pointerAyahId => _pointerAyahId;
  String get pointerSurahNameAr => _pointerSurahNameAr;
  int? get pointerAyahNo => _pointerAyahNo;

  void recordWhisperLatencyMs(int value) {
    _whisperLatencyMs.add(value.toDouble());
    notifyListeners();
  }

  void recordSearchLatencyMs(int value) {
    _searchLatencyMs.add(value.toDouble());
    notifyListeners();
  }

  void recordLiveTick({
    required bool vadSkipped,
    required bool lowConfidence,
    int? whisperLatencyMs,
    int? searchLatencyMs,
    required int windowBack,
    required int windowForward,
    required int pointerAyahId,
    required String pointerSurahNameAr,
    required int pointerAyahNo,
  }) {
    if (whisperLatencyMs != null) {
      _whisperLatencyMs.add(whisperLatencyMs.toDouble());
    }
    if (searchLatencyMs != null) {
      _searchLatencyMs.add(searchLatencyMs.toDouble());
    }
    _vadSkippedFlags.add(vadSkipped ? 1 : 0);
    _lowConfidenceFlags.add(lowConfidence ? 1 : 0);

    _windowBack = windowBack;
    _windowForward = windowForward;
    _pointerAyahId = pointerAyahId;
    _pointerSurahNameAr = pointerSurahNameAr;
    _pointerAyahNo = pointerAyahNo;
    notifyListeners();
  }
}
