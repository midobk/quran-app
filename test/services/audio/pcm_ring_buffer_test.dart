import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app/services/audio/pcm_ring_buffer.dart';

void main() {
  test('ring buffer returns newest samples with correct length', () {
    final PcmRingBuffer buffer = PcmRingBuffer(10);

    buffer.append(Float32List.fromList(<double>[0.0, 0.1, 0.2, 0.3, 0.4, 0.5]));
    final Float32List first = buffer.getLastSamples(4);
    expect(first.length, 4);
    expect(first[0], closeTo(0.2, 1e-5));
    expect(first[1], closeTo(0.3, 1e-5));
    expect(first[2], closeTo(0.4, 1e-5));
    expect(first[3], closeTo(0.5, 1e-5));

    buffer.append(Float32List.fromList(<double>[0.6, 0.7, 0.8, 0.9, 1.0, -0.2, -0.3]));

    final Float32List lastTen = buffer.getLastSamples(10);
    expect(lastTen.length, 10);
    expect(lastTen[0], closeTo(0.3, 1e-5));
    expect(lastTen[1], closeTo(0.4, 1e-5));
    expect(lastTen[2], closeTo(0.5, 1e-5));
    expect(lastTen[3], closeTo(0.6, 1e-5));
    expect(lastTen[4], closeTo(0.7, 1e-5));
    expect(lastTen[5], closeTo(0.8, 1e-5));
    expect(lastTen[6], closeTo(0.9, 1e-5));
    expect(lastTen[7], closeTo(1.0, 1e-5));
    expect(lastTen[8], closeTo(-0.2, 1e-5));
    expect(lastTen[9], closeTo(-0.3, 1e-5));

    final Float32List overRequest = buffer.getLastSamples(100);
    expect(overRequest.length, 10);
    expect(overRequest.last, closeTo(-0.3, 1e-5));
  });
}
