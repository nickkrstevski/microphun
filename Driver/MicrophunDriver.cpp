// Two single-direction Core Audio devices, one sample clock, one local audio path.
#include <CoreAudio/AudioServerPlugIn.h>
#include <CoreFoundation/CFPlugInCOM.h>
#include <mach/mach_time.h>
#include <array>
#include <atomic>
#include <algorithm>
#include <cmath>
#include <cstring>
#include <limits>

namespace {
using Driver = AudioServerPlugInDriverRef;
using ID = AudioObjectID;
using Address = AudioObjectPropertyAddress;
using Cycle = AudioServerPlugInIOCycleInfo;
constexpr ID plugin = kAudioObjectPlugInObject, mic = 2, feed = 3, micStream = 4, feedStream = 5;
constexpr UInt32 rate = 48000, period = 512, delay = 2048, capacity = 32768;
constexpr auto global = kAudioObjectPropertyScopeGlobal;
constexpr auto input = kAudioObjectPropertyScopeInput, output = kAudioObjectPropertyScopeOutput;
CFStringRef micUID() { return CFSTR("com.nickkrstevski.microphun.mic"); }
CFStringRef feedUID() { return CFSTR("com.nickkrstevski.microphun.send"); }
std::atomic<UInt32> clients[2]{}, active[2]{1,1};
std::atomic<ULONG> refs{1};
AudioServerPlugInHostRef host;
uint64_t origin;
double ticksPerFrame;
static_assert(std::atomic<uint64_t>::is_always_lock_free);
// Each slot atomically publishes one Float32 together with its sample-time tag.
std::array<std::atomic<uint64_t>,capacity> samples{};
std::atomic<int64_t> beginSample{0}, endSample{0};
bool device(ID id) { return id==mic || id==feed; }
bool stream(ID id) { return id==micStream || id==feedStream; }
int side(ID id) { return id==mic || id==micStream ? 0 : 1; }

AudioStreamBasicDescription format() {
    AudioStreamBasicDescription f{};
    f.mSampleRate=rate; f.mFormatID=kAudioFormatLinearPCM; f.mFormatFlags=kAudioFormatFlagsNativeFloatPacked;
    f.mFramesPerPacket=1; f.mChannelsPerFrame=1; f.mBitsPerChannel=32; f.mBytesPerFrame=f.mBytesPerPacket=4;
    return f;
}
struct Reply {
    UInt32 available;
    UInt32 *used;
    void *buffer;
    OSStatus bytes(const void *p, UInt32 size) {
        *used=size;
        if (!buffer) return noErr;
        if (size>available) return kAudioHardwareBadPropertySizeError;
        if (size) std::memcpy(buffer,p,size);
        return noErr;
    }
    template<class T> OSStatus value(T v) { return bytes(&v,sizeof(v)); }
    OSStatus stringValue(CFStringRef s) {
        auto status=value(s);
        if (buffer && !status) CFRetain(s);
        return status;
    }
    OSStatus ids(const ID *p,UInt32 n) {
        if (buffer) n=std::min(n,UInt32(available/sizeof(ID)));
        return bytes(p,n*sizeof(ID));
    }
};
OSStatus property(ID id,const Address &a,UInt32 qsize,const void *q,Reply r) {
    if (id!=plugin && !device(id) && !stream(id)) return kAudioHardwareBadObjectError;
    if (a.mElement!=kAudioObjectPropertyElementMain) return kAudioHardwareUnknownPropertyError;
    const bool isMic=side(id)==0;
    const bool matches=a.mScope==global || a.mScope==(isMic ? input : output);
    const ID devices[]={mic,feed}, child=isMic ? micStream : feedStream;
    const AudioClassID klass=id==plugin ? kAudioPlugInClassID : device(id) ? kAudioDeviceClassID : kAudioStreamClassID;
    switch(a.mSelector) {
    case kAudioObjectPropertyBaseClass: return r.value<AudioClassID>(kAudioObjectClassID);
    case kAudioObjectPropertyClass: return r.value(klass);
    case kAudioObjectPropertyOwner: return r.value<ID>(id==plugin ? kAudioObjectUnknown : device(id) ? plugin : isMic ? mic : feed);
    case kAudioObjectPropertyName: return r.stringValue(id==plugin ? CFSTR("Microphun Audio") : isMic ? CFSTR("Microphun Mic") : CFSTR("Microphun Send"));
    case kAudioObjectPropertyManufacturer: return r.stringValue(CFSTR("Microphun"));
    case kAudioObjectPropertyOwnedObjects:
        if (id==plugin) return r.ids(devices,2);
        return r.ids(&child,device(id) && matches ? 1 : 0);
    }
    if (id==plugin) switch(a.mSelector) {
    case kAudioPlugInPropertyBundleID: return r.stringValue(CFSTR("com.nickkrstevski.microphun.driver"));
    case kAudioPlugInPropertyDeviceList: return r.ids(devices,2);
    case kAudioPlugInPropertyBoxList: case kAudioPlugInPropertyClockDeviceList: return r.bytes(nullptr,0);
    case kAudioPlugInPropertyTranslateUIDToDevice: {
        ID found=kAudioObjectUnknown;
        if (q && qsize==sizeof(CFStringRef)) {
            auto uid=*static_cast<const CFStringRef*>(q);
            if (uid && CFEqual(uid,micUID())) found=mic;
            if (uid && CFEqual(uid,feedUID())) found=feed;
        }
        return r.value(found);
    }}
    if (device(id)) switch(a.mSelector) {
    case kAudioDevicePropertyDeviceUID: return r.stringValue(isMic ? micUID() : feedUID());
    case kAudioDevicePropertyModelUID: return r.stringValue(isMic ? CFSTR("MicrophunInput.v1") : CFSTR("MicrophunSend.v1"));
    case kAudioDevicePropertyTransportType: return r.value<UInt32>(kAudioDeviceTransportTypeVirtual);
    case kAudioDevicePropertyClockDomain: return r.value<UInt32>(0);
    case kAudioDevicePropertyDeviceIsAlive: return r.value<UInt32>(1);
    case kAudioDevicePropertyDeviceIsRunning: return r.value<UInt32>(clients[side(id)].load()!=0);
    case kAudioDevicePropertyDeviceCanBeDefaultDevice: return r.value<UInt32>(isMic && a.mScope==input);
    case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice: case kAudioDevicePropertyIsHidden:
    case kAudioDevicePropertySafetyOffset: return r.value<UInt32>(0);
    case kAudioDevicePropertyLatency: return r.value<UInt32>(isMic ? delay : 0);
    case kAudioDevicePropertyStreams: return r.ids(&child,matches ? 1 : 0);
    case kAudioObjectPropertyControlList: return r.bytes(nullptr,0);
    case kAudioDevicePropertyNominalSampleRate: return r.value<Float64>(rate);
    case kAudioDevicePropertyAvailableNominalSampleRates: return r.value(AudioValueRange{rate,rate});
    case kAudioDevicePropertyZeroTimeStampPeriod: return r.value<UInt32>(period);
    }
    if (stream(id)) switch(a.mSelector) {
    case kAudioStreamPropertyDirection: return r.value<UInt32>(isMic);
    case kAudioStreamPropertyIsActive: return r.value<UInt32>(active[side(id)].load());
    case kAudioStreamPropertyStartingChannel: return r.value<UInt32>(1);
    case kAudioStreamPropertyLatency: return r.value<UInt32>(0);
    case kAudioStreamPropertyTerminalType: return r.value<UInt32>(isMic ? kAudioStreamTerminalTypeMicrophone : kAudioStreamTerminalTypeLine);
    case kAudioStreamPropertyPhysicalFormat: case kAudioStreamPropertyVirtualFormat: return r.value(format());
    case kAudioStreamPropertyAvailablePhysicalFormats: case kAudioStreamPropertyAvailableVirtualFormats:
        return r.value(AudioStreamRangedDescription{format(),{rate,rate}});
    }
    return kAudioHardwareUnknownPropertyError;
}
Boolean has(Driver,ID id,pid_t,const Address *a) {
    UInt32 n=0; return a && property(id,*a,0,nullptr,{0,&n,nullptr})==noErr;
}
OSStatus size(Driver,ID id,pid_t,const Address *a,UInt32 qn,const void *q,UInt32 *n) {
    return a && n ? property(id,*a,qn,q,{0,n,nullptr}) : kAudioHardwareIllegalOperationError;
}
OSStatus get(Driver,ID id,pid_t,const Address *a,UInt32 qn,const void *q,UInt32 n,UInt32 *used,void *out) {
    return a && used && (out || n==0) ? property(id,*a,qn,q,{n,used,out}) : kAudioHardwareIllegalOperationError;
}
OSStatus canSet(Driver d,ID id,pid_t p,const Address *a,Boolean *yes) {
    if (!yes || !has(d,id,p,a)) return kAudioHardwareUnknownPropertyError;
    *yes=(stream(id) && (a->mSelector==kAudioStreamPropertyIsActive || a->mSelector==kAudioStreamPropertyPhysicalFormat || a->mSelector==kAudioStreamPropertyVirtualFormat))
        || (device(id) && a->mSelector==kAudioDevicePropertyNominalSampleRate);
    return noErr;
}
OSStatus set(Driver d,ID id,pid_t pid,const Address *a,UInt32,const void*,UInt32 n,const void *p) {
    Boolean ok=false;
    if (!p || canSet(d,id,pid,a,&ok) || !ok) return kAudioHardwareIllegalOperationError;
    if (a->mSelector==kAudioStreamPropertyIsActive) {
        if (n!=sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
        UInt32 v=!!*static_cast<const UInt32*>(p);
        if (active[side(id)].exchange(v)!=v && host) host->PropertiesChanged(host,id,1,a);
        return noErr;
    }
    if (a->mSelector==kAudioDevicePropertyNominalSampleRate) {
        if (n!=sizeof(Float64)) return kAudioHardwareBadPropertySizeError;
        return *static_cast<const Float64*>(p)==rate ? noErr : kAudioDeviceUnsupportedFormatError;
    }
    if (n!=sizeof(AudioStreamBasicDescription)) return kAudioHardwareBadPropertySizeError;
    auto f=format(); return std::memcmp(&f,p,sizeof(f))==0 ? noErr : kAudioDeviceUnsupportedFormatError;
}
OSStatus init(Driver,AudioServerPlugInHostRef h) {
    host=h; mach_timebase_info_data_t tb{}; mach_timebase_info(&tb);
    ticksPerFrame=(1e9/rate)*tb.denom/tb.numer; origin=mach_absolute_time(); return noErr;
}
OSStatus start(Driver,ID id,UInt32) {
    if (!device(id)) return kAudioHardwareBadDeviceError;
    if (clients[side(id)].fetch_add(1)==0 && id==feed) { beginSample=0; endSample=0; }
    return noErr;
}
OSStatus stop(Driver,ID id,UInt32) {
    if (!device(id)) return kAudioHardwareBadDeviceError;
    auto &count=clients[side(id)];
    UInt32 n=count.load();
    while (n && !count.compare_exchange_weak(n,n-1)) {}
    return noErr;
}
OSStatus timestamp(Driver,ID id,UInt32,Float64 *sample,UInt64 *hostTime,UInt64 *seed) {
    if (!device(id) || !sample || !hostTime || !seed) return kAudioHardwareIllegalOperationError;
    const auto periods=uint64_t((mach_absolute_time()-origin)/(period*ticksPerFrame));
    *sample=periods*period; *hostTime=origin+uint64_t(*sample*ticksPerFrame); *seed=1;
    return noErr;
}
OSStatus will(Driver,ID id,UInt32,UInt32 op,Boolean *yes,Boolean *inPlace) {
    if (!device(id) || !yes || !inPlace) return kAudioHardwareIllegalOperationError;
    *yes=(id==mic && op==kAudioServerPlugInIOOperationReadInput) || (id==feed && op==kAudioServerPlugInIOOperationWriteMix);
    *inPlace=true; return noErr;
}
OSStatus boundary(Driver,ID,UInt32,UInt32,UInt32,const Cycle*) { return noErr; }
OSStatus io(Driver,ID id,ID streamID,UInt32,UInt32 op,UInt32 n,const Cycle *cycle,void *buf,void*) {
    if (!cycle || !buf || n>capacity) return kAudioHardwareIllegalOperationError;
    auto *v=static_cast<float*>(buf);
    if (id==feed && streamID==feedStream && op==kAudioServerPlugInIOOperationWriteMix) {
        int64_t first=int64_t(cycle->mOutputTime.mSampleTime);
        if (first!=endSample.load()) beginSample=first;
        for (UInt32 i=0;i<n;++i) {
            uint32_t bits=0; if (active[1].load(std::memory_order_relaxed)) std::memcpy(&bits,v+i,4);
            uint64_t t=first+i; samples[t%capacity].store((t<<32)|bits,std::memory_order_relaxed);
        }
        endSample.store(first+n,std::memory_order_release);
    } else if (id==mic && streamID==micStream && op==kAudioServerPlugInIOOperationReadInput) {
        const int64_t end=endSample.load(std::memory_order_acquire);
        const int64_t begin=std::max(beginSample.load(),end-capacity);
        const bool enabled=clients[1].load() && active[0].load();
        const int64_t first=int64_t(cycle->mInputTime.mSampleTime)-delay;
        for (UInt32 i=0;i<n;++i) {
            int64_t t=first+i; uint32_t bits=0;
            if (enabled && t>=begin && t<end && t>=0) {
                auto slot=samples[t%capacity].load(std::memory_order_relaxed);
                if (uint32_t(slot>>32)==uint32_t(t)) bits=uint32_t(slot);
            }
            std::memcpy(v+i,&bits,4);
        }
    } else return kAudioHardwareUnsupportedOperationError;
    return noErr;
}
extern AudioServerPlugInDriverInterface api;
AudioServerPlugInDriverInterface *apiPtr=&api;
ULONG retain(void*) { return ++refs; }
ULONG release(void*) { auto n=refs.load(); while(n>1 && !refs.compare_exchange_weak(n,n-1)) {} return n>1?n-1:1; }
HRESULT query(void*,REFIID iid,LPVOID *out) {
    if (!out) return E_POINTER;
    *out=nullptr;
    auto uuid=CFUUIDCreateFromUUIDBytes(nullptr,iid);
    const bool ok=CFEqual(uuid,IUnknownUUID) || CFEqual(uuid,kAudioServerPlugInDriverInterfaceUUID);
    CFRelease(uuid);
    if (!ok) return E_NOINTERFACE;
    *out=&apiPtr; retain(nullptr); return S_OK;
}
OSStatus create(Driver,CFDictionaryRef,const AudioServerPlugInClientInfo*,ID*) { return kAudioHardwareUnsupportedOperationError; }
OSStatus destroy(Driver,ID) { return kAudioHardwareUnsupportedOperationError; }
OSStatus client(Driver,ID id,const AudioServerPlugInClientInfo*) { return device(id)?noErr:kAudioHardwareBadDeviceError; }
OSStatus config(Driver,ID,UInt64,void*) { return noErr; }
AudioServerPlugInDriverInterface api={nullptr,query,retain,release,init,create,destroy,client,client,config,config,
    has,canSet,size,get,set,start,stop,timestamp,will,boundary,io,boundary};
}
extern "C" __attribute__((visibility("default"))) void *MicrophunFactory(CFAllocatorRef,CFUUIDRef type) {
    if (!CFEqual(type,kAudioServerPlugInTypeUUID)) return nullptr;
    retain(nullptr); return &apiPtr;
}
