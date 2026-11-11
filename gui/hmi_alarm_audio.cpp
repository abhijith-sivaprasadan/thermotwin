#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <mmsystem.h>
#include <algorithm>
#include <cstring>
#include <cstdint>
#include <vector>
#include "alarm_pcm.h"

// Exclusively UI-thread calls. The WinMM waveOut backend is async, keeps its
// PCM buffer alive until WHDR_DONE, and does not pause the Fortran process tick.
// Failure to open an output device is *not* permission to fake a sound.
namespace {
HWAVEOUT device = nullptr;
WAVEHDR header{};
std::vector<std::int16_t> buffer;
bool prepared = false;

void finish(bool force) {
    if (!device) return;
    if (force) waveOutReset(device);
    if (!force && !(header.dwFlags & WHDR_DONE)) return;
    if (prepared) waveOutUnprepareHeader(device,&header,sizeof(header));
    waveOutClose(device);
    device = nullptr;
    prepared = false;
    buffer.clear();
    std::memset(&header,0,sizeof(header));
}
}
extern "C" int hmi_alarm_has_audio_device() {
    return waveOutGetNumDevs() > 0 ? 1 : 0;
}
extern "C" void hmi_alarm_audio_tick() {
    finish(false);
}
extern "C" void hmi_alarm_audio_stop() {
    finish(true);
}
extern "C" int hmi_alarm_audio_play(int priority, int volume_pct) {
    finish(false);
    if (device) return 0; // previous cue still sounding; don't layer tones
    if (hmi_alarm_has_audio_device() == 0) return -2;
    buffer = thermotwin_alarm::make_signal(priority,volume_pct);
    if (buffer.empty()) return -1;
    WAVEFORMATEX format{};
    format.wFormatTag=WAVE_FORMAT_PCM;
    format.nChannels=1;
    format.nSamplesPerSec=thermotwin_alarm::sample_rate;
    format.wBitsPerSample=16;
    format.nBlockAlign=2;
    format.nAvgBytesPerSec=thermotwin_alarm::sample_rate*2;
    format.cbSize=0;
    if (waveOutOpen(&device,WAVE_MAPPER,&format,0,0,CALLBACK_NULL)!=MMSYSERR_NOERROR) {
        device=nullptr;
        buffer.clear();
        return -3;
    }
    header.lpData=reinterpret_cast<LPSTR>(buffer.data());
    header.dwBufferLength=static_cast<DWORD>(buffer.size()*sizeof(std::int16_t));
    header.dwFlags=0;
    if (waveOutPrepareHeader(device,&header,sizeof(header))!=MMSYSERR_NOERROR) {
        waveOutClose(device);device=nullptr;buffer.clear();return -4;
    }
    prepared=true;
    if (waveOutWrite(device,&header,sizeof(header))!=MMSYSERR_NOERROR) {
        finish(true);return -5;
    }
    return 1;
}
