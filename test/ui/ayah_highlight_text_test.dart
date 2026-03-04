import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app/ui/widgets/ayah_highlight_text.dart';

void main() {
  testWidgets('highlights contiguous matched token range when mapping succeeds', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AyahHighlightText(
            uthmaniText: 'اللَّهُ نُورُ السَّمَاوَاتِ وَالْأَرْضِ',
            ayahNormalizedTokens: <String>['الله', 'نور', 'السماوات', 'والارض'],
            matchStartTokenIndex: 0,
            matchEndTokenIndex: 2,
            matchedTokens: <String>['الله', 'نور', 'السماوات'],
          ),
        ),
      ),
    );

    final List<TextSpan> tokenSpans = _extractTokenSpans(tester);
    expect(tokenSpans.length, 4);
    expect(_isHighlighted(tokenSpans[0]), isTrue);
    expect(_isHighlighted(tokenSpans[1]), isTrue);
    expect(_isHighlighted(tokenSpans[2]), isTrue);
    expect(_isHighlighted(tokenSpans[3]), isFalse);
  });

  testWidgets('falls back to token-level highlighting when contiguous mapping fails', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AyahHighlightText(
            uthmaniText: 'اللَّهُ فِي السَّمَاوَاتِ',
            ayahNormalizedTokens: <String>['الله', 'السماوات'],
            matchStartTokenIndex: 0,
            matchEndTokenIndex: 1,
            matchedTokens: <String>['الله', 'السماوات'],
          ),
        ),
      ),
    );

    final List<TextSpan> tokenSpans = _extractTokenSpans(tester);
    expect(tokenSpans.length, 3);
    expect(_isHighlighted(tokenSpans[0]), isTrue);
    expect(_isHighlighted(tokenSpans[1]), isFalse);
    expect(_isHighlighted(tokenSpans[2]), isTrue);
  });

  testWidgets('renders rich RTL text safely', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AyahHighlightText(
            uthmaniText: 'وَهُوَ الَّذِي يُحْيِي وَيُمِيتُ وَإِلَيْهِ تُرْجَعُونَ',
            ayahNormalizedTokens: <String>['وهو', 'الذي', 'يحيي', 'ويميت', 'واليه', 'ترجعون'],
            matchStartTokenIndex: null,
            matchEndTokenIndex: null,
            matchedTokens: <String>['يحيي', 'ويميت'],
          ),
        ),
      ),
    );

    expect(find.byType(AyahHighlightText), findsOneWidget);
    final RichText richText = tester.widget<RichText>(find.byType(RichText));
    expect(richText.textDirection, TextDirection.rtl);
    expect(tester.takeException(), isNull);
  });
}

bool _isHighlighted(TextSpan span) {
  return span.style?.backgroundColor != null;
}

List<TextSpan> _extractTokenSpans(WidgetTester tester) {
  final RichText richText = tester.widget<RichText>(find.byType(RichText));
  final TextSpan root = richText.text as TextSpan;
  final List<TextSpan> allSpans = <TextSpan>[];
  _collectTextSpans(root, allSpans);

  return allSpans
      .where((TextSpan span) => (span.text ?? '').trim().isNotEmpty)
      .toList(growable: false);
}

void _collectTextSpans(TextSpan span, List<TextSpan> output) {
  output.add(span);
  final List<InlineSpan>? children = span.children;
  if (children == null || children.isEmpty) {
    return;
  }
  for (final InlineSpan child in children) {
    if (child is TextSpan) {
      _collectTextSpans(child, output);
    }
  }
}
