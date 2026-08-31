/* SPDX-License-Identifier: Apache-2.0 */
#ifndef KEYCAP_AUDIO_H
#define KEYCAP_AUDIO_H

#include "audio_bands.h"

#include <stdbool.h>
#include <stdint.h>

struct keycap_audio_frame {
	/* Overall loudness, 0..255, spread across the keys as one bar. */
	uint8_t level;
	/* Per-band levels, 0..255, lowest band first. */
	uint8_t band[KEYCAP_AUDIO_BANDS];
	/* Colour-wheel position of the sound's current centre of gravity. */
	uint8_t pitch;
	/* Nothing has played for long enough to power the microphone down. */
	bool quiet;
	/* Bass transients counted so far, for effects that advance with the
	 * music rather than with a clock.
	 */
	uint32_t beats;
};

/* Power the microphone and begin analysis. Idempotent.
 *
 * The microphone is only powered while the audio effect is selected: the
 * regulator is switched off again on stop, so "off" means unpowered rather
 * than merely ignored.
 */
int keycap_audio_start(void);
void keycap_audio_stop(void);
bool keycap_audio_is_running(void);

/* Latest analysis. Lock-free and safe to call from any thread. */
void keycap_audio_get(struct keycap_audio_frame *frame);

#endif
