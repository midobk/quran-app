import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/arabic/arabic_normalizer.dart';
import '../../core/arabic/surah_transliteration.dart';
import '../../core/di/service_locator.dart';
import '../../core/logging/app_logger.dart';
import '../../core/navigation/app_routes.dart';
import '../../data/quran/ayah_row.dart';
import '../../data/quran/quran_repository.dart';
import '../../services/ads/ads_service.dart';
import '../../services/asr/model_manager.dart';
import '../../services/asr/whisper_cpp_service.dart';
import '../../services/audio/mic_service.dart';
import '../../services/diagnostics/diagnostics_store.dart';
import '../../services/search/quran_search_engine.dart';
import '../../services/settings/app_settings_behavior.dart';
import '../../services/settings/app_settings_service.dart';
import '../../ui/theme/quran_listener_design.dart';
import '../../ui/widgets/ayah_highlight_text.dart';
import 'live_screen_controller.dart';

class LiveScreen extends StatefulWidget {
  const LiveScreen({
    required this.initialLockedAyahId,
    super.key,
    this.controller,
    this.initialSurahNameAr,
    this.initialAyahNo,
    this.settingsService,
  });

  final int initialLockedAyahId;
  final LiveScreenController? controller;
  final String? initialSurahNameAr;
  final int? initialAyahNo;
  final AppSettingsService? settingsService;

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  final ArabicNormalizer _normalizer = const ArabicNormalizer();
  late final AppSettingsService _settingsService;
  late final LiveScreenController _controller;
  bool _showDebug = false;
  int _manualJumpCount = 0;
  int? _lastObservedAyahId;

  @override
  void initState() {
    super.initState();
    _settingsService =
        widget.settingsService ??
        (serviceLocator.isRegistered<AppSettingsService>()
            ? serviceLocator<AppSettingsService>()
            : AppSettingsService());
    final AppSettings settings = _settingsService.settings;
    _showDebug = settings.debugMode;
    _controller =
        widget.controller ??
        LiveScreenController(
          initialPointerAyahId: widget.initialLockedAyahId,
          micService: serviceLocator<MicService>(),
          whisperService: serviceLocator<WhisperCppService>(),
          modelManager: serviceLocator<ModelManager>(),
          searchEngine: serviceLocator<QuranSearchEngine>(),
          repository: serviceLocator<QuranRepository>(),
          logger: serviceLocator<AppLogger>(),
          diagnosticsStore: serviceLocator<DiagnosticsStore>(),
          autoAdvanceEnabled: settings.autoDetectAyah,
          trackingTuning: liveTrackingTuningFromSettings(settings),
        );
    _controller.addListener(_handleControllerUpdated);
    _controller.init();
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerUpdated);
    _controller.dispose();
    super.dispose();
  }

  void _handleControllerUpdated() {
    final int? ayahId = _controller.currentAyah?.id;
    if (ayahId == null) {
      return;
    }
    final int? previousAyahId = _lastObservedAyahId;
    _lastObservedAyahId = ayahId;
    if (previousAyahId == null || previousAyahId == ayahId) {
      return;
    }
    if (!_settingsService.settings.hapticFeedback) {
      return;
    }
    unawaited(_triggerHapticFeedback());
  }

  Future<void> _triggerHapticFeedback() async {
    try {
      await HapticFeedback.selectionClick();
    } on MissingPluginException {
      // Ignore unsupported platforms and widget tests.
    } catch (_) {
      // Keep live mode responsive if haptics are unavailable.
    }
  }

  Future<void> _recalibrate() async {
    await _maybeShowInterstitial('recalibrate');
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushReplacementNamed(AppRoutes.listeningWarmup);
  }

  Future<void> _onManualJump(Future<void> Function() jumpAction) async {
    await jumpAction();
    _manualJumpCount++;
    if (_manualJumpCount >= 4) {
      _manualJumpCount = 0;
      await _maybeShowInterstitial('manual_jump');
    }
  }

  Future<void> _maybeShowInterstitial(String trigger) async {
    if (!serviceLocator.isRegistered<AdsService>()) {
      return;
    }

    try {
      await serviceLocator<AdsService>().maybeShowInterstitial(trigger);
    } on Object {
      // Keep user action responsive even when ad service is unavailable.
    }
  }

  void _handleBack() {
    final NavigatorState navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    navigator.pushNamedAndRemoveUntil(AppRoutes.home, (Route<dynamic> route) => false);
  }

  double _progressForAyah(AyahRow ayah) {
    final List<String> tokens = _normalizer.tokenize(ayah.textNorm);
    if (tokens.isEmpty) {
      return 0;
    }
    if (_controller.matchEndTokenIndex != null && _controller.matchEndTokenIndex! >= 0) {
      final int clampedEnd = _controller.matchEndTokenIndex!.clamp(0, tokens.length - 1);
      return ((clampedEnd + 1) / tokens.length).clamp(0.04, 1.0);
    }
    if (_controller.isSpeechDetected) {
      return 0.24;
    }
    return 0.06;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: QuranListenerBackground(
        patternOpacity: 0.04,
        child: SafeArea(
          bottom: false,
          child: AnimatedBuilder(
            animation: Listenable.merge(<Listenable>[_controller, _settingsService]),
            builder: (BuildContext context, _) {
              final AppSettings settings = _settingsService.settings;
              final QuranListenerPalette colors = context.quranPalette;
              final ThemeData theme = Theme.of(context);
              final double arabicFontSize = settings.arabicFontSize;
              if (_controller.isInitializing) {
                return const Center(child: CircularProgressIndicator());
              }
              if (_controller.errorMessage != null) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text('Live mode error', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text(
                          _controller.errorMessage!,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(onPressed: _recalibrate, child: const Text('Recalibrate')),
                      ],
                    ),
                  ),
                );
              }

              final AyahRow? ayah = _controller.currentAyah;
              if (ayah == null) {
                final String fallbackLabel =
                    widget.initialSurahNameAr != null && widget.initialAyahNo != null
                    ? 'سورة ${widget.initialSurahNameAr} • آية ${widget.initialAyahNo}'
                    : 'Ayah #${widget.initialLockedAyahId}';
                return Center(child: Text('No ayah data found yet for $fallbackLabel'));
              }

              final QuranListenerConfidenceLevel level = confidenceLevelFromScore(
                _controller.lastConfidence,
              );
              final Color levelColor = confidenceColor(level);
              final double progress = _progressForAyah(ayah);

              return Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                    child: Row(
                      children: <Widget>[
                        QuranListenerIconButton(
                          size: 40,
                          icon: const Icon(Icons.arrow_back_rounded),
                          onPressed: _handleBack,
                        ),
                        const Spacer(),
                        QuranListenerIconButton(
                          size: 40,
                          icon: Icon(_showDebug ? Icons.bug_report : Icons.bug_report_outlined),
                          onPressed: () {
                            setState(() {
                              _showDebug = !_showDebug;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  if (_controller.isLostTrack)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: QuranListenerColors.statusLow.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: QuranListenerColors.statusLow.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          'Lost track. Tap Recalibrate.',
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(color: QuranListenerColors.statusLow),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                SurahTransliteration.displayName(
                                  surahNo: ayah.surahNo,
                                  fallback: ayah.surahNameEn,
                                ),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Ayah ${ayah.ayahNo}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: levelColor.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            children: <Widget>[
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: levelColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                confidenceLabel(level),
                                style: Theme.of(
                                  context,
                                ).textTheme.bodySmall?.copyWith(color: levelColor),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        minHeight: 3,
                        value: progress,
                        backgroundColor: colors.strokeDefault,
                        valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                      ),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          AyahHighlightText(
                            uthmaniText: ayah.textUthmani,
                            ayahNormalizedTokens: _normalizer.tokenize(ayah.textNorm),
                            matchStartTokenIndex: _controller.matchStartTokenIndex,
                            matchEndTokenIndex: _controller.matchEndTokenIndex,
                            matchedTokens: _controller.matchedTokens,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: arabicFontSize,
                              height: 1.7,
                            ),
                            highlightStyle: TextStyle(
                              color: theme.colorScheme.primary,
                              fontSize: arabicFontSize,
                              height: 1.7,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            '۝',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: QuranListenerColors.brandAccent,
                              fontSize: 30,
                              fontFamily: 'Amiri',
                              fontFamilyFallback: <String>['Noto Naskh Arabic', 'Noto Sans Arabic'],
                            ),
                          ),
                          if (settings.showTranslation &&
                              ayah.translationEn.trim().isNotEmpty) ...<Widget>[
                            const SizedBox(height: 10),
                            Text(
                              ayah.translationEn,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                          const SizedBox(height: 18),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: colors.bgSurface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: colors.strokeDefault),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                Text(
                                  'Live transcript',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _controller.currentTranscriptSnippet.trim().isEmpty
                                      ? '(listening...)'
                                      : _controller.currentTranscriptSnippet,
                                  textDirection: TextDirection.rtl,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyLarge,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: colors.strokeDefault)),
                    ),
                    child: Column(
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _recalibrate,
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('Recalibrate'),
                              ),
                            ),
                            const SizedBox(width: 14),
                            QuranListenerIconButton(
                              icon: const Icon(Icons.chevron_left_rounded),
                              onPressed: () => _onManualJump(_controller.goToPreviousAyah),
                            ),
                            const SizedBox(width: 8),
                            QuranListenerIconButton(
                              size: 56,
                              backgroundColor: theme.colorScheme.primary,
                              foregroundColor: theme.colorScheme.onPrimary,
                              icon: Icon(
                                _controller.isTrackingPaused
                                    ? Icons.play_arrow_rounded
                                    : Icons.pause_rounded,
                              ),
                              onPressed: _controller.toggleTrackingPaused,
                            ),
                            const SizedBox(width: 8),
                            QuranListenerIconButton(
                              icon: const Icon(Icons.chevron_right_rounded),
                              onPressed: () => _onManualJump(_controller.goToNextAyah),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Speech: ${_controller.isSpeechDetected} • RMS: ${_controller.currentRms.toStringAsFixed(4)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (_showDebug)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'score ${_controller.lastConfidence.toStringAsFixed(2)} • n=${_controller.lastNUsed} '
                              '• win ${_controller.lastWindowBack}/${_controller.lastWindowForward} '
                              '• whisper ${_controller.lastWhisperLatencyMs}ms '
                              '• search ${_controller.lastSearchLatencyMs}ms',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
