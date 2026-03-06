import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app/services/settings/app_settings_behavior.dart';
import 'package:quran_app/services/settings/app_settings_service.dart';

void main() {
  test('default confidence threshold preserves the existing tuning baseline', () {
    const AppSettings settings = AppSettings(confidenceThreshold: 70);

    final searchConfig = searchConfigFromSettings(settings);
    final liveTuning = liveTrackingTuningFromSettings(settings);

    expect(searchConfig.autoLockMinScore, 1.20);
    expect(searchConfig.autoLockMinMargin, 0.30);
    expect(liveTuning.autoAdvanceMinScore, 1.15);
    expect(liveTuning.autoAdvanceAltMinScore, 1.05);
    expect(liveTuning.autoAdvanceAltMargin, 0.25);
    expect(liveTuning.veryStrongScore, 1.35);
  });

  test('higher confidence threshold tightens search and live tracking', () {
    const AppSettings settings = AppSettings(confidenceThreshold: 100);

    final searchConfig = searchConfigFromSettings(settings);
    final liveTuning = liveTrackingTuningFromSettings(settings);

    expect(searchConfig.autoLockMinScore, greaterThan(1.20));
    expect(searchConfig.autoLockMinMargin, greaterThan(0.30));
    expect(liveTuning.autoAdvanceMinScore, greaterThan(1.15));
    expect(liveTuning.autoAdvanceAltMargin, greaterThan(0.25));
  });
}
