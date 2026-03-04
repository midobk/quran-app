import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app/core/arabic/arabic_normalizer.dart';

void main() {
  group('ArabicNormalizer.normalize', () {
    const ArabicNormalizer normalizer = ArabicNormalizer();

    test('removes basic harakat', () {
      expect(normalizer.normalize('بِسْمِ'), 'بسم');
    });

    test('removes shadda and dagger alif', () {
      expect(normalizer.normalize('الرَّحْمٰنُ'), 'الرحمن');
    });

    test('removes Quranic pause mark', () {
      expect(normalizer.normalize('الْحَمْدُ لِلَّهِۚ'), 'الحمد لله');
    });

    test('removes Quranic ornaments and marks in verse-like input', () {
      expect(
        normalizer.normalize('۞سَلَامٌۚ قَوْلًا مِن رَّبٍّ رَّحِيمٍۖ'),
        'سلام قولا من رب رحيم',
      );
    });

    test('removes tatweel', () {
      expect(normalizer.normalize('الـســلام'), 'السلام');
    });

    test('normalizes hamza variants to bare alif', () {
      expect(normalizer.normalize('أمير وإمام وآدم'), 'امير وامام وادم');
    });

    test('normalizes waw/ya hamza forms and alif maqsura', () {
      expect(normalizer.normalize('رؤيا سئل هدى'), 'رويا سيل هدي');
    });

    test('maps ta marbuta to ha by default', () {
      expect(normalizer.normalize('رحمة واسعة'), 'رحمه واسعه');
    });

    test('does not map ta marbuta when disabled', () {
      const ArabicNormalizer localNormalizer = ArabicNormalizer(mapTaMarbutaToHa: false);
      expect(localNormalizer.normalize('رحمة واسعة'), 'رحمة واسعة');
    });

    test('maps alif wasla to bare alif in Quran-like text', () {
      expect(normalizer.normalize('ٱلْحَمْدُ لِلَّهِ رَبِّ ٱلْعَٰلَمِينَ'), 'الحمد لله رب العلمين');
    });

    test('replaces punctuation with spaces', () {
      expect(normalizer.normalize('سلام،عليكم! كيف؟'), 'سلام عليكم كيف');
    });

    test('removes latin text and digits', () {
      expect(normalizer.normalize('abc123سلام---عليكم'), 'سلام عليكم');
    });

    test('collapses multiple whitespace and trims', () {
      expect(normalizer.normalize('  سلام   عليكم \n ورحمة\tالله  '), 'سلام عليكم ورحمه الله');
    });

    test('returns empty string for empty input', () {
      expect(normalizer.normalize(''), '');
    });

    test('returns empty string for punctuation only input', () {
      expect(normalizer.normalize('!؟،؛.-_'), '');
    });

    test('normalizes Quran-like ayah snippet', () {
      expect(
        normalizer.normalize('إِنَّا أَعْطَيْنَاكَ الْكَوْثَرَ۝ فَصَلِّ لِرَبِّكَ وَانْحَرْۚ'),
        'انا اعطيناك الكوثر فصل لربك وانحر',
      );
    });
  });

  group('ArabicNormalizer.tokenize', () {
    const ArabicNormalizer normalizer = ArabicNormalizer();

    test('splits normalized sentence into tokens', () {
      expect(normalizer.tokenize('السلام عليكم ورحمه الله'), <String>[
        'السلام',
        'عليكم',
        'ورحمه',
        'الله',
      ]);
    });

    test('removes empty tokens from extra spaces', () {
      expect(normalizer.tokenize('  سلام   عليكم  '), <String>['سلام', 'عليكم']);
    });

    test('returns empty list for blank input', () {
      expect(normalizer.tokenize(''), <String>[]);
      expect(normalizer.tokenize('   '), <String>[]);
    });
  });
}
