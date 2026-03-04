import 'package:flutter/material.dart';

import '../../core/arabic/arabic_normalizer.dart';

class AyahHighlightText extends StatelessWidget {
  const AyahHighlightText({
    required this.uthmaniText,
    required this.ayahNormalizedTokens,
    required this.matchStartTokenIndex,
    required this.matchEndTokenIndex,
    required this.matchedTokens,
    super.key,
    this.style,
    this.highlightStyle,
  });

  final String uthmaniText;
  final List<String> ayahNormalizedTokens;
  final int? matchStartTokenIndex;
  final int? matchEndTokenIndex;
  final List<String> matchedTokens;
  final TextStyle? style;
  final TextStyle? highlightStyle;

  static const ArabicNormalizer _normalizer = ArabicNormalizer();
  static final RegExp _splitWhitespacePattern = RegExp(r'\s+');

  @override
  Widget build(BuildContext context) {
    final TextStyle baseStyle = style ?? DefaultTextStyle.of(context).style;
    final Color highlightColor = Theme.of(
      context,
    ).colorScheme.secondaryContainer.withValues(alpha: 0.8);
    final TextStyle activeHighlightStyle =
        highlightStyle ?? baseStyle.copyWith(backgroundColor: highlightColor);

    final List<String> displayTokens = _tokenizeDisplayTokens(uthmaniText);
    if (displayTokens.isEmpty) {
      return Text(
        uthmaniText,
        style: baseStyle,
        textDirection: TextDirection.rtl,
        textAlign: TextAlign.right,
        softWrap: true,
      );
    }

    final List<String> displayNormalizedTokens = displayTokens
        .map((String token) => _normalizer.normalize(token))
        .toList(growable: false);
    final List<bool> highlightMask = _buildHighlightMask(
      displayNormalizedTokens: displayNormalizedTokens,
    );

    final List<InlineSpan> spans = <InlineSpan>[];
    for (int i = 0; i < displayTokens.length; i++) {
      spans.add(
        TextSpan(
          text: displayTokens[i],
          style: highlightMask[i] ? activeHighlightStyle : baseStyle,
        ),
      );
      if (i != displayTokens.length - 1) {
        spans.add(TextSpan(text: ' ', style: baseStyle));
      }
    }

    return Text.rich(
      TextSpan(children: spans),
      textDirection: TextDirection.rtl,
      textAlign: TextAlign.right,
      softWrap: true,
    );
  }

  List<bool> _buildHighlightMask({required List<String> displayNormalizedTokens}) {
    final List<bool> mask = List<bool>.filled(displayNormalizedTokens.length, false);
    final List<String> phraseTokens = _resolvePhraseTokens();

    if (phraseTokens.isNotEmpty) {
      final int contiguousStart = _findContiguousRangeStart(
        haystack: displayNormalizedTokens,
        needle: phraseTokens,
      );
      if (contiguousStart >= 0) {
        final int contiguousEnd = contiguousStart + phraseTokens.length - 1;
        for (int i = contiguousStart; i <= contiguousEnd; i++) {
          mask[i] = true;
        }
        return mask;
      }
    }

    final Set<String> fallbackTokenSet = _buildFallbackTokenSet(phraseTokens: phraseTokens);
    if (fallbackTokenSet.isEmpty) {
      return mask;
    }

    bool hasAny = false;
    for (int i = 0; i < displayNormalizedTokens.length; i++) {
      final String token = displayNormalizedTokens[i];
      if (token.isNotEmpty && fallbackTokenSet.contains(token)) {
        mask[i] = true;
        hasAny = true;
      }
    }

    if (!hasAny) {
      return List<bool>.filled(displayNormalizedTokens.length, false);
    }
    return mask;
  }

  List<String> _resolvePhraseTokens() {
    if (matchStartTokenIndex != null &&
        matchEndTokenIndex != null &&
        matchStartTokenIndex! >= 0 &&
        matchEndTokenIndex! >= matchStartTokenIndex! &&
        matchEndTokenIndex! < ayahNormalizedTokens.length) {
      final List<String> rangeTokens = ayahNormalizedTokens
          .sublist(matchStartTokenIndex!, matchEndTokenIndex! + 1)
          .where((String token) => token.isNotEmpty)
          .toList(growable: false);
      if (rangeTokens.isNotEmpty) {
        return rangeTokens;
      }
    }

    return _normalizeTokenList(matchedTokens);
  }

  Set<String> _buildFallbackTokenSet({required List<String> phraseTokens}) {
    final Set<String> tokens = <String>{};
    tokens.addAll(phraseTokens);
    tokens.addAll(_normalizeTokenList(matchedTokens));
    tokens.removeWhere((String token) => token.isEmpty);
    return tokens;
  }

  List<String> _normalizeTokenList(List<String> input) {
    final List<String> tokens = <String>[];
    for (final String token in input) {
      if (token.trim().isEmpty) {
        continue;
      }
      tokens.addAll(_normalizer.tokenize(_normalizer.normalize(token)));
    }
    return tokens;
  }

  List<String> _tokenizeDisplayTokens(String text) {
    return text
        .trim()
        .split(_splitWhitespacePattern)
        .where((String token) => token.isNotEmpty)
        .toList(growable: false);
  }

  int _findContiguousRangeStart({required List<String> haystack, required List<String> needle}) {
    if (needle.isEmpty || haystack.length < needle.length) {
      return -1;
    }

    for (int start = 0; start <= haystack.length - needle.length; start++) {
      bool allMatch = true;
      for (int i = 0; i < needle.length; i++) {
        if (haystack[start + i] != needle[i]) {
          allMatch = false;
          break;
        }
      }
      if (allMatch) {
        return start;
      }
    }

    return -1;
  }
}
