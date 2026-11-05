// 4-voice synthesizer (square/triangle/saw/sine/noise + ADSR) played through
// the ESP32-S3 sigma-delta modulator on PIN_AUDIO.
#pragma once
#include <stdint.h>

namespace audio {

enum : uint8_t { W_SQUARE = 0, W_TRIANGLE = 1, W_SAW = 2, W_SINE = 3, W_NOISE = 4 };

void begin();   // call on core 1 (the sample-rate timer interrupt runs there)

void setFreq(uint8_t v, uint16_t hz);
void setWave(uint8_t v, uint8_t wave, uint8_t duty);
void setVolume(uint8_t v, uint8_t vol);
void setEnvelope(uint8_t v, uint8_t a, uint8_t d, uint8_t s, uint8_t r);
void gate(uint8_t v, bool on);
void note(uint8_t v, uint8_t midi, uint8_t frames);  // frames = 1/60 s, 0 = hold
void master(uint8_t vol);
void beep(uint16_t hz, uint8_t frames);  // safe to call from either core
void stopAll();
uint8_t activeMask();

} // namespace audio
