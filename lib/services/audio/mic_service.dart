import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import '../../core/logging/app_logger.dart';
import 'energy_vad.dart';
import 'linear_resampler.dart';
import 'pcm_ring_buffer.dart';

class MicService {
  MicService({
    AudioRecorder? recorder,
    AppLogger? logger,
    this.captureSampleRate = 48000,
    this.targetSampleRate = 16000,
    this.ringBufferSeconds = 12,
  }) : _recorder = recorder ?? AudioRecorder(),
       _logger = logger ?? const AppLogger(),
       _ringBuffer = PcmRingBuffer(targetSampleRate * ringBufferSeconds),
       _resampler = LinearResampler(
         inputSampleRate: captureSampleRate.toDouble(),
         outputSampleRate: targetSampleRate.toDouble(),
       ),
       _vad = EnergyVad();

  final AudioRecorder _recorder;
  final AppLogger _logger;

  final int captureSampleRate;
  final int targetSampleRate;
  final int ringBufferSeconds;

  final PcmRingBuffer _ringBuffer;
  final LinearResampler _resampler;
  final EnergyVad _vad;

  final StreamController<MicStats> _statsController = StreamController<MicStats>.broadcast();

  StreamSubscription<Uint8List>? _audioSubscription;

  bool _initialized = false;
  bool _isRunning = false;
  DateTime _lastStatsAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool get isRunning => _isRunning;
  double get currentRms => _vad.currentRms;
  bool get isSpeech => _vad.isSpeech;

  int get inputSampleRate => captureSampleRate;
  double get bufferSeconds => _ringBuffer.length / targetSampleRate;

  Stream<MicStats> get statsStream => _statsController.stream;

  Future<void> init() async {
    if (_initialized) {
      return;
    }

    final bool hasPermission = await _recorder.hasPermission(request: true);
    if (!hasPermission) {
      throw const MicPermissionDeniedException();
    }

    _initialized = true;
    _emitStats(force: true);
  }

  Future<void> start() async {
    if (_isRunning) {
      return;
    }

    await init();

    _resampler.reset();
    _vad.reset();
    _ringBuffer.clear();

    final RecordConfig config = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: captureSampleRate,
      numChannels: 1,
      streamBufferSize: 4096,
    );

    final Stream<Uint8List> stream = await _recorder.startStream(config);
    _audioSubscription = stream.listen(
      _onAudioData,
      onError: (Object error, StackTrace stackTrace) {
        _logger.warning('Mic stream error: $error');
      },
      cancelOnError: false,
    );

    _isRunning = true;
    _emitStats(force: true);
  }

  Future<void> stop() async {
    if (!_isRunning) {
      return;
    }

    await _audioSubscription?.cancel();
    _audioSubscription = null;

    await _recorder.stop();
    _isRunning = false;
    _emitStats(force: true);
  }

  Future<void> dispose() async {
    if (_initialized || _isRunning) {
      await stop();
      await _recorder.dispose();
    }
    await _statsController.close();
  }

  Float32List getLastSecondsPcm16k(double seconds) {
    if (seconds <= 0) {
      return Float32List(0);
    }

    final int sampleCount = (seconds * targetSampleRate).round();
    return _ringBuffer.getLastSamples(sampleCount);
  }

  void _onAudioData(Uint8List bytes) {
    final Float32List capturePcm = _pcm16leToFloat32(bytes);
    if (capturePcm.isEmpty) {
      return;
    }

    final Float32List resampled = _resampler.process(capturePcm);
    if (resampled.isEmpty) {
      return;
    }

    _ringBuffer.append(resampled);
    _vad.process(resampled);

    _emitStats();
  }

  Float32List _pcm16leToFloat32(Uint8List bytes) {
    if (bytes.isEmpty) {
      return Float32List(0);
    }

    final ByteData byteData = ByteData.sublistView(bytes);
    final int sampleCount = bytes.lengthInBytes ~/ 2;
    final Float32List out = Float32List(sampleCount);

    for (int i = 0; i < sampleCount; i++) {
      final int value = byteData.getInt16(i * 2, Endian.little);
      final double scaled = value / 32768.0;
      out[i] = scaled.clamp(-1.0, 1.0).toDouble();
    }

    return out;
  }

  void _emitStats({bool force = false}) {
    if (_statsController.isClosed || !_statsController.hasListener) {
      return;
    }

    final DateTime now = DateTime.now();
    if (!force && now.difference(_lastStatsAt).inMilliseconds < 100) {
      return;
    }
    _lastStatsAt = now;

    _statsController.add(
      MicStats(
        rms: currentRms,
        isSpeech: isSpeech,
        sampleRate: inputSampleRate,
        bufferSeconds: bufferSeconds,
        isRunning: isRunning,
      ),
    );
  }
}

class MicStats {
  const MicStats({
    required this.rms,
    required this.isSpeech,
    required this.sampleRate,
    required this.bufferSeconds,
    required this.isRunning,
  });

  final double rms;
  final bool isSpeech;
  final int sampleRate;
  final double bufferSeconds;
  final bool isRunning;
}

class MicPermissionDeniedException implements Exception {
  const MicPermissionDeniedException();

  @override
  String toString() {
    return 'Microphone permission denied.';
  }
}
