import 'dart:isolate';
import 'dart:typed_data';

import '../../core/logging/app_logger.dart';
import 'whisper_bindings.dart';

abstract class WhisperTranscriberService {
  Future<void> init({required String modelPath});
  Future<String> transcribe(Float32List pcm16k, {String lang});
  Future<void> dispose();
}

class WhisperCppService implements WhisperTranscriberService {
  WhisperCppService({AppLogger? logger}) : _logger = logger ?? const AppLogger();

  static const String _fallbackTranscript = 'الله نور السماوات';

  final AppLogger _logger;

  bool _initialized = false;
  bool _nativeAvailable = true;
  String? _modelPath;
  bool? _lastInitSuccessful;
  String? _lastInitError;
  int? _lastTranscriptionTimeMs;
  String? _lastTranscriptionError;

  bool get isInitialized => _initialized;
  String? get modelPath => _modelPath;
  bool? get lastInitSuccessful => _lastInitSuccessful;
  String? get lastInitError => _lastInitError;
  int? get lastTranscriptionTimeMs => _lastTranscriptionTimeMs;
  String? get lastTranscriptionError => _lastTranscriptionError;

  @override
  Future<void> init({required String modelPath}) async {
    final String trimmedPath = modelPath.trim();
    if (trimmedPath.isEmpty) {
      throw ArgumentError('modelPath must not be empty.');
    }
    if (_initialized && _modelPath == trimmedPath) {
      return;
    }

    try {
      final int code = await Isolate.run<int>(() {
        final WhisperBindings bindings = WhisperBindings();
        return bindings.init(trimmedPath);
      });

      if (code != 0) {
        throw StateError('Whisper init failed (code=$code) for model: $trimmedPath');
      }

      _modelPath = trimmedPath;
      _initialized = true;
      _nativeAvailable = true;
      _lastInitSuccessful = true;
      _lastInitError = null;
      _logger.info('WhisperCppService initialized with model at $trimmedPath');
    } catch (error) {
      _modelPath = trimmedPath;
      _initialized = true;
      _nativeAvailable = false;
      _lastInitSuccessful = false;
      _lastInitError = '$error';
      _logger.warning('Whisper native bridge unavailable. Falling back to mock transcript mode: $error');
    }
  }

  @override
  Future<String> transcribe(Float32List pcm16k, {String lang = 'ar'}) async {
    if (!_initialized) {
      throw StateError('WhisperCppService is not initialized. Call init(modelPath: ...) first.');
    }
    if (pcm16k.isEmpty) {
      return '';
    }

    _lastTranscriptionError = null;

    if (!_nativeAvailable) {
      _lastTranscriptionTimeMs = 0;
      return _fallbackTranscript;
    }

    final TransferableTypedData pcmData = TransferableTypedData.fromList(<Uint8List>[
      pcm16k.buffer.asUint8List(pcm16k.offsetInBytes, pcm16k.lengthInBytes),
    ]);

    final Stopwatch stopwatch = Stopwatch()..start();
    try {
      final _TranscribeResponse response = await Isolate.run<_TranscribeResponse>(() {
        final ByteData byteData = pcmData.materialize().asByteData();
        final Float32List pcm = byteData.buffer.asFloat32List(
          byteData.offsetInBytes,
          byteData.lengthInBytes ~/ Float32List.bytesPerElement,
        );

        final WhisperBindings bindings = WhisperBindings();
        final WhisperTranscribeNativeResult result = bindings.transcribe(pcm, lang: lang);
        return _TranscribeResponse(code: result.code, text: result.text);
      });

      if (response.code != 0) {
        throw StateError(
          'Whisper transcription failed (code=${response.code}). Check model file and PCM format (16kHz mono f32).',
        );
      }

      return response.text.trim();
    } catch (error) {
      _lastTranscriptionError = '$error';
      rethrow;
    } finally {
      stopwatch.stop();
      _lastTranscriptionTimeMs = stopwatch.elapsedMilliseconds;
    }
  }

  @override
  Future<void> dispose() async {
    if (!_initialized) {
      return;
    }

    if (_nativeAvailable) {
      await Isolate.run<void>(() {
        final WhisperBindings bindings = WhisperBindings();
        bindings.free();
      });
    }

    _initialized = false;
    _nativeAvailable = true;
    _modelPath = null;
    _logger.info('WhisperCppService disposed.');
  }
}

class _TranscribeResponse {
  const _TranscribeResponse({required this.code, required this.text});

  final int code;
  final String text;
}
