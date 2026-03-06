import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/di/service_locator.dart';
import '../../data/quran/quran_repository.dart';
import '../../services/asr/model_manager.dart';
import '../../services/asr/whisper_cpp_service.dart';
import '../../services/audio/mic_service.dart';
import '../../services/indexing/quran_index_builder.dart';
import '../../services/settings/app_settings_service.dart';
import '../../services/theme/theme_service.dart';
import '../../ui/theme/quran_listener_design.dart';
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
  late final AppSettingsService _settingsService;

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
    _themeService.addListener(_handleThemeModeChanged);
    _settingsService = serviceLocator<AppSettingsService>();
    _settingsService.addListener(_handleSettingsChanged);
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
    _settingsService.removeListener(_handleSettingsChanged);
    _themeService.removeListener(_handleThemeModeChanged);
    super.dispose();
  }

  AppSettings get _appSettings => _settingsService.settings;

  void _handleSettingsChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  void _handleThemeModeChanged() {
    if (!mounted) {
      return;
    }
    setState(() {
      _themeMode = _themeService.themeMode;
    });
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
            'Whisper test completed in ${stopwatch.elapsedMilliseconds} ms\n'
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
          '8s chunk preview\n'
          'length=${chunk.length} samples\n'
          'min=${minValue.toStringAsFixed(4)} max=${maxValue.toStringAsFixed(4)}\n'
          'valid=${(!hasNaN && inRange)} (nan=$hasNaN, inRange=$inRange)';
    });
  }

  @override
  Widget build(BuildContext context) {
    final QuranListenerPalette colors = context.quranPalette;
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      backgroundColor: colors.bgDefault,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                children: <Widget>[
                  _BackCircleButton(onTap: () => Navigator.of(context).pop()),
                  const SizedBox(width: 12),
                  Text(
                    'Settings',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.strokeDefault),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                children: <Widget>[
                  const _FigmaSectionHeading('RECITATION TRACKING'),
                  _FigmaSettingRow(
                    title: 'Auto-detect ayah',
                    subtitle: 'Automatically identify the current ayah',
                    trailing: _GoldSwitch(
                      value: _appSettings.autoDetectAyah,
                      onChanged: (bool value) {
                        unawaited(_settingsService.setAutoDetectAyah(value));
                      },
                    ),
                  ),
                  const _RowDivider(),
                  _FigmaSettingRow(
                    title: 'Confidence threshold',
                    subtitle: '${_appSettings.confidenceThreshold.round()}%',
                    trailing: SizedBox(
                      width: 122,
                      child: _GoldSlider(
                        value: _appSettings.confidenceThreshold,
                        min: 30,
                        max: 100,
                        onChanged: (double value) {
                          unawaited(_settingsService.setConfidenceThreshold(value));
                        },
                      ),
                    ),
                  ),
                  const _RowDivider(),
                  _FigmaSettingRow(
                    title: 'Keep screen awake',
                    subtitle: 'Prevents display from sleeping',
                    trailing: _GoldSwitch(
                      value: _appSettings.keepScreenAwake,
                      onChanged: (bool value) {
                        unawaited(_settingsService.setKeepScreenAwake(value));
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  const _FigmaSectionHeading('DISPLAY'),
                  _FigmaSettingRow(
                    title: 'Theme mode',
                    subtitle: 'Follow your phone or choose a fixed theme',
                    trailing: SizedBox(
                      width: 140,
                      child: DropdownButtonFormField<AppThemeMode>(
                        key: ValueKey<AppThemeMode>(_themeMode),
                        initialValue: _themeMode,
                        isDense: true,
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        items: const <DropdownMenuItem<AppThemeMode>>[
                          DropdownMenuItem<AppThemeMode>(
                            value: AppThemeMode.system,
                            child: Text('System'),
                          ),
                          DropdownMenuItem<AppThemeMode>(
                            value: AppThemeMode.light,
                            child: Text('Light'),
                          ),
                          DropdownMenuItem<AppThemeMode>(
                            value: AppThemeMode.dark,
                            child: Text('Dark'),
                          ),
                        ],
                        onChanged: _onThemeModeChanged,
                      ),
                    ),
                  ),
                  const _RowDivider(),
                  _FigmaSettingRow(
                    title: 'Show translation',
                    subtitle: 'English text below Arabic',
                    trailing: _GoldSwitch(
                      value: _appSettings.showTranslation,
                      onChanged: (bool value) {
                        unawaited(_settingsService.setShowTranslation(value));
                      },
                    ),
                  ),
                  const _RowDivider(),
                  _FigmaSettingRow(
                    title: 'Arabic font size',
                    subtitle: '${_appSettings.arabicFontSize.round()}px',
                    trailing: SizedBox(
                      width: 122,
                      child: _GoldSlider(
                        value: _appSettings.arabicFontSize,
                        min: 32,
                        max: 72,
                        onChanged: (double value) {
                          unawaited(_settingsService.setArabicFontSize(value));
                        },
                      ),
                    ),
                  ),
                  const _RowDivider(),
                  _FigmaSettingRow(
                    title: 'Haptic feedback',
                    subtitle: 'Vibrate on ayah change',
                    trailing: _GoldSwitch(
                      value: _appSettings.hapticFeedback,
                      onChanged: (bool value) {
                        unawaited(_settingsService.setHapticFeedback(value));
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  const _FigmaSectionHeading('DEVELOPER / DEBUG'),
                  _FigmaSettingRow(
                    title: 'Debug mode',
                    subtitle: 'Show diagnostic overlay',
                    trailing: _GoldSwitch(
                      value: _appSettings.debugMode,
                      onChanged: (bool value) {
                        unawaited(_settingsService.setDebugMode(value));
                      },
                    ),
                  ),
                  if (_appSettings.debugMode) ..._buildAdvancedDebugOptions(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildAdvancedDebugOptions(BuildContext context) {
    return <Widget>[
      const SizedBox(height: 18),
      const _SectionTitle(title: 'Advanced Debug Options'),
      _SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Ads Mode (Dev)', style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 10),
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
            const SizedBox(height: 8),
            Text(
              'Applies immediately for this session. App restart defaults to Off.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: _isRebuilding ? null : _onRebuildIndexPressed,
              child: const Text('Rebuild Index (Dev)'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _openDbHealthCheck,
              child: const Text('DB Health Check (Dev)'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: _openDiagnostics, child: const Text('Diagnostics')),
            if (_isRebuilding) ...<Widget>[
              const SizedBox(height: 10),
              const LinearProgressIndicator(),
              const SizedBox(height: 6),
              Text('Index rebuild in progress...', style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
      const SizedBox(height: 18),
      const _SectionTitle(title: 'Whisper.cpp (Offline ASR)'),
      _SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _InfoRow(label: 'Model path', value: _modelStatus?.modelPath ?? '-'),
            _InfoRow(label: 'Model exists', value: '${_modelStatus?.exists ?? false}'),
            _InfoRow(
              label: 'Bundled asset available',
              value: '${_modelStatus?.bundledAssetAvailable ?? false}',
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _isModelBusy ? null : _recopyBundledModel,
              child: const Text('Re-copy bundled model to storage'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _isRunningWhisperTest ? null : _runWhisperTest,
              child: const Text('Run Whisper Test'),
            ),
            if (_isRunningWhisperTest) ...<Widget>[
              const SizedBox(height: 10),
              const LinearProgressIndicator(),
            ],
            if (_whisperTestSummary != null) ...<Widget>[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.quranPalette.bgDefault.withValues(alpha: 0.58),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.quranPalette.strokeDefault),
                ),
                child: Text(_whisperTestSummary!, style: Theme.of(context).textTheme.bodySmall),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 18),
      const _SectionTitle(title: 'Mic Debug (16kHz Pipeline)'),
      _SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: ElevatedButton(
                    onPressed: _micService.isRunning ? null : _startMic,
                    child: const Text('Start Mic'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _micService.isRunning ? _stopMic : null,
                    child: const Text('Stop Mic'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _captureChunkPreview,
              child: const Text('Capture 8s chunk preview'),
            ),
            const SizedBox(height: 10),
            _InfoRow(label: 'Running', value: '${_micService.isRunning}'),
            _InfoRow(
              label: 'Sample rate in',
              value: '${_latestMicStats?.sampleRate ?? _micService.inputSampleRate}',
            ),
            _InfoRow(
              label: 'Buffer seconds stored',
              value: (_latestMicStats?.bufferSeconds ?? _micService.bufferSeconds).toStringAsFixed(
                2,
              ),
            ),
            _InfoRow(
              label: 'RMS',
              value: (_latestMicStats?.rms ?? _micService.currentRms).toStringAsFixed(5),
            ),
            _InfoRow(
              label: 'isSpeech',
              value: '${_latestMicStats?.isSpeech ?? _micService.isSpeech}',
            ),
            if (_micDebugSummary != null) ...<Widget>[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.quranPalette.bgDefault.withValues(alpha: 0.58),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.quranPalette.strokeDefault),
                ),
                child: Text(_micDebugSummary!, style: Theme.of(context).textTheme.bodySmall),
              ),
            ],
          ],
        ),
      ),
    ];
  }
}

class _FigmaSectionHeading extends StatelessWidget {
  const _FigmaSectionHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _FigmaSettingRow extends StatelessWidget {
  const _FigmaSettingRow({required this.title, required this.subtitle, required this.trailing});

  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: context.quranPalette.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: context.quranPalette.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          trailing,
        ],
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(height: 1, color: context.quranPalette.strokeDefault);
  }
}

class _BackCircleButton extends StatelessWidget {
  const _BackCircleButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final QuranListenerPalette colors = context.quranPalette;

    return Material(
      color: colors.bgSurface,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(Icons.arrow_back_rounded, color: colors.textSecondary, size: 21),
        ),
      ),
    );
  }
}

class _GoldSwitch extends StatelessWidget {
  const _GoldSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final QuranListenerPalette colors = context.quranPalette;
    final ThemeData theme = Theme.of(context);

    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: 52,
        height: 31,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: value ? theme.colorScheme.primary : colors.strokeDefault,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Align(
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 27,
            height: 27,
            decoration: const BoxDecoration(color: Color(0xFFF2F2F2), shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}

class _GoldSlider extends StatelessWidget {
  const _GoldSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 3,
        activeTrackColor: theme.colorScheme.primary,
        inactiveTrackColor: context.quranPalette.strokeDefault,
        thumbColor: theme.colorScheme.primary,
        overlayShape: SliderComponentShape.noOverlay,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
      ),
      child: Slider(value: value, min: min, max: max, onChanged: onChanged),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.quranPalette.bgSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.quranPalette.strokeDefault),
      ),
      child: child,
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodySmall,
          children: <InlineSpan>[
            TextSpan(
              text: '$label: ',
              style: TextStyle(color: context.quranPalette.textPrimary),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}
