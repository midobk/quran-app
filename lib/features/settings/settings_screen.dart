import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/di/service_locator.dart';
import '../../data/quran/quran_repository.dart';
import '../../services/asr/model_manager.dart';
import '../../services/asr/whisper_cpp_service.dart';
import '../../services/audio/mic_service.dart';
import '../../services/indexing/quran_index_builder.dart';
import '../../services/theme/theme_service.dart';
import 'db_health_check_screen.dart';
import 'diagnostics_screen.dart';
import 'model_missing_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final QuranRepository _repository;
  late final ModelManager _modelManager;
  late final WhisperCppService _whisperService;
  late final MicService _micService;
  late final ThemeService _themeService;

  bool _isRebuilding = false;
  bool _isModelBusy = false;
  bool _isRunningWhisperTest = false;
  bool _isSwitchingAdsMode = false;
  AdsMode _adsMode = currentAdsMode;
  AppThemeMode _themeMode = AppThemeMode.system;
  ModelStatus? _modelStatus;
  String? _whisperTestSummary;
  String? _micDebugSummary;
  MicStats? _latestMicStats;
  StreamSubscription<MicStats>? _micStatsSubscription;
  Timer? _whisperTestWatchdog;
  int _whisperTestRunId = 0;

  @override
  void initState() {
    super.initState();
    _repository = serviceLocator<QuranRepository>();
    _modelManager = serviceLocator<ModelManager>();
    _whisperService = serviceLocator<WhisperCppService>();
    _micService = serviceLocator<MicService>();
    _themeService = serviceLocator<ThemeService>();
    _themeMode = _themeService.themeMode;
    _loadModelStatus();
    _micStatsSubscription = _micService.statsStream.listen((MicStats stats) {
      if (!mounted) {
        return;
      }
      setState(() {
        _latestMicStats = stats;
      });
    });
  }

  @override
  void dispose() {
    unawaited(_micStatsSubscription?.cancel());
    _whisperTestWatchdog?.cancel();
    super.dispose();
  }

  Future<void> _onRebuildIndexPressed() async {
    if (_isRebuilding) {
      return;
    }

    setState(() {
      _isRebuilding = true;
    });

    final ValueNotifier<IndexProgress> progressNotifier = ValueNotifier<IndexProgress>(
      const IndexProgress(processed: 0, total: 0, currentAyahId: null),
    );

    bool isDialogOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('Rebuilding Index'),
            content: ValueListenableBuilder<IndexProgress>(
              valueListenable: progressNotifier,
              builder: (BuildContext context, IndexProgress progress, Widget? child) {
                final int percent = (progress.percent * 100).round();
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    LinearProgressIndicator(
                      value: progress.total == 0 ? 1 : progress.percent.clamp(0, 1).toDouble(),
                    ),
                    const SizedBox(height: 12),
                    Text('Progress: $percent%'),
                    Text('Processed: ${progress.processed}/${progress.total}'),
                    Text('Current ayah id: ${progress.currentAyahId ?? '-'}'),
                  ],
                );
              },
            ),
          ),
        );
      },
    );

    void closeDialogIfOpen() {
      if (!mounted || !isDialogOpen) {
        return;
      }

      Navigator.of(context, rootNavigator: true).pop();
      isDialogOpen = false;
    }

    try {
      await _repository.rebuildIndex(
        onProgress: (IndexProgress progress) {
          progressNotifier.value = progress;
        },
      );

      if (mounted) {
        closeDialogIfOpen();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Index rebuild completed.')));
      }
    } catch (error) {
      if (mounted) {
        closeDialogIfOpen();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Index rebuild failed: $error')));
      }
    } finally {
      progressNotifier.dispose();
      if (mounted) {
        setState(() {
          _isRebuilding = false;
        });
      }
    }
  }

  Future<void> _openDbHealthCheck() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const DBHealthCheckScreen()));
  }

  Future<void> _openDiagnostics() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const DiagnosticsScreen()));
  }

  Future<void> _onAdsModeChanged(AdsMode? mode) async {
    if (mode == null || mode == _adsMode || _isSwitchingAdsMode) {
      return;
    }

    setState(() {
      _isSwitchingAdsMode = true;
    });

    try {
      await switchAdsMode(mode);
      if (!mounted) {
        return;
      }
      setState(() {
        _adsMode = mode;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Ads mode applied immediately (session-only).')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to switch ads mode: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _isSwitchingAdsMode = false;
        });
      }
    }
  }

  Future<void> _onThemeModeChanged(AppThemeMode? mode) async {
    if (mode == null || mode == _themeMode) {
      return;
    }

    await _themeService.setThemeMode(mode);
    if (!mounted) {
      return;
    }

    setState(() {
      _themeMode = mode;
    });
  }

  Future<void> _loadModelStatus() async {
    final ModelStatus status = await _modelManager.getStatus();
    if (!mounted) {
      return;
    }
    setState(() {
      _modelStatus = status;
    });
  }

  Future<void> _recopyBundledModel() async {
    if (_isModelBusy) {
      return;
    }
    setState(() {
      _isModelBusy = true;
    });

    try {
      final ModelStatus status = await _modelManager.ensureBundledModelCopied(forceRecopy: true);
      if (!mounted) {
        return;
      }

      setState(() {
        _modelStatus = status;
      });

      final String message = status.exists
          ? 'Model copied to app storage.'
          : 'Bundled model is missing. Add assets/models/whisper.gguf (or whisper.bin) and run flutter pub get.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Model copy failed: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _isModelBusy = false;
        });
      }
    }
  }

  Future<void> _runWhisperTest() async {
    if (_isRunningWhisperTest) {
      return;
    }
    final int runId = ++_whisperTestRunId;
    setState(() {
      _isRunningWhisperTest = true;
      _whisperTestSummary = null;
    });
    _whisperTestWatchdog?.cancel();
    _whisperTestWatchdog = Timer(const Duration(seconds: 35), () {
      if (!mounted || !_isRunningWhisperTest || runId != _whisperTestRunId) {
        return;
      }
      setState(() {
        _isRunningWhisperTest = false;
        _whisperTestSummary =
            'Whisper test timed out after 35s. Model may be incompatible or too slow on this device.';
      });
    });

    try {
      final ModelStatus status = await _modelManager.ensureBundledModelCopied();
      if (!mounted) {
        return;
      }

      setState(() {
        _modelStatus = status;
      });

      if (!status.exists) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ModelMissingScreen(expectedModelPath: status.modelPath),
          ),
        );
        return;
      }

      await _whisperService
          .init(modelPath: status.modelPath)
          .timeout(
            const Duration(seconds: 25),
            onTimeout: () => throw TimeoutException(
              'Whisper init timed out. Verify model file integrity and size.',
            ),
          );

      final Stopwatch stopwatch = Stopwatch()..start();
      final Float32List dummyPcm = Float32List(16000);
      final String text = await _whisperService
          .transcribe(dummyPcm, lang: 'ar')
          .timeout(
            const Duration(seconds: 25),
            onTimeout: () => throw TimeoutException(
              'Whisper transcription timed out. Try a smaller model (tiny/base) and re-copy.',
            ),
          );
      stopwatch.stop();

      if (!mounted) {
        return;
      }

      setState(() {
        _whisperTestSummary =
            'Whisper test completed in ${stopwatch.elapsedMilliseconds} ms\\n'
            'Returned text: ${text.isEmpty ? '(empty)' : text}';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _whisperTestSummary = 'Whisper test failed: $error';
      });
    } finally {
      _whisperTestWatchdog?.cancel();
      if (mounted) {
        setState(() {
          if (runId == _whisperTestRunId) {
            _isRunningWhisperTest = false;
          }
        });
      }
    }
  }

  Future<void> _startMic() async {
    try {
      await _micService.start();
      if (!mounted) {
        return;
      }
      setState(() {
        _micDebugSummary = 'Microphone capture started.';
      });
    } on MicPermissionDeniedException {
      if (!mounted) {
        return;
      }
      setState(() {
        _micDebugSummary =
            'Microphone permission denied. Please allow mic access in system settings.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _micDebugSummary = 'Failed to start mic: $error';
      });
    }
  }

  Future<void> _stopMic() async {
    try {
      await _micService.stop();
      if (!mounted) {
        return;
      }
      setState(() {
        _micDebugSummary = 'Microphone capture stopped.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _micDebugSummary = 'Failed to stop mic: $error';
      });
    }
  }

  void _captureChunkPreview() {
    final Float32List chunk = _micService.getLastSecondsPcm16k(8);
    if (chunk.isEmpty) {
      setState(() {
        _micDebugSummary = '8s preview is empty. Start mic and speak for a few seconds.';
      });
      return;
    }

    double minValue = chunk.first;
    double maxValue = chunk.first;
    bool hasNaN = false;
    bool inRange = true;

    for (final double sample in chunk) {
      if (sample.isNaN) {
        hasNaN = true;
      }
      if (sample < -1.0 || sample > 1.0) {
        inRange = false;
      }
      if (sample < minValue) {
        minValue = sample;
      }
      if (sample > maxValue) {
        maxValue = sample;
      }
    }

    setState(() {
      _micDebugSummary =
          '8s chunk preview\\n'
          'length=${chunk.length} samples\\n'
          'min=${minValue.toStringAsFixed(4)} max=${maxValue.toStringAsFixed(4)}\\n'
          'valid=${(!hasNaN && inRange)} (nan=$hasNaN, inRange=$inRange)';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: <Widget>[
            const Text('Appearance'),
            const SizedBox(height: 12),
            DropdownButtonFormField<AppThemeMode>(
              initialValue: _themeMode,
              items: const <DropdownMenuItem<AppThemeMode>>[
                DropdownMenuItem<AppThemeMode>(value: AppThemeMode.system, child: Text('System')),
                DropdownMenuItem<AppThemeMode>(value: AppThemeMode.light, child: Text('Light')),
                DropdownMenuItem<AppThemeMode>(value: AppThemeMode.dark, child: Text('Dark')),
              ],
              onChanged: _onThemeModeChanged,
            ),
            const SizedBox(height: 4),
            const Text(
              'Applies immediately and is saved on this device.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 8),
            const Text('Developer Tools'),
            const SizedBox(height: 12),
            const Text('Ads Mode (Dev)'),
            const SizedBox(height: 8),
            DropdownButtonFormField<AdsMode>(
              key: ValueKey<AdsMode>(_adsMode),
              initialValue: _adsMode,
              items: const <DropdownMenuItem<AdsMode>>[
                DropdownMenuItem<AdsMode>(value: AdsMode.off, child: Text('Off (NoAdsService)')),
                DropdownMenuItem<AdsMode>(
                  value: AdsMode.stub,
                  child: Text('Stub (StubAdsService)'),
                ),
              ],
              onChanged: _isSwitchingAdsMode ? null : _onAdsModeChanged,
            ),
            const SizedBox(height: 4),
            const Text(
              'Applies immediately for this session. App restart defaults to Off.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _isRebuilding ? null : _onRebuildIndexPressed,
              child: const Text('Rebuild Index (Dev)'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _openDbHealthCheck,
              child: const Text('DB Health Check (Dev)'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _openDiagnostics, child: const Text('Diagnostics')),
            if (_isRebuilding) ...<Widget>[
              const SizedBox(height: 12),
              const Text('Index rebuild in progress...'),
            ],
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 8),
            const Text('Whisper.cpp (Offline ASR)'),
            const SizedBox(height: 8),
            Text('Model path: ${_modelStatus?.modelPath ?? '-'}'),
            Text('Model exists: ${_modelStatus?.exists ?? false}'),
            Text('Bundled model asset available: ${_modelStatus?.bundledAssetAvailable ?? false}'),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _isModelBusy ? null : _recopyBundledModel,
              child: const Text('Re-copy bundled model to storage (Dev)'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _isRunningWhisperTest ? null : _runWhisperTest,
              child: const Text('Run Whisper Test'),
            ),
            if (_isRunningWhisperTest) ...<Widget>[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],
            if (_whisperTestSummary != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(_whisperTestSummary!),
            ],
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 8),
            const Text('Mic Debug (16kHz Pipeline)'),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: ElevatedButton(
                    onPressed: _micService.isRunning ? null : _startMic,
                    child: const Text('Start Mic'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _micService.isRunning ? _stopMic : null,
                    child: const Text('Stop Mic'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _captureChunkPreview,
              child: const Text('Capture 8s chunk preview'),
            ),
            const SizedBox(height: 8),
            Text('Running: ${_micService.isRunning}'),
            Text('Sample rate in: ${_latestMicStats?.sampleRate ?? _micService.inputSampleRate}'),
            Text(
              'Buffer seconds stored: ${(_latestMicStats?.bufferSeconds ?? _micService.bufferSeconds).toStringAsFixed(2)}',
            ),
            Text('RMS: ${(_latestMicStats?.rms ?? _micService.currentRms).toStringAsFixed(5)}'),
            Text('isSpeech: ${_latestMicStats?.isSpeech ?? _micService.isSpeech}'),
            if (_micDebugSummary != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(_micDebugSummary!),
            ],
          ],
        ),
      ),
    );
  }
}
