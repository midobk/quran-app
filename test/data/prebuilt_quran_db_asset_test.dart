import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app/data/quran/ayah_row.dart';
import 'package:quran_app/data/quran/quran_repository.dart';
import 'package:quran_app/services/database/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  test('prebuilt quran.db copy exposes non-empty ayahs and translation', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp('quran_asset_db_test_');
    final File assetDbFile = File('assets/db/quran.db');

    expect(await assetDbFile.exists(), isTrue);
    final Uint8List bundledBytes = await assetDbFile.readAsBytes();

    final DatabaseService firstService = DatabaseService(
      databaseFactoryOverride: databaseFactoryFfi,
      documentsPathProvider: () async => tempDir.path,
      bundledDbLoader: () async => bundledBytes,
    );
    final QuranRepository firstRepository = QuranRepository(firstService);

    final DatabaseService secondService = DatabaseService(
      databaseFactoryOverride: databaseFactoryFfi,
      documentsPathProvider: () async => tempDir.path,
      bundledDbLoader: () async => Uint8List.fromList(<int>[1, 2, 3]),
    );

    addTearDown(() async {
      await firstService.dispose();
      await secondService.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    await firstService.init();
    expect(firstService.dbPath, isNotNull);
    expect(await File(firstService.dbPath!).exists(), isTrue);

    final int ayahCount = await firstRepository.getAyahCount();
    expect(ayahCount, greaterThan(0));

    final AyahRow? ayahOne = await firstRepository.getAyahById(1);
    expect(ayahOne, isNotNull);
    expect(ayahOne!.translationEn.trim(), isNotEmpty);

    await firstService.db.execute('CREATE TABLE IF NOT EXISTS _copy_check(marker TEXT NOT NULL)');
    await firstService.db.insert('_copy_check', <String, Object?>{'marker': 'persisted'});
    await firstService.dispose();

    await secondService.init();
    final List<Map<String, Object?>> rows = await secondService.db.query('_copy_check');
    expect(rows, isNotEmpty);
  });
}
