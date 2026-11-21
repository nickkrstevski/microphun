#pragma once
#include <array>
#include "Radio.hpp"
#include <algorithm>
#include <cmath>
#include <cstdint>

// Two overlapping delay taps shift pitch while the signal keeps its original duration.
class Voice {
    static constexpr int mask = 8191;
    static constexpr float tau = 6.28318530718f;
    std::array<float, mask+1> history{}, shifted{};
    uint32_t head = 0;
    float phase = 0, lfo = 0, ring = 0, held = 0;
    float pitch = 0, ratio = 1, wet = 0, mix = 0;
    int mode = 0;
    Radio radio;
    float slowPhase = 0, fastPhase = 0, tapeTone = 0;
    struct Comb {
        std::array<float, 2400> line{};
        int cursor = 0;
        float damp = 0;
        float step(float x, int length) {
            float y = line[cursor];
            damp += .44f * (y - damp);
            line[cursor] = x + .77f * damp;
            if (++cursor == length) cursor = 0;
            return y;
        }
    };
    std::array<Comb, 4> combs{};
    std::array<float, 257> diffuser{};
    int di = 0;
    float tap(const std::array<float, mask+1>& line, float delay) {
        int i = (int)delay;
        float frac = delay-i;
        return line[(head-i)&mask]*(1-frac) + line[(head-i-1)&mask]*frac;
    }
public:
    void configure(float semitones, float reverb, int type, float depth) {
        pitch = semitones;
        ratio = std::pow(2.f, pitch / 12.f);
        if (type == 4 && mode != type) radio = Radio{};
        wet = reverb; mix = depth; mode = type;
    }
    float step(float x) {
        history[head & mask] = x;
        float v = x;
        if (std::abs(pitch) > .01f) {
            constexpr float window = 2048.f;
            phase += (1-ratio)/window;
            phase -= std::floor(phase);
            float b = phase < .5f ? phase + .5f : phase - .5f;
            float w = .5f - .5f*std::cos(tau*phase);
            v = w*tap(history, 2+phase*window) + (1-w)*tap(history, 2+b*window);
        }
        shifted[head & mask] = v;
        ring += 64.f/48000; if (ring >= 1) ring -= 1;
        lfo += 5.4f/48000; if (lfo >= 1) lfo -= 1;
        slowPhase += .72f/48000; if (slowPhase >= 1) slowPhase -= 1;
        fastPhase += 7.1f/48000; if (fastPhase >= 1) fastPhase -= 1;
        float fx = v;
        switch (mode) {
        case 1: fx = v * std::cos(tau*ring); break;
        case 2: fx = tap(shifted, 150.f + 133.f*std::sin(tau*lfo)); break;
        case 3:
            if ((head & 7) == 0) held = std::round(v * 24.f)/24.f;
            fx = held; break;
        case 4: fx = radio.step(v); break;
        case 5: {
            const float a = tap(shifted, 790 + 92*std::sin(tau*slowPhase));
            const float b = tap(shifted, 1270 + 137*std::sin(tau*(slowPhase+.31f)));
            const float c = tap(shifted, 1640 + 49*std::sin(tau*lfo));
            fx = .40f*v + .31f*a + .27f*b + .23f*c;
            break;
        }
        case 6: {
            const float wow = 175 + 120*std::sin(tau*slowPhase) + 19*std::sin(tau*fastPhase);
            const float echo = .28f*tap(shifted, 4560+wow);
            tapeTone += .29f*(tap(shifted,wow)+echo-tapeTone);
            fx = .70f*std::tanh(2.3f*tapeTone);
            break;
        }
        }
        ++head;
        v += mix * (fx-v);
        constexpr int lengths[] = {1429, 1613, 1867, 2137};
        float reflections = 0;
        for (int i=0; i<4; ++i) reflections += combs[i].step(v, lengths[i]) * .25f;
        float delayed = diffuser[di];
        float diffuse = delayed - .55f*reflections;
        diffuser[di] = reflections + .55f*diffuse;
        if (++di == int(diffuser.size())) di = 0;
        return v*(1-.52f*wet) + diffuse*wet;
    }
};
