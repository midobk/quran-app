class LiveTrackingTuning {
  const LiveTrackingTuning({
    this.autoAdvanceMinScore = 1.15,
    this.autoAdvanceAltMinScore = 1.05,
    this.autoAdvanceAltMargin = 0.25,
    this.veryStrongScore = 1.35,
  });

  final double autoAdvanceMinScore;
  final double autoAdvanceAltMinScore;
  final double autoAdvanceAltMargin;
  final double veryStrongScore;
}

class LiveTrackingLogic {
  static const int maxSafeForwardJump = 2;
  static const int recoveryEnterTicks = 3;
  static const int lostTrackBannerTicks = 6;

  static bool isConfidentCandidate({
    required double topScore,
    double? secondScore,
    LiveTrackingTuning tuning = const LiveTrackingTuning(),
  }) {
    if (topScore >= tuning.autoAdvanceMinScore) {
      return true;
    }

    final double margin = secondScore == null ? topScore : (topScore - secondScore);
    return topScore >= tuning.autoAdvanceAltMinScore && margin >= tuning.autoAdvanceAltMargin;
  }

  static bool shouldEnterRecovery({
    required int consecutiveLowConfidence,
    required int consecutiveNoResults,
  }) {
    return consecutiveLowConfidence >= recoveryEnterTicks ||
        consecutiveNoResults >= recoveryEnterTicks;
  }

  static bool shouldShowLostTrackBanner({
    required bool isRecoveryMode,
    required int recoveryTicks,
  }) {
    return isRecoveryMode && recoveryTicks >= lostTrackBannerTicks;
  }

  static bool shouldAdvancePointer({
    required int currentAyahId,
    required int candidateAyahId,
    required double topScore,
    double? secondScore,
    required bool isRecoveryMode,
    required int recoveryTicks,
    LiveTrackingTuning tuning = const LiveTrackingTuning(),
  }) {
    if (candidateAyahId < currentAyahId) {
      return false;
    }
    if (candidateAyahId == currentAyahId) {
      return false;
    }

    final bool confident = isConfidentCandidate(
      topScore: topScore,
      secondScore: secondScore,
      tuning: tuning,
    );
    final bool veryStrong = topScore >= tuning.veryStrongScore;
    if (!confident && !veryStrong) {
      return false;
    }

    final int jump = candidateAyahId - currentAyahId;
    if (jump > maxSafeForwardJump && !veryStrong) {
      return false;
    }

    if (isRecoveryMode && recoveryTicks >= lostTrackBannerTicks && !veryStrong) {
      return false;
    }

    return true;
  }
}
