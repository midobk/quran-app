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

  test('getPreviousAyah and getNextAyah follow Quran order across sparse ids', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp('quran_repo_neighbors_test_');
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
    for (final Map<String, Object?> row in <Map<String, Object?>>[
      <String, Object?>{
        'id': 10,
        'surah_no': 112,
        'ayah_no': 4,
        'surah_name_ar': 'الإخلاص',
        'text_uthmani': 'ختام',
        'text_norm': 'ختام',
      },
      <String, Object?>{
        'id': 11,
        'surah_no': 2,
        'ayah_no': 255,
        'surah_name_ar': 'البقرة',
        'text_uthmani': 'غير مجاور',
        'text_norm': 'غير مجاور',
      },
      <String, Object?>{
        'id': 99,
        'surah_no': 113,
        'ayah_no': 1,
        'surah_name_ar': 'الفلق',
        'text_uthmani': 'بداية',
        'text_norm': 'بداية',
      },
    ]) {
      await databaseService.db.insert('ayah', row, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    final AyahRow anchorAyah = (await repository.getAyahById(10))!;
    final AyahRow nextAyah = (await repository.getNextAyah(anchorAyah))!;
    final AyahRow previousAyah = (await repository.getPreviousAyah(nextAyah))!;
    final AyahRow directPreviousAyah = (await repository.getPreviousAyah(anchorAyah))!;

    expect(nextAyah.id, 99);
    expect(nextAyah.surahNo, 113);
    expect(nextAyah.ayahNo, 1);

    expect(previousAyah.id, 10);
    expect(previousAyah.surahNo, 112);
    expect(previousAyah.ayahNo, 4);

    expect(directPreviousAyah.id, 11);
    expect(directPreviousAyah.surahNo, 2);
    expect(directPreviousAyah.ayahNo, 255);
  });
}
