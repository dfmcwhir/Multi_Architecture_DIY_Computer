// 4-voice synthesizer. A 31.25 kHz timer interrupt on core 1 mixes the voices
// and sets the sigma-delta modulator density; an RC filter on the pin turns
// the bit stream back into audio.
#pragma GCC optimize("O2")

#include "audio.h"
#include "config.h"
#include <math.h>
#include <string.h>
#include "driver/sdm.h"
#include "driver/gptimer.h"
#include "esp_attr.h"
#include "esp_log.h"

static const char *TAG = "audio";

namespace audio {

static const uint32_t ENV_MAX = 255u << 16;

struct Voice {
  uint32_t phase, inc;
  uint8_t wave, duty, vol, stage;   // stage 0 off, 1 attack, 2 decay, 3 sustain, 4 release
  uint32_t env, atk, dec, rel, sus;
  uint32_t gateLeft;                // samples until auto release, 0 = held
  uint32_t lfsr;
  int8_t noise;
};

static Voice s_v[AUDIO_VOICES];
static volatile uint8_t s_master = 200;
static DRAM_ATTR int8_t s_sine[256];
static sdm_channel_handle_t s_sdm = nullptr;

// Beep requests can come from the other core (BEL character).
static volatile uint16_t s_beepHz = 0;
static volatile uint8_t s_beepFrames = 0;
static volatile bool s_beepReq = false;

// Envelope times in ms for setting values 0..15 (SID-like).
static const uint16_t ENV_MS[16] = {2, 8, 16, 24, 38, 56, 68, 80, 100, 250, 500, 800, 1000, 3000, 5000, 8000};

static uint32_t rateFor(uint8_t setting) {
  uint32_t samples = (uint32_t)ENV_MS[setting & 15] * AUDIO_SAMPLE_RATE / 1000;
  if (!samples) samples = 1;
  return ENV_MAX / samples;
}

static inline uint32_t incFor(uint32_t hz) {
  return (uint32_t)(((uint64_t)hz << 32) / AUDIO_SAMPLE_RATE);
}

static void startGate(Voice &v, uint32_t samples) {
  v.gateLeft = samples;
  v.stage = 1;
}

static bool IRAM_ATTR onSample(gptimer_handle_t, const gptimer_alarm_event_data_t *, void *) {
  if (s_beepReq) {
    s_beepReq = false;
    Voice &v = s_v[AUDIO_VOICES - 1];
    v.inc = incFor(s_beepHz);
    v.wave = W_SQUARE; v.duty = 128; v.vol = 200;
    v.atk = ENV_MAX; v.dec = ENV_MAX; v.sus = ENV_MAX; v.rel = ENV_MAX / 200;
    v.gateLeft = (uint32_t)s_beepFrames * AUDIO_SAMPLE_RATE / 60 + 1;
    v.stage = 1;
  }
  int32_t mix = 0;
  for (int i = 0; i < AUDIO_VOICES; i++) {
    Voice &v = s_v[i];
    switch (v.stage) {
      case 0: continue;
      case 1: v.env += v.atk; if (v.env >= ENV_MAX) { v.env = ENV_MAX; v.stage = 2; } break;
      case 2:
        if (v.env <= v.sus + v.dec) { v.env = v.sus; v.stage = 3; } else v.env -= v.dec;
        break;
      case 3: break;
      case 4:
        if (v.env <= v.rel) { v.env = 0; v.stage = 0; continue; }
        v.env -= v.rel;
        break;
    }
    if (v.gateLeft && --v.gateLeft == 0 && v.stage < 4) v.stage = 4;

    uint32_t old = v.phase;
    v.phase += v.inc;
    uint8_t p = v.phase >> 24;
    int s;
    switch (v.wave) {
      case W_SQUARE:   s = p < v.duty ? 127 : -127; break;
      case W_TRIANGLE: s = p < 128 ? (int)p * 2 - 128 : 383 - (int)p * 2; break;
      case W_SAW:      s = (int)p - 128; break;
      case W_SINE:     s = s_sine[p]; break;
      default:
        if (v.phase < old) {      // wrapped: new random value
          uint32_t l = v.lfsr;
          l = (l >> 1) ^ (-(l & 1u) & 0xB400u);
          v.lfsr = l;
          v.noise = (int8_t)(l & 0xFF);
        }
        s = v.noise;
        break;
    }
    mix += (s * (int32_t)(v.env >> 16) * v.vol) >> 16;
  }
  mix = (mix * s_master) >> 9;
  if (mix > 127) mix = 127;
  if (mix < -128) mix = -128;
  sdm_channel_set_pulse_density(s_sdm, (int8_t)mix);
  return false;
}

void begin() {
  for (int i = 0; i < 256; i++) s_sine[i] = (int8_t)lrintf(127.0f * sinf(i * 2.0f * (float)M_PI / 256.0f));
  memset(s_v, 0, sizeof s_v);
  for (int i = 0; i < AUDIO_VOICES; i++) {
    s_v[i].duty = 128;
    s_v[i].vol = 200;
    s_v[i].lfsr = 0xACE1u + i;
    setEnvelope(i, 0, 0, 15, 1);
  }

  sdm_config_t sc = {};
  sc.gpio_num = PIN_AUDIO;
  sc.clk_src = SDM_CLK_SRC_DEFAULT;
  sc.sample_rate_hz = 5 * 1000 * 1000;
  ESP_ERROR_CHECK(sdm_new_channel(&sc, &s_sdm));
  ESP_ERROR_CHECK(sdm_channel_enable(s_sdm));

  gptimer_handle_t timer;
  gptimer_config_t tc = {};
  tc.clk_src = GPTIMER_CLK_SRC_DEFAULT;
  tc.direction = GPTIMER_COUNT_UP;
  tc.resolution_hz = 1000000;
  ESP_ERROR_CHECK(gptimer_new_timer(&tc, &timer));
  gptimer_event_callbacks_t cb = {};
  cb.on_alarm = onSample;
  ESP_ERROR_CHECK(gptimer_register_event_callbacks(timer, &cb, nullptr));
  gptimer_alarm_config_t ac = {};
  ac.alarm_count = 1000000 / AUDIO_SAMPLE_RATE;   // 32 us
  ac.reload_count = 0;
  ac.flags.auto_reload_on_alarm = true;
  ESP_ERROR_CHECK(gptimer_set_alarm_action(timer, &ac));
  ESP_ERROR_CHECK(gptimer_enable(timer));
  ESP_ERROR_CHECK(gptimer_start(timer));
  ESP_LOGI(TAG, "audio running at %d Hz", AUDIO_SAMPLE_RATE);
}

void setFreq(uint8_t v, uint16_t hz) { if (v < AUDIO_VOICES) s_v[v].inc = incFor(hz); }

void setWave(uint8_t v, uint8_t wave, uint8_t duty) {
  if (v >= AUDIO_VOICES) return;
  s_v[v].wave = wave > W_NOISE ? (uint8_t)W_SQUARE : wave;
  s_v[v].duty = duty ? duty : 128;
}

void setVolume(uint8_t v, uint8_t vol) { if (v < AUDIO_VOICES) s_v[v].vol = vol; }

void setEnvelope(uint8_t v, uint8_t a, uint8_t d, uint8_t s, uint8_t r) {
  if (v >= AUDIO_VOICES) return;
  Voice &x = s_v[v];
  x.atk = a ? rateFor(a) : ENV_MAX;     // 0 = instant
  x.dec = rateFor(d);
  x.sus = (uint32_t)(s & 15) * 17 << 16;
  x.rel = rateFor(r);
}

void gate(uint8_t v, bool on) {
  if (v >= AUDIO_VOICES) return;
  if (on) startGate(s_v[v], 0);
  else if (s_v[v].stage) s_v[v].stage = 4;
}

void note(uint8_t v, uint8_t midi, uint8_t frames) {
  if (v >= AUDIO_VOICES) return;
  float hz = 440.0f * powf(2.0f, ((int)midi - 69) / 12.0f);
  s_v[v].inc = (uint32_t)(hz * 4294967296.0 / AUDIO_SAMPLE_RATE);
  startGate(s_v[v], frames ? (uint32_t)frames * AUDIO_SAMPLE_RATE / 60 : 0);
}

void master(uint8_t vol) { s_master = vol; }

void beep(uint16_t hz, uint8_t frames) {
  s_beepHz = hz;
  s_beepFrames = frames;
  s_beepReq = true;
}

void stopAll() {
  for (auto &v : s_v) { v.stage = 0; v.env = 0; }
}

uint8_t activeMask() {
  uint8_t m = 0;
  for (int i = 0; i < AUDIO_VOICES; i++) if (s_v[i].stage) m |= 1 << i;
  return m;
}

} // namespace audio
