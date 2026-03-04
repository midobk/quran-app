# Offline QA Checklist

## 1) Airplane Mode End-to-End
1. Enable airplane mode on device (Wi-Fi + cellular off).
2. Launch app and open `Settings -> Diagnostics`.
3. Verify:
   - DB path is populated.
   - `ayah count` is `6236`.
   - `token_index` rows are greater than `0`.
   - Model `exists` is `true`.
4. Start listening flow and confirm results appear without any network requirement.

## 2) First-Run DB Copy Verification
1. Uninstall app (or clear app data).
2. Reinstall and launch once.
3. Open `Settings -> Diagnostics`.
4. Confirm:
   - DB file path points to app local storage.
   - Ayah count is non-zero and expected `6236`.
   - Sample ayah fetch (`id=1`) returns Arabic + English translation.

## 3) Whisper Model Health
1. Open `Settings -> Diagnostics`.
2. Confirm model fields:
   - Bundled asset name is shown.
   - Local model path is shown.
   - `exists = true`.
   - File size is non-zero.
3. In `Settings`, run `Run Whisper Test`.
4. Confirm transcription runs and does not crash on silence/dummy input.

## 4) Mic Permission Denial
1. Revoke microphone permission in OS settings.
2. Attempt `Start Listening` or start mic in `Settings`.
3. Confirm app shows a clear friendly error and does not crash.
4. Grant permission again and verify capture resumes.

## 5) Performance Sanity Thresholds
Target guidance on Samsung-class device:
- Avg whisper latency `< 1500 ms` (Diagnostics live stats).
- Avg search latency `< 100 ms` for near-window search.
- VAD skip rate should be high during silence (expected CPU saving).

If whisper latency is persistently high:
- Guardrail should increase tick interval and reduce chunk length automatically.
- Verify live debug line shows interval/chunk adjustments.

## 6) Lost-Track Recovery Behavior
1. Start Live tracking and recite normally.
2. Introduce noise/silence for multiple ticks.
3. Verify:
   - Recovery window expands (`back=5`, `forward=25`).
   - Lost-track banner appears after sustained recovery.
   - App does not jump wildly backward/forward.
4. Tap `Recalibrate` and confirm return to warmup flow.
