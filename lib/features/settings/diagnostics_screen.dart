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
      appBar: AppBar(
        title: const Text('Diagnostics'),
        actions: <Widget>[IconButton(onPressed: _refreshAll, icon: const Icon(Icons.refresh))],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(child: Text('Diagnostics failed: $_errorMessage'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                _buildSectionTitle(context, 'A) Database Health'),
                _buildDataRow('DB path', _dbPath),
                _buildDataRow('Ayah count', '$_ayahCount (expected $_expectedAyahCount)'),
                _buildDataRow('token_index rows', '$_tokenIndexCount'),
                _buildDataRow(
                  'translation columns',
                  'translation_en=$_hasTranslationColumn, surah_name_en=$_hasSurahNameEnColumn',
                ),
                const SizedBox(height: 8),
                Text(
                  'Sample ayah (surah 1 ayah 2) Uthmani: $_sampleAyah2Uthmani',
                  textDirection: TextDirection.rtl,
                ),
                const SizedBox(height: 4),
                Text(
                  'Sample ayah (surah 1 ayah 2) plain: $_sampleAyah2Plain',
                  textDirection: TextDirection.rtl,
                ),
                const SizedBox(height: 4),
                Text(
                  'Sample ayah (surah 1 ayah 2) plain_norm: $_sampleAyah2PlainNorm',
                  textDirection: TextDirection.rtl,
                ),
                _buildDataRow('Sample plain contains "العالمين"', '$_sampleAyah2PlainHasAlamin'),
                if (_sampleAyah != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    'Sample ayah #1: ${_sampleAyah!.textUthmani}',
                    textDirection: TextDirection.rtl,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _sampleAyah!.translationEn.isEmpty
                        ? '(translation_en empty)'
                        : _sampleAyah!.translationEn,
                    textDirection: TextDirection.ltr,
                  ),
                ],
                const Divider(height: 28),
                _buildSectionTitle(context, 'B) Model Health (Whisper)'),
                _buildDataRow('Bundled asset name', _bundledAssetName),
                _buildDataRow('Local model path', _modelPath),
                _buildDataRow('Exists', '$_modelExists'),
                _buildDataRow('File size', '${_modelSizeMb.toStringAsFixed(2)} MB'),
                _buildDataRow(
                  'Last init status',
                  _whisperService.lastInitSuccessful == null
                      ? 'Not attempted'
                      : _whisperService.lastInitSuccessful!
                      ? 'Success'
                      : 'Failure: ${_whisperService.lastInitError ?? '-'}',
                ),
                _buildDataRow(
                  'Last transcription time',
                  _whisperService.lastTranscriptionTimeMs == null
                      ? '-'
                      : '${_whisperService.lastTranscriptionTimeMs} ms',
                ),
                const Divider(height: 28),
                _buildSectionTitle(context, 'C) Audio Health'),
                _buildDataRow('Input sample rate', '${_micService.inputSampleRate} Hz'),
                _buildDataRow(
                  'Resampling active',
                  _micService.inputSampleRate == _micService.targetSampleRate ? 'No' : 'Yes',
                ),
                _buildDataRow(
                  'Ring buffer length',
                  '${_micService.bufferSeconds.toStringAsFixed(2)} s',
                ),
                _buildDataRow('Current RMS', _micService.currentRms.toStringAsFixed(5)),
                _buildDataRow('VAD isSpeech', '${_micService.isSpeech}'),
                _buildDataRow(
                  'VAD skip rate (last ${_diagnosticsStore.samplesCount})',
                  '${_diagnosticsStore.vadSkipRatePercent.toStringAsFixed(1)}%',
                ),
                const Divider(height: 28),
                _buildSectionTitle(context, 'D) Live Tracking Stats'),
                _buildDataRow(
                  'Avg whisper latency',
                  '${_diagnosticsStore.avgWhisperLatencyMs.toStringAsFixed(1)} ms',
                ),
                _buildDataRow(
                  'Avg search latency',
                  '${_diagnosticsStore.avgSearchLatencyMs.toStringAsFixed(1)} ms',
                ),
                _buildDataRow(
                  '% ticks skipped (VAD)',
                  '${_diagnosticsStore.vadSkipRatePercent.toStringAsFixed(1)}%',
                ),
                _buildDataRow(
                  '% ticks low confidence',
                  '${_diagnosticsStore.lowConfidenceRatePercent.toStringAsFixed(1)}%',
                ),
                _buildDataRow(
                  'Current window',
                  'back=${_diagnosticsStore.windowBack}, forward=${_diagnosticsStore.windowForward}',
                ),
                _buildDataRow(
                  'Current pointer',
                  _diagnosticsStore.pointerAyahId == null
                      ? '-'
                      : '#${_diagnosticsStore.pointerAyahId} • سورة ${_diagnosticsStore.pointerSurahNameAr} • آية ${_diagnosticsStore.pointerAyahNo}',
                ),
                const Divider(height: 28),
                _buildSectionTitle(context, 'E) Search Token Diagnostics'),
                SwitchListTile(
                  value: _showTokenFilteringDebug,
                  title: const Text('Show token filter/mapping details'),
                  subtitle: const Text('Includes normalized tokens and fuzzy mappings'),
                  contentPadding: EdgeInsets.zero,
                  onChanged: (bool value) {
                    setState(() {
                      _showTokenFilteringDebug = value;
                    });
                  },
                ),
                if (_showTokenFilteringDebug) ..._buildSearchDiagnostics(),
              ],
            ),
    );
  }

  List<Widget> _buildSearchDiagnostics() {
    final SearchDiagnostics? diagnostics = _searchEngine.lastDiagnostics;
    if (diagnostics == null) {
      return <Widget>[const Text('No search diagnostics yet. Run a search first.')];
    }

    final TokenFilterDiagnostics filter = diagnostics.tokenFilter;
    final List<Widget> widgets = <Widget>[
      _buildDataRow('Normalized transcript', diagnostics.normalizedTranscript),
      _buildDataRow(
        'Token counts',
        '${filter.beforeCount} -> ${filter.afterCount} (mapped=${filter.mappedCount}, dropped=${filter.droppedCount})',
      ),
      _buildDataRow('Fallback used', '${filter.fallbackUsed}'),
      _buildDataRow('Filter+map time', '${filter.elapsedMs} ms'),
      _buildDataRow('Original tokens', filter.originalTokens.join(' | ')),
      _buildDataRow('Filtered tokens', filter.filteredTokens.join(' | ')),
    ];

    if (filter.mappingPairs.isEmpty) {
      widgets.add(const Text('Mappings: (none)'));
      return widgets;
    }

    widgets.add(const SizedBox(height: 8));
    widgets.add(const Text('Mappings'));
    for (final TokenMappingPair mapping in filter.mappingPairs) {
      widgets.add(
        Text(
          '${mapping.original} -> ${mapping.mapped} '
          '(d=${mapping.distance}, c=${mapping.confidence.toStringAsFixed(2)})',
          textDirection: TextDirection.rtl,
        ),
      );
    }
    return widgets;
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }

  Widget _buildDataRow(String label, String value) {
    return Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('$label: $value'));
  }
}
