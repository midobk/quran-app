import 'package:flutter/material.dart';

import '../../core/logging/app_logger.dart';
import 'ads_service.dart';

class StubAdsService implements AdsService {
  StubAdsService(this._logger);

  final AppLogger _logger;

  bool _isInitialized = false;
  final List<String> _triggerLog = <String>[];

  List<String> get triggerLog => List<String>.unmodifiable(_triggerLog);

  @override
  Future<void> init() async {
    _isInitialized = true;
    _logger.info('StubAdsService initialized for placeholder ad flows.');
  }

  @override
  Widget banner({Key? key}) {
    return Container(
      key: key,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text('Ad Banner Placeholder (Offline Stub)'),
    );
  }

  @override
  Future<void> maybeShowInterstitial(String trigger) async {
    _triggerLog.add(trigger);
    _logger.debug('StubAdsService interstitial trigger: $trigger (initialized: $_isInitialized)');
  }

  @override
  void dispose() {
    _isInitialized = false;
    _triggerLog.clear();
    _logger.info('StubAdsService disposed.');
  }
}
