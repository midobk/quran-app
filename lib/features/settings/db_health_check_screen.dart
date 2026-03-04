import 'package:flutter/material.dart';

import '../../core/arabic/arabic_normalizer.dart';
import '../../core/di/service_locator.dart';
import '../../data/quran/ayah_row.dart';
import '../../data/quran/quran_repository.dart';
import '../../services/database/database_service.dart';
import '../../services/search/quran_search_engine.dart';

class DBHealthCheckScreen extends StatefulWidget {
  const DBHealthCheckScreen({super.key});

  @override
  State<DBHealthCheckScreen> createState() => _DBHealthCheckScreenState();
}

class _DBHealthCheckScreenState extends State<DBHealthCheckScreen> {
  static const String _sampleTranscript = 'ٱللَّهُ';
  static const int _expectedAyahCount = 6236;

  final ArabicNormalizer _normalizer = const ArabicNormalizer();
  late final DatabaseService _databaseService;
  late final QuranRepository _repository;
  late final QuranSearchEngine _searchEngine;

  bool _isLoading = true;
  String? _errorMessage;
  String _dbPath = '-';
  int _ayahCount = 0;
  int _tokenIndexCount = 0;
  String _normalizedSampleQuery = '';
  AyahRow? _sampleAyah;
  List<SearchResult> _sampleResults = const <SearchResult>[];

  @override
  void initState() {
    super.initState();
    _databaseService = serviceLocator<DatabaseService>();
    _repository = serviceLocator<QuranRepository>();
    _searchEngine = serviceLocator<QuranSearchEngine>();
    _runHealthCheck();
  }

  Future<void> _runHealthCheck() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _databaseService.init();
      final List<Map<String, Object?>> tokenCountRows = await _databaseService.db.rawQuery(
        'SELECT COUNT(*) AS count FROM token_index',
      );

      final int tokenCount = (tokenCountRows.first['count'] as int?) ?? 0;
      final int ayahCount = await _repository.getAyahCount();
      final AyahRow? ayahOne = await _repository.getAyahById(1);
      final String normalizedSample = _normalizer.normalize(_sampleTranscript);
      final List<SearchResult> sampleResults = await _searchEngine.searchGlobal(
        _sampleTranscript,
        config: const SearchConfig(maxN: 3, topK: 3),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _dbPath = _databaseService.dbPath ?? '(unknown)';
        _tokenIndexCount = tokenCount;
        _ayahCount = ayahCount;
        _sampleAyah = ayahOne;
        _normalizedSampleQuery = normalizedSample;
        _sampleResults = sampleResults.take(3).toList(growable: false);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _errorMessage = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DB Health Check'),
        actions: <Widget>[IconButton(onPressed: _runHealthCheck, icon: const Icon(Icons.refresh))],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(child: Text('DB health check failed: $_errorMessage'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                Text('DB path in use', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                SelectableText(_dbPath),
                const SizedBox(height: 16),
                Text(
                  'Total ayah count: $_ayahCount (expected $_expectedAyahCount)',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                Text('token_index rows: $_tokenIndexCount'),
                const Divider(height: 28),
                Text('Sample fetch (ayah id 1)', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                if (_sampleAyah == null)
                  const Text('No ayah found for id 1.')
                else ...<Widget>[
                  Text(
                    'سورة ${_sampleAyah!.surahNameAr} • آية ${_sampleAyah!.ayahNo}',
                    textDirection: TextDirection.rtl,
                  ),
                  const SizedBox(height: 4),
                  Text(_sampleAyah!.textUthmani, textDirection: TextDirection.rtl),
                  const SizedBox(height: 6),
                  Text(
                    _sampleAyah!.translationEn.isEmpty
                        ? '(translation_en is empty)'
                        : _sampleAyah!.translationEn,
                    style: Theme.of(context).textTheme.bodySmall,
                    textDirection: TextDirection.ltr,
                  ),
                ],
                const Divider(height: 28),
                Text('Sample normalized search', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text('Input: $_sampleTranscript'),
                Text('Normalized: $_normalizedSampleQuery'),
                const SizedBox(height: 8),
                if (_sampleResults.isEmpty)
                  const Text('No search results found.')
                else
                  ..._sampleResults.map((SearchResult result) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '${result.ayah.id}. سورة ${result.ayah.surahNameAr} • آية ${result.ayah.ayahNo} • score ${result.score.toStringAsFixed(2)}',
                        textDirection: TextDirection.rtl,
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}
