import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/arabic/arabic_normalizer.dart';
import '../../services/database/database_service.dart';
import '../../services/indexing/quran_index_builder.dart';
import 'ayah_row.dart';

class QuranRepository {
  QuranRepository(this._databaseService, {QuranIndexBuilder? indexBuilder})
    : _indexBuilder =
          indexBuilder ??
          QuranIndexBuilder(
            databaseService: _databaseService,
            normalizer: const ArabicNormalizer(),
          );

  final DatabaseService _databaseService;
  final QuranIndexBuilder _indexBuilder;

  Future<void> ensureDevSeedDataIfEmpty() async {
    if (!kDebugMode) {
      return;
    }

    await _databaseService.init();
    final Database database = _databaseService.db;
    final int existingAyahCount =
        Sqflite.firstIntValue(await database.rawQuery('SELECT COUNT(*) FROM ayah')) ?? 0;

    if (existingAyahCount > 0) {
      return;
    }

    final Batch seedBatch = database.batch();
    for (final _SeedAyah row in _devSeedAyahs) {
      seedBatch.insert('ayah', <String, Object?>{
        'id': row.id,
        'surah_no': row.surahNo,
        'ayah_no': row.ayahNo,
        'surah_name_ar': row.surahNameAr,
        'surah_name_en': row.surahNameEn,
        'text_uthmani': row.textUthmani,
        'text_norm': row.textNorm,
        'text_plain': row.textPlain,
        'text_plain_norm': row.textPlainNorm,
        'translation_en': row.translationEn,
        // Keep legacy column populated for backwards compatibility.
        'text_en': row.translationEn,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await seedBatch.commit(noResult: true);

    await rebuildIndex(onProgress: (_) {});
  }

  Future<List<AyahRow>> searchByNormContains(String query, {int limit = 20}) async {
    final String trimmed = query.trim();
    if (trimmed.isEmpty || limit <= 0) {
      return <AyahRow>[];
    }

    await _databaseService.init();
    final Database database = _databaseService.db;

    final List<Map<String, Object?>> rows = await database.query(
      'ayah',
      columns: _ayahColumns,
      where: "(text_plain_norm LIKE ? OR (TRIM(text_plain_norm) = '' AND text_norm LIKE ?))",
      whereArgs: <Object?>['%$trimmed%', '%$trimmed%'],
      orderBy: 'surah_no ASC, ayah_no ASC',
      limit: limit,
    );

    return rows.map(AyahRow.fromMap).toList(growable: false);
  }

  Future<AyahRow?> getAyahById(int id) async {
    await _databaseService.init();
    final Database database = _databaseService.db;

    final List<Map<String, Object?>> rows = await database.query(
      'ayah',
      columns: _ayahColumns,
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return AyahRow.fromMap(rows.first);
  }

  Future<AyahRow?> getPreviousAyah(AyahRow ayah) {
    return _getAdjacentAyah(
      where: '(surah_no < ?) OR (surah_no = ? AND ayah_no < ?)',
      whereArgs: <Object?>[ayah.surahNo, ayah.surahNo, ayah.ayahNo],
      orderBy: 'surah_no DESC, ayah_no DESC, id DESC',
    );
  }

  Future<AyahRow?> getNextAyah(AyahRow ayah) {
    return _getAdjacentAyah(
      where: '(surah_no > ?) OR (surah_no = ? AND ayah_no > ?)',
      whereArgs: <Object?>[ayah.surahNo, ayah.surahNo, ayah.ayahNo],
      orderBy: 'surah_no ASC, ayah_no ASC, id ASC',
    );
  }

  Future<int> getAyahCount() async {
    await _databaseService.init();
    final Database database = _databaseService.db;
    final List<Map<String, Object?>> rows = await database.rawQuery(
      'SELECT COUNT(*) AS count FROM ayah',
    );
    return (rows.first['count'] as int?) ?? 0;
  }

  Future<List<AyahRow>> getAyahsByIds(Iterable<int> ids) async {
    final List<int> uniqueIds = ids.toSet().toList(growable: false);
    if (uniqueIds.isEmpty) {
      return <AyahRow>[];
    }

    await _databaseService.init();
    final Database database = _databaseService.db;

    uniqueIds.sort();
    const int chunkSize = 900;
    final List<AyahRow> allRows = <AyahRow>[];

    for (int offset = 0; offset < uniqueIds.length; offset += chunkSize) {
      final int endExclusive = (offset + chunkSize).clamp(0, uniqueIds.length);
      final List<int> chunk = uniqueIds.sublist(offset, endExclusive);
      final String placeholders = List<String>.filled(chunk.length, '?').join(',');

      final List<Map<String, Object?>> rows = await database.rawQuery(
        'SELECT ${_ayahColumns.join(',')} FROM ayah WHERE id IN ($placeholders)',
        chunk,
      );
      allRows.addAll(rows.map(AyahRow.fromMap));
    }

    allRows.sort((AyahRow a, AyahRow b) => a.id.compareTo(b.id));
    return allRows;
  }

  Future<List<int>> getCandidateAyahIdsForToken(
    String token, {
    int? minAyahId,
    int? maxAyahId,
  }) async {
    if (token.trim().isEmpty) {
      return <int>[];
    }

    await _databaseService.init();
    final Database database = _databaseService.db;

    final _QueryFilter whereFilter = _buildTokenIndexWhere(
      token: token,
      minAyahId: minAyahId,
      maxAyahId: maxAyahId,
    );

    final List<Map<String, Object?>> rows = await database.query(
      'token_index',
      columns: <String>['ayah_id'],
      where: whereFilter.whereClause,
      whereArgs: whereFilter.whereArgs,
      orderBy: 'ayah_id ASC',
    );

    return rows.map((Map<String, Object?> row) => row['ayah_id'] as int).toList(growable: false);
  }

  Future<void> rebuildIndex({required void Function(IndexProgress progress) onProgress}) {
    return _indexBuilder.rebuild(onProgress: onProgress);
  }

  Future<AyahRow?> _getAdjacentAyah({
    required String where,
    required List<Object?> whereArgs,
    required String orderBy,
  }) async {
    await _databaseService.init();
    final Database database = _databaseService.db;

    final List<Map<String, Object?>> rows = await database.query(
      'ayah',
      columns: _ayahColumns,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: 1,
    );
    return rows.isEmpty ? null : AyahRow.fromMap(rows.first);
  }

  _QueryFilter _buildTokenIndexWhere({required String token, int? minAyahId, int? maxAyahId}) {
    final List<String> whereParts = <String>['token = ?'];
    final List<Object?> whereArgs = <Object?>[token];

    if (minAyahId != null) {
      whereParts.add('ayah_id >= ?');
      whereArgs.add(minAyahId);
    }
    if (maxAyahId != null) {
      whereParts.add('ayah_id <= ?');
      whereArgs.add(maxAyahId);
    }

    return _QueryFilter(whereClause: whereParts.join(' AND '), whereArgs: whereArgs);
  }
}

const List<String> _ayahColumns = <String>[
  'id',
  'surah_no',
  'ayah_no',
  'surah_name_ar',
  'surah_name_en',
  'text_uthmani',
  'text_norm',
  'text_plain',
  'text_plain_norm',
  'translation_en',
  'text_en',
];

class _QueryFilter {
  const _QueryFilter({required this.whereClause, required this.whereArgs});

  final String whereClause;
  final List<Object?> whereArgs;
}

class _SeedAyah {
  const _SeedAyah({
    required this.id,
    required this.surahNo,
    required this.ayahNo,
    required this.surahNameAr,
    required this.surahNameEn,
    required this.textUthmani,
    required this.textNorm,
    required this.textPlain,
    required this.textPlainNorm,
    required this.translationEn,
  });

  final int id;
  final int surahNo;
  final int ayahNo;
  final String surahNameAr;
  final String surahNameEn;
  final String textUthmani;
  final String textNorm;
  final String textPlain;
  final String textPlainNorm;
  final String translationEn;
}

const List<_SeedAyah> _devSeedAyahs = <_SeedAyah>[
  _SeedAyah(
    id: 1,
    surahNo: 1,
    ayahNo: 1,
    surahNameAr: 'الفاتحة',
    surahNameEn: 'Al-Fatihah',
    textUthmani: 'بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ',
    textNorm: 'بسم الله الرحمن الرحيم',
    textPlain: 'بسم الله الرحمن الرحيم',
    textPlainNorm: 'بسم الله الرحمن الرحيم',
    translationEn: 'In the Name of Allah—the Most Compassionate, Most Merciful.',
  ),
  _SeedAyah(
    id: 2,
    surahNo: 1,
    ayahNo: 2,
    surahNameAr: 'الفاتحة',
    surahNameEn: 'Al-Fatihah',
    textUthmani: 'الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ',
    textNorm: 'الحمد لله رب العالمين',
    textPlain: 'الحمد لله رب العالمين',
    textPlainNorm: 'الحمد لله رب العالمين',
    translationEn: 'All praise is for Allah—Lord of all worlds.',
  ),
  _SeedAyah(
    id: 3,
    surahNo: 24,
    ayahNo: 35,
    surahNameAr: 'النور',
    surahNameEn: 'An-Nur',
    textUthmani: 'اللَّهُ نُورُ السَّمَاوَاتِ وَالْأَرْضِ',
    textNorm: 'الله نور السماوات والارض',
    textPlain: 'الله نور السماوات والارض',
    textPlainNorm: 'الله نور السماوات والارض',
    translationEn: 'Allah is the Light of the heavens and the earth.',
  ),
  _SeedAyah(
    id: 4,
    surahNo: 2,
    ayahNo: 173,
    surahNameAr: 'البقرة',
    surahNameEn: 'Al-Baqarah',
    textUthmani: 'إِنَّ اللَّهَ غَفُورٌ رَحِيمٌ',
    textNorm: 'ان الله غفور رحيم',
    textPlain: 'ان الله غفور رحيم',
    textPlainNorm: 'ان الله غفور رحيم',
    translationEn: 'Surely Allah is All-Forgiving, Most Merciful.',
  ),
  _SeedAyah(
    id: 5,
    surahNo: 87,
    ayahNo: 1,
    surahNameAr: 'الأعلى',
    surahNameEn: 'Al-Ala',
    textUthmani: 'اللَّهُ أَكْبَرُ اللَّهُ أَكْبَرُ',
    textNorm: 'الله اكبر الله اكبر',
    textPlain: 'الله اكبر الله اكبر',
    textPlainNorm: 'الله اكبر الله اكبر',
    translationEn: 'Allah is the Greatest, Allah is the Greatest.',
  ),
  _SeedAyah(
    id: 6,
    surahNo: 57,
    ayahNo: 1,
    surahNameAr: 'الحديد',
    surahNameEn: 'Al-Hadid',
    textUthmani: 'سَبَّحَ لِلَّهِ مَا فِي السَّمَاوَاتِ وَالْأَرْضِ',
    textNorm: 'سبح لله ما في السماوات والارض',
    textPlain: 'سبح لله ما في السماوات والارض',
    textPlainNorm: 'سبح لله ما في السماوات والارض',
    translationEn: 'Whatever is in the heavens and the earth glorifies Allah.',
  ),
];
