import 'package:flutter/material.dart';

import '../../core/arabic/arabic_normalizer.dart';
import '../../core/arabic/surah_transliteration.dart';
import '../../core/di/service_locator.dart';
import '../../core/navigation/app_routes.dart';
import '../../services/ads/ads_service.dart';
import '../../services/search/quran_search_engine.dart';
import '../../services/settings/app_settings_behavior.dart';
import '../../services/settings/app_settings_service.dart';
import '../../ui/theme/quran_listener_design.dart';
import '../../ui/widgets/ayah_highlight_text.dart';
import '../live/live_screen.dart';
import 'results_controller.dart';

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({
    required this.transcript,
    required this.results,
    super.key,
    this.autoLockConfig,
    this.liveScreenBuilder,
    this.settingsService,
  });

  final String transcript;
  final List<SearchResult> results;
  final SearchConfig? autoLockConfig;
  final Widget Function(SearchResult result)? liveScreenBuilder;
  final AppSettingsService? settingsService;

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  final ArabicNormalizer _normalizer = const ArabicNormalizer();
  late final AppSettingsService _settingsService;
  late final ResultsController _controller;

  @override
  void initState() {
    super.initState();
    _settingsService =
        widget.settingsService ??
        (serviceLocator.isRegistered<AppSettingsService>()
            ? serviceLocator<AppSettingsService>()
            : AppSettingsService());
    _controller = ResultsController(
      results: widget.results,
      autoLockConfig: widget.autoLockConfig ?? searchConfigFromSettings(_settingsService.settings),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_settingsService.settings.autoDetectAyah) {
        return;
      }
      _controller.triggerAutoLockIfEligible(
        (SearchResult result) => _openLiveScreen(result, triggerAd: false),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openLiveScreen(SearchResult result, {required bool triggerAd}) async {
    if (!mounted) {
      return;
    }

    if (triggerAd) {
      await _maybeShowInterstitial('locked_result');
      if (!mounted) {
        return;
      }
    }

    final Widget destination =
        widget.liveScreenBuilder?.call(result) ??
        LiveScreen(
          initialLockedAyahId: result.ayah.id,
          initialSurahNameAr: result.ayah.surahNameAr,
          initialAyahNo: result.ayah.ayahNo,
          settingsService: _settingsService,
        );

    await Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute<void>(builder: (_) => destination));
  }

  Future<void> _maybeShowInterstitial(String trigger) async {
    if (!serviceLocator.isRegistered<AdsService>()) {
      return;
    }

    try {
      await serviceLocator<AdsService>().maybeShowInterstitial(trigger);
    } on Object {
      // Keep navigation robust even if ad service is unavailable in tests/debug.
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: QuranListenerBackground(
        child: SafeArea(
          bottom: false,
          child: AnimatedBuilder(
            animation: Listenable.merge(<Listenable>[_controller, _settingsService]),
            builder: (BuildContext context, _) {
              final AppSettings settings = _settingsService.settings;
              final QuranListenerPalette colors = context.quranPalette;
              final ThemeData theme = Theme.of(context);
              final double resultArabicFontSize = settings.arabicFontSize.clamp(32, 44).toDouble();
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
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'Possible Ayah Matches',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${widget.results.length} matches found',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  if (widget.transcript.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colors.bgSurface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colors.strokeDefault),
                        ),
                        child: Text(
                          widget.transcript,
                          textDirection: TextDirection.rtl,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(color: colors.textPrimary),
                        ),
                      ),
                    ),
                  if (_controller.autoLockMessage != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          _controller.autoLockMessage!,
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
                        ),
                      ),
                    ),
                  Expanded(
                    child: widget.results.isEmpty
                        ? Center(
                            child: Text(
                              'No results found. Try listening again.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                            itemCount: widget.results.length,
                            separatorBuilder: (BuildContext context, int index) =>
                                const SizedBox(height: 10),
                            itemBuilder: (BuildContext context, int index) {
                              final SearchResult result = widget.results[index];
                              return _ResultCard(
                                normalizer: _normalizer,
                                result: result,
                                onTap: () => _openLiveScreen(result, triggerAd: true),
                                showTranslation: settings.showTranslation,
                                arabicFontSize: resultArabicFontSize,
                              );
                            },
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

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.result,
    required this.onTap,
    required this.normalizer,
    required this.showTranslation,
    required this.arabicFontSize,
  });

  final SearchResult result;
  final VoidCallback onTap;
  final ArabicNormalizer normalizer;
  final bool showTranslation;
  final double arabicFontSize;

  @override
  Widget build(BuildContext context) {
    final QuranListenerConfidenceLevel level = confidenceLevelFromScore(result.score);
    final QuranListenerPalette colors = context.quranPalette;
    final ThemeData theme = Theme.of(context);
    final Color levelColor = confidenceColor(level);

    return Material(
      color: colors.bgSurface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      SurahTransliteration.displayName(
                        surahNo: result.ayah.surahNo,
                        fallback: result.ayah.surahNameEn,
                      ),
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                  Text('Ayah ${result.ayah.ayahNo}', style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(width: 8),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: levelColor, shape: BoxShape.circle),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AyahHighlightText(
                uthmaniText: result.ayah.textUthmani,
                ayahNormalizedTokens: normalizer.tokenize(result.ayah.textNorm),
                matchStartTokenIndex: result.matchStartTokenIndex,
                matchEndTokenIndex: result.matchEndTokenIndex,
                matchedTokens: result.matchedTokens,
                style: TextStyle(color: colors.textPrimary, fontSize: arabicFontSize, height: 1.7),
                highlightStyle: TextStyle(
                  color: theme.colorScheme.primary,
                  fontSize: arabicFontSize,
                  fontWeight: FontWeight.w500,
                  height: 1.7,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '۝',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontSize: 30,
                  fontFamily: 'Amiri',
                  fontFamilyFallback: const <String>['Noto Naskh Arabic', 'Noto Sans Arabic'],
                ),
              ),
              if (showTranslation && result.ayah.translationEn.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(result.ayah.translationEn, style: Theme.of(context).textTheme.bodyMedium),
              ],
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Text(
                  'Tap to lock',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
