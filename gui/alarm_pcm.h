#pragma once
// Deterministic, original simulator alarm annunciation: 16-bit mono at 22.05 kHz.
// These tones are NOT recordings from a specific plant/OEM; do not use as a
// safety-system substitute. Audio is intentionally restrained and OS-volume controlled.
#include <cstdint>
#include <vector>

namespace thermotwin_alarm {
constexpr int sample_rate = 22050;
std::vector<std::int16_t> make_signal(int priority, int volume_pct = 65);
}
