// Portable independent envelope/PCM test and optionally write original WAVs.
#include "alarm_pcm.h"
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>
namespace {
void need(bool ok,const char* msg){if(!ok){std::cerr<<msg<<"\n";std::exit(1);}}
void wav(const std::string& name,const std::vector<std::int16_t>& a){
    std::ofstream f(name,std::ios::binary);
    need(bool(f),"cannot write WAV preview");
    auto u16=[&](std::uint16_t n){char c[2]={char(n&255),char((n>>8)&255)};f.write(c,2);};
    auto u32=[&](std::uint32_t n){u16(std::uint16_t(n&65535));u16(std::uint16_t(n>>16));};
    f.write("RIFF",4);u32(std::uint32_t(36+a.size()*2));f.write("WAVEfmt ",8);
    u32(16);u16(1);u16(1);u32(thermotwin_alarm::sample_rate);
    u32(thermotwin_alarm::sample_rate*2);u16(2);u16(16);
    f.write("data",4);u32(std::uint32_t(a.size()*2));
    for(auto x:a)u16(static_cast<std::uint16_t>(x));
    need(bool(f),"WAV write failed");
}
}
int main(int argc,char** argv) {
    const auto critical=thermotwin_alarm::make_signal(1);
    const auto warning=thermotwin_alarm::make_signal(2);
    need(critical.size()>17500 && critical.size()<20000,"critical duration outside contract");
    need(warning.size()>14000 && warning.size()<16000,"warning duration outside contract");
    need(critical!=warning,"priority patterns must be distinct");
    need(thermotwin_alarm::make_signal(0).empty(),"invalid priority must be silent");
    need(thermotwin_alarm::make_signal(1,0).empty(),"muted signal must be empty");
    for (const auto& a:{critical,warning}) {
        need(a.front()==0 && a.back()==0,"attack/release should be silent at ends");
        auto peak=*std::max_element(a.begin(),a.end(),[](auto x,auto y){return std::abs(int(x))<std::abs(int(y));});
        need(std::abs(int(peak))<16000,"peak too high for operator audio");
        need(std::abs(int(peak))>1000,"signal unexpectedly inaudible");
        std::size_t nonzero=0;for(auto x:a)if(x!=0)++nonzero;
        need(nonzero>a.size()/2,"alarm pattern lost its tonal pulses");
        // Ensure internal silence exists (the gap is perceptible).
        auto consecutive=0; bool gap=false;
        for(auto x:a){consecutive=(x==0?consecutive+1:0);if(consecutive>2000)gap=true;}
        need(gap,"priority annunciator must contain true gap");
    }
    std::cout<<"PASS original P1/P2 PCM, gap, envelope, amplitude, distinct priority\n";
    if(argc==2) {
        const std::string dir=argv[1];
        wav(dir+"/P1-critical-original.wav",critical);
        wav(dir+"/P2-warning-original.wav",warning);
        std::cout<<"Wrote original WAV previews to "<<dir<<"\n";
    }
}
