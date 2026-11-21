#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct MicEngine MicEngine;
MicEngine *mic_create(void);
void mic_destroy(MicEngine *);
int32_t mic_start(MicEngine *, const char *input, const char *send, const char *monitor);
int32_t mic_reconnect(MicEngine *, const char *input, const char *send, const char *monitor);
void mic_stop(MicEngine *);
const char *mic_failure_stage(MicEngine *);
void mic_adjust(MicEngine *, float semitones, float reverb, int mode, float depth, float pads, float monitor);
void mic_play(MicEngine *, const float *pcm, int frames);
void mic_monitor_voice(MicEngine *, int enabled);
void mic_isolate(MicEngine *, int enabled);
float mic_peak(MicEngine *);
int mic_playing(MicEngine *);
int32_t mic_health(MicEngine *);
#ifdef __cplusplus
}
#endif
