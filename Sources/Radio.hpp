#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>

// A voice-operated, narrow-band radio channel at 48 kHz.
class Radio {
    struct Filter {
        float b0,b1,b2,a1,a2;
        float z1=0,z2=0;
        float step(float x) {
            const float y=b0*x+z1;
            z1=b1*x-a1*y+z2; z2=b2*x-a2*y;
            return y;
        }
        static Filter butterworth(float hz,bool highpass) {
            const float w=6.283185307f*hz/48000.f;
            const float c=std::cos(w), a=std::sin(w)*.70710678f;
            const float b0=(highpass ? 1+c : 1-c)*.5f/(1+a);
            return {b0,highpass ? -2*b0 : 2*b0,b0,-2*c/(1+a),(1-a)/(1+a)};
        }
    };
    Filter high=Filter::butterworth(370,true), low=Filter::butterworth(2550,false);
    Filter outputLow=Filter::butterworth(3060,false);
    float envelope=0, gate=0, noiseLow=0, chirpPhase=0;
    int hold=0, keyedSamples=0, tail=0;
    bool keyed=false;
    uint32_t noise=0x43af9c17;
public:
    float step(float x) {
        const float band=low.step(high.step(x));
        const float amplitude=std::abs(band);
        envelope+=(amplitude>envelope ? .011f : .00065f)*(amplitude-envelope);
        if (envelope>.0035f) { hold=7200; keyed=true; tail=0; }
        else if (hold>0) --hold;
        else if (keyed) {
            // Short syllable gaps keep the carrier up. End a phrase with a radio chirp.
            tail=keyedSamples>8200 ? 3600 : 0;
            keyed=false; keyedSamples=0; chirpPhase=0;
        }
        if (keyed) keyedSamples=std::min(keyedSamples+1,48000);
        gate+=(keyed ? .012f : .0015f)*((keyed ? 1.f : 0.f)-gate);
        noise^=noise<<13; noise^=noise>>17; noise^=noise<<5;
        const float white=float(noise>>8)*(2.f/16777216.f)-1.f;
        noiseLow+=.26f*(white-noiseLow);
        const float gain=std::min(6.f, .90f/std::sqrt(envelope+.001f));
        const float voice=.72f*std::tanh(band*gain*2.8f);
        float signal=gate*(voice + .023f*(white-noiseLow));
        if (tail>0) {
            const float fade=std::min({1.f,(3600-tail)/150.f,tail/500.f});
            signal+=fade*(.060f*std::sin(chirpPhase)+.020f*white);
            chirpPhase+=6.283185307f*2475/48000;
            if (chirpPhase>=6.283185307f) chirpPhase-=6.283185307f;
            --tail;
        }
        return outputLow.step(signal);
    }
};
