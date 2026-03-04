import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app/core/arabic/arabic_normalizer.dart';
import 'package:quran_app/services/database/database_service.dart';
import 'package:quran_app/services/indexing/quran_index_builder.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  test('rebuild creates expected token_index pairs without per-ayah duplicates', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp('quran_index_builder_test_');
    final DatabaseService databaseService = DatabaseService(
      databaseFactoryOverride: databaseFactoryFfi,
      documentsPathProvider: () async => tempDir.path,
      bundledDbLoader: () async => null,
    );

    addTearDown(() async {
      await databaseService.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    await databaseService.init();

    await databaseService.db.insert('ayah', <String, Object?>{
      'id': 1,
      'surah_no': 1,
      'ayah_no': 1,
      'surah_name_ar': 'الفاتحة',
      'text_uthmani': 'اللَّهُ أَكْبَرُ',
      'text_norm': 'الله الله اكبر',
    });

    await databaseService.db.insert('ayah', <String, Object?>{
      'id': 2,
      'surah_no': 1,
      'ayah_no': 2,
      'surah_name_ar': 'الفاتحة',
      'text_uthmani': 'اللَّهُ كَبِيرٌ',
      'text_norm': 'الله كبير',
    });

    await databaseService.db.insert('ayah', <String, Object?>{
      'id': 3,
      'surah_no': 1,
      'ayah_no': 3,
      'surah_name_ar': 'الفاتحة',
      'text_uthmani': '',
      'text_norm': '',
    });

    await databaseService.db.execute('DROP TABLE IF EXISTS token_index');

    final QuranIndexBuilder builder = QuranIndexBuilder(
      databaseService: databaseService,
      normalizer: const ArabicNormalizer(),
      readBatchSize: 2,
    );

    final List<IndexProgress> progressUpdates = <IndexProgress>[];
    await builder.rebuild(onProgress: progressUpdates.add);

    expect(progressUpdates, isNotEmpty);
    expect(progressUpdates.first.processed, 0);
    expect(progressUpdates.first.total, 3);
    expect(progressUpdates.last.processed, 3);
    expect(progressUpdates.last.total, 3);

    final List<Map<String, Object?>> tokenRows = await databaseService.db.query(
      'token_index',
      columns: <String>['token', 'ayah_id'],
      orderBy: 'token ASC, ayah_id ASC',
    );

    expect(tokenRows.length, 4);
    expect(tokenRows[0]['token'], 'اكبر');
    expect(tokenRows[0]['ayah_id'], 1);
    expect(tokenRows[1]['token'], 'الله');
    expect(tokenRows[1]['ayah_id'], 1);
    expect(tokenRows[2]['token'], 'الله');
    expect(tokenRows[2]['ayah_id'], 2);
    expect(tokenRows[3]['token'], 'كبير');
    expect(tokenRows[3]['ayah_id'], 2);

    final List<Map<String, Object?>> duplicateRows = await databaseService.db.rawQuery(
      'SELECT COUNT(*) AS count FROM token_index WHERE token = ? AND ayah_id = ?',
      <Object?>['الله', 1],
    );
    final int duplicateCount = (duplicateRows.first['count'] as int?) ?? 0;
    expect(duplicateCount, 1);
  });
}
