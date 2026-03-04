import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

typedef _WcppInitNative = ffi.Int32 Function(ffi.Pointer<Utf8> modelPath);
typedef _WcppInitDart = int Function(ffi.Pointer<Utf8> modelPath);

typedef _WcppTranscribeNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Float> pcm16k,
      ffi.Int32 length,
      ffi.Pointer<Utf8> lang,
      ffi.Pointer<ffi.Char> outText,
      ffi.Int32 outTextCapacity,
    );
typedef _WcppTranscribeDart =
    int Function(
      ffi.Pointer<ffi.Float> pcm16k,
      int length,
      ffi.Pointer<Utf8> lang,
      ffi.Pointer<ffi.Char> outText,
      int outTextCapacity,
    );

typedef _WcppFreeNative = ffi.Void Function();
typedef _WcppFreeDart = void Function();

class WhisperBindings {
  WhisperBindings({ffi.DynamicLibrary? library}) : _library = library ?? _openLibrary() {
    _wcppInit = _library.lookupFunction<_WcppInitNative, _WcppInitDart>('wcpp_init');
    _wcppTranscribe = _library.lookupFunction<_WcppTranscribeNative, _WcppTranscribeDart>(
      'wcpp_transcribe_f32',
    );
    _wcppFree = _library.lookupFunction<_WcppFreeNative, _WcppFreeDart>('wcpp_free');
  }

  final ffi.DynamicLibrary _library;

  late final _WcppInitDart _wcppInit;
  late final _WcppTranscribeDart _wcppTranscribe;
  late final _WcppFreeDart _wcppFree;

  int init(String modelPath) {
    final ffi.Pointer<Utf8> modelPathPtr = modelPath.toNativeUtf8();
    try {
      return _wcppInit(modelPathPtr);
    } finally {
      calloc.free(modelPathPtr);
    }
  }

  WhisperTranscribeNativeResult transcribe(Float32List pcm16k, {String lang = 'ar'}) {
    final ffi.Pointer<ffi.Float> pcmPtr = calloc<ffi.Float>(pcm16k.length);
    final ffi.Pointer<Utf8> langPtr = (lang.trim().isEmpty ? 'ar' : lang).toNativeUtf8();
    const int outCapacity = 16384;
    final ffi.Pointer<ffi.Char> outPtr = calloc<ffi.Char>(outCapacity);

    try {
      pcmPtr.asTypedList(pcm16k.length).setAll(0, pcm16k);
      outPtr.value = 0;

      final int code = _wcppTranscribe(pcmPtr, pcm16k.length, langPtr, outPtr, outCapacity);
      final String text = outPtr.cast<Utf8>().toDartString();
      return WhisperTranscribeNativeResult(code: code, text: text);
    } finally {
      calloc.free(pcmPtr);
      calloc.free(langPtr);
      calloc.free(outPtr);
    }
  }

  void free() {
    _wcppFree();
  }

  static ffi.DynamicLibrary _openLibrary() {
    if (Platform.isAndroid) {
      return ffi.DynamicLibrary.open('libwcpp_bridge.so');
    }
    if (Platform.isIOS) {
      return ffi.DynamicLibrary.process();
    }

    throw UnsupportedError('Whisper FFI is only supported on Android and iOS.');
  }
}

class WhisperTranscribeNativeResult {
  const WhisperTranscribeNativeResult({required this.code, required this.text});

  final int code;
  final String text;
}
