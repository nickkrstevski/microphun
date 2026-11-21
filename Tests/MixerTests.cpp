// Exercise the same mixer and clock compensation used in the device callbacks.
#include "../Sources/Mixer.cpp"
#include <cassert>
#include <iostream>
#include <vector>
int main() {
    constexpr int rate = 48000;
    Voice clean;
    clean.configure(0,0,0,0);
    for (int n=0;n<rate;++n) {
        float input = .3f*std::sin(2*M_PI*220*n/rate);
        assert(clean.step(input) == input);
    }
    for (auto semitones : {-12, 12}) {
        Voice v; v.configure(semitones,0,0,0);
        std::vector<float> audio(rate);
        for (int i=0;i<rate;++i) audio[i] = v.step(.3f*std::sin(2*M_PI*220*i/rate));
        double largest = 0; int strongest = 0;
        for (int hz=70; hz<500; ++hz) {
            double re=0,im=0;
            for (int i=4000; i<rate; i+=4) {
                re += audio[i]*std::cos(2*M_PI*hz*i/rate);
                im += audio[i]*std::sin(2*M_PI*hz*i/rate);
            }
            if (std::hypot(re,im)>largest) { largest = std::hypot(re,im); strongest=hz; }
        }
        assert(std::abs(strongest - (semitones > 0 ? 440 : 110)) < 23);
        std::cout << "Pitch " << semitones << " st: dominant frequency " << strongest << " Hz\n";
    }
    Voice room;
    room.configure(0,1,0,0); room.step(1.f);
    float tail=0;
    for (int i=1;i<rate;++i) tail+=std::abs(room.step(0));
    assert(tail>1);
    for (int mode: {1,2,3,4,5,6}) {
        Voice v; v.configure(0,0,mode,1);
        double delta = 0;
        for (int i=0; i<rate; ++i) {
            float x = .3f*std::sin(2*M_PI*220*i/rate);
            float y=v.step(x); assert(std::isfinite(y)); delta+=std::abs(x-y);
        }
        assert(delta>100);
    }
    Radio radio;
    for (int i=0; i<rate; ++i) assert(radio.step(0)==0);
    for (int i=0; i<rate; ++i) radio.step(.2f*std::sin(2*M_PI*850*i/rate));
    double tailEnergy=0;
    for (int i=0; i<rate; ++i) {
        float y=radio.step(0);
        if (i>rate/2) assert(std::abs(y)<.00001f);
        else tailEnergy+=y*y;
    }
    assert(tailEnergy>.25);
    Isolation isolate(true), bypass(false);
    double clickEnergy=0, reducedEnergy=0;
    for (int i=0;i<rate*4;i+=block) {
        float clicks[block], clean[block];
        for (int j=0;j<block;++j) {
            int age=(i+j)%6421;
            clicks[j]=clean[j]=float(.35*std::exp(-age/57.)*
                (std::sin(1.41*age)+.4*std::cos(.173*age))*(age<420));
        }
        bypass.process(clean,block,false);
        for (int j=0;j<block;++j) assert(clean[j]==clicks[j]);
        isolate.process(clean,block,true);
        for (int j=0;j<block;++j) { clickEnergy+=clicks[j]*clicks[j]; reducedEnergy+=clean[j]*clean[j]; }
    }
    double suppression=10*std::log10(reducedEnergy/clickEnergy);
    assert(suppression < -6);
    std::cout << "Synthetic keyboard attenuation: " << suppression << " dB\n";
    auto engine=std::unique_ptr<MicEngine>(mic_create());
    Session s(engine.get());
    float original[block], out[block], clip[block];
    std::fill_n(original,block,.1f); std::fill_n(clip,block,.4f);
    for (int i=0;i<4;++i) s.inputPipe.push(original,block);
    mic_play(engine.get(),clip,block);
    render(s,out);
    for (auto sample:out) assert(std::abs(sample-.4f)<.0001f);
    assert(mic_playing(engine.get()) == 0);
    render(s,out);
    for (auto sample:out) assert(std::abs(sample-.1f)<.0001f);
    // One pad cursor feeds both buses at the same instant. Muting the local
    // voice preserves both the outgoing voice and the audible pad.
    float local[block];
    mic_monitor_voice(engine.get(),false);
    mic_play(engine.get(),clip,block);
    for (int i=0;i<3;++i) s.inputPipe.push(original,block);
    render(s,out,local);
    for (int i=0;i<block;++i) {
        assert(std::abs(out[i]-.4f)<.0001f);
        assert(std::abs(local[i]-.3f)<.0001f);
    }
    render(s,out,local);
    for (int i=0;i<block;++i) { assert(std::abs(out[i]-.1f)<.0001f); assert(local[i]==0); }
    mic_monitor_voice(engine.get(),true);
    mic_play(engine.get(),clip,block);
    render(s,out,local);
    for (int i=0;i<block;++i) assert(local[i]==out[i]);
    s.primary.audible=true;
    mic_monitor_voice(engine.get(),false);
    mic_play(engine.get(),clip,block);
    render(s,out);
    for (auto sample:out) assert(std::abs(sample-.3f)<.0001f);
    // An overfull monitor resynchronises instead of retaining stale audio.
    Pipe pipe;
    for (int i=0;i<140;++i) pipe.push(original,block);
    pipe.pull(out,block); assert(out[0] == original[0]);
    assert(mic_start(engine.get(),nullptr,nullptr,nullptr) != 0);
    std::cout << "Passed dry voice, pitch, reverb, modulation, soundboard mix, pipe and route checks.\n";
}
