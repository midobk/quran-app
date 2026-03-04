import 'dart:collection';

import 'package:sqflite/sqflite.dart';

import '../database/database_service.dart';

class VocabService {
  VocabService({required DatabaseService databaseService}) : _databaseService = databaseService;

  final DatabaseService _databaseService;

  final Map<String, int> _tokenFreq = <String, int>{};
  Future<void>? _pendingInit;
  bool _isInitialized = false;
  int _tokenIndexRowCount = -1;

  int get size => _tokenFreq.length;
  bool contains(String token) => _tokenFreq.containsKey(token);
  int? freq(String token) => _tokenFreq[token];
  UnmodifiableMapView<String, int> get tokenFreq => UnmodifiableMapView<String, int>(_tokenFreq);

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
    await _databaseService.init();
    final Database db = _databaseService.db;

    await db.execute('''
      CREATE TABLE IF NOT EXISTS vocab(
        token TEXT PRIMARY KEY,
        freq INTEGER NOT NULL
      );
    ''');

    await db.execute('CREATE INDEX IF NOT EXISTS idx_vocab_token ON vocab(token);');

    final int vocabCount =
        Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM vocab')) ?? 0;
    if (vocabCount == 0) {
      await db.execute('''
        INSERT INTO vocab(token, freq)
        SELECT token, COUNT(DISTINCT ayah_id)
        FROM token_index
        GROUP BY token;
      ''');
    }

    final List<Map<String, Object?>> rows = await db.query(
      'vocab',
      columns: <String>['token', 'freq'],
    );

    _tokenFreq
      ..clear()
      ..addEntries(
        rows.map((Map<String, Object?> row) {
          return MapEntry<String, int>(row['token'] as String, row['freq'] as int);
        }),
      );

    _tokenIndexRowCount =
        Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM token_index')) ?? 0;
    _isInitialized = true;
    _pendingInit = null;
  }

  Future<void> refreshIfStale() async {
    await init();

    final Database db = _databaseService.db;
    final int tokenIndexCount =
        Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM token_index')) ?? 0;

    final bool mustRefresh =
        tokenIndexCount != _tokenIndexRowCount || (tokenIndexCount > 0 && _tokenFreq.isEmpty);
    if (!mustRefresh) {
      return;
    }

    await db.transaction((Transaction tx) async {
      await tx.execute('DELETE FROM vocab');
      if (tokenIndexCount > 0) {
        await tx.execute('''
          INSERT INTO vocab(token, freq)
          SELECT token, COUNT(DISTINCT ayah_id)
          FROM token_index
          GROUP BY token;
        ''');
      }
    });

    final List<Map<String, Object?>> rows = await db.query(
      'vocab',
      columns: <String>['token', 'freq'],
    );
    _tokenFreq
      ..clear()
      ..addEntries(
        rows.map((Map<String, Object?> row) {
          return MapEntry<String, int>(row['token'] as String, row['freq'] as int);
        }),
      );
    _tokenIndexRowCount = tokenIndexCount;
  }
}
