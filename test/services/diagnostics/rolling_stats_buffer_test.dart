import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app/services/diagnostics/rolling_stats_buffer.dart';

void main() {
  test('rolling stats buffer keeps only last N values', () {
    final RollingStatsBuffer buffer = RollingStatsBuffer(capacity: 3);

    buffer.add(1);
    buffer.add(2);
    buffer.add(3);
    buffer.add(4);

    expect(buffer.length, 3);
    expect(buffer.values, <double>[2, 3, 4]);
    expect(buffer.average, closeTo(3, 1e-8));
  });
}
