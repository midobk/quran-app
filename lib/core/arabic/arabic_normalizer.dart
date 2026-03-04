class ArabicNormalizer {
  const ArabicNormalizer({this.mapTaMarbutaToHa = true});

  final bool mapTaMarbutaToHa;

  static final RegExp _harakatAndQuranMarksPattern = RegExp(
    r'[\u0610-\u061A\u0640\u064B-\u065F\u0670\u06D6-\u06ED\u08D3-\u08FF]',
  );
  static final RegExp _nonArabicLetterOrWhitespacePattern = RegExp(
    r'[^\u0621-\u063A\u0641-\u064A\s]',
  );
  static final RegExp _multiWhitespacePattern = RegExp(r'\s+');

  static const Map<String, String> _baseLetterMap = <String, String>{
    'أ': 'ا',
    'إ': 'ا',
    'آ': 'ا',
    'ٱ': 'ا',
    'ؤ': 'و',
    'ئ': 'ي',
    'ى': 'ي',
  };

  String normalize(String input) {
    if (input.isEmpty) {
      return '';
    }

    // Normalization improves Quran search recall for ASR/noisy text by
    // removing diacritics and unifying common letter variants.
    String normalized = input.replaceAll(_harakatAndQuranMarksPattern, '');

    for (final MapEntry<String, String> mapping in _baseLetterMap.entries) {
      normalized = normalized.replaceAll(mapping.key, mapping.value);
    }

    if (mapTaMarbutaToHa) {
      normalized = normalized.replaceAll('ة', 'ه');
    }

    normalized = normalized.replaceAll(_nonArabicLetterOrWhitespacePattern, ' ');
    normalized = normalized.replaceAll(_multiWhitespacePattern, ' ').trim();
    return normalized;
  }

  List<String> tokenize(String normalized) {
    if (normalized.isEmpty) {
      return <String>[];
    }

    return normalized
        .split(_multiWhitespacePattern)
        .where((String token) => token.isNotEmpty)
        .toList(growable: false);
  }
}
