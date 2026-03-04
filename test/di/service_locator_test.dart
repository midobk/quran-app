import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app/core/di/service_locator.dart';
import 'package:quran_app/services/ads/ads_service.dart';
import 'package:quran_app/services/ads/no_ads_service.dart';

void main() {
  setUp(() async {
    await resetDependencies();
    await setupDependencies();
  });

  tearDown(() async {
    await resetDependencies();
  });

  test('resolves AdsService as NoAdsService by default', () {
    final AdsService adsService = serviceLocator<AdsService>();

    expect(adsService, isA<NoAdsService>());
  });
}
