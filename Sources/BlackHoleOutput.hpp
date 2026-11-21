#pragma once

#include <CoreAudio/CoreAudio.h>
#include <CoreFoundation/CoreFoundation.h>
#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>

// Write to the device's output stream only. Input and monitor keep their own clocks.
class BlackHoleOutput {
public:
    static constexpr unsigned blockSize = 256;
    using Render = void (*)(void *,float *);

    BlackHoleOutput(Render render,void *context): render(render),context(context) {}
    BlackHoleOutput(const BlackHoleOutput &) = delete;
    ~BlackHoleOutput() {
        if (running) AudioDeviceStop(device,io);
        if (io) AudioDeviceDestroyIOProcID(device,io);
    }

    OSStatus open() {
        CFStringRef uid = CFSTR("BlackHole2ch_UID");
        AudioObjectPropertyAddress lookup{kAudioHardwarePropertyTranslateUIDToDevice,kAudioObjectPropertyScopeGlobal,0};
        UInt32 size = sizeof(device);
        auto err = AudioObjectGetPropertyData(kAudioObjectSystemObject,&lookup,sizeof(uid),&uid,&size,&device);
        if (err || !device) return err ? err : kAudioHardwareBadDeviceError;

        if ((err = refreshFormat())) return err;
        if ((err = AudioDeviceCreateIOProcID(device,write,this,&io))) return err;
        AudioHardwareIOProcStreamUsage usage{};
        usage.mIOProc = reinterpret_cast<void *>(io);
        usage.mNumberStreams = 1;
        usage.mStreamIsOn[0] = 0;
        AudioObjectPropertyAddress input{kAudioDevicePropertyIOProcStreamUsage,kAudioObjectPropertyScopeInput,0};
        return AudioObjectSetPropertyData(device,&input,0,nullptr,sizeof(usage),&usage);
    }

    OSStatus start() {
        const auto err = AudioDeviceStart(device,io);
        running = err == noErr;
        return err;
    }

    OSStatus refreshFormat() {
        AudioStreamBasicDescription f{};
        AudioObjectPropertyAddress a{kAudioDevicePropertyStreamFormat,kAudioObjectPropertyScopeOutput,0};
        UInt32 size = sizeof(f);
        auto err = AudioObjectGetPropertyData(device,&a,0,nullptr,&size,&f);
        if (err) return err;
        if (f.mFormatID != kAudioFormatLinearPCM || !(f.mFormatFlags & kAudioFormatFlagIsFloat) ||
            f.mBitsPerChannel != 32 || f.mChannelsPerFrame != 2 || !std::isfinite(f.mSampleRate) ||
            f.mSampleRate < 8000 || f.mSampleRate > 768000) return kAudioDeviceUnsupportedFormatError;
        step.store(48000.0 / f.mSampleRate,std::memory_order_relaxed);
        return noErr;
    }

private:
    Render render;
    void *context;
    AudioDeviceID device = 0;
    AudioDeviceIOProcID io = nullptr;
    bool running = false;
    std::array<float,blockSize> pcm{};
    unsigned offset = blockSize;
    std::atomic<double> step{1};
    double fraction = 0;
    float current = 0,next = 0;

    float sample() {
        if (offset == blockSize) { render(context,pcm.data()); offset = 0; }
        return pcm[offset++];
    }

    static OSStatus write(AudioDeviceID,const AudioTimeStamp *,const AudioBufferList *,const AudioTimeStamp *,
                          AudioBufferList *out,const AudioTimeStamp *,void *ptr) {
        auto &s = *static_cast<BlackHoleOutput *>(ptr);
        if (!out || !out->mNumberBuffers) return noErr;
        auto &first = out->mBuffers[0];
        if (!first.mNumberChannels) return noErr;
        const UInt32 frames = first.mDataByteSize / (sizeof(float)*first.mNumberChannels);
        const double step = s.step.load(std::memory_order_relaxed);
        for (UInt32 i=0;i<frames;++i) {
            float value = s.current + (s.next-s.current)*s.fraction;
            for (UInt32 b=0;b<out->mNumberBuffers;++b) {
                const auto &buffer = out->mBuffers[b];
                if (buffer.mData) {
                    auto dst = static_cast<float *>(buffer.mData)+i*buffer.mNumberChannels;
                    std::fill_n(dst,buffer.mNumberChannels,value);
                }
            }
            s.fraction += step;
            while (s.fraction >= 1) {
                s.current = s.next; s.next = s.sample(); s.fraction -= 1;
            }
        }
        return noErr;
    }
};
