import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app/core/di/service_locator.dart';
import 'package:quran_app/services/ads/ads_service.dart';
import 'package:quran_app/services/ads/stub_ads_service.dart';

void main() {
  setUp(() async {
    await resetDependencies();
    await setupDependencies();
  });

  tearDown(() async {
    await resetDependencies();
  });

  test('switching ads mode to stub records interstitial triggers', () async {
    await switchAdsMode(AdsMode.stub);

    final AdsService adsService = serviceLocator<AdsService>();
    expect(adsService, isA<StubAdsService>());

    await adsService.maybeShowInterstitial('locked_result');

    final StubAdsService stub = adsService as StubAdsService;
    expect(stub.triggerLog, contains('locked_result'));
  });
}
