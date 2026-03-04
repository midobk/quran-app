import 'package:get_it/get_it.dart';

import '../../services/ads/ads_service.dart';
import '../../services/ads/no_ads_service.dart';
import '../../services/ads/stub_ads_service.dart';
import '../logging/app_logger.dart';
import '../navigation/app_router.dart';

final GetIt serviceLocator = GetIt.instance;

Future<void> setupDependencies({bool useStubAds = false}) async {
  if (serviceLocator.isRegistered<AppLogger>()) {
    return;
  }

  serviceLocator.registerLazySingleton<AppLogger>(AppLogger.new);
  serviceLocator.registerLazySingleton<AppRouter>(AppRouter.new);
  serviceLocator.registerLazySingleton<AdsService>(
    () => useStubAds
        ? StubAdsService(serviceLocator<AppLogger>())
        : NoAdsService(serviceLocator<AppLogger>()),
  );

  await serviceLocator<AdsService>().init();
}

Future<void> resetDependencies() {
  return serviceLocator.reset();
}
