import 'package:flutter/widgets.dart';

import '../../core/di/service_locator.dart';
import '../../services/ads/ads_service.dart';

class AdBannerSlot extends StatelessWidget {
  const AdBannerSlot({super.key, this.height = 60});

  final double height;

  @override
  Widget build(BuildContext context) {
    Widget banner = const SizedBox.shrink();

    if (serviceLocator.isRegistered<AdsService>()) {
      try {
        banner = serviceLocator<AdsService>().banner();
      } on Object {
        banner = const SizedBox.shrink();
      }
    }

    return SizedBox(
      height: height,
      child: Align(alignment: Alignment.center, child: banner),
    );
  }
}
