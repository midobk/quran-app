import 'package:flutter/widgets.dart';

abstract class AdsService {
  Future<void> init();
  Widget banner({Key? key});
  Future<void> maybeShowInterstitial(String trigger);
  void dispose();
}
