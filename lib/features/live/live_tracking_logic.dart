class LiveTrackingLogic {
  static const double autoAdvanceMinScore = 1.15;
  static const double autoAdvanceAltMinScore = 1.05;
  static const double autoAdvanceAltMargin = 0.25;
  static const double veryStrongScore = 1.35;
  static const int maxSafeForwardJump = 2;
  static const int recoveryEnterTicks = 3;
  static const int lostTrackBannerTicks = 6;

  static bool isConfidentCandidate({required double topScore, double? secondScore}) {
    if (topScore >= autoAdvanceMinScore) {
      return true;
    }

    final double margin = secondScore == null ? topScore : (topScore - secondScore);
    return topScore >= autoAdvanceAltMinScore && margin >= autoAdvanceAltMargin;
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
  }) {
    if (candidateAyahId < currentAyahId) {
      return false;
    }
    if (candidateAyahId == currentAyahId) {
      return false;
    }

    final bool confident = isConfidentCandidate(topScore: topScore, secondScore: secondScore);
    final bool veryStrong = topScore >= veryStrongScore;
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
