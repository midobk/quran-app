import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app/core/arabic/arabic_normalizer.dart';
import 'package:quran_app/data/quran/quran_repository.dart';
import 'package:quran_app/services/database/database_service.dart';
import 'package:quran_app/services/indexing/quran_index_builder.dart';
import 'package:quran_app/services/search/quran_search_engine.dart';
import 'package:quran_app/services/search/vocab_matcher.dart';
import 'package:quran_app/services/search/vocab_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late _SearchHarness harness;

  setUpAll(() async {
    sqfliteFfiInit();
    harness = await _createHarness();
  });

  tearDownAll(() async {
    await harness.databaseService.dispose();
    if (await harness.tempDir.exists()) {
      await harness.tempDir.delete(recursive: true);
    }
  });

  test('exact contiguous phrase match returns correct ayah with phrase bonus', () async {
    final List<SearchResult> results = await harness.engine.searchGlobal('الله نور السماوات');

    expect(results, isNotEmpty);
    final SearchResult top = results.first;

    expect(top.ayah.id, 3);
    expect(top.nUsed, 3);
    expect(top.matchStartTokenIndex, 0);
    expect(top.matchEndTokenIndex, 2);
    expect(top.matchedTokens, <String>['الله', 'نور', 'السماوات']);
    expect(top.score, closeTo(1.6, 0.0001));
  });

  test('noisy transcript still matches after normalization', () async {
    final List<SearchResult> results = await harness.engine.searchGlobal(
      'إِنَّ ٱللَّهَ غَفُورٌ رَحِيمٌ',
    );

    expect(results, isNotEmpty);
    expect(results.first.ayah.id, 7);
    expect(results.first.nUsed, 4);
    expect(results.first.matchedTokens, <String>['ان', 'الله', 'غفور', 'رحيم']);
  });

  test('common phrase collision ranks the intended ayah first', () async {
    final List<SearchResult> results = await harness.engine.searchGlobal(
      'الله اكبر الله',
      config: const SearchConfig(maxN: 3, topK: 10, autoLockMinScore: 5, autoLockMinMargin: 1),
    );

    expect(results.length, greaterThanOrEqualTo(2));
    expect(results.first.ayah.id, 5);
    expect(results[1].ayah.id, 11);
    expect(results.first.score, greaterThan(results[1].score));
  });

  test('early stop triggers when top score margin is large', () async {
    final List<SearchResult> results = await harness.engine.searchGlobal('الله اكبر الله');

    expect(results.length, greaterThanOrEqualTo(2));
    expect(results.first.ayah.id, 5);
    expect(results[1].ayah.id, 11);
    expect(results.first.nUsed, 3);
    expect(
      results.first.score - results[1].score,
      greaterThanOrEqualTo(const SearchConfig().autoLockMinMargin),
    );
  });

  test('searchNear restricts to local window and blocks far jumps', () async {
    final List<SearchResult> globalResults = await harness.engine.searchGlobal('الله اكبر الله');
    expect(globalResults, isNotEmpty);
    expect(globalResults.first.ayah.id, 5);

    final List<SearchResult> nearResults = await harness.engine.searchNear(
      2,
      'الله اكبر الله',
      radiusBack: 1,
      radiusForward: 1,
    );

    expect(nearResults, isNotEmpty);
    expect(
      nearResults.every((SearchResult result) => result.ayah.id >= 1 && result.ayah.id <= 3),
      isTrue,
    );
    expect(
      nearResults.any((SearchResult result) => result.ayah.id == 5 || result.ayah.id == 11),
      isFalse,
    );
  });

  test('search uses text_plain_norm and matches العالمين despite text_norm mismatch', () async {
    final List<SearchResult> results = await harness.engine.searchGlobal(
      'الحمد لله رب العالمين',
      config: const SearchConfig(maxN: 4, topK: 5, autoLockMinScore: 99, autoLockMinMargin: 99),
    );

    expect(results, isNotEmpty);
    expect(results.first.ayah.id, 2);
  });

  test('filterAndMapTokens never drops connector tokens و and ف', () async {
    final TokenFilterResult filtered = await harness.engine.filterAndMapTokens(<String>[
      'و',
      'ف',
      'الله',
      'نور',
      'السماوات',
    ]);

    expect(filtered.diagnostics.fallbackUsed, isFalse);
    expect(filtered.finalTokens.contains('و'), isTrue);
    expect(filtered.finalTokens.contains('ف'), isTrue);
  });

  test('unknown token maps to closest vocab token within edit threshold', () async {
    final TokenFilterResult filtered = await harness.engine.filterAndMapTokens(<String>[
      'الله',
      'نور',
      'السموات',
    ]);

    expect(filtered.finalTokens, contains('السماوات'));
    expect(
      filtered.diagnostics.mappingPairs.any(
        (TokenMappingPair pair) =>
            pair.original == 'السموات' && pair.mapped == 'السماوات' && pair.distance <= 1,
      ),
      isTrue,
    );
  });

  test('token mapping cache is used on repeated match calls', () async {
    await harness.vocabMatcher.init();

    const String probeToken = 'العقابب';
    final int beforeHits = harness.vocabMatcher.cacheHits;
    await harness.vocabMatcher.match(probeToken);
    final int afterFirst = harness.vocabMatcher.cacheHits;
    await harness.vocabMatcher.match(probeToken);
    final int afterSecond = harness.vocabMatcher.cacheHits;

    expect(afterFirst, beforeHits);
    expect(afterSecond, greaterThan(afterFirst));
  });

  test('fallback triggers when too few usable tokens remain', () async {
    final TokenFilterResult filtered = await harness.engine.filterAndMapTokens(<String>[
      'و',
      'ف',
      'سسسس',
    ]);

    expect(filtered.diagnostics.fallbackUsed, isTrue);
    expect(filtered.finalTokens, <String>['و', 'ف', 'سسسس']);
    expect(filtered.tokenWeights, <double>[1, 1, 1]);
  });

  test('weighted coverage makes rare-token matches outrank common-only matches', () async {
    final List<SearchResult> results = await harness.engine.searchGlobal(
      'الله الله العقاب',
      config: const SearchConfig(maxN: 1, topK: 10, autoLockMinScore: 10, autoLockMinMargin: 10),
    );

    expect(results.length, greaterThanOrEqualTo(2));
    expect(results.first.ayah.id, 9);

    final int ayah5Index = results.indexWhere((SearchResult result) => result.ayah.id == 5);
    expect(ayah5Index, greaterThan(0));
  });


  test('anchorValidate picks A and likelyNextAyahId when transcript spans A to A+1', () async {
    final InitialLockComputation result = await harness.engine.anchorValidate(
      'ثابت بداية الاية المحورية كلمات مشتركة انتقال واضح تمام تكملة الاية التالية نهاية قوية',
    );

    expect(result.lock, isNotNull);
    expect(result.lock!.ayahId, 20);
    expect(result.lock!.likelyNextAyahId, 21);
  });

  test('anchorValidate picks A when transcript starts in A-1 and ends in A', () async {
    final InitialLockComputation result = await harness.engine.anchorValidate(
      'تمهيد سابق ثم دخول الاية المحورية كلمات مشتركة انتقال واضح تمام',
    );

    expect(result.lock, isNotNull);
    expect(result.lock!.ayahId, 20);
  });
}

Future<_SearchHarness> _createHarness() async {
  final Directory tempDir = await Directory.systemTemp.createTemp('quran_search_engine_test_');
  final DatabaseService databaseService = DatabaseService(
    databaseFactoryOverride: databaseFactoryFfi,
    documentsPathProvider: () async => tempDir.path,
    bundledDbLoader: () async => null,
  );
  await databaseService.init();

  await _seedAyahs(databaseService);

  final QuranIndexBuilder indexBuilder = QuranIndexBuilder(
    databaseService: databaseService,
    normalizer: const ArabicNormalizer(),
  );
  await indexBuilder.rebuild(onProgress: (_) {});

  final QuranRepository repository = QuranRepository(databaseService);
  final VocabService vocabService = VocabService(databaseService: databaseService);
  final VocabMatcher vocabMatcher = VocabMatcher(vocabService: vocabService);
  final QuranSearchEngine engine = QuranSearchEngine(
    repository: repository,
    vocabService: vocabService,
    vocabMatcher: vocabMatcher,
    normalizer: const ArabicNormalizer(),
  );

  return _SearchHarness(
    tempDir: tempDir,
    databaseService: databaseService,
    engine: engine,
    vocabMatcher: vocabMatcher,
  );
}

Future<void> _seedAyahs(DatabaseService databaseService) async {
  final List<Map<String, Object?>> rows = <Map<String, Object?>>[
    _ayah(1, 1, 1, 'الفاتحة', 'بسم الله الرحمن الرحيم', 'بسم الله الرحمن الرحيم'),
    _ayah(
      2,
      1,
      2,
      'الفاتحة',
      'الحمد لله رب العالمين',
      'الحمد لله رب العلمين',
      textPlain: 'الحمد لله رب العالمين',
      textPlainNorm: 'الحمد لله رب العالمين',
    ),
    _ayah(3, 24, 35, 'النور', 'الله نور السماوات والارض', 'الله نور السماوات والارض'),
    _ayah(4, 2, 10, 'البقرة', 'في قلوبهم مرض فزادهم الله مرضا', 'في قلوبهم مرض فزادهم الله مرضا'),
    _ayah(5, 87, 1, 'الاعلى', 'الله اكبر الله اكبر', 'الله اكبر الله اكبر'),
    _ayah(
      6,
      57,
      1,
      'الحديد',
      'سبح لله ما في السماوات وما في الارض',
      'سبح لله ما في السماوات وما في الارض',
    ),
    _ayah(7, 2, 173, 'البقرة', 'ان الله غفور رحيم', 'ان الله غفور رحيم'),
    _ayah(8, 23, 80, 'المؤمنون', 'وهو الذي يحيي ويميت', 'وهو الذي يحيي ويميت'),
    _ayah(9, 5, 98, 'المائدة', 'الله شديد العقاب', 'الله شديد العقاب'),
    _ayah(10, 24, 35, 'النور', 'نور على نور', 'نور على نور'),
    _ayah(11, 74, 3, 'المدثر', 'الله اكبر كبيرا', 'الله اكبر كبيرا'),
    _ayah(12, 12, 64, 'يوسف', 'ولا غالب الا الله', 'ولا غالب الا الله'),
    _ayah(20, 50, 1, 'ق', 'الاية المحورية كلمات مشتركة انتقال واضح تمام', 'الاية المحورية كلمات مشتركة انتقال واضح تمام'),
    _ayah(21, 50, 2, 'ق', 'تكملة الاية التالية نهاية قوية', 'تكملة الاية التالية نهاية قوية'),
    _ayah(22, 50, 3, 'ق', 'نص لاحق مختلف تماما', 'نص لاحق مختلف تماما'),
  ];

  final batch = databaseService.db.batch();
  for (final Map<String, Object?> row in rows) {
    batch.insert('ayah', row);
  }
  await batch.commit(noResult: true);
}

Map<String, Object?> _ayah(
  int id,
  int surahNo,
  int ayahNo,
  String surahNameAr,
  String textUthmani,
  String textNorm, {
  String? textPlain,
  String? textPlainNorm,
}) {
  final String resolvedTextPlain = textPlain ?? textNorm;
  final String resolvedTextPlainNorm = textPlainNorm ?? resolvedTextPlain;

  return <String, Object?>{
    'id': id,
    'surah_no': surahNo,
    'ayah_no': ayahNo,
    'surah_name_ar': surahNameAr,
    'text_uthmani': textUthmani,
    'text_norm': textNorm,
    'text_plain': resolvedTextPlain,
    'text_plain_norm': resolvedTextPlainNorm,
  };
}

class _SearchHarness {
  const _SearchHarness({
    required this.tempDir,
    required this.databaseService,
    required this.engine,
    required this.vocabMatcher,
  });

  final Directory tempDir;
  final DatabaseService databaseService;
  final QuranSearchEngine engine;
  final VocabMatcher vocabMatcher;
}
