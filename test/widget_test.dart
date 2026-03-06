import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app/core/di/service_locator.dart';
import 'package:quran_app/ui/app.dart';

void main() {
  setUp(() async {
    await resetDependencies();
    await setupDependencies();
  });

  tearDown(() async {
    await resetDependencies();
  });

  testWidgets('QuranApp boots to HomeScreen', (WidgetTester tester) async {
    await tester.pumpWidget(const QuranApp());
    await tester.pumpAndSettle();

    expect(find.text('Quran Listener'), findsOneWidget);
    expect(find.text('Start Listening'), findsOneWidget);
  });
}
