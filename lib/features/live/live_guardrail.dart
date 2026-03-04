class LiveGuardrailConfig {
  const LiveGuardrailConfig({
    this.highLatencyThresholdMs = 1500,
    this.consecutiveHighLatencyTicks = 3,
    this.tickIntervalStepMs = 200,
    this.maxTickIntervalMs = 2400,
    this.minChunkSeconds = 5,
  });

  final int highLatencyThresholdMs;
  final int consecutiveHighLatencyTicks;
  final int tickIntervalStepMs;
  final int maxTickIntervalMs;
  final int minChunkSeconds;
}

class LiveGuardrailState {
  const LiveGuardrailState({
    required this.tickIntervalMs,
    required this.chunkSeconds,
    required this.highLatencyStreak,
  });

  final int tickIntervalMs;
  final int chunkSeconds;
  final int highLatencyStreak;
}

class LiveGuardrailDecision {
  const LiveGuardrailDecision({
    required this.tickIntervalMs,
    required this.chunkSeconds,
    required this.highLatencyStreak,
    required this.changed,
  });

  final int tickIntervalMs;
  final int chunkSeconds;
  final int highLatencyStreak;
  final bool changed;
}

class LiveGuardrailLogic {
  static LiveGuardrailDecision evaluate({
    required LiveGuardrailState state,
    required LiveGuardrailConfig config,
    required int? lastWhisperLatencyMs,
  }) {
    int highLatencyStreak = state.highLatencyStreak;
    int tickIntervalMs = state.tickIntervalMs;
    int chunkSeconds = state.chunkSeconds;

    if (lastWhisperLatencyMs == null) {
      highLatencyStreak = 0;
      return LiveGuardrailDecision(
        tickIntervalMs: tickIntervalMs,
        chunkSeconds: chunkSeconds,
        highLatencyStreak: highLatencyStreak,
        changed: false,
      );
    }

    if (lastWhisperLatencyMs >= config.highLatencyThresholdMs) {
      highLatencyStreak++;
    } else {
      highLatencyStreak = 0;
    }

    bool changed = false;
    if (highLatencyStreak >= config.consecutiveHighLatencyTicks) {
      final int stepTarget = tickIntervalMs + config.tickIntervalStepMs;
      final int nextTickInterval = stepTarget > config.maxTickIntervalMs
          ? config.maxTickIntervalMs
          : stepTarget;
      if (nextTickInterval != tickIntervalMs) {
        tickIntervalMs = nextTickInterval;
        changed = true;
      }

      if (chunkSeconds > config.minChunkSeconds) {
        chunkSeconds -= 1;
        changed = true;
      }

      highLatencyStreak = 0;
    }

    return LiveGuardrailDecision(
      tickIntervalMs: tickIntervalMs,
      chunkSeconds: chunkSeconds,
      highLatencyStreak: highLatencyStreak,
      changed: changed,
    );
  }
}
