import 'dart:math' as math;

import '../../core/arabic/arabic_normalizer.dart';
import '../../core/logging/app_logger.dart';
import '../../data/quran/ayah_row.dart';
import '../../data/quran/quran_repository.dart';
import 'vocab_matcher.dart';
import 'vocab_service.dart';

class SearchResult {
  const SearchResult({
    required this.ayah,
    required this.score,
    required this.nUsed,
    required this.matchStartTokenIndex,
    required this.matchEndTokenIndex,
    required this.matchedTokens,
  });

  final AyahRow ayah;
  final double score;
  final int nUsed;
  final int? matchStartTokenIndex;
  final int? matchEndTokenIndex;
  final List<String> matchedTokens;
}

class SearchConfig {
  const SearchConfig({
    this.maxN = 5,
    this.topK = 20,
    this.autoLockMinScore = 1.2,
    this.autoLockMinMargin = 0.3,
  });

  final int maxN;
  final int topK;
  final double autoLockMinScore;
  final double autoLockMinMargin;
}

class TokenMappingPair {
  const TokenMappingPair({
    required this.original,
    required this.mapped,
    required this.distance,
    required this.confidence,
  });

  final String original;
  final String mapped;
  final int distance;
  final double confidence;
}

class TokenFilterDiagnostics {
  const TokenFilterDiagnostics({
    required this.originalTokens,
    required this.filteredTokens,
    required this.mappingPairs,
    required this.beforeCount,
    required this.afterCount,
    required this.mappedCount,
    required this.droppedCount,
    required this.fallbackUsed,
    required this.elapsedMs,
  });

  final List<String> originalTokens;
  final List<String> filteredTokens;
  final List<TokenMappingPair> mappingPairs;
  final int beforeCount;
  final int afterCount;
  final int mappedCount;
  final int droppedCount;
  final bool fallbackUsed;
  final int elapsedMs;
}

class TokenFilterResult {
  const TokenFilterResult({
    required this.finalTokens,
    required this.tokenWeights,
    required this.diagnostics,
  });

  final List<String> finalTokens;
  final List<double> tokenWeights;
  final TokenFilterDiagnostics diagnostics;
}

class SearchDiagnostics {
  const SearchDiagnostics({required this.normalizedTranscript, required this.tokenFilter});

  final String normalizedTranscript;
  final TokenFilterDiagnostics tokenFilter;
}

class InitialLockResult {
  const InitialLockResult({
    required this.ayahId,
    required this.likelyNextAyahId,
    required this.score,
    required this.debugScores,
    required this.selectedPath,
  });

  final int ayahId;
  final int? likelyNextAyahId;
  final double score;
  final Map<String, double> debugScores;
  final String selectedPath;
}

class InitialLockComputation {
  const InitialLockComputation({required this.anchorCandidates, required this.lock});

  final List<SearchResult> anchorCandidates;
  final InitialLockResult? lock;
}

class QuranSearchEngine {
  QuranSearchEngine({
    required QuranRepository repository,
    required VocabService vocabService,
    VocabMatcher? vocabMatcher,
    ArabicNormalizer normalizer = const ArabicNormalizer(),
    AppLogger logger = const AppLogger(),
  }) : _repository = repository,
       _vocabService = vocabService,
       _vocabMatcher = vocabMatcher ?? VocabMatcher(vocabService: vocabService),
       _normalizer = normalizer,
       _logger = logger;

  final QuranRepository _repository;
  final VocabService _vocabService;
  final VocabMatcher _vocabMatcher;
  final ArabicNormalizer _normalizer;
  final AppLogger _logger;

  SearchDiagnostics? _lastDiagnostics;

  SearchDiagnostics? get lastDiagnostics => _lastDiagnostics;

  Future<List<SearchResult>> searchGlobal(String transcript, {SearchConfig? config}) {
    return _searchInternal(transcript, config: config ?? const SearchConfig());
  }

  Future<InitialLockComputation> anchorValidate(
    String transcript, {
    SearchConfig? config,
    int anchorTopN = 8,
  }) async {
    final SearchConfig effectiveConfig = config ?? const SearchConfig();
    final String normalizedTranscript = _normalizer.normalize(transcript);
    final List<String> transcriptTokens = _normalizer.tokenize(normalizedTranscript);
    if (transcriptTokens.isEmpty) {
      return const InitialLockComputation(anchorCandidates: <SearchResult>[], lock: null);
    }

    await _vocabService.init();
    await _vocabService.refreshIfStale();
    await _vocabMatcher.init();

    final TokenFilterResult filterResult = await filterAndMapTokens(transcriptTokens);
    final List<String> effectiveTokens = filterResult.finalTokens;
    if (effectiveTokens.isEmpty) {
      return const InitialLockComputation(anchorCandidates: <SearchResult>[], lock: null);
    }

    final _WindowSlices windows = _buildWindows(effectiveTokens);
    _logger.info(
      'Anchor+Validate token windows: total=${effectiveTokens.length}, '
      'start=${windows.start.length}, mid=${windows.mid.length}, end=${windows.end.length}',
    );

    final String midQuery = windows.mid.join(' ');
    final List<SearchResult> anchorCandidates = await searchGlobal(
      midQuery,
      config: effectiveConfig,
    );
    final List<SearchResult> topAnchors = anchorCandidates.take(math.max(1, anchorTopN)).toList();
    if (topAnchors.isEmpty) {
      return const InitialLockComputation(anchorCandidates: <SearchResult>[], lock: null);
    }

    final Map<int, AyahRow> ayahCache = <int, AyahRow>{};
    final Set<int> missingAyahIds = <int>{};
    _PathEvaluation? bestEvaluation;
    final Map<int, double> bestEndWithoutNextByAnchor = <int, double>{};

    for (final SearchResult anchor in topAnchors) {
      final int anchorId = anchor.ayah.id;
      ayahCache[anchorId] = anchor.ayah;
      final bool hasPrevious = anchorId > 1
          ? await _cacheAyahIfPresent(anchorId - 1, ayahCache, missingAyahIds)
          : false;
      final bool hasNext = await _cacheAyahIfPresent(anchorId + 1, ayahCache, missingAyahIds);
      final List<List<int>> paths = <List<int>>[
        <int>[anchorId],
        if (hasNext) <int>[anchorId, anchorId + 1],
        if (hasPrevious) <int>[anchorId - 1, anchorId],
        if (hasPrevious && hasNext) <int>[anchorId - 1, anchorId, anchorId + 1],
      ];

      for (final List<int> path in paths) {
        final List<String> virtualTokens = await _buildVirtualTokens(path, ayahCache);
        if (virtualTokens.isEmpty) {
          continue;
        }

        final double startScore = _scoreWindow(windows.start, virtualTokens);
        final double midScore = _scoreWindow(windows.mid, virtualTokens);
        final double endScore = _scoreWindow(windows.end, virtualTokens);
        final double finalScore = (0.50 * midScore) + (0.25 * startScore) + (0.25 * endScore);

        if (!path.contains(anchorId + 1)) {
          final double existing = bestEndWithoutNextByAnchor[anchorId] ?? -1;
          if (endScore > existing) {
            bestEndWithoutNextByAnchor[anchorId] = endScore;
          }
        }

        final _PathEvaluation current = _PathEvaluation(
          anchorId: anchorId,
          path: path,
          startScore: startScore,
          midScore: midScore,
          endScore: endScore,
          finalScore: finalScore,
        );
        if (bestEvaluation == null || current.finalScore > bestEvaluation.finalScore) {
          bestEvaluation = current;
        }
      }
    }

    if (bestEvaluation == null) {
      return InitialLockComputation(anchorCandidates: topAnchors, lock: null);
    }

    final bool includesNext = bestEvaluation.path.contains(bestEvaluation.anchorId + 1);
    final double bestEndWithoutNext = bestEndWithoutNextByAnchor[bestEvaluation.anchorId] ?? 0;
    final bool strongEndSupport = bestEvaluation.endScore >= bestEndWithoutNext + 0.15;
    final int? likelyNextAyahId = includesNext && strongEndSupport
        ? bestEvaluation.anchorId + 1
        : null;

    _logger.info(
      'Anchor+Validate selected path=${bestEvaluation.path.join("->")} '
      'scores(start=${bestEvaluation.startScore.toStringAsFixed(3)}, '
      'mid=${bestEvaluation.midScore.toStringAsFixed(3)}, '
      'end=${bestEvaluation.endScore.toStringAsFixed(3)}, '
      'final=${bestEvaluation.finalScore.toStringAsFixed(3)})',
    );

    return InitialLockComputation(
      anchorCandidates: topAnchors,
      lock: InitialLockResult(
        ayahId: bestEvaluation.anchorId,
        likelyNextAyahId: likelyNextAyahId,
        score: bestEvaluation.finalScore,
        selectedPath: bestEvaluation.path.join('->'),
        debugScores: <String, double>{
          'start': bestEvaluation.startScore,
          'mid': bestEvaluation.midScore,
          'end': bestEvaluation.endScore,
        },
      ),
    );
  }

  Future<List<SearchResult>> searchNear(
    int pointerAyahId,
    String transcript, {
    int radiusBack = 2,
    int radiusForward = 10,
    SearchConfig? config,
  }) {
    final int safeRadiusBack = math.max(0, radiusBack);
    final int safeRadiusForward = math.max(0, radiusForward);

    final int minAyahId = math.max(1, pointerAyahId - safeRadiusBack);
    final int maxAyahId = math.max(minAyahId, pointerAyahId + safeRadiusForward);

    return _searchInternal(
      transcript,
      config: config ?? const SearchConfig(),
      minAyahId: minAyahId,
      maxAyahId: maxAyahId,
    );
  }

  Future<List<SearchResult>> _searchInternal(
    String transcript, {
    required SearchConfig config,
    int? minAyahId,
    int? maxAyahId,
  }) async {
    if (config.maxN <= 0 || config.topK <= 0) {
      return <SearchResult>[];
    }

    final String normalizedTranscript = _normalizer.normalize(transcript);
    final List<String> transcriptTokens = _normalizer.tokenize(normalizedTranscript);
    if (transcriptTokens.isEmpty) {
      _lastDiagnostics = SearchDiagnostics(
        normalizedTranscript: normalizedTranscript,
        tokenFilter: const TokenFilterDiagnostics(
          originalTokens: <String>[],
          filteredTokens: <String>[],
          mappingPairs: <TokenMappingPair>[],
          beforeCount: 0,
          afterCount: 0,
          mappedCount: 0,
          droppedCount: 0,
          fallbackUsed: false,
          elapsedMs: 0,
        ),
      );
      return <SearchResult>[];
    }

    await _vocabService.init();
    await _vocabService.refreshIfStale();
    await _vocabMatcher.init();

    final TokenFilterResult filterResult = await filterAndMapTokens(transcriptTokens);
    _lastDiagnostics = SearchDiagnostics(
      normalizedTranscript: normalizedTranscript,
      tokenFilter: filterResult.diagnostics,
    );

    _logger.debug(
      'Token filter+map ${filterResult.diagnostics.beforeCount}->${filterResult.diagnostics.afterCount} '
      '(mapped=${filterResult.diagnostics.mappedCount}, dropped=${filterResult.diagnostics.droppedCount}, '
      'fallback=${filterResult.diagnostics.fallbackUsed}) in ${filterResult.diagnostics.elapsedMs} ms',
    );

    final List<String> effectiveTokens = filterResult.finalTokens;
    final List<double> effectiveWeights = filterResult.tokenWeights;
    if (effectiveTokens.isEmpty) {
      return <SearchResult>[];
    }

    final int startN = math.min(config.maxN, effectiveTokens.length);
    final Map<String, Set<int>> postingCache = <String, Set<int>>{};
    final Map<int, AyahRow> ayahCache = <int, AyahRow>{};
    final Map<int, List<String>> ayahTokenCache = <int, List<String>>{};

    List<SearchResult> bestOverall = <SearchResult>[];

    for (int n = startN; n >= 1; n--) {
      final List<_WeightedNgram> ngrams = _buildContiguousNgrams(
        tokens: effectiveTokens,
        tokenWeights: effectiveWeights,
        n: n,
      );
      if (ngrams.isEmpty) {
        continue;
      }

      final List<_NgramCandidateSet> candidateSets = <_NgramCandidateSet>[];
      final Set<int> allCandidateIds = <int>{};

      for (final _WeightedNgram ngram in ngrams) {
        final Set<int> candidateAyahIds = await _getCandidateAyahIdsForNgram(
          ngramTokens: ngram.tokens,
          minAyahId: minAyahId,
          maxAyahId: maxAyahId,
          postingCache: postingCache,
        );
        if (candidateAyahIds.isEmpty) {
          continue;
        }

        allCandidateIds.addAll(candidateAyahIds);
        candidateSets.add(_NgramCandidateSet(ngram: ngram, candidateAyahIds: candidateAyahIds));
      }

      if (allCandidateIds.isEmpty) {
        continue;
      }

      final List<int> missingAyahIds = allCandidateIds
          .where((int ayahId) => !ayahCache.containsKey(ayahId))
          .toList(growable: false);
      if (missingAyahIds.isNotEmpty) {
        final List<AyahRow> missingAyahs = await _repository.getAyahsByIds(missingAyahIds);
        for (final AyahRow ayah in missingAyahs) {
          ayahCache[ayah.id] = ayah;
          ayahTokenCache[ayah.id] = _normalizer.tokenize(ayah.searchTextNorm);
        }
      }

      final Map<int, SearchResult> bestResultPerAyah = <int, SearchResult>{};

      for (final _NgramCandidateSet candidateSet in candidateSets) {
        for (final int ayahId in candidateSet.candidateAyahIds) {
          final AyahRow? ayah = ayahCache[ayahId];
          final List<String>? ayahTokens = ayahTokenCache[ayahId];
          if (ayah == null || ayahTokens == null || ayahTokens.isEmpty) {
            continue;
          }

          final _MatchScore match = _scoreMatch(
            ayahTokens: ayahTokens,
            queryTokens: effectiveTokens,
            queryWeights: effectiveWeights,
            ngramTokens: candidateSet.ngram.tokens,
            n: n,
          );
          if (match.matchedTokens.isEmpty) {
            continue;
          }

          final SearchResult result = SearchResult(
            ayah: ayah,
            score: match.score,
            nUsed: n,
            matchStartTokenIndex: match.startIndex,
            matchEndTokenIndex: match.endIndex,
            matchedTokens: match.matchedTokens,
          );

          final SearchResult? existing = bestResultPerAyah[ayahId];
          if (existing == null || result.score > existing.score) {
            bestResultPerAyah[ayahId] = result;
          }
        }
      }

      if (bestResultPerAyah.isEmpty) {
        continue;
      }

      final List<SearchResult> resultsForN = bestResultPerAyah.values.toList(growable: false)
        ..sort((SearchResult a, SearchResult b) {
          final int scoreCmp = b.score.compareTo(a.score);
          if (scoreCmp != 0) {
            return scoreCmp;
          }
          return a.ayah.id.compareTo(b.ayah.id);
        });

      final List<SearchResult> topResults = resultsForN.take(config.topK).toList(growable: false);

      if (_isBetterResultSet(topResults, bestOverall)) {
        bestOverall = topResults;
      }

      if (_shouldEarlyStop(topResults, config)) {
        return topResults;
      }
    }

    return bestOverall;
  }

  Future<TokenFilterResult> filterAndMapTokens(List<String> transcriptTokens) async {
    final Stopwatch stopwatch = Stopwatch()..start();

    final List<String> originalTokens = List<String>.from(transcriptTokens);
    final List<String> filteredTokens = <String>[];
    final List<double> filteredWeights = <double>[];
    final List<TokenMappingPair> mappings = <TokenMappingPair>[];
    int mappedCount = 0;
    int droppedCount = 0;

    for (final String token in transcriptTokens) {
      if (token.isEmpty) {
        continue;
      }

      if (_isConnectorToken(token)) {
        filteredTokens.add(token);
        filteredWeights.add(0.2);
        continue;
      }

      final int? knownFreq = _vocabService.freq(token);
      if (knownFreq != null) {
        filteredTokens.add(token);
        filteredWeights.add(_rarityWeight(token: token, freq: knownFreq));
        continue;
      }

      final MatchResult? match = await _vocabMatcher.match(token);
      if (match == null) {
        droppedCount++;
        continue;
      }

      final int mappedFreq = _vocabService.freq(match.token) ?? 1;
      filteredTokens.add(match.token);
      filteredWeights.add(match.confidence * _rarityWeight(token: match.token, freq: mappedFreq));
      mappings.add(
        TokenMappingPair(
          original: token,
          mapped: match.token,
          distance: match.distance,
          confidence: match.confidence,
        ),
      );
      mappedCount++;
    }

    bool fallbackUsed = false;
    List<String> finalTokens = filteredTokens;
    List<double> finalWeights = filteredWeights;

    final int informativeTokenCount = filteredTokens
        .where((String token) => !_isConnectorToken(token))
        .length;
    if (informativeTokenCount < 3 && originalTokens.isNotEmpty) {
      fallbackUsed = true;
      finalTokens = List<String>.from(originalTokens);
      finalWeights = List<double>.filled(originalTokens.length, 1.0);
    }

    stopwatch.stop();

    return TokenFilterResult(
      finalTokens: finalTokens,
      tokenWeights: finalWeights,
      diagnostics: TokenFilterDiagnostics(
        originalTokens: originalTokens,
        filteredTokens: List<String>.from(finalTokens),
        mappingPairs: List<TokenMappingPair>.from(mappings),
        beforeCount: originalTokens.length,
        afterCount: finalTokens.length,
        mappedCount: mappedCount,
        droppedCount: droppedCount,
        fallbackUsed: fallbackUsed,
        elapsedMs: stopwatch.elapsedMilliseconds,
      ),
    );
  }

  List<_WeightedNgram> _buildContiguousNgrams({
    required List<String> tokens,
    required List<double> tokenWeights,
    required int n,
  }) {
    if (n <= 0 || tokens.length < n || tokenWeights.length != tokens.length) {
      return <_WeightedNgram>[];
    }

    final Map<String, _WeightedNgram> byKey = <String, _WeightedNgram>{};

    for (int start = 0; start <= tokens.length - n; start++) {
      final List<String> ngramTokens = tokens.sublist(start, start + n);
      final List<double> ngramWeights = tokenWeights.sublist(start, start + n);
      final _WeightedNgram ngram = _WeightedNgram(tokens: ngramTokens, weights: ngramWeights);
      final String key = ngram.tokens.join('\u0001');

      final _WeightedNgram? existing = byKey[key];
      if (existing == null || ngram.totalWeight > existing.totalWeight) {
        byKey[key] = ngram;
      }
    }

    return byKey.values.toList(growable: false);
  }

  Future<Set<int>> _getCandidateAyahIdsForNgram({
    required List<String> ngramTokens,
    required Map<String, Set<int>> postingCache,
    int? minAyahId,
    int? maxAyahId,
  }) async {
    final List<String> uniqueTokens = ngramTokens.toSet().toList(growable: false);
    if (uniqueTokens.isEmpty) {
      return <int>{};
    }

    final Map<String, Set<int>> postingLists = <String, Set<int>>{};

    for (final String token in uniqueTokens) {
      final Set<int>? cached = postingCache[token];
      if (cached != null) {
        if (cached.isEmpty) {
          return <int>{};
        }
        postingLists[token] = cached;
        continue;
      }

      final List<int> ayahIds = await _repository.getCandidateAyahIdsForToken(
        token,
        minAyahId: minAyahId,
        maxAyahId: maxAyahId,
      );
      final Set<int> postings = ayahIds.toSet();
      postingCache[token] = postings;

      if (postings.isEmpty) {
        return <int>{};
      }
      postingLists[token] = postings;
    }

    uniqueTokens.sort(
      (String a, String b) => postingLists[a]!.length.compareTo(postingLists[b]!.length),
    );

    Set<int> candidateIds = Set<int>.from(postingLists[uniqueTokens.first]!);
    for (final String token in uniqueTokens.skip(1)) {
      candidateIds = candidateIds.intersection(postingLists[token]!);
      if (candidateIds.isEmpty) {
        return <int>{};
      }
    }

    return candidateIds;
  }

  _MatchScore _scoreMatch({
    required List<String> ayahTokens,
    required List<String> queryTokens,
    required List<double> queryWeights,
    required List<String> ngramTokens,
    required int n,
  }) {
    final int? phraseStart = _findPhraseStart(ayahTokens, ngramTokens);
    final bool hasPhrase = phraseStart != null;
    final int? phraseEnd = hasPhrase ? phraseStart + n - 1 : null;

    final int matchedTokenCountForNgram = hasPhrase
        ? n
        : _countMultisetOverlap(ngramTokens: ngramTokens, ayahTokens: ayahTokens);
    final List<String> matchedTokens = hasPhrase
        ? List<String>.from(ngramTokens)
        : _collectMatchedTokens(ngramTokens: ngramTokens, ayahTokens: ayahTokens);

    if (matchedTokenCountForNgram <= 0 || matchedTokens.isEmpty) {
      return const _MatchScore(
        score: 0,
        matchedTokens: <String>[],
        startIndex: null,
        endIndex: null,
      );
    }

    final _WeightedOverlap weightedOverlap = _computeWeightedOverlap(
      queryTokens: queryTokens,
      queryWeights: queryWeights,
      ayahTokens: ayahTokens,
    );
    if (weightedOverlap.matchedTokenCount <= 0) {
      return const _MatchScore(
        score: 0,
        matchedTokens: <String>[],
        startIndex: null,
        endIndex: null,
      );
    }

    final double totalWeight = queryWeights.fold<double>(0, (double sum, double w) => sum + w);
    final double weightedCoverage = totalWeight <= 0
        ? 0
        : weightedOverlap.matchedWeight / totalWeight;
    final double phraseBonus = hasPhrase ? 0.6 : 0;

    final int extraMatchedTokensOutsidePhrase = math.max(
      0,
      weightedOverlap.matchedTokenCount - matchedTokenCountForNgram,
    );
    final double extraBonus = math.min(0.5, 0.1 * extraMatchedTokensOutsidePhrase);

    final double lengthPenalty = ayahTokens.length < n ? 0.2 : 0;
    final double finalScore = weightedCoverage + phraseBonus + extraBonus - lengthPenalty;

    return _MatchScore(
      score: finalScore,
      matchedTokens: matchedTokens,
      startIndex: phraseStart,
      endIndex: phraseEnd,
    );
  }

  int? _findPhraseStart(List<String> ayahTokens, List<String> phraseTokens) {
    if (phraseTokens.isEmpty || ayahTokens.length < phraseTokens.length) {
      return null;
    }

    for (int start = 0; start <= ayahTokens.length - phraseTokens.length; start++) {
      bool allMatch = true;
      for (int i = 0; i < phraseTokens.length; i++) {
        if (ayahTokens[start + i] != phraseTokens[i]) {
          allMatch = false;
          break;
        }
      }
      if (allMatch) {
        return start;
      }
    }
    return null;
  }

  _WeightedOverlap _computeWeightedOverlap({
    required List<String> queryTokens,
    required List<double> queryWeights,
    required List<String> ayahTokens,
  }) {
    final Map<String, int> ayahTokenCounts = <String, int>{};
    for (final String token in ayahTokens) {
      ayahTokenCounts[token] = (ayahTokenCounts[token] ?? 0) + 1;
    }

    double matchedWeight = 0;
    int matchedTokenCount = 0;

    for (int i = 0; i < queryTokens.length; i++) {
      final String token = queryTokens[i];
      final int available = ayahTokenCounts[token] ?? 0;
      if (available <= 0) {
        continue;
      }

      matchedWeight += queryWeights[i];
      matchedTokenCount++;
      ayahTokenCounts[token] = available - 1;
    }

    return _WeightedOverlap(matchedWeight: matchedWeight, matchedTokenCount: matchedTokenCount);
  }

  int _countMultisetOverlap({required List<String> ngramTokens, required List<String> ayahTokens}) {
    final Map<String, int> ayahTokenCounts = <String, int>{};
    for (final String token in ayahTokens) {
      ayahTokenCounts[token] = (ayahTokenCounts[token] ?? 0) + 1;
    }

    int matchedCount = 0;
    for (final String token in ngramTokens) {
      final int available = ayahTokenCounts[token] ?? 0;
      if (available > 0) {
        matchedCount++;
        ayahTokenCounts[token] = available - 1;
      }
    }
    return matchedCount;
  }

  List<String> _collectMatchedTokens({
    required List<String> ngramTokens,
    required List<String> ayahTokens,
  }) {
    final Map<String, int> ayahTokenCounts = <String, int>{};
    for (final String token in ayahTokens) {
      ayahTokenCounts[token] = (ayahTokenCounts[token] ?? 0) + 1;
    }

    final List<String> matchedTokens = <String>[];
    for (final String token in ngramTokens) {
      final int available = ayahTokenCounts[token] ?? 0;
      if (available > 0) {
        matchedTokens.add(token);
        ayahTokenCounts[token] = available - 1;
      }
    }
    return matchedTokens;
  }

  bool _isConnectorToken(String token) {
    return token == 'و' || token == 'ف';
  }

  double _rarityWeight({required String token, required int freq}) {
    if (_isConnectorToken(token)) {
      return 0.2;
    }

    final double denominator = math.log(freq + 10) / math.ln10;
    final double raw = denominator <= 0 ? 1 : (1 / denominator);
    return raw.clamp(0.3, 1.0).toDouble();
  }

  bool _isBetterResultSet(List<SearchResult> candidate, List<SearchResult> baseline) {
    if (candidate.isEmpty) {
      return false;
    }
    if (baseline.isEmpty) {
      return true;
    }
    return candidate.first.score > baseline.first.score;
  }

  bool _shouldEarlyStop(List<SearchResult> topResults, SearchConfig config) {
    if (topResults.isEmpty) {
      return false;
    }

    if (topResults.length == 1) {
      return topResults.first.score >= config.autoLockMinScore;
    }

    final SearchResult first = topResults[0];
    final SearchResult second = topResults[1];
    final double margin = first.score - second.score;

    return first.score >= config.autoLockMinScore && margin >= config.autoLockMinMargin;
  }

  _WindowSlices _buildWindows(List<String> tokens) {
    if (tokens.isEmpty) {
      return const _WindowSlices(start: <String>[], mid: <String>[], end: <String>[]);
    }

    final int baseCount = (tokens.length * 0.35).round();
    final int minCount = tokens.length >= 12 ? 4 : 1;
    final int windowCount = baseCount.clamp(minCount, tokens.length).toInt();

    final List<String> start = tokens.sublist(0, windowCount);
    final int midStart = ((tokens.length - windowCount) / 2).floor();
    final List<String> mid = tokens.sublist(midStart, midStart + windowCount);
    final List<String> end = tokens.sublist(tokens.length - windowCount);

    return _WindowSlices(start: start, mid: mid, end: end);
  }

  Future<bool> _cacheAyahIfPresent(
    int ayahId,
    Map<int, AyahRow> ayahCache,
    Set<int> missingAyahIds,
  ) async {
    if (ayahId < 1) {
      return false;
    }
    if (ayahCache.containsKey(ayahId)) {
      return true;
    }
    if (missingAyahIds.contains(ayahId)) {
      return false;
    }

    final AyahRow? ayah = await _repository.getAyahById(ayahId);
    if (ayah == null) {
      missingAyahIds.add(ayahId);
      return false;
    }

    ayahCache[ayahId] = ayah;
    return true;
  }

  Future<List<String>> _buildVirtualTokens(List<int> ayahIds, Map<int, AyahRow> ayahCache) async {
    final List<int> missingIds = ayahIds.where((int id) => !ayahCache.containsKey(id)).toList();
    if (missingIds.isNotEmpty) {
      final List<AyahRow> ayahs = await _repository.getAyahsByIds(missingIds);
      for (final AyahRow ayah in ayahs) {
        ayahCache[ayah.id] = ayah;
      }
    }

    final List<String> virtualTokens = <String>[];
    for (final int id in ayahIds) {
      final AyahRow? ayah = ayahCache[id];
      if (ayah == null) {
        continue;
      }
      final String source = ayah.searchTextNorm;
      virtualTokens.addAll(_normalizer.tokenize(source));
    }
    return virtualTokens;
  }

  double _scoreWindow(List<String> windowTokens, List<String> virtualTokens) {
    if (windowTokens.isEmpty || virtualTokens.isEmpty) {
      return 0;
    }

    final List<double> windowWeights = List<double>.filled(windowTokens.length, 1.0);
    final int startN = math.min(5, windowTokens.length);
    double bestScore = 0;

    for (int n = startN; n >= 1; n--) {
      final List<_WeightedNgram> ngrams = _buildContiguousNgrams(
        tokens: windowTokens,
        tokenWeights: windowWeights,
        n: n,
      );
      for (final _WeightedNgram ngram in ngrams) {
        final _MatchScore score = _scoreMatch(
          ayahTokens: virtualTokens,
          queryTokens: windowTokens,
          queryWeights: windowWeights,
          ngramTokens: ngram.tokens,
          n: n,
        );
        if (score.score > bestScore) {
          bestScore = score.score;
        }
      }
    }

    return bestScore;
  }
}

class _WindowSlices {
  const _WindowSlices({required this.start, required this.mid, required this.end});

  final List<String> start;
  final List<String> mid;
  final List<String> end;
}

class _PathEvaluation {
  const _PathEvaluation({
    required this.anchorId,
    required this.path,
    required this.startScore,
    required this.midScore,
    required this.endScore,
    required this.finalScore,
  });

  final int anchorId;
  final List<int> path;
  final double startScore;
  final double midScore;
  final double endScore;
  final double finalScore;
}

class _NgramCandidateSet {
  const _NgramCandidateSet({required this.ngram, required this.candidateAyahIds});

  final _WeightedNgram ngram;
  final Set<int> candidateAyahIds;
}

class _WeightedNgram {
  const _WeightedNgram({required this.tokens, required this.weights});

  final List<String> tokens;
  final List<double> weights;

  double get totalWeight => weights.fold<double>(0, (double sum, double w) => sum + w);
}

class _MatchScore {
  const _MatchScore({
    required this.score,
    required this.matchedTokens,
    required this.startIndex,
    required this.endIndex,
  });

  final double score;
  final List<String> matchedTokens;
  final int? startIndex;
  final int? endIndex;
}

class _WeightedOverlap {
  const _WeightedOverlap({required this.matchedWeight, required this.matchedTokenCount});

  final double matchedWeight;
  final int matchedTokenCount;
}
