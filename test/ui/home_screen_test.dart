import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app/core/di/service_locator.dart';
import 'package:quran_app/features/home/home_screen.dart';

void main() {
  setUp(() async {
    await resetDependencies();
    await setupDependencies();
  });

  tearDown(() async {
    await resetDependencies();
  });

  testWidgets('HomeScreen renders primary listening and utility actions', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

    expect(find.text('Start Listening'), findsOneWidget);
    expect(find.byIcon(Icons.settings_rounded), findsOneWidget);
    expect(find.byIcon(Icons.monitor_heart_rounded), findsOneWidget);
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
  });
}
