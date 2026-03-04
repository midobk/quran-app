import 'dart:math' as math;
import 'dart:typed_data';

/// Streaming linear interpolation resampler for mono float PCM.
class LinearResampler {
  LinearResampler({required this.inputSampleRate, this.outputSampleRate = 16000})
    : assert(inputSampleRate > 0),
      assert(outputSampleRate > 0),
      _step = inputSampleRate / outputSampleRate;

  final double inputSampleRate;
  final double outputSampleRate;

  final List<double> _pending = <double>[];
  final double _step;
  double _readPosition = 0;

  Float32List process(Float32List input) {
    if (input.isEmpty) {
      return Float32List(0);
    }

    for (final double sample in input) {
      if (!sample.isNaN) {
        _pending.add(sample);
      }
    }

    if (_pending.length < 2) {
      return Float32List(0);
    }

    final List<double> out = <double>[];

    while (_readPosition + 1 < _pending.length) {
      final int leftIndex = _readPosition.floor();
      final int rightIndex = leftIndex + 1;
      final double frac = _readPosition - leftIndex;

      final double left = _pending[leftIndex];
      final double right = _pending[rightIndex];
      final double sample = left + (right - left) * frac;

      if (sample.isNaN) {
        out.add(0);
      } else {
        out.add(sample.clamp(-1.0, 1.0));
      }

      _readPosition += _step;
    }

    final int dropCount = math.max(0, _readPosition.floor() - 1);
    if (dropCount > 0) {
      _pending.removeRange(0, dropCount);
      _readPosition -= dropCount;
    }

    return Float32List.fromList(out);
  }

  void reset() {
    _pending.clear();
    _readPosition = 0;
  }
}
