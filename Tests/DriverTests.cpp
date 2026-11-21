#include <CoreAudio/AudioServerPlugIn.h>
#include <dlfcn.h>
#include <cstdio>
#include <cassert>
#include <cmath>
#include <array>
int main(int argc,char **argv) {
    assert(argc==2);
    void *module=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);
    if (!module) { puts(dlerror()); return 1; }
    auto factory=reinterpret_cast<void*(*)(CFAllocatorRef,CFUUIDRef)>(dlsym(module,"MicrophunFactory"));
    assert(factory);
    auto d=static_cast<AudioServerPlugInDriverRef>(factory(nullptr,kAudioServerPlugInTypeUUID));
    assert(d && !(*d)->Initialize(d,nullptr));
    auto address=[](UInt32 key,UInt32 scope) { return AudioObjectPropertyAddress{key,scope,0}; };
    auto a=address(kAudioPlugInPropertyDeviceList,kAudioObjectPropertyScopeGlobal);
    UInt32 devices[2]{}, n=0;
    assert(!(*d)->GetPropertyData(d,kAudioObjectPlugInObject,0,&a,0,nullptr,sizeof(devices),&n,devices) && n==sizeof(devices));
    UInt32 streams[2]{};
    for(int i=0;i<2;++i) {
        a=address(kAudioDevicePropertyStreams,i==0?kAudioObjectPropertyScopeInput:kAudioObjectPropertyScopeOutput);
        assert(!(*d)->GetPropertyData(d,devices[i],0,&a,0,nullptr,4,&n,&streams[i]) && n==4);
        a.mScope=i==0?kAudioObjectPropertyScopeOutput:kAudioObjectPropertyScopeInput;
        assert(!(*d)->GetPropertyDataSize(d,devices[i],0,&a,0,nullptr,&n) && n==0);
        assert(!(*d)->StartIO(d,devices[i],123));
    }
    std::array<float,256> sent{},read{};
    for(int i=0;i<256;++i) sent[i]=.3f*std::sin(.17f*i);
    AudioServerPlugInIOCycleInfo cycle{};
    for(int64_t t: {4096LL, 100000LL, 4294969400LL}) {
        cycle.mOutputTime.mSampleTime=t;
        cycle.mInputTime.mSampleTime=t+2048;
        assert(!(*d)->DoIOOperation(d,devices[1],streams[1],0,kAudioServerPlugInIOOperationWriteMix,256,&cycle,sent.data(),nullptr));
        assert(!(*d)->DoIOOperation(d,devices[0],streams[0],0,kAudioServerPlugInIOOperationReadInput,256,&cycle,read.data(),nullptr));
        assert(read==sent);
        cycle.mInputTime.mSampleTime+=256;
        assert(!(*d)->DoIOOperation(d,devices[0],streams[0],0,kAudioServerPlugInIOOperationReadInput,256,&cycle,read.data(),nullptr));
        for(float x:read) assert(x==0);
    }
    for(auto id:devices) assert(!(*d)->StopIO(d,id,123));
    puts("Packaged driver: input-only mic, output-only feed, exact PCM round trip and silence on gaps passed.");
}
