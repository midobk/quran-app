#include <cstdio>
#include <cstring>
#include <mutex>
#include <string>

#include "whisper.h"

namespace {

constexpr int kErrInvalidArgs = 1;
constexpr int kErrModelLoadFailed = 2;
constexpr int kErrNotInitialized = 3;
constexpr int kErrTranscribeFailed = 4;

std::mutex g_mutex;
whisper_context * g_ctx = nullptr;

const char * resolve_lang(const char * lang) {
    if (lang == nullptr || lang[0] == '\0') {
        return "ar";
    }
    if (whisper_lang_id(lang) < 0) {
        return "ar";
    }
    return lang;
}

} // namespace

extern "C" {

int wcpp_init(const char * model_path) {
    if (model_path == nullptr || model_path[0] == '\0') {
        return kErrInvalidArgs;
    }

    std::lock_guard<std::mutex> lock(g_mutex);

    if (g_ctx != nullptr) {
        whisper_free(g_ctx);
        g_ctx = nullptr;
    }

    whisper_context_params cparams = whisper_context_default_params();
    g_ctx = whisper_init_from_file_with_params(model_path, cparams);

    return g_ctx == nullptr ? kErrModelLoadFailed : 0;
}

int wcpp_transcribe_f32(
    const float * pcm16k,
    int length,
    const char * lang,
    char * out_text,
    int out_text_capacity
) {
    if (pcm16k == nullptr || length <= 0 || out_text == nullptr || out_text_capacity <= 0) {
        return kErrInvalidArgs;
    }

    std::lock_guard<std::mutex> lock(g_mutex);

    if (g_ctx == nullptr) {
        return kErrNotInitialized;
    }

    whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    params.print_realtime = false;
    params.print_progress = false;
    params.print_timestamps = false;
    params.print_special = false;
    params.translate = false;
    params.no_timestamps = true;
    params.no_context = true;
    params.single_segment = true;
    params.max_tokens = 64;
    params.n_threads = 1;
    params.language = resolve_lang(lang);

    const int rc = whisper_full(g_ctx, params, pcm16k, length);
    if (rc != 0) {
        return kErrTranscribeFailed;
    }

    std::string text;
    const int segment_count = whisper_full_n_segments(g_ctx);
    for (int i = 0; i < segment_count; ++i) {
        const char * segment = whisper_full_get_segment_text(g_ctx, i);
        if (segment == nullptr) {
            continue;
        }

        if (!text.empty()) {
            text.push_back(' ');
        }
        text += segment;
    }

    std::snprintf(out_text, static_cast<size_t>(out_text_capacity), "%s", text.c_str());
    return 0;
}

void wcpp_free(void) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_ctx != nullptr) {
        whisper_free(g_ctx);
        g_ctx = nullptr;
    }
}

} // extern "C"
