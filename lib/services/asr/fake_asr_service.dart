import 'dart:async';

import 'asr_service.dart';

class FakeAsrService implements AsrService {
  FakeAsrService({List<String>? warmupTranscripts, List<String>? liveSnippets})
    : _warmupTranscripts = warmupTranscripts ?? _defaultWarmupTranscripts,
      _liveSnippets = liveSnippets ?? _defaultLiveSnippets;

  final List<String> _warmupTranscripts;
  final List<String> _liveSnippets;

  bool _isInitialized = false;
  int _warmupCursor = 0;
  int _liveCursorOffset = 0;

  @override
  Future<void> init() async {
    _isInitialized = true;
  }

  @override
  Future<String> transcribeWarmupSample({Duration duration = const Duration(seconds: 10)}) async {
    _ensureInitialized();
    await Future<void>.delayed(const Duration(milliseconds: 250));

    final String transcript = _warmupTranscripts[_warmupCursor % _warmupTranscripts.length];
    _warmupCursor++;
    _liveCursorOffset = _warmupCursor;
    return transcript;
  }

  @override
  Stream<String> liveTranscriptStream() {
    _ensureInitialized();

    return Stream<String>.periodic(const Duration(milliseconds: 1200), (int tick) {
      final int index = (tick + _liveCursorOffset) % _liveSnippets.length;
      return _liveSnippets[index];
    });
  }

  @override
  Future<void> dispose() async {
    _isInitialized = false;
  }

  void _ensureInitialized() {
    if (!_isInitialized) {
      throw StateError('FakeAsrService is not initialized. Call init() first.');
    }
  }
}

const List<String> _defaultWarmupTranscripts = <String>[
  'الله نور السماوات والارض',
  'ان الله غفور رحيم',
  'الله اكبر الله اكبر',
];

const List<String> _defaultLiveSnippets = <String>[
  'الله نور السماوات',
  'نور السماوات والارض',
  'الله غفور رحيم',
  'الله اكبر الله',
  'الحمد لله رب العالمين',
];
