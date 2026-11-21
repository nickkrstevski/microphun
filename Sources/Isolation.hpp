#pragma once
#include "../Vendor/rnnoise/include/rnnoise.h"
#include <algorithm>
#include <array>
#include <cmath>

// Adapt arbitrary Core Audio callback sizes to 10 ms RNNoise frames.
// Each capture session owns its state. Pads enter the mixer downstream.
class Isolation {
    static constexpr int frameSize = 480;
    DenoiseState *state = rnnoise_create(nullptr);
    std::array<float,frameSize> input{}, filtered{};
    int index = 0;
    float speechGain = .22f, wet;
public:
    explicit Isolation(bool enabled): wet(enabled ? 1.f : 0.f) {
        // Initialise the FFT tables on the control thread before capture starts.
        rnnoise_process_frame(state,filtered.data(),input.data());
    }
    Isolation(const Isolation&) = delete;
    Isolation& operator=(const Isolation&) = delete;
    ~Isolation() { rnnoise_destroy(state); }

    void process(float *samples, int count, bool enabled) {
        const float target = enabled ? 1.f : 0.f;
        for (int i=0; i<count; ++i) {
            float dry = samples[i];
            input[index] = std::clamp(dry,-1.f,1.f)*32768;
            wet += std::clamp(target-wet,-.005f,.005f);
            samples[i] = dry + wet*(filtered[index]/32768.f-dry);
            if (++index != frameSize) continue;
            index = 0;
            const float probability = rnnoise_process_frame(state,filtered.data(),input.data());
            // Keep a soft floor and release slowly to preserve quiet endings.
            const float next = std::max(.22f,std::clamp((probability-.1f)*2.4f,0.f,1.f));
            const float end = speechGain+(next>speechGain ? .85f : .08f)*(next-speechGain);
            const float step = (end-speechGain)/frameSize;
            for (float &sample:filtered) { speechGain+=step; sample*=speechGain; }
            speechGain=end;
        }
    }
};
