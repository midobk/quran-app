import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app/core/di/service_locator.dart';
import 'package:quran_app/ui/widgets/ad_banner_slot.dart';

void main() {
  group('without DI', () {
    setUp(() async {
      await resetDependencies();
    });

    tearDown(() async {
      await resetDependencies();
    });

    testWidgets('AdBannerSlot builds safely without DI', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: AdBannerSlot())));

      expect(find.byType(AdBannerSlot), findsOneWidget);
    });
  });

  group('with DI', () {
    setUp(() async {
      await resetDependencies();
      await setupDependencies();
    });

    tearDown(() async {
      await resetDependencies();
    });

    testWidgets('AdBannerSlot builds with registered ads service', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: AdBannerSlot())));

      expect(find.byType(AdBannerSlot), findsOneWidget);
    });
  });
}
