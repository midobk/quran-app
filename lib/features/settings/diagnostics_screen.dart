import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/di/service_locator.dart';
import '../../data/quran/ayah_row.dart';
import '../../data/quran/quran_repository.dart';
import '../../services/asr/model_manager.dart';
import '../../services/asr/whisper_cpp_service.dart';
import '../../services/audio/mic_service.dart';
import '../../services/database/database_service.dart';
import '../../services/diagnostics/diagnostics_store.dart';
import '../../services/search/quran_search_engine.dart';
import '../../ui/theme/quran_listener_design.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  static const int _expectedAyahCount = 6236;

  late final DatabaseService _databaseService;
  late final QuranRepository _repository;
  late final ModelManager _modelManager;
  late final WhisperCppService _whisperService;
  late final MicService _micService;
  late final DiagnosticsStore _diagnosticsStore;
  late final QuranSearchEngine _searchEngine;

  StreamSubscription<MicStats>? _micSubscription;
  bool _isLoading = true;
  String? _errorMessage;
  bool _showTokenFilteringDebug = false;

  String _dbPath = '-';
  int _ayahCount = 0;
  int _tokenIndexCount = 0;
  AyahRow? _sampleAyah;
  String _sampleAyah2Uthmani = '-';
  String _sampleAyah2Plain = '-';
  String _sampleAyah2PlainNorm = '-';
  bool _sampleAyah2PlainHasAlamin = false;
  bool _hasTranslationColumn = false;
  bool _hasSurahNameEnColumn = false;

  String _bundledAssetName = '-';
  String _modelPath = '-';
  bool _modelExists = false;
  double _modelSizeMb = 0;

  @override
  void initState() {
    super.initState();
    _databaseService = serviceLocator<DatabaseService>();
    _repository = serviceLocator<QuranRepository>();
    _modelManager = serviceLocator<ModelManager>();
    _whisperService = serviceLocator<WhisperCppService>();
    _micService = serviceLocator<MicService>();
    _diagnosticsStore = serviceLocator<DiagnosticsStore>();
    _searchEngine = serviceLocator<QuranSearchEngine>();
    _diagnosticsStore.addListener(_onDiagnosticsChanged);
    _micSubscription = _micService.statsStream.listen((_) {
      if (mounted) {
        setState(() {});
      }
    });
    _refreshAll();
  }

  @override
  void dispose() {
    _diagnosticsStore.removeListener(_onDiagnosticsChanged);
    unawaited(_micSubscription?.cancel());
    super.dispose();
  }

  void _onDiagnosticsChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _refreshAll() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _loadDatabaseHealth();
      await _loadModelHealth();
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _errorMessage = '$error';
      });
    }
  }

  Future<void> _loadDatabaseHealth() async {
    await _databaseService.init();

    final List<Map<String, Object?>> tokenRows = await _databaseService.db.rawQuery(
      'SELECT COUNT(*) AS count FROM token_index',
    );
    final List<Map<String, Object?>> sampleAyah2Rows = await _databaseService.db.query(
      'ayah',
      columns: <String>['text_uthmani', 'text_plain', 'text_plain_norm'],
      where: 'surah_no = ? AND ayah_no = ?',
      whereArgs: <Object?>[1, 2],
      limit: 1,
    );
    final List<Map<String, Object?>> columnRows = await _databaseService.db.rawQuery(
      'PRAGMA table_info(ayah)',
    );

    final ModelStatus modelStatus = await _modelManager.getStatus();
    final int ayahCount = await _repository.getAyahCount();
    final AyahRow? ayahOne = await _repository.getAyahById(1);

    _dbPath = _databaseService.dbPath ?? '(unknown)';
    _tokenIndexCount = (tokenRows.first['count'] as int?) ?? 0;
    _ayahCount = ayahCount;
    _sampleAyah = ayahOne;
    if (sampleAyah2Rows.isNotEmpty) {
      final Map<String, Object?> row = sampleAyah2Rows.first;
      _sampleAyah2Uthmani = (row['text_uthmani'] as String?) ?? '';
      _sampleAyah2Plain = (row['text_plain'] as String?) ?? '';
      _sampleAyah2PlainNorm = (row['text_plain_norm'] as String?) ?? '';
      _sampleAyah2PlainHasAlamin = _sampleAyah2Plain.contains('العالمين');
    } else {
      _sampleAyah2Uthmani = '-';
      _sampleAyah2Plain = '-';
      _sampleAyah2PlainNorm = '-';
      _sampleAyah2PlainHasAlamin = false;
    }
    _hasTranslationColumn = columnRows.any(
      (Map<String, Object?> row) => row['name'] == 'translation_en',
    );
    _hasSurahNameEnColumn = columnRows.any(
      (Map<String, Object?> row) => row['name'] == 'surah_name_en',
    );

    _bundledAssetName = p.basename(modelStatus.bundledAssetPath);
  }

  Future<void> _loadModelHealth() async {
    final ModelStatus status = await _modelManager.getStatus();
    final File file = File(status.modelPath);
    final bool exists = await file.exists();
    final int sizeBytes = exists ? await file.length() : 0;

    _modelPath = status.modelPath;
    _modelExists = exists;
    _modelSizeMb = sizeBytes / (1024 * 1024);
    _bundledAssetName = p.basename(status.bundledAssetPath);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: QuranListenerBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                child: Row(
                  children: <Widget>[
                    QuranListenerIconButton(
                      size: 40,
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text('Diagnostics', style: Theme.of(context).textTheme.titleLarge),
                          Text(
                            'System health & debug info',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    QuranListenerIconButton(
                      size: 40,
                      icon: const Icon(Icons.refresh_rounded),
                      onPressed: _refreshAll,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(child: _buildBody(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('Diagnostics failed', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 14),
              ElevatedButton(onPressed: _refreshAll, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final QuranListenerPalette colors = context.quranPalette;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: <Widget>[
        _SectionLabel(title: 'Database Health'),
        _DiagnosticField(
          label: 'Ayah Count',
          value: '$_ayahCount / expected $_expectedAyahCount',
          status: _ayahCount == _expectedAyahCount ? _FieldStatus.ok : _FieldStatus.warn,
        ),
        _DiagnosticField(label: 'DB Path', value: _dbPath),
        _DiagnosticField(label: 'token_index rows', value: '$_tokenIndexCount'),
        _DiagnosticField(
          label: 'translation columns',
          value: 'translation_en=$_hasTranslationColumn, surah_name_en=$_hasSurahNameEnColumn',
        ),
        _DiagnosticField(
          label: 'Sample plain contains "العالمين"',
          value: '$_sampleAyah2PlainHasAlamin',
          status: _sampleAyah2PlainHasAlamin ? _FieldStatus.ok : _FieldStatus.warn,
        ),
        _DiagnosticField(
          label: 'Sample (1:2) Uthmani',
          value: _sampleAyah2Uthmani,
          monospace: false,
          textDirection: TextDirection.rtl,
        ),
        _DiagnosticField(
          label: 'Sample (1:2) plain',
          value: _sampleAyah2Plain,
          monospace: false,
          textDirection: TextDirection.rtl,
        ),
        _DiagnosticField(
          label: 'Sample (1:2) plain_norm',
          value: _sampleAyah2PlainNorm,
          monospace: false,
          textDirection: TextDirection.rtl,
        ),
        if (_sampleAyah != null)
          _DiagnosticField(
            label: 'Sample Ayah #1',
            value: _sampleAyah!.textUthmani,
            monospace: false,
            textDirection: TextDirection.rtl,
          ),
        const SizedBox(height: 18),
        _SectionLabel(title: 'Model Health (Whisper)'),
        _DiagnosticField(label: 'Bundled asset', value: _bundledAssetName),
        _DiagnosticField(label: 'Local model path', value: _modelPath),
        _DiagnosticField(
          label: 'Model exists',
          value: '$_modelExists',
          status: _modelExists ? _FieldStatus.ok : _FieldStatus.error,
        ),
        _DiagnosticField(label: 'File size', value: '${_modelSizeMb.toStringAsFixed(2)} MB'),
        _DiagnosticField(
          label: 'Last init status',
          value: _whisperService.lastInitSuccessful == null
              ? 'Not attempted'
              : _whisperService.lastInitSuccessful!
              ? 'Success'
              : 'Failure: ${_whisperService.lastInitError ?? '-'}',
          status: _whisperService.lastInitSuccessful == null
              ? _FieldStatus.neutral
              : _whisperService.lastInitSuccessful!
              ? _FieldStatus.ok
              : _FieldStatus.error,
        ),
        _DiagnosticField(
          label: 'Last transcription',
          value: _whisperService.lastTranscriptionTimeMs == null
              ? '-'
              : '${_whisperService.lastTranscriptionTimeMs} ms',
        ),
        const SizedBox(height: 18),
        _SectionLabel(title: 'Audio Health'),
        _DiagnosticField(label: 'Input sample rate', value: '${_micService.inputSampleRate} Hz'),
        _DiagnosticField(
          label: 'Resampling active',
          value: _micService.inputSampleRate == _micService.targetSampleRate ? 'No' : 'Yes',
        ),
        _DiagnosticField(
          label: 'Ring buffer length',
          value: '${_micService.bufferSeconds.toStringAsFixed(2)} s',
        ),
        _DiagnosticField(label: 'Current RMS', value: _micService.currentRms.toStringAsFixed(5)),
        _DiagnosticField(
          label: 'VAD isSpeech',
          value: '${_micService.isSpeech}',
          status: _micService.isSpeech ? _FieldStatus.ok : _FieldStatus.warn,
        ),
        _DiagnosticField(
          label: 'VAD skip rate',
          value:
              '${_diagnosticsStore.vadSkipRatePercent.toStringAsFixed(1)}% (last ${_diagnosticsStore.samplesCount})',
        ),
        const SizedBox(height: 18),
        _SectionLabel(title: 'Live Tracking Stats'),
        _DiagnosticField(
          label: 'Avg whisper latency',
          value: '${_diagnosticsStore.avgWhisperLatencyMs.toStringAsFixed(1)} ms',
        ),
        _DiagnosticField(
          label: 'Avg search latency',
          value: '${_diagnosticsStore.avgSearchLatencyMs.toStringAsFixed(1)} ms',
        ),
        _DiagnosticField(
          label: 'Low confidence ticks',
          value: '${_diagnosticsStore.lowConfidenceRatePercent.toStringAsFixed(1)}%',
        ),
        _DiagnosticField(
          label: 'Window',
          value: 'back=${_diagnosticsStore.windowBack}, forward=${_diagnosticsStore.windowForward}',
        ),
        _DiagnosticField(
          label: 'Current pointer',
          value: _diagnosticsStore.pointerAyahId == null
              ? '-'
              : '#${_diagnosticsStore.pointerAyahId} • سورة ${_diagnosticsStore.pointerSurahNameAr} • آية ${_diagnosticsStore.pointerAyahNo}',
          textDirection: TextDirection.rtl,
        ),
        const SizedBox(height: 18),
        _SectionLabel(title: 'Search Token Diagnostics'),
        Container(
          decoration: BoxDecoration(
            color: colors.bgSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.strokeDefault),
          ),
          child: SwitchListTile(
            value: _showTokenFilteringDebug,
            title: const Text('Show token filter/mapping details'),
            subtitle: const Text('Includes normalized tokens and fuzzy mappings'),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            onChanged: (bool value) {
              setState(() {
                _showTokenFilteringDebug = value;
              });
            },
          ),
        ),
        if (_showTokenFilteringDebug) ..._buildSearchDiagnostics(),
      ],
    );
  }

  List<Widget> _buildSearchDiagnostics() {
    final SearchDiagnostics? diagnostics = _searchEngine.lastDiagnostics;
    if (diagnostics == null) {
      return <Widget>[
        const SizedBox(height: 8),
        const _DiagnosticField(
          label: 'Search diagnostics',
          value: 'No data yet. Run a search first.',
        ),
      ];
    }

    final TokenFilterDiagnostics filter = diagnostics.tokenFilter;
    final List<Widget> widgets = <Widget>[
      const SizedBox(height: 8),
      _DiagnosticField(label: 'Normalized transcript', value: diagnostics.normalizedTranscript),
      _DiagnosticField(
        label: 'Token counts',
        value:
            '${filter.beforeCount} -> ${filter.afterCount} (mapped=${filter.mappedCount}, dropped=${filter.droppedCount})',
      ),
      _DiagnosticField(label: 'Fallback used', value: '${filter.fallbackUsed}'),
      _DiagnosticField(label: 'Filter+map time', value: '${filter.elapsedMs} ms'),
      _DiagnosticField(label: 'Original tokens', value: filter.originalTokens.join(' | ')),
      _DiagnosticField(label: 'Filtered tokens', value: filter.filteredTokens.join(' | ')),
    ];

    if (filter.mappingPairs.isEmpty) {
      widgets.add(const _DiagnosticField(label: 'Mappings', value: '(none)'));
      return widgets;
    }

    for (final TokenMappingPair mapping in filter.mappingPairs) {
      widgets.add(
        _DiagnosticField(
          label: 'Mapping',
          value:
              '${mapping.original} -> ${mapping.mapped} (d=${mapping.distance}, c=${mapping.confidence.toStringAsFixed(2)})',
          textDirection: TextDirection.rtl,
        ),
      );
    }
    return widgets;
  }
}

enum _FieldStatus { ok, warn, error, neutral }

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title});

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

class _DiagnosticField extends StatelessWidget {
  const _DiagnosticField({
    required this.label,
    required this.value,
    this.status = _FieldStatus.neutral,
    this.monospace = true,
    this.textDirection,
  });

  final String label;
  final String value;
  final _FieldStatus status;
  final bool monospace;
  final TextDirection? textDirection;

  @override
  Widget build(BuildContext context) {
    final QuranListenerPalette colors = context.quranPalette;
    final Color statusColor = switch (status) {
      _FieldStatus.ok => QuranListenerColors.statusHigh,
      _FieldStatus.warn => QuranListenerColors.statusMedium,
      _FieldStatus.error => QuranListenerColors.statusLow,
      _FieldStatus.neutral => colors.textSecondary,
    };

    final String? statusLabel = switch (status) {
      _FieldStatus.ok => 'OK',
      _FieldStatus.warn => 'Warning',
      _FieldStatus.error => 'Error',
      _FieldStatus.neutral => null,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.bgSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.strokeDefault),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    label.toUpperCase(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(letterSpacing: 0.9),
                  ),
                ),
                if (statusLabel != null)
                  Row(
                    children: <Widget>[
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        statusLabel,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: statusColor),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              textDirection: textDirection,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.textPrimary,
                fontFamily: monospace ? 'Courier' : null,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
