import 'package:flutter/widgets.dart';

import '../../core/logging/app_logger.dart';
import 'ads_service.dart';

class NoAdsService implements AdsService {
  NoAdsService(this._logger);

  final AppLogger _logger;

  @override
  Future<void> init() async {
    _logger.info('NoAdsService initialized. Ads are disabled.');
  }

  @override
  Widget banner({Key? key}) {
    return SizedBox.shrink(key: key);
  }

  @override
  Future<void> maybeShowInterstitial(String trigger) async {
    _logger.debug('NoAdsService ignored interstitial trigger: $trigger');
  }

  @override
  void dispose() {
    _logger.info('NoAdsService disposed.');
  }
}
