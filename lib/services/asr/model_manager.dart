import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ModelManager {
  ModelManager({
    AssetBundle? assetBundle,
    Future<Directory> Function()? appDirectoryProvider,
    this.modelFileName = 'whisper.gguf',
    List<String>? bundledModelAssetCandidates,
  }) : _assetBundle = assetBundle ?? rootBundle,
       _appDirectoryProvider = appDirectoryProvider ?? getApplicationSupportDirectory,
       _bundledModelAssetCandidates =
           bundledModelAssetCandidates ?? _defaultBundledModelAssetCandidates;

  final AssetBundle _assetBundle;
  final Future<Directory> Function() _appDirectoryProvider;
  final List<String> _bundledModelAssetCandidates;
  final String modelFileName;

  String get bundledModelAssetPath => _bundledModelAssetCandidates.first;

  Future<ModelStatus> getStatus() async {
    final File? existingModel = await _findExistingModelFile();
    final _BundledAssetData? bundledAsset = await _resolveBundledAsset();
    final File fallbackTarget = await _targetModelFile(modelFileName);

    return ModelStatus(
      modelPath: (existingModel ?? fallbackTarget).path,
      exists: existingModel != null,
      bundledAssetPath: bundledAsset?.assetPath ?? bundledModelAssetPath,
      copiedFromBundle: false,
      bundledAssetAvailable: bundledAsset != null,
    );
  }

  Future<ModelStatus> ensureBundledModelCopied({bool forceRecopy = false}) async {
    final File? existingModel = await _findExistingModelFile();

    if (!forceRecopy && existingModel != null) {
      return ModelStatus(
        modelPath: existingModel.path,
        exists: true,
        bundledAssetPath: bundledModelAssetPath,
        copiedFromBundle: false,
        bundledAssetAvailable: await _bundledAssetAvailable(),
      );
    }

    final _BundledAssetData? bundledAsset = await _resolveBundledAsset();
    if (bundledAsset == null) {
      final File fallbackTarget = await _targetModelFile(modelFileName);
      return ModelStatus(
        modelPath: (existingModel ?? fallbackTarget).path,
        exists: existingModel != null,
        bundledAssetPath: bundledModelAssetPath,
        copiedFromBundle: false,
        bundledAssetAvailable: false,
      );
    }

    final File target = await _targetModelFile(p.basename(bundledAsset.assetPath));
    final Uint8List bytes = bundledAsset.bytes.buffer.asUint8List(
      bundledAsset.bytes.offsetInBytes,
      bundledAsset.bytes.lengthInBytes,
    );
    await target.parent.create(recursive: true);
    await target.writeAsBytes(bytes, flush: true);

    return ModelStatus(
      modelPath: target.path,
      exists: true,
      bundledAssetPath: bundledAsset.assetPath,
      copiedFromBundle: true,
      bundledAssetAvailable: true,
    );
  }

  Future<File> _targetModelFile(String fileName) async {
    final Directory appDir = await _appDirectoryProvider();
    return File(p.join(appDir.path, 'models', fileName));
  }

  Future<File?> _findExistingModelFile() async {
    final List<String> candidateFileNames = <String>{
      modelFileName,
      ..._bundledModelAssetCandidates.map(p.basename),
    }.toList(growable: false);

    for (final String fileName in candidateFileNames) {
      final File file = await _targetModelFile(fileName);
      if (await file.exists()) {
        return file;
      }
    }
    return null;
  }

  Future<bool> _bundledAssetAvailable() async {
    return (await _resolveBundledAsset()) != null;
  }

  Future<_BundledAssetData?> _resolveBundledAsset() async {
    for (final String assetPath in _bundledModelAssetCandidates) {
      try {
        final ByteData bytes = await _assetBundle.load(assetPath);
        return _BundledAssetData(assetPath: assetPath, bytes: bytes);
      } on Object {
        continue;
      }
    }
    return null;
  }
}

class ModelStatus {
  const ModelStatus({
    required this.modelPath,
    required this.exists,
    required this.bundledAssetPath,
    required this.copiedFromBundle,
    required this.bundledAssetAvailable,
  });

  final String modelPath;
  final bool exists;
  final String bundledAssetPath;
  final bool copiedFromBundle;
  final bool bundledAssetAvailable;
}

class _BundledAssetData {
  const _BundledAssetData({required this.assetPath, required this.bytes});

  final String assetPath;
  final ByteData bytes;
}

const List<String> _defaultBundledModelAssetCandidates = <String>[
  'assets/models/whisper.gguf',
  'assets/models/whisper.bin',
  'assets/models/ggml-base.bin',
  'assets/models/ggml-small.bin',
];
