import 'package:flutter/material.dart';

import '../../core/arabic/arabic_normalizer.dart';
import '../../core/di/service_locator.dart';
import '../../services/ads/ads_service.dart';
import '../../services/search/quran_search_engine.dart';
import '../../ui/widgets/ad_banner_slot.dart';
import '../../ui/widgets/ayah_highlight_text.dart';
import '../live/live_screen.dart';
import 'results_controller.dart';

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({
    required this.transcript,
    required this.results,
    super.key,
    this.autoLockConfig = const SearchConfig(),
    this.liveScreenBuilder,
  });

  final String transcript;
  final List<SearchResult> results;
  final SearchConfig autoLockConfig;
  final Widget Function(SearchResult result)? liveScreenBuilder;

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  final ArabicNormalizer _normalizer = const ArabicNormalizer();
  late final ResultsController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ResultsController(results: widget.results, autoLockConfig: widget.autoLockConfig);

    WidgetsBinding.instance.addPostFrameCallback((_) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Results')),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, _) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'Transcript: ${widget.transcript}',
                  style: Theme.of(context).textTheme.bodySmall,
                  textDirection: TextDirection.rtl,
                ),
                if (_controller.autoLockMessage != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(_controller.autoLockMessage!, style: Theme.of(context).textTheme.bodySmall),
                ],
                const SizedBox(height: 12),
                Expanded(
                  child: widget.results.isEmpty
                      ? const Center(child: Text('No results found. Try listening again.'))
                      : ListView.builder(
                          itemCount: widget.results.length,
                          itemBuilder: (BuildContext context, int index) {
                            final SearchResult result = widget.results[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              child: InkWell(
                                onTap: () => _openLiveScreen(result, triggerAd: true),
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: <Widget>[
                                      Text(
                                        'سورة ${result.ayah.surahNameAr} • آية ${result.ayah.ayahNo}',
                                        textDirection: TextDirection.rtl,
                                        style: Theme.of(context).textTheme.titleSmall,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'score ${result.score.toStringAsFixed(2)} • n=${result.nUsed}',
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                      const SizedBox(height: 10),
                                      AyahHighlightText(
                                        uthmaniText: result.ayah.textUthmani,
                                        ayahNormalizedTokens: _normalizer.tokenize(
                                          result.ayah.textNorm,
                                        ),
                                        matchStartTokenIndex: result.matchStartTokenIndex,
                                        matchEndTokenIndex: result.matchEndTokenIndex,
                                        matchedTokens: result.matchedTokens,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodyLarge?.copyWith(height: 1.9),
                                      ),
                                      if (result.ayah.translationEn.trim().isNotEmpty) ...<Widget>[
                                        const SizedBox(height: 8),
                                        Text(
                                          result.ayah.translationEn,
                                          style: Theme.of(context).textTheme.bodyMedium,
                                          textDirection: TextDirection.ltr,
                                          textAlign: TextAlign.start,
                                        ),
                                      ],
                                      const SizedBox(height: 10),
                                      Align(
                                        alignment: AlignmentDirectional.centerEnd,
                                        child: TextButton(
                                          onPressed: () => _openLiveScreen(result, triggerAd: true),
                                          child: const Text('Lock on this ayah'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 8),
                const AdBannerSlot(),
              ],
            ),
          );
        },
      ),
    );
  }
}
