import 'dart:convert';

class MasaqAyahKey {
  const MasaqAyahKey({required this.surahNo, required this.ayahNo});

  final int surahNo;
  final int ayahNo;

  @override
  bool operator ==(Object other) {
    return other is MasaqAyahKey && other.surahNo == surahNo && other.ayahNo == ayahNo;
  }

  @override
  int get hashCode => Object.hash(surahNo, ayahNo);

  @override
  String toString() => 'MasaqAyahKey(surahNo: $surahNo, ayahNo: $ayahNo)';
}

class MasaqWordRow {
  const MasaqWordRow({
    required this.surahNo,
    required this.ayahNo,
    required this.column5,
    required this.withoutDiacritics,
  });

  final int surahNo;
  final int ayahNo;
  final int column5;
  final String withoutDiacritics;
}

class MasaqPlainTextBuilder {
  const MasaqPlainTextBuilder._();

  static List<MasaqWordRow> parseRowsFromCsv(String csvText) {
    final List<String> lines = const LineSplitter()
        .convert(csvText)
        .where((String line) => line.trim().isNotEmpty)
        .toList(growable: false);

    if (lines.isEmpty) {
      return const <MasaqWordRow>[];
    }

    final List<String> header = _parseCsvLine(lines.first);
    final int suraIndex = header.indexOf('Sura_No');
    final int verseIndex = header.indexOf('Verse_No');
    final int column5Index = header.indexOf('Column5');
    final int withoutDiacriticsIndex = header.indexOf('Without_Diacritics');

    if (suraIndex < 0 || verseIndex < 0 || column5Index < 0 || withoutDiacriticsIndex < 0) {
      throw const FormatException(
        'Missing required MASAQ columns. Expected Sura_No, Verse_No, Column5, Without_Diacritics.',
      );
    }

    final List<MasaqWordRow> rows = <MasaqWordRow>[];

    for (final String line in lines.skip(1)) {
      final List<String> cells = _parseCsvLine(line);
      final int? suraNo = _tryParseIndex(cells, suraIndex);
      final int? verseNo = _tryParseIndex(cells, verseIndex);
      final int? column5 = _tryParseIndex(cells, column5Index);
      if (suraNo == null || verseNo == null || column5 == null) {
        continue;
      }

      final String withoutDiacritics = _getCell(cells, withoutDiacriticsIndex).trim();
      rows.add(
        MasaqWordRow(
          surahNo: suraNo,
          ayahNo: verseNo,
          column5: column5,
          withoutDiacritics: withoutDiacritics,
        ),
      );
    }

    return rows;
  }

  static Map<MasaqAyahKey, String> reconstruct(Iterable<MasaqWordRow> rows) {
    final Map<_WordPositionKey, String> firstNonEmptyByWordPosition = <_WordPositionKey, String>{};

    for (final MasaqWordRow row in rows) {
      final String token = row.withoutDiacritics.trim();
      if (token.isEmpty) {
        continue;
      }

      final _WordPositionKey positionKey = _WordPositionKey(
        surahNo: row.surahNo,
        ayahNo: row.ayahNo,
        column5: row.column5,
      );
      firstNonEmptyByWordPosition.putIfAbsent(positionKey, () => token);
    }

    final Map<MasaqAyahKey, Map<int, String>> ayahWords = <MasaqAyahKey, Map<int, String>>{};

    for (final MapEntry<_WordPositionKey, String> entry in firstNonEmptyByWordPosition.entries) {
      final MasaqAyahKey ayahKey = MasaqAyahKey(
        surahNo: entry.key.surahNo,
        ayahNo: entry.key.ayahNo,
      );
      final Map<int, String> wordsByOrder = ayahWords.putIfAbsent(ayahKey, () => <int, String>{});
      wordsByOrder[entry.key.column5] = entry.value;
    }

    final Map<MasaqAyahKey, String> out = <MasaqAyahKey, String>{};
    for (final MapEntry<MasaqAyahKey, Map<int, String>> entry in ayahWords.entries) {
      final List<int> sortedKeys = entry.value.keys.toList(growable: false)..sort();
      final List<String> orderedWords = sortedKeys
          .map((int key) => entry.value[key]!.trim())
          .where((String value) => value.isNotEmpty)
          .toList(growable: false);

      out[entry.key] = orderedWords.join(' ');
    }

    return out;
  }

  static int? _tryParseIndex(List<String> cells, int index) {
    if (index < 0 || index >= cells.length) {
      return null;
    }
    return int.tryParse(cells[index].trim());
  }

  static String _getCell(List<String> cells, int index) {
    if (index < 0 || index >= cells.length) {
      return '';
    }
    return cells[index];
  }

  static List<String> _parseCsvLine(String line) {
    final List<String> cells = <String>[];
    final StringBuffer cell = StringBuffer();

    bool inQuotes = false;
    int i = 0;
    while (i < line.length) {
      final String char = line[i];
      if (char == '"') {
        final bool isEscapedQuote = inQuotes && i + 1 < line.length && line[i + 1] == '"';
        if (isEscapedQuote) {
          cell.write('"');
          i += 2;
          continue;
        }
        inQuotes = !inQuotes;
        i++;
        continue;
      }

      if (char == ',' && !inQuotes) {
        cells.add(cell.toString());
        cell.clear();
        i++;
        continue;
      }

      cell.write(char);
      i++;
    }

    cells.add(cell.toString());
    return cells;
  }
}

class _WordPositionKey {
  const _WordPositionKey({required this.surahNo, required this.ayahNo, required this.column5});

  final int surahNo;
  final int ayahNo;
  final int column5;

  @override
  bool operator ==(Object other) {
    return other is _WordPositionKey &&
        other.surahNo == surahNo &&
        other.ayahNo == ayahNo &&
        other.column5 == column5;
  }

  @override
  int get hashCode => Object.hash(surahNo, ayahNo, column5);
}
