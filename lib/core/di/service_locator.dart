import 'package:get_it/get_it.dart';

import '../../data/quran/quran_repository.dart';
import '../../services/ads/ads_service.dart';
import '../../services/ads/no_ads_service.dart';
import '../../services/ads/stub_ads_service.dart';
import '../../services/asr/asr_service.dart';
import '../../services/asr/fake_asr_service.dart';
import '../../services/asr/model_manager.dart';
import '../../services/asr/whisper_cpp_service.dart';
import '../../services/audio/mic_service.dart';
import '../../services/database/database_service.dart';
import '../../services/diagnostics/diagnostics_store.dart';
import '../../services/search/quran_search_engine.dart';
import '../../services/search/vocab_matcher.dart';
import '../../services/search/vocab_service.dart';
import '../../services/theme/theme_service.dart';
import '../logging/app_logger.dart';
import '../navigation/app_router.dart';

final GetIt serviceLocator = GetIt.instance;
AdsMode _currentAdsMode = AdsMode.off;

enum AdsMode { off, stub }

AdsMode get currentAdsMode => _currentAdsMode;

Future<void> setupDependencies({bool useStubAds = false}) async {
  if (serviceLocator.isRegistered<AppLogger>()) {
    return;
  }

  serviceLocator.registerLazySingleton<AppLogger>(AppLogger.new);
  serviceLocator.registerLazySingleton<AppRouter>(AppRouter.new);
  _currentAdsMode = useStubAds ? AdsMode.stub : AdsMode.off;
  serviceLocator.registerLazySingleton<AdsService>(
    () => _currentAdsMode == AdsMode.stub
        ? StubAdsService(serviceLocator<AppLogger>())
        : NoAdsService(serviceLocator<AppLogger>()),
    dispose: (AdsService service) => service.dispose(),
  );
  serviceLocator.registerLazySingleton<AsrService>(
    FakeAsrService.new,
    dispose: (AsrService service) => service.dispose(),
  );
  serviceLocator.registerLazySingleton<ModelManager>(ModelManager.new);
  serviceLocator.registerLazySingleton<WhisperCppService>(
    () => WhisperCppService(logger: serviceLocator<AppLogger>()),
    dispose: (WhisperCppService service) => service.dispose(),
  );
  serviceLocator.registerLazySingleton<MicService>(
    () => MicService(logger: serviceLocator<AppLogger>()),
    dispose: (MicService service) => service.dispose(),
  );
  serviceLocator.registerLazySingleton<DiagnosticsStore>(DiagnosticsStore.new);
  serviceLocator.registerLazySingleton<ThemeService>(
    () => ThemeService(logger: serviceLocator<AppLogger>()),
  );
  serviceLocator.registerLazySingleton<DatabaseService>(
    DatabaseService.new,
    dispose: (DatabaseService service) => service.dispose(),
  );
  serviceLocator.registerLazySingleton<QuranRepository>(
    () => QuranRepository(serviceLocator<DatabaseService>()),
  );
  serviceLocator.registerLazySingleton<VocabService>(
    () => VocabService(databaseService: serviceLocator<DatabaseService>()),
  );
  serviceLocator.registerLazySingleton<VocabMatcher>(
    () => VocabMatcher(vocabService: serviceLocator<VocabService>()),
  );
  serviceLocator.registerLazySingleton<QuranSearchEngine>(
    () => QuranSearchEngine(
      repository: serviceLocator<QuranRepository>(),
      vocabService: serviceLocator<VocabService>(),
      vocabMatcher: serviceLocator<VocabMatcher>(),
      logger: serviceLocator<AppLogger>(),
    ),
  );

  await serviceLocator<ThemeService>().init();
  await serviceLocator<AdsService>().init();
}

Future<void> switchAdsMode(AdsMode mode) async {
  if (!serviceLocator.isRegistered<AppLogger>()) {
    throw StateError('Dependencies are not initialized.');
  }

  if (serviceLocator.isRegistered<AdsService>() && _currentAdsMode == mode) {
    return;
  }

  if (serviceLocator.isRegistered<AdsService>()) {
    await serviceLocator.unregister<AdsService>(
      disposingFunction: (AdsService service) => service.dispose(),
    );
  }

  _currentAdsMode = mode;
  serviceLocator.registerLazySingleton<AdsService>(
    () => mode == AdsMode.stub
        ? StubAdsService(serviceLocator<AppLogger>())
        : NoAdsService(serviceLocator<AppLogger>()),
    dispose: (AdsService service) => service.dispose(),
  );
  await serviceLocator<AdsService>().init();
}

Future<void> resetDependencies({bool disposeServices = false}) {
  _currentAdsMode = AdsMode.off;
  return serviceLocator.reset(dispose: disposeServices);
}
