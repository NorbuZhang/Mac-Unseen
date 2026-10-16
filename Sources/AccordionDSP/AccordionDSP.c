// Two detuned reeds and an attack/release envelope, adapted from MAcordion
// by bruiselea: https://github.com/bruiselea/MAcordion
// See Resources/Licenses/MAcordion.txt. The fixed voice bank and atomic
// controls below keep the audio callback allocation-free and non-blocking.
#include "AccordionDSP.h"
#include <math.h>
#include <stdatomic.h>
#include <stdlib.h>

typedef struct {
    float phase1, phase2, step1, step2, envelope;
} Voice;

struct MUAccordion {
    _Atomic uint32_t controls;
    _Atomic uint32_t level;
    Voice voices[17];
    double sampleRate;
    int octave;
    float gain, filtered;
};

MUAccordion *MUAccordionCreate(double sampleRate) {
    if (!isfinite(sampleRate) || sampleRate < 8000 || sampleRate > 384000)
        return NULL;
    MUAccordion *s = calloc(1, sizeof(*s));
    if (!s) return NULL;
    atomic_init(&s->controls, 4u << 17);
    atomic_init(&s->level, 0);
    if (!atomic_is_lock_free(&s->controls) || !atomic_is_lock_free(&s->level)) {
        free(s);
        return NULL;
    }
    s->sampleRate = sampleRate;
    s->octave = -1;
    return s;
}

void MUAccordionDestroy(MUAccordion *s) { free(s); }

void MUAccordionSetNotes(MUAccordion *s, uint32_t notes, int octave) {
    if (!s) return;
    octave = octave < 2 ? 2 : (octave > 6 ? 6 : octave);
    atomic_store_explicit(&s->controls, (notes & 0x1ffffu) | ((uint32_t)octave << 17), memory_order_relaxed);
}

void MUAccordionSetLevel(MUAccordion *s, float level) {
    if (!s) return;
    if (!isfinite(level)) level = 0;
    level = fminf(3, fmaxf(0, level));
    atomic_store_explicit(&s->level, (uint32_t)(level * 65535), memory_order_relaxed);
}

// PolyBLEP removes the sharp discontinuity of a naive saw wave.
static float reed(float phase, float step) {
    float correction = 0;
    if (phase < step) {
        float t = phase / step;
        correction = t + t - t * t - 1;
    } else if (phase > 1 - step) {
        float t = (phase - 1) / step;
        correction = t * t + t + t + 1;
    }
    return 2 * phase - 1 - correction;
}

void MUAccordionRender(MUAccordion *s, float *output, size_t frames) {
    if (!s || !output) return;
    uint32_t controls = atomic_load_explicit(&s->controls, memory_order_relaxed);
    int octave = (int)(controls >> 17);
    float target = atomic_load_explicit(&s->level, memory_order_relaxed) / 65535.0f;
    float rate = (float)s->sampleRate;
    if (octave != s->octave) {
        for (int i = 0; i < 17; i++) {
            float frequency = 440 * powf(2, ((octave + 1) * 12 + i - 69) / 12.0f);
            s->voices[i].step1 = fminf(0.45f, frequency * 0.9985f / rate);
            s->voices[i].step2 = fminf(0.45f, frequency * 1.0015f / rate);
        }
        s->octave = octave;
    }
    float filter = 1 - expf(-2 * 3.14159265f * fminf(7000, rate * 0.4f) / rate);
    float gainSmoothing = 1 - expf(-1 / (rate * 0.008f));
    for (size_t f = 0; f < frames; f++) {
        float sample = 0;
        s->gain += (target - s->gain) * gainSmoothing;
        for (int i = 0; i < 17; i++) {
            Voice *v = &s->voices[i];
            int held = (controls & (1u << i)) != 0;
            v->envelope = held ? fminf(1, v->envelope + 35 / rate)
                               : fmaxf(0, v->envelope - 12 / rate);
            if (v->envelope == 0) continue;
            sample += (reed(v->phase1, v->step1) + reed(v->phase2, v->step2)) * 0.5f * v->envelope;
            v->phase1 += v->step1;
            v->phase2 += v->step2;
            if (v->phase1 >= 1) v->phase1 -= 1;
            if (v->phase2 >= 1) v->phase2 -= 1;
        }
        s->filtered += (sample - s->filtered) * filter;
        float amplified = s->filtered * s->gain * 0.035f;
        // Preserve the exact gain mapping at ordinary levels. Compress only
        // peaks above the soft knee so loud chords cannot exceed full scale.
        float magnitude = fabsf(amplified);
        if (magnitude > 0.85f)
            amplified = copysignf(0.85f + 0.13f * tanhf((magnitude - 0.85f) / 0.13f), amplified);
        output[f] = amplified;
    }
}
