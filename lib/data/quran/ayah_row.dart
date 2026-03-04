class AyahRow {
  const AyahRow({
    required this.id,
    required this.surahNo,
    required this.ayahNo,
    required this.surahNameAr,
    this.surahNameEn = '',
    required this.textUthmani,
    required this.textNorm,
    this.textPlain = '',
    this.textPlainNorm = '',
    this.translationEn = '',
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

  // Backward-compatible alias used by older UI/tests.
  String get textEn => translationEn;
  String get searchTextNorm => textPlainNorm.isNotEmpty ? textPlainNorm : textNorm;

  factory AyahRow.fromMap(Map<String, Object?> map) {
    return AyahRow(
      id: map['id'] as int,
      surahNo: map['surah_no'] as int,
      ayahNo: map['ayah_no'] as int,
      surahNameAr: map['surah_name_ar'] as String,
      surahNameEn: (map['surah_name_en'] as String?) ?? '',
      textUthmani: map['text_uthmani'] as String,
      textNorm: map['text_norm'] as String,
      textPlain: (map['text_plain'] as String?) ?? '',
      textPlainNorm: (map['text_plain_norm'] as String?) ?? ((map['text_norm'] as String?) ?? ''),
      translationEn: (map['translation_en'] as String?) ?? (map['text_en'] as String?) ?? '',
    );
  }
}
