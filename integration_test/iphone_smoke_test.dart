import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:quran_app/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('iphone smoke test covers home, search, settings, and listening flow', (
    WidgetTester tester,
  ) async {
    await app.main();
    await _pumpUntilVisible(tester, find.text('Start Listening'));

    expect(find.text('Quran Search (Debug)'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.text('Quran Search (Debug)'));
    await tester.pumpAndSettle();
    expect(find.text('Quran Search (Debug)'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'الحمد لله رب العالمين');
    await tester.tap(find.text('Search'));
    await tester.pump();
    await _pumpUntil(
      tester,
      () =>
          find.byType(Card).evaluate().isNotEmpty ||
          find.textContaining('No ranked matches').evaluate().isNotEmpty ||
          find.textContaining('Search failed').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 12),
    );
    expect(find.textContaining('Search failed'), findsNothing);
    expect(find.byType(Card), findsWidgets);

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Developer Tools'), findsOneWidget);
    expect(find.text('Diagnostics'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start Listening'));
    await tester.pump();
    await _pumpUntil(
      tester,
      () =>
          find.text('Listening Warmup').evaluate().isNotEmpty ||
          find.text('Model Missing').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 12),
    );
    expect(find.text('Model Missing'), findsNothing);

    await _pumpUntil(
      tester,
      () =>
          find.text('Results').evaluate().isNotEmpty ||
          find.text('Live Display').evaluate().isNotEmpty ||
          find.textContaining('Warmup failed').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 25),
    );
    expect(find.textContaining('Warmup failed'), findsNothing);
    expect(
      find.text('Results').evaluate().isNotEmpty || find.text('Live Display').evaluate().isNotEmpty,
      isTrue,
    );
  });
}

Future<void> _pumpUntilVisible(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 10),
  Duration step = const Duration(milliseconds: 250),
}) {
  return _pumpUntil(tester, () => finder.evaluate().isNotEmpty, timeout: timeout, step: step);
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 10),
  Duration step = const Duration(milliseconds: 250),
}) async {
  final DateTime end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(step);
    if (predicate()) {
      return;
    }
  }

  throw TestFailure('Timed out after ${timeout.inSeconds}s waiting for condition.');
}
