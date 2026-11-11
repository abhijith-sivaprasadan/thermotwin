#include "alarm_pcm.h"
#include <algorithm>
#include <cmath>

namespace thermotwin_alarm {
namespace {
constexpr double kTau = 6.2831853071795864769;
struct Element { double hz; int milliseconds; };
// Steady two-tone industrial-style annunciation, no siren sweeps, music or toy effects.
// All rates are *short cue patterns*, and repeat timing belongs to the Fortran alarm
// lifecycle (not the rendering function). A zero frequency denotes silence.
constexpr Element critical[] = {
    {780.0, 190}, {0.0, 95}, {990.0, 190}, {0.0, 100}, {780.0, 300}
};
constexpr Element warning[] = {
    {560.0, 260}, {0.0, 140}, {640.0, 260}
};
} // namespace

std::vector<std::int16_t> make_signal(int priority, int volume_pct) {
    if (priority != 1 && priority != 2) return {};
    if (volume_pct <= 0) return {};
    const double gain = static_cast<double>(std::clamp(volume_pct, 0, 100)) / 100.0;
    const Element* steps = priority == 1 ? critical : warning;
    const std::size_t n = priority == 1 ? sizeof(critical)/sizeof(Element) :
                                           sizeof(warning)/sizeof(Element);
    std::vector<std::int16_t> samples;
    const int total_ms = priority == 1 ? 875 : 660;
    samples.reserve(static_cast<std::size_t>((sample_rate*total_ms)/1000));
    for (std::size_t i = 0; i < n; ++i) {
        const auto& e = steps[i];
        const int count = sample_rate * e.milliseconds / 1000;
        const int ramp = sample_rate * 9 / 1000;
        for (int j = 0; j < count; ++j) {
            double v = 0.0;
            if (e.hz > 0.0) {
                // Attack/release avoids loud click transients between pulses.
                const double envelope = std::min({1.0, double(j)/std::max(1,ramp),
                             double(count-1-j)/std::max(1,ramp)});
                const double phase = kTau*e.hz*static_cast<double>(j)/sample_rate;
                // A faint harmonic gives a clean annunciator edge without distortion.
                v = (0.85*std::sin(phase) + 0.10*std::sin(2.0*phase));
                v *= std::max(0.0,envelope) * gain * 0.30;
            }
            samples.push_back(static_cast<std::int16_t>(
                std::lround(std::clamp(v,-1.0,1.0)*32767.0)));
        }
    }
    return samples;
}
}
