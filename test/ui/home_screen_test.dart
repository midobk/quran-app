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

  testWidgets('HomeScreen renders all required action buttons', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

    expect(find.widgetWithText(ElevatedButton, 'Start Listening'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Quran Search (Debug)'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Settings'), findsOneWidget);
  });
}
