import '../../features/live/live_tracking_logic.dart';
import '../search/quran_search_engine.dart';
import 'app_settings_service.dart';

SearchConfig searchConfigFromSettings(AppSettings settings) {
  final double adjustment = _confidenceAdjustment(settings.confidenceThreshold);
  return SearchConfig(
    autoLockMinScore: _clampDouble(1.20 + adjustment, min: 0.95, max: 1.45),
    autoLockMinMargin: _clampDouble(0.30 + (adjustment * 0.5), min: 0.18, max: 0.45),
  );
}

LiveTrackingTuning liveTrackingTuningFromSettings(AppSettings settings) {
  final double adjustment = _confidenceAdjustment(settings.confidenceThreshold);
  return LiveTrackingTuning(
    autoAdvanceMinScore: _clampDouble(1.15 + adjustment, min: 0.90, max: 1.40),
    autoAdvanceAltMinScore: _clampDouble(1.05 + adjustment, min: 0.80, max: 1.30),
    autoAdvanceAltMargin: _clampDouble(0.25 + (adjustment * 0.5), min: 0.15, max: 0.40),
    veryStrongScore: _clampDouble(1.35 + (adjustment * 0.4), min: 1.10, max: 1.55),
  );
}

double _confidenceAdjustment(double threshold) {
  final double safeThreshold = _clampDouble(threshold, min: 30, max: 100);
  return (safeThreshold - 70) * 0.006;
}

double _clampDouble(double value, {required double min, required double max}) {
  if (value < min) {
    return min;
  }
  if (value > max) {
    return max;
  }
  return value;
}
