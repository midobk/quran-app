import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app/data/quran/ayah_row.dart';
import 'package:quran_app/data/quran/quran_repository.dart';
import 'package:quran_app/services/database/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  test('initializes schema and supports offline repository queries', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp('quran_repo_test_');
    final DatabaseService databaseService = DatabaseService(
      databaseFactoryOverride: databaseFactoryFfi,
      documentsPathProvider: () async => tempDir.path,
      bundledDbLoader: () async => null,
    );
    final QuranRepository repository = QuranRepository(databaseService);

    addTearDown(() async {
      await databaseService.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    await databaseService.init();
    expect(await repository.getAyahCount(), 0);

    await databaseService.db.insert('ayah', <String, Object?>{
      'id': 1,
      'surah_no': 1,
      'ayah_no': 1,
      'surah_name_ar': 'الفاتحة',
      'text_uthmani': 'بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ',
      'text_norm': 'بسم الله الرحمن الرحيم',
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    await databaseService.db.insert('ayah', <String, Object?>{
      'id': 2,
      'surah_no': 1,
      'ayah_no': 2,
      'surah_name_ar': 'الفاتحة',
      'text_uthmani': 'الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ',
      'text_norm': 'الحمد لله رب العالمين',
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    expect(await repository.getAyahCount(), 2);

    final List<AyahRow> results = await repository.searchByNormContains('الرحمن');
    expect(results.length, 1);
    expect(results.first.id, 1);

    final ayahById = await repository.getAyahById(2);
    expect(ayahById, isNotNull);
    expect(ayahById!.textNorm, 'الحمد لله رب العالمين');
  });
}
