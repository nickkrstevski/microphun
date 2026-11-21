#include "Mixer.h"
#include "BlackHoleOutput.hpp"
#include <cstring>
#include "Voice.hpp"
#include "Isolation.hpp"
#include <AudioToolbox/AudioToolbox.h>
#include <CoreFoundation/CoreFoundation.h>
#include <atomic>
#include <mutex>
#include <memory>

namespace {
constexpr int block = BlackHoleOutput::blockSize;
// Each pipe has one producer and one consumer. The consumer adjusts its
// fractional read position to follow independently clocked audio devices.
class Pipe {
    static constexpr unsigned capacity = 32768;
    std::array<float, capacity> samples{};
    std::atomic<uint32_t> write{0}, read{0};
    bool primed = false;
    double fraction = 0;
public:
    void push(const float *src, uint32_t n) {
        uint32_t w = write.load(std::memory_order_relaxed);
        uint32_t space = capacity - (w - read.load(std::memory_order_acquire));
        n = std::min(n, space);
        for (unsigned i=0; i<n; ++i) samples[(w+i)%capacity] = src[i];
        write.store(w+n, std::memory_order_release);
    }
    void pull(float *dst, int n) {
        uint32_t r = read.load(std::memory_order_relaxed);
        uint32_t count = write.load(std::memory_order_acquire)-r;
        constexpr unsigned target = 3*block;
        if (count > 8*target) { r += count-target; count = target; fraction = 0; }
        if (!primed && count >= target) primed = true;
        double step = 1 + std::clamp((double(count)-target-block*.5)*.0000015, -.003, .003);
        for (int i=0; i<n; ++i) {
            if (primed && count >= 3) {
                float a = samples[r%capacity], b = samples[(r+1)%capacity];
                dst[i] = a + (b-a)*fraction;
                fraction += step;
                unsigned consumed = unsigned(fraction);
                fraction -= consumed; r += consumed; count -= consumed;
            } else { dst[i] = 0; primed = false; fraction = 0; }
        }
        read.store(r, std::memory_order_release);
    }
};
struct Session;
struct Output { Session *session; bool secondary; bool audible; AudioQueueRef queue = nullptr; };
struct Clip { const float *pcm = nullptr; int remaining = 0; };
}
struct MicEngine {
    std::unique_ptr<Session> live;
    std::atomic<float> pitch{0}, wet{0}, depth{0}, pads{.75f}, volume{.4f}, peak{0};
    std::atomic<bool> isolate{true}, monitorVoice{true};
    std::atomic<int> mode{0}, playing{0};
    std::atomic<int32_t> fault{0};
    std::mutex clipLock;
    Clip clip;
    const char *stage = "";
};
namespace {
struct Session {
    MicEngine *owner;
    Pipe inputPipe, monitorPipe;
    Voice voice;
    std::unique_ptr<Isolation> isolation;
    AudioQueueRef input = nullptr;
    Output primary, secondary;
    std::unique_ptr<BlackHoleOutput> directSend;
    bool withSecondary = false;
    std::atomic<bool> stopping{false};
    Session(MicEngine *e): owner(e), primary{this,false,false}, secondary{this,true,true} {}
    ~Session() {
        stopping.store(true);
        directSend.reset();
        for (auto q : {input,primary.queue,secondary.queue}) {
            if (q) { AudioQueueStop(q,true); AudioQueueDispose(q,true); }
        }
    }
};
AudioStreamBasicDescription format() {
    AudioStreamBasicDescription f{};
    f.mSampleRate = 48000; f.mFormatID = kAudioFormatLinearPCM;
    f.mFormatFlags = kAudioFormatFlagsNativeFloatPacked;
    f.mBytesPerPacket = f.mBytesPerFrame = sizeof(float);
    f.mFramesPerPacket = f.mChannelsPerFrame = 1; f.mBitsPerChannel = 32;
    return f;
}
OSStatus bindDevice(AudioQueueRef q, const char *uid) {
    auto ref = CFStringCreateWithCString(nullptr,uid,kCFStringEncodingUTF8);
    if (!ref) return kAudio_ParamError;
    OSStatus err = AudioQueueSetProperty(q,kAudioQueueProperty_CurrentDevice,&ref,sizeof(ref));
    CFRelease(ref); return err;
}
void inputCallback(void *p, AudioQueueRef q, AudioQueueBufferRef b,
                   const AudioTimeStamp *, UInt32, const AudioStreamPacketDescription *) {
    auto &s = *static_cast<Session*>(p);
    if (s.stopping.load()) return;
    auto *samples = static_cast<float*>(b->mAudioData);
    const int count = b->mAudioDataByteSize/sizeof(float);
    s.isolation->process(samples,count,s.owner->isolate.load());
    s.inputPipe.push(samples,count);
    if (auto err = AudioQueueEnqueueBuffer(q,b,0,nullptr)) s.owner->fault.store(err);
}
float limitMix(float sample) {
    const float a = std::abs(sample);
    return a <= .84f ? sample : std::copysign(.84f + .15f*std::tanh((a-.84f)/.15f),sample);
}
void render(Session &s, float *out, float *monitor = nullptr) {
    auto &e = *s.owner;
    s.inputPipe.pull(out,block);
    s.voice.configure(e.pitch.load(),e.wet.load(),e.mode.load(),e.depth.load());
    float pads = e.pads.load(), peak = 0;
    const bool monitorVoice = e.monitorVoice.load();
    // UI swaps an immutable sample pointer. Never block the audio callback.
    std::unique_lock<std::mutex> lock(e.clipLock, std::try_to_lock);
    for (int i=0;i<block;++i) {
        const float voice = s.voice.step(out[i]);
        float pad = 0;
        if (lock.owns_lock() && e.clip.remaining > 0) {
            pad = *e.clip.pcm++ * pads;
            --e.clip.remaining;
        }
        const float fullMix = limitMix(voice+pad);
        const float localMix = monitorVoice ? fullMix : limitMix(pad);
        if (monitor) monitor[i] = localMix;
        out[i] = s.primary.audible ? localMix : fullMix;
        peak = std::max(peak,std::abs(out[i]));
    }
    if (lock.owns_lock()) e.playing.store(e.clip.remaining > 0);
    e.peak.store(std::max(peak,e.peak.load()*.94f));
}
void renderPrimary(void *ptr,float *out) {
    auto &s = *static_cast<Session *>(ptr);
    std::array<float,block> local;
    render(s,out,s.withSecondary ? local.data() : nullptr);
    if (s.withSecondary) s.monitorPipe.push(local.data(),block);
}
void outputCallback(void *p, AudioQueueRef q, AudioQueueBufferRef b) {
    auto &o = *static_cast<Output*>(p); auto &s = *o.session;
    if (s.stopping.load()) return;
    auto out = static_cast<float*>(b->mAudioData);
    if (o.secondary) s.monitorPipe.pull(out,block);
    else renderPrimary(&s,out);
    if (o.audible) {
        float gain = s.owner->volume.load();
        for (int i=0;i<block;++i) out[i] *= gain;
    }
    b->mAudioDataByteSize = block*sizeof(float);
    if (auto err = AudioQueueEnqueueBuffer(q,b,0,nullptr)) s.owner->fault.store(err);
}
OSStatus prime(AudioQueueRef q) {
    for (int i=0;i<3;++i) {
        AudioQueueBufferRef b = nullptr;
        OSStatus err = AudioQueueAllocateBuffer(q,block*sizeof(float),&b);
        if (err) return err;
        b->mAudioDataByteSize = block*sizeof(float);
        std::fill_n(static_cast<float*>(b->mAudioData),block,0);
        if ((err = AudioQueueEnqueueBuffer(q,b,0,nullptr))) return err;
    }
    return noErr;
}
OSStatus openOutput(Output &out,const char *uid) {
    auto f = format();
    OSStatus err = AudioQueueNewOutput(&f,outputCallback,&out,nullptr,nullptr,0,&out.queue);
    if (!err) err = bindDevice(out.queue,uid);
    if (!err) err = prime(out.queue);
    return err;
}
}
MicEngine *mic_create() { return new MicEngine; }
void mic_destroy(MicEngine *e) { mic_stop(e); delete e; }
void mic_play(MicEngine *e,const float *pcm,int frames) {
    std::lock_guard<std::mutex> lock(e->clipLock);
    e->clip = {pcm,pcm ? frames : 0}; e->playing.store(e->clip.remaining>0);
}
void mic_stop(MicEngine *e) {
    e->live.reset(); mic_play(e,nullptr,0); e->peak.store(0); e->fault.store(0);
}
int32_t mic_start(MicEngine *e,const char *input,const char *send,const char *monitor) {
    mic_stop(e);
    return mic_reconnect(e,input,send,monitor);
}
int32_t mic_reconnect(MicEngine *e,const char *input,const char *send,const char *monitor) {
    // Quiesce both callbacks before replacing devices. Preserve the pad cursor across the gap.
    e->live.reset(); e->fault.store(0); e->peak.store(0);
    e->stage = "routing";
    if (!send && !monitor) return kAudio_ParamError;
    auto s = std::make_unique<Session>(e);
    s->withSecondary = send && monitor;
    s->primary.audible = !send;
    OSStatus err = 0;
    if (input) {
        s->isolation = std::make_unique<Isolation>(e->isolate.load());
        e->stage = "microphone";
        auto f = format();
        err = AudioQueueNewInput(&f,inputCallback,s.get(),nullptr,nullptr,0,&s->input);
        if (!err) err = bindDevice(s->input,input);
        if (!err) err = prime(s->input);
        if (err) return err;
    }
    e->stage = send ? "virtual microphone" : "monitor";
    if (send && std::strcmp(send,"BlackHole2ch_UID") == 0) {
        s->directSend = std::make_unique<BlackHoleOutput>(renderPrimary,s.get());
        err = s->directSend->open();
    } else {
        err = openOutput(s->primary,send ? send : monitor);
    }
    if (err) return err;
    if (s->withSecondary) {
        e->stage = "monitor";
        if ((err = openOutput(s->secondary,monitor))) return err;
    }
    if (s->input) {
        e->stage = "microphone";
        if ((err = AudioQueueStart(s->input,nullptr))) return err;
    }
    e->stage = send ? "virtual microphone" : "monitor";
    err = s->directSend ? s->directSend->start() : AudioQueueStart(s->primary.queue,nullptr);
    if (err) return err;
    if (s->withSecondary) {
        e->stage = "monitor";
        if ((err = AudioQueueStart(s->secondary.queue,nullptr))) return err;
    }
    e->live = std::move(s); return noErr;
}
const char *mic_failure_stage(MicEngine *e) { return e->stage; }
void mic_adjust(MicEngine *e,float semitones,float wet,int mode,float depth,float pads,float volume) {
    e->pitch = semitones; e->wet = wet; e->mode = mode;
    e->depth = depth; e->pads = pads; e->volume = volume;
}
void mic_monitor_voice(MicEngine *e,int enabled) { e->monitorVoice.store(enabled != 0); }
void mic_isolate(MicEngine *e,int enabled) { e->isolate.store(enabled != 0); }
float mic_peak(MicEngine *e) { return e->peak.load(); }
int mic_playing(MicEngine *e) { return e->playing.load(); }
int32_t mic_health(MicEngine *e) {
    if (!e->live) return 0;
    if (int err = e->fault.load()) return err;
    auto &s = *e->live;
    if (s.directSend) { if (auto err = s.directSend->refreshFormat()) return err; }
    for (auto q : {s.input,s.primary.queue,s.secondary.queue}) {
        if (!q) continue;
        UInt32 running = 0, size = sizeof(running);
        auto err = AudioQueueGetProperty(q,kAudioQueueProperty_IsRunning,&running,&size);
        if (err || !running) return err ? err : -1;
    }
    return 0;
}
