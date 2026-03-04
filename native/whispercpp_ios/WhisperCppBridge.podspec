Pod::Spec.new do |s|
  s.name             = 'WhisperCppBridge'
  s.version          = '0.1.0'
  s.summary          = 'whisper.cpp C bridge for offline ASR in Flutter.'
  s.description      = 'Builds whisper.cpp + ggml and exposes a small C ABI for Flutter FFI.'
  s.homepage         = 'https://github.com/ggerganov/whisper.cpp'
  s.license          = { :type => 'MIT', :file => '../whispercpp/LICENSE' }
  s.author           = { 'ggml authors' => 'https://github.com/ggerganov/whisper.cpp' }
  s.source           = { :path => '.' }
  s.platform         = :ios, '13.0'
  s.requires_arc     = false

  s.source_files = [
    'src/**/*.{h,c,cc,cpp,m,mm}',
    '../whispercpp/src/whisper.cpp',
    '../whispercpp/ggml/src/ggml.c',
    '../whispercpp/ggml/src/ggml.cpp',
    '../whispercpp/ggml/src/ggml-alloc.c',
    '../whispercpp/ggml/src/ggml-backend.cpp',
    '../whispercpp/ggml/src/ggml-backend-reg.cpp',
    '../whispercpp/ggml/src/ggml-opt.cpp',
    '../whispercpp/ggml/src/ggml-quants.c',
    '../whispercpp/ggml/src/ggml-threading.cpp',
    '../whispercpp/ggml/src/gguf.cpp',
    '../whispercpp/ggml/src/ggml-cpu/*.c',
    '../whispercpp/ggml/src/ggml-cpu/*.cpp'
  ]

  s.public_header_files = 'src/include/wcpp_bridge.h'
  s.header_mappings_dir = 'src/include'

  s.pod_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'HEADER_SEARCH_PATHS' => '$(PODS_TARGET_SRCROOT)/src/include $(PODS_TARGET_SRCROOT)/../whispercpp/include $(PODS_TARGET_SRCROOT)/../whispercpp/ggml/include $(PODS_TARGET_SRCROOT)/../whispercpp/src $(PODS_TARGET_SRCROOT)/../whispercpp/ggml/src',
    'OTHER_CFLAGS' => '-DGGML_USE_ACCELERATE'
  }

  s.frameworks = 'Accelerate', 'Foundation'
  s.libraries = 'c++'
end
