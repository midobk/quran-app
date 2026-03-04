import 'package:flutter/material.dart';

import '../../core/arabic/arabic_normalizer.dart';
import '../../core/di/service_locator.dart';
import '../../data/quran/quran_repository.dart';
import '../../services/search/quran_search_engine.dart';
import '../../ui/widgets/ayah_highlight_text.dart';

class QuranSearchDebugScreen extends StatefulWidget {
  const QuranSearchDebugScreen({super.key});

  @override
  State<QuranSearchDebugScreen> createState() => _QuranSearchDebugScreenState();
}

class _QuranSearchDebugScreenState extends State<QuranSearchDebugScreen> {
  final TextEditingController _queryController = TextEditingController();
  final ArabicNormalizer _normalizer = const ArabicNormalizer();

  late final QuranRepository _repository;
  late final QuranSearchEngine _searchEngine;
  List<SearchResult> _results = <SearchResult>[];
  String _message = 'Initializing local Quran database...';
  bool _isLoading = true;
  bool _isSearching = false;
  int _ayahCount = 0;

  @override
  void initState() {
    super.initState();
    _repository = serviceLocator<QuranRepository>();
    _searchEngine = serviceLocator<QuranSearchEngine>();
    _loadAyahCount();
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _loadAyahCount() async {
    try {
      final int count = await _repository.getAyahCount();
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _ayahCount = count;
        _message = count == 0
            ? 'DB has 0 ayahs — add dataset later.'
            : 'Database ready with $count ayah(s).';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _message = 'Database initialization failed: $error';
      });
    }
  }

  Future<void> _search() async {
    final String query = _queryController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _results = <SearchResult>[];
        _message = _ayahCount == 0
            ? 'DB has 0 ayahs — add dataset later.'
            : 'Enter transcript text and press Search.';
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      final List<SearchResult> matches = await _searchEngine.searchGlobal(query);
      if (!mounted) {
        return;
      }

      setState(() {
        _isSearching = false;
        _results = matches;
        _message = matches.isEmpty
            ? 'No ranked matches found for "$query".'
            : 'Found ${matches.length} ranked result(s).';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isSearching = false;
        _results = <SearchResult>[];
        _message = 'Search failed: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quran Search (Debug)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Ayah count: $_ayahCount'),
            const SizedBox(height: 12),
            TextField(
              controller: _queryController,
              textDirection: TextDirection.rtl,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Search query',
                hintText: 'اكتب نصا تجريبيا للبحث',
              ),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: (_isLoading || _isSearching) ? null : _search,
              child: const Text('Search'),
            ),
            if (_isLoading || _isSearching) ...<Widget>[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 12),
            Text(_message),
            const SizedBox(height: 12),
            Expanded(
              child: _results.isEmpty
                  ? const SizedBox.shrink()
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (BuildContext context, int index) {
                        final SearchResult result = _results[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
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
                                  ayahNormalizedTokens: _normalizer.tokenize(result.ayah.textNorm),
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
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
