import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app/core/arabic/arabic_normalizer.dart';
import 'package:quran_app/services/database/masaq_plain_text_builder.dart';

void main() {
  test('reconstructs ayah plain text by grouping (sura, verse, column5)', () async {
    final File sampleFile = File('test/resources/masaq_sample.csv');
    final String csvText = await sampleFile.readAsString();

    final List<MasaqWordRow> rows = MasaqPlainTextBuilder.parseRowsFromCsv(csvText);
    final Map<MasaqAyahKey, String> ayahText = MasaqPlainTextBuilder.reconstruct(rows);

    expect(ayahText[const MasaqAyahKey(surahNo: 1, ayahNo: 1)], 'بسم الله الرحمن الرحيم');
    expect(ayahText[const MasaqAyahKey(surahNo: 1, ayahNo: 2)], 'الحمد لله رب العالمين');
  });

  test('normalizing MASAQ plain keeps العالمين form', () async {
    final File sampleFile = File('test/resources/masaq_sample.csv');
    final String csvText = await sampleFile.readAsString();
    final List<MasaqWordRow> rows = MasaqPlainTextBuilder.parseRowsFromCsv(csvText);
    final Map<MasaqAyahKey, String> ayahText = MasaqPlainTextBuilder.reconstruct(rows);

    const ArabicNormalizer normalizer = ArabicNormalizer();
    final String normalized = normalizer.normalize(
      ayahText[const MasaqAyahKey(surahNo: 1, ayahNo: 2)]!,
    );

    expect(normalized, contains('العالمين'));
    expect(normalized, isNot(contains('العلمين')));
  });
}
