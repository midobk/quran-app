#ifndef WCPP_BRIDGE_H_
#define WCPP_BRIDGE_H_

#ifdef __cplusplus
extern "C" {
#endif

int wcpp_init(const char * model_path);

int wcpp_transcribe_f32(
    const float * pcm16k,
    int length,
    const char * lang,
    char * out_text,
    int out_text_capacity
);

void wcpp_free(void);

#ifdef __cplusplus
}
#endif

#endif  // WCPP_BRIDGE_H_
