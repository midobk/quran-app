import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../services/search/quran_search_engine.dart';

class ResultsController extends ChangeNotifier {
  ResultsController({
    required this.results,
    required this.autoLockConfig,
    this.autoLockDelay = const Duration(milliseconds: 900),
  });

  final List<SearchResult> results;
  final SearchConfig autoLockConfig;
  final Duration autoLockDelay;

  bool _isAutoLocking = false;
  bool _hasHandledAutoLock = false;
  String? _autoLockMessage;

  bool get isAutoLocking => _isAutoLocking;
  String? get autoLockMessage => _autoLockMessage;

  Future<void> triggerAutoLockIfEligible(
    Future<void> Function(SearchResult result) onAutoLock,
  ) async {
    if (_hasHandledAutoLock) {
      return;
    }
    _hasHandledAutoLock = true;

    final SearchResult? lockCandidate = _resolveAutoLockCandidate();
    if (lockCandidate == null) {
      return;
    }

    _isAutoLocking = true;
    _autoLockMessage = 'Auto-locking to top match...';
    notifyListeners();

    await Future<void>.delayed(autoLockDelay);
    await onAutoLock(lockCandidate);
  }

  SearchResult? _resolveAutoLockCandidate() {
    if (results.isEmpty) {
      return null;
    }

    final SearchResult top = results.first;
    if (results.length == 1) {
      return top.score >= autoLockConfig.autoLockMinScore ? top : null;
    }

    final SearchResult second = results[1];
    final double margin = top.score - second.score;
    if (top.score >= autoLockConfig.autoLockMinScore &&
        margin >= autoLockConfig.autoLockMinMargin) {
      return top;
    }
    return null;
  }
}
