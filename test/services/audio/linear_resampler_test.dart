import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app/services/audio/linear_resampler.dart';

void main() {
  test('linear resampler downsamples 48k sine wave to 16k with valid range', () {
    const int inputRate = 48000;
    const int outputRate = 16000;
    const double frequencyHz = 440;
    const int inputLength = inputRate;

    final List<double> source = List<double>.generate(inputLength, (int i) {
      final double t = i / inputRate;
      return math.sin(2 * math.pi * frequencyHz * t) * 0.8;
    });

    final LinearResampler resampler = LinearResampler(
      inputSampleRate: inputRate.toDouble(),
      outputSampleRate: outputRate.toDouble(),
    );

    final Float32List out = resampler.process(Float32List.fromList(source));

    expect(out.length, inInclusiveRange(outputRate - 2, outputRate + 2));

    bool hasNaN = false;
    double peak = 0;
    for (final double sample in out) {
      if (sample.isNaN) {
        hasNaN = true;
      }
      if (sample.abs() > peak) {
        peak = sample.abs();
      }
      expect(sample, inInclusiveRange(-1.0, 1.0));
    }

    expect(hasNaN, isFalse);
    expect(peak, greaterThan(0.5));
  });
}
