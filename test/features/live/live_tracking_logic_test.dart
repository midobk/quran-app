import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app/features/live/live_tracking_logic.dart';

void main() {
  test('pointer advances for confident forward candidate', () {
    final bool shouldAdvance = LiveTrackingLogic.shouldAdvancePointer(
      currentAyahId: 100,
      candidateAyahId: 101,
      topScore: 1.20,
      secondScore: 0.80,
      isRecoveryMode: false,
      recoveryTicks: 0,
    );

    expect(shouldAdvance, isTrue);
  });

  test('pointer does not move backwards or on weak jump', () {
    final bool backward = LiveTrackingLogic.shouldAdvancePointer(
      currentAyahId: 100,
      candidateAyahId: 99,
      topScore: 1.50,
      secondScore: 0.20,
      isRecoveryMode: false,
      recoveryTicks: 0,
    );
    final bool farWeakJump = LiveTrackingLogic.shouldAdvancePointer(
      currentAyahId: 100,
      candidateAyahId: 104,
      topScore: 1.20,
      secondScore: 0.70,
      isRecoveryMode: false,
      recoveryTicks: 0,
    );

    expect(backward, isFalse);
    expect(farWeakJump, isFalse);
  });

  test('repeated misses trigger recovery mode', () {
    expect(
      LiveTrackingLogic.shouldEnterRecovery(consecutiveLowConfidence: 0, consecutiveNoResults: 2),
      isFalse,
    );
    expect(
      LiveTrackingLogic.shouldEnterRecovery(consecutiveLowConfidence: 0, consecutiveNoResults: 3),
      isTrue,
    );
    expect(
      LiveTrackingLogic.shouldShowLostTrackBanner(isRecoveryMode: true, recoveryTicks: 6),
      isTrue,
    );
  });

  test('persistent recovery requires very strong score to advance', () {
    final bool blocked = LiveTrackingLogic.shouldAdvancePointer(
      currentAyahId: 100,
      candidateAyahId: 101,
      topScore: 1.20,
      secondScore: 0.70,
      isRecoveryMode: true,
      recoveryTicks: 6,
    );
    final bool accepted = LiveTrackingLogic.shouldAdvancePointer(
      currentAyahId: 100,
      candidateAyahId: 101,
      topScore: 1.40,
      secondScore: 0.20,
      isRecoveryMode: true,
      recoveryTicks: 6,
    );

    expect(blocked, isFalse);
    expect(accepted, isTrue);
  });
}
