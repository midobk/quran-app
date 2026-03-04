import 'package:sqflite/sqflite.dart';

import '../../core/arabic/arabic_normalizer.dart';
import '../database/database_service.dart';

class IndexProgress {
  const IndexProgress({required this.processed, required this.total, required this.currentAyahId});

  final int processed;
  final int total;
  final int? currentAyahId;

  double get percent => total == 0 ? 1 : processed / total;
}

typedef IndexProgressCallback = void Function(IndexProgress progress);

class QuranIndexBuilder {
  QuranIndexBuilder({
    required DatabaseService databaseService,
    required ArabicNormalizer normalizer,
    this.readBatchSize = 400,
  }) : _databaseService = databaseService,
       _normalizer = normalizer;

  final DatabaseService _databaseService;
  final ArabicNormalizer _normalizer;
  final int readBatchSize;

  Future<void> rebuild({required IndexProgressCallback onProgress}) async {
    await _databaseService.init();
    final Database database = _databaseService.db;

    await _ensureTokenIndexSchema(database);

    final int totalAyahs =
        Sqflite.firstIntValue(await database.rawQuery('SELECT COUNT(*) FROM ayah')) ?? 0;
    onProgress(IndexProgress(processed: 0, total: totalAyahs, currentAyahId: null));

    await database.transaction((Transaction transaction) async {
      await transaction.delete('token_index');

      if (totalAyahs == 0) {
        return;
      }

      int processed = 0;
      int lastAyahId = 0;

      while (true) {
        final List<Map<String, Object?>> rows = await transaction.query(
          'ayah',
          columns: <String>['id', 'text_plain_norm', 'text_norm'],
          where: 'id > ?',
          whereArgs: <Object?>[lastAyahId],
          orderBy: 'id ASC',
          limit: readBatchSize,
        );

        if (rows.isEmpty) {
          break;
        }

        final Batch batch = transaction.batch();
        bool hasInsertions = false;

        for (final Map<String, Object?> row in rows) {
          final int ayahId = row['id'] as int;
          lastAyahId = ayahId;

          final String textPlainNorm = ((row['text_plain_norm'] as String?) ?? '').trim();
          final String textNorm = ((row['text_norm'] as String?) ?? '').trim();
          final String indexedText = textPlainNorm.isNotEmpty ? textPlainNorm : textNorm;
          if (indexedText.isNotEmpty) {
            final Set<String> uniqueTokens = _normalizer.tokenize(indexedText).toSet();
            for (final String token in uniqueTokens) {
              if (token.isEmpty) {
                continue;
              }

              batch.insert('token_index', <String, Object?>{
                'token': token,
                'ayah_id': ayahId,
              }, conflictAlgorithm: ConflictAlgorithm.ignore);
              hasInsertions = true;
            }
          }

          processed++;
          onProgress(IndexProgress(processed: processed, total: totalAyahs, currentAyahId: ayahId));
        }

        if (hasInsertions) {
          await batch.commit(noResult: true);
        }
      }

      await _ensureVocabSchema(transaction);
      await transaction.delete('vocab');
      await transaction.execute('''
        INSERT INTO vocab(token, freq)
        SELECT token, COUNT(DISTINCT ayah_id)
        FROM token_index
        GROUP BY token
      ''');
    });
  }

  Future<void> _ensureTokenIndexSchema(DatabaseExecutor executor) async {
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS token_index(
        token TEXT NOT NULL,
        ayah_id INTEGER NOT NULL,
        PRIMARY KEY(token, ayah_id)
      );
    ''');

    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_token_index_token
      ON token_index(token);
    ''');
  }

  Future<void> _ensureVocabSchema(DatabaseExecutor executor) async {
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS vocab(
        token TEXT PRIMARY KEY,
        freq INTEGER NOT NULL
      );
    ''');

    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_vocab_token
      ON vocab(token);
    ''');
  }
}
