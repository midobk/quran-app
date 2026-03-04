import 'dart:math' as math;
import 'dart:typed_data';

class EnergyVad {
  EnergyVad({
    this.frameSize = 320,
    this.thresholdFactor = 2.2,
    this.minRmsThreshold = 0.01,
    this.hangoverFrames = 10,
  }) : assert(frameSize > 0),
       assert(thresholdFactor > 0),
       assert(minRmsThreshold >= 0),
       assert(hangoverFrames >= 0);

  final int frameSize;
  final double thresholdFactor;
  final double minRmsThreshold;
  final int hangoverFrames;

  final List<double> _frameBuffer = <double>[];

  double _noiseFloor = 0.005;
  double _currentRms = 0;
  bool _isSpeech = false;
  int _hangoverLeft = 0;

  double get currentRms => _currentRms;
  bool get isSpeech => _isSpeech;

  void reset() {
    _frameBuffer.clear();
    _noiseFloor = 0.005;
    _currentRms = 0;
    _isSpeech = false;
    _hangoverLeft = 0;
  }

  void process(Float32List pcm16k) {
    if (pcm16k.isEmpty) {
      return;
    }

    _frameBuffer.addAll(pcm16k);

    while (_frameBuffer.length >= frameSize) {
      final List<double> frame = _frameBuffer.sublist(0, frameSize);
      _frameBuffer.removeRange(0, frameSize);

      final double rms = _computeRms(frame);
      _currentRms = rms;

      final double dynamicThreshold = math.max(minRmsThreshold, _noiseFloor * thresholdFactor);
      final bool speechCandidate = rms >= dynamicThreshold;

      if (speechCandidate) {
        _isSpeech = true;
        _hangoverLeft = hangoverFrames;

        // Keep floor stable during speech to avoid drifting too high.
        _noiseFloor = _noiseFloor * 0.995 + rms * 0.005;
      } else {
        _noiseFloor = _noiseFloor * 0.95 + rms * 0.05;

        if (_hangoverLeft > 0) {
          _hangoverLeft--;
          _isSpeech = true;
        } else {
          _isSpeech = false;
        }
      }
    }
  }

  double _computeRms(List<double> frame) {
    double sumSquares = 0;
    for (final double sample in frame) {
      if (sample.isNaN) {
        continue;
      }
      sumSquares += sample * sample;
    }

    if (frame.isEmpty) {
      return 0;
    }

    return math.sqrt(sumSquares / frame.length);
  }
}
