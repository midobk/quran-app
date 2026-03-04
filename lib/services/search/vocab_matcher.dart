import 'dart:collection';
import 'dart:math' as math;

import 'vocab_service.dart';

class MatchResult {
  const MatchResult({required this.token, required this.distance, required this.confidence});

  final String token;
  final int distance;
  final double confidence;
}

class VocabMatcher {
  VocabMatcher({
    required VocabService vocabService,
    this.candidateLimit = 600,
    this.cacheSize = 1000,
  }) : assert(candidateLimit > 0),
       assert(cacheSize > 0),
       _vocabService = vocabService;

  final VocabService _vocabService;
  final int candidateLimit;
  final int cacheSize;

  final Map<String, List<String>> _buckets = <String, List<String>>{};
  final LinkedHashMap<String, MatchResult?> _cache = LinkedHashMap<String, MatchResult?>();

  Future<void>? _pendingInit;
  bool _isInitialized = false;
  int _lastVocabSize = -1;
  int _cacheHits = 0;

  int get cacheHits => _cacheHits;

  Future<void> init() {
    if (_isInitialized) {
      return Future<void>.value();
    }

    final Future<void>? pending = _pendingInit;
    if (pending != null) {
      return pending;
    }

    final Future<void> initialization = _initInternal();
    _pendingInit = initialization;
    return initialization.whenComplete(() {
      if (!_isInitialized) {
        _pendingInit = null;
      }
    });
  }

  Future<void> _initInternal() async {
    await _vocabService.init();
    final int currentVocabSize = _vocabService.size;
    if (!_isInitialized || _lastVocabSize != currentVocabSize) {
      _buildBuckets();
      _cache.clear();
      _lastVocabSize = currentVocabSize;
      _isInitialized = true;
    }
    _pendingInit = null;
  }

  Future<MatchResult?> match(String token) async {
    final String normalizedToken = token.trim();
    if (normalizedToken.isEmpty) {
      return null;
    }

    await init();

    if (_vocabService.contains(normalizedToken)) {
      return MatchResult(token: normalizedToken, distance: 0, confidence: 1);
    }

    final MatchResult? cached = _readCache(normalizedToken);
    if (_cache.containsKey(normalizedToken)) {
      return cached;
    }

    final int maxDistance = _maxDistanceForLength(normalizedToken.length);
    if (maxDistance <= 0) {
      _writeCache(normalizedToken, null);
      return null;
    }

    final List<String> candidates = _collectCandidates(normalizedToken);
    if (candidates.isEmpty) {
      _writeCache(normalizedToken, null);
      return null;
    }

    String? bestToken;
    int bestDistance = maxDistance + 1;
    int bestFreq = 1 << 30;

    for (final String candidate in candidates) {
      final int distance = _boundedLevenshtein(
        normalizedToken,
        candidate,
        maxDistance: maxDistance,
      );
      if (distance > maxDistance) {
        continue;
      }

      final int freq = _vocabService.freq(candidate) ?? (1 << 30);
      final bool betterDistance = distance < bestDistance;
      final bool sameDistanceRarer = distance == bestDistance && freq < bestFreq;
      if (betterDistance || sameDistanceRarer) {
        bestToken = candidate;
        bestDistance = distance;
        bestFreq = freq;
        if (bestDistance == 0) {
          break;
        }
      }
    }

    if (bestToken == null || bestDistance > maxDistance) {
      _writeCache(normalizedToken, null);
      return null;
    }

    final MatchResult result = MatchResult(
      token: bestToken,
      distance: bestDistance,
      confidence: _confidenceForDistance(bestDistance),
    );
    _writeCache(normalizedToken, result);
    return result;
  }

  void _buildBuckets() {
    _buckets.clear();

    final Map<String, int> tokenFreq = _vocabService.tokenFreq;
    for (final String token in tokenFreq.keys) {
      if (token.isEmpty) {
        continue;
      }
      final String key = _bucketKey(token, token.length);
      _buckets.putIfAbsent(key, () => <String>[]).add(token);
    }

    for (final List<String> bucket in _buckets.values) {
      bucket.sort((String a, String b) {
        final int freqA = tokenFreq[a] ?? (1 << 30);
        final int freqB = tokenFreq[b] ?? (1 << 30);
        final int freqCmp = freqA.compareTo(freqB);
        if (freqCmp != 0) {
          return freqCmp;
        }
        return a.compareTo(b);
      });
    }
  }

  MatchResult? _readCache(String token) {
    if (!_cache.containsKey(token)) {
      return null;
    }

    _cacheHits++;
    final MatchResult? value = _cache.remove(token);
    _cache[token] = value;
    return value;
  }

  void _writeCache(String token, MatchResult? result) {
    if (_cache.length >= cacheSize && !_cache.containsKey(token)) {
      _cache.remove(_cache.keys.first);
    }
    _cache[token] = result;
  }

  List<String> _collectCandidates(String token) {
    final Set<String> seen = <String>{};
    final List<String> candidates = <String>[];

    for (final String key in _candidateBucketKeys(token)) {
      final List<String>? bucket = _buckets[key];
      if (bucket == null) {
        continue;
      }

      for (final String candidate in bucket) {
        if (!seen.add(candidate)) {
          continue;
        }
        candidates.add(candidate);
        if (candidates.length >= candidateLimit) {
          return candidates;
        }
      }
    }

    return candidates;
  }

  List<String> _candidateBucketKeys(String token) {
    final int length = token.length;
    final List<int> lengths = <int>[
      length,
      length - 1,
      length + 1,
    ].where((int value) => value > 0).toList(growable: false);

    final Set<String> keys = <String>{};
    for (final int targetLength in lengths) {
      keys.add(_bucketKey(token, targetLength));
    }
    return keys.toList(growable: false);
  }

  String _bucketKey(String token, int targetLength) {
    final int desiredPrefixLength = targetLength >= 5 ? 2 : 1;
    final int prefixLength = math.max(1, math.min(desiredPrefixLength, token.length));
    final String prefix = token.substring(0, prefixLength);
    return '$prefix:$targetLength';
  }

  int _maxDistanceForLength(int length) {
    if (length <= 3) {
      return 0;
    }
    if (length <= 6) {
      return 1;
    }
    return 2;
  }

  double _confidenceForDistance(int distance) {
    switch (distance) {
      case 0:
        return 1;
      case 1:
        return 0.75;
      case 2:
        return 0.60;
      default:
        return 0;
    }
  }

  int _boundedLevenshtein(String source, String target, {required int maxDistance}) {
    if (source == target) {
      return 0;
    }

    final int sourceLength = source.length;
    final int targetLength = target.length;
    if ((sourceLength - targetLength).abs() > maxDistance) {
      return maxDistance + 1;
    }

    final List<int> previous = List<int>.generate(targetLength + 1, (int i) => i);
    final List<int> current = List<int>.filled(targetLength + 1, 0);

    for (int i = 1; i <= sourceLength; i++) {
      current[0] = i;
      final int start = math.max(1, i - maxDistance);
      final int end = math.min(targetLength, i + maxDistance);

      for (int j = 1; j < start; j++) {
        current[j] = maxDistance + 1;
      }

      int rowMin = current[0];
      for (int j = start; j <= end; j++) {
        final int substitutionCost = source.codeUnitAt(i - 1) == target.codeUnitAt(j - 1) ? 0 : 1;
        final int insertion = current[j - 1] + 1;
        final int deletion = previous[j] + 1;
        final int substitution = previous[j - 1] + substitutionCost;

        final int value = math.min(math.min(insertion, deletion), substitution);
        current[j] = value;
        if (value < rowMin) {
          rowMin = value;
        }
      }

      for (int j = end + 1; j <= targetLength; j++) {
        current[j] = maxDistance + 1;
      }

      if (rowMin > maxDistance) {
        return maxDistance + 1;
      }

      for (int j = 0; j <= targetLength; j++) {
        previous[j] = current[j];
      }
    }

    return previous[targetLength];
  }
}
