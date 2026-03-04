import 'dart:math' as math;
import 'dart:typed_data';

class PcmRingBuffer {
  PcmRingBuffer(int capacitySamples)
    : assert(capacitySamples > 0),
      _buffer = Float32List(capacitySamples);

  final Float32List _buffer;
  int _writeIndex = 0;
  int _length = 0;

  int get capacity => _buffer.length;
  int get length => _length;

  void clear() {
    _writeIndex = 0;
    _length = 0;
  }

  void append(Float32List samples) {
    if (samples.isEmpty) {
      return;
    }

    for (final double sample in samples) {
      final double clamped = sample.isNaN ? 0 : sample.clamp(-1.0, 1.0);
      _buffer[_writeIndex] = clamped;
      _writeIndex = (_writeIndex + 1) % _buffer.length;
      if (_length < _buffer.length) {
        _length++;
      }
    }
  }

  Float32List getLastSamples(int sampleCount) {
    if (sampleCount <= 0 || _length == 0) {
      return Float32List(0);
    }

    final int count = math.min(sampleCount, _length);
    final Float32List out = Float32List(count);

    int start = (_writeIndex - count) % _buffer.length;
    if (start < 0) {
      start += _buffer.length;
    }

    final int firstPartLen = math.min(count, _buffer.length - start);
    out.setAll(0, _buffer.sublist(start, start + firstPartLen));

    final int secondPartLen = count - firstPartLen;
    if (secondPartLen > 0) {
      out.setAll(firstPartLen, _buffer.sublist(0, secondPartLen));
    }

    return out;
  }
}
