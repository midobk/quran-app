import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseService {
  DatabaseService({
    DatabaseFactory? databaseFactoryOverride,
    Future<String> Function()? documentsPathProvider,
    Future<Uint8List?> Function()? bundledDbLoader,
    this.databaseName = 'quran.db',
  }) : _databaseFactory = databaseFactoryOverride ?? databaseFactory,
       _documentsPathProvider = documentsPathProvider ?? _defaultDocumentsPathProvider,
       _bundledDbLoader = bundledDbLoader ?? _defaultBundledDbLoader;

  static const String bundledDbAssetPath = 'assets/db/quran.db';

  final DatabaseFactory _databaseFactory;
  final Future<String> Function() _documentsPathProvider;
  final Future<Uint8List?> Function() _bundledDbLoader;
  final String databaseName;

  Database? _db;
  Future<void>? _pendingInitialization;
  String? _dbPath;

  Database get db {
    final Database? current = _db;
    if (current == null) {
      throw StateError('Database has not been initialized. Call init() first.');
    }
    return current;
  }

  String? get dbPath => _dbPath;

  Future<void> init() {
    if (_db != null) {
      return Future<void>.value();
    }

    final Future<void>? pending = _pendingInitialization;
    if (pending != null) {
      return pending;
    }

    final Future<void> initialization = _initInternal();
    _pendingInitialization = initialization;
    return initialization.whenComplete(() {
      if (_db == null) {
        _pendingInitialization = null;
      }
    });
  }

  Future<void> _initInternal() async {
    final String documentsPath = await _documentsPathProvider();
    await Directory(documentsPath).create(recursive: true);

    _dbPath = p.join(documentsPath, databaseName);
    final File dbFile = File(_dbPath!);

    if (!await dbFile.exists()) {
      final Uint8List? bundledDbBytes = await _bundledDbLoader();
      if (bundledDbBytes != null && bundledDbBytes.isNotEmpty) {
        await dbFile.writeAsBytes(bundledDbBytes, flush: true);
      }
    }

    final Database database = await _databaseFactory.openDatabase(
      _dbPath!,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (Database db, int version) async {
          await _createSchema(db);
        },
        onOpen: (Database db) async {
          await _createSchema(db);
        },
      ),
    );

    _db = database;
    _pendingInitialization = null;
  }

  Future<void> dispose() async {
    final Database? current = _db;
    _db = null;
    _pendingInitialization = null;

    if (current != null) {
      await current.close();
    }
  }

  static Future<String> _defaultDocumentsPathProvider() async {
    try {
      final Directory directory = await getApplicationDocumentsDirectory();
      return directory.path;
    } on MissingPluginException {
      return p.join(Directory.systemTemp.path, 'quran_app');
    } on UnsupportedError {
      return p.join(Directory.systemTemp.path, 'quran_app');
    }
  }

  static Future<Uint8List?> _defaultBundledDbLoader() async {
    try {
      final ByteData data = await rootBundle.load(bundledDbAssetPath);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } on Object {
      return null;
    }
  }

  static Future<void> _createSchema(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS ayah(
        id INTEGER PRIMARY KEY,
        surah_no INTEGER NOT NULL,
        ayah_no INTEGER NOT NULL,
        surah_name_ar TEXT NOT NULL,
        surah_name_en TEXT NOT NULL DEFAULT '',
        text_uthmani TEXT NOT NULL,
        text_norm TEXT NOT NULL,
        text_plain TEXT NOT NULL DEFAULT '',
        text_plain_norm TEXT NOT NULL DEFAULT '',
        translation_en TEXT NOT NULL DEFAULT '',
        text_en TEXT NOT NULL DEFAULT ''
      );
    ''');

    final List<Map<String, Object?>> columns = await database.rawQuery('PRAGMA table_info(ayah)');
    final bool hasSurahNameEn = columns.any(
      (Map<String, Object?> row) => row['name'] == 'surah_name_en',
    );
    if (!hasSurahNameEn) {
      await database.execute("ALTER TABLE ayah ADD COLUMN surah_name_en TEXT NOT NULL DEFAULT ''");
    }

    final bool hasTextEn = columns.any((Map<String, Object?> row) => row['name'] == 'text_en');
    if (!hasTextEn) {
      await database.execute("ALTER TABLE ayah ADD COLUMN text_en TEXT NOT NULL DEFAULT ''");
    }

    final bool hasTranslationEn = columns.any(
      (Map<String, Object?> row) => row['name'] == 'translation_en',
    );
    if (!hasTranslationEn) {
      await database.execute("ALTER TABLE ayah ADD COLUMN translation_en TEXT NOT NULL DEFAULT ''");
    }

    final bool hasTextPlain = columns.any(
      (Map<String, Object?> row) => row['name'] == 'text_plain',
    );
    if (!hasTextPlain) {
      await database.execute("ALTER TABLE ayah ADD COLUMN text_plain TEXT NOT NULL DEFAULT ''");
    }

    final bool hasTextPlainNorm = columns.any(
      (Map<String, Object?> row) => row['name'] == 'text_plain_norm',
    );
    if (!hasTextPlainNorm) {
      await database.execute(
        "ALTER TABLE ayah ADD COLUMN text_plain_norm TEXT NOT NULL DEFAULT ''",
      );
    }

    // Backfill the canonical translation_en column from legacy text_en if needed.
    await database.execute('''
      UPDATE ayah
      SET translation_en = text_en
      WHERE TRIM(translation_en) = '' AND TRIM(text_en) <> ''
    ''');

    // Backfill plain-text columns for legacy databases that do not have MASAQ data yet.
    await database.execute('''
      UPDATE ayah
      SET text_plain = text_norm
      WHERE TRIM(text_plain) = '' AND TRIM(text_norm) <> ''
    ''');

    await database.execute('''
      UPDATE ayah
      SET text_plain_norm = text_norm
      WHERE TRIM(text_plain_norm) = '' AND TRIM(text_norm) <> ''
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS token_index(
        token TEXT NOT NULL,
        ayah_id INTEGER NOT NULL,
        PRIMARY KEY(token, ayah_id)
      );
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_token_index_token
      ON token_index(token);
    ''');
  }
}
