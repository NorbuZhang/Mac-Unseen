#ifndef MU_ACCORDION_DSP_H
#define MU_ACCORDION_DSP_H
#include <stdint.h>
#include <stddef.h>

typedef struct MUAccordion MUAccordion;
MUAccordion *MUAccordionCreate(double sampleRate);
void MUAccordionDestroy(MUAccordion *state);
// Control-thread calls. Each bit selects one chromatic note, C through E
// in the following octave (17 voices); octave 4 starts at middle C.
void MUAccordionSetNotes(MUAccordion *state, uint32_t notes, int octave);
// Expression times master gain, 0...3 relative to the original output level.
void MUAccordionSetLevel(MUAccordion *state, float level);
// Single audio-thread call: no locks, allocation, or external resources.
void MUAccordionRender(MUAccordion *state, float *output, size_t frames);
#endif
