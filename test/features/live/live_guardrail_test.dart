import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app/features/live/live_guardrail.dart';

void main() {
  test('guardrail increases interval and reduces chunk after repeated high latency', () {
    const LiveGuardrailConfig config = LiveGuardrailConfig(
      highLatencyThresholdMs: 1500,
      consecutiveHighLatencyTicks: 3,
      tickIntervalStepMs: 200,
      maxTickIntervalMs: 2200,
      minChunkSeconds: 5,
    );

    LiveGuardrailState state = const LiveGuardrailState(
      tickIntervalMs: 1200,
      chunkSeconds: 7,
      highLatencyStreak: 0,
    );

    LiveGuardrailDecision decision = LiveGuardrailLogic.evaluate(
      state: state,
      config: config,
      lastWhisperLatencyMs: 1600,
    );
    state = LiveGuardrailState(
      tickIntervalMs: decision.tickIntervalMs,
      chunkSeconds: decision.chunkSeconds,
      highLatencyStreak: decision.highLatencyStreak,
    );
    expect(decision.changed, isFalse);

    decision = LiveGuardrailLogic.evaluate(
      state: state,
      config: config,
      lastWhisperLatencyMs: 1700,
    );
    state = LiveGuardrailState(
      tickIntervalMs: decision.tickIntervalMs,
      chunkSeconds: decision.chunkSeconds,
      highLatencyStreak: decision.highLatencyStreak,
    );
    expect(decision.changed, isFalse);

    decision = LiveGuardrailLogic.evaluate(
      state: state,
      config: config,
      lastWhisperLatencyMs: 1800,
    );
    expect(decision.changed, isTrue);
    expect(decision.tickIntervalMs, 1400);
    expect(decision.chunkSeconds, 6);
    expect(decision.highLatencyStreak, 0);
  });
}
