abstract class AsrService {
  Future<void> init();
  Future<String> transcribeWarmupSample({Duration duration = const Duration(seconds: 10)});
  Stream<String> liveTranscriptStream();
  Future<void> dispose();
}
