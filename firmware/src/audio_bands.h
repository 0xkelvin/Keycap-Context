/* SPDX-License-Identifier: Apache-2.0 */
#ifndef KEYCAP_AUDIO_BANDS_H
#define KEYCAP_AUDIO_BANDS_H

#include "protocol.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define KEYCAP_AUDIO_BANDS KEYCAP_LED_COUNT

/* How far a level falls per frame, as a percentage of the gap to the new
 * value. Rise is always immediate. Fixed rather than user-configurable because
 * Speed drives the colour cycle; this is tuned to read like a VU needle.
 */
#define KEYCAP_AUDIO_RELEASE 18u

/* Level held on an otherwise dark key so the device never looks faulty. */
#define KEYCAP_AUDIO_EMBER 16u

/* Beats per full turn of the colour wheel for the tempo effect. Two bars of
 * four, so the colour returns to where it started on a musical boundary.
 */
#define KEYCAP_TEMPO_BEATS_PER_CYCLE 8u

/* Frames of silence before the microphone is put to sleep. Frames arrive every
 * 16 ms, so this is about ten minutes.
 *
 * A selected effect otherwise holds the microphone powered all day whether or
 * not anything is playing. Sleeping on silence means it is live when there is
 * music, not merely when the effect is chosen.
 */
#define KEYCAP_AUDIO_SLEEP_FRAMES 37500u

/* A DC blocker and a bank of one-pole low-pass filters.
 *
 * A 256-point FFT was the obvious choice for the spectrum, but four LEDs cannot
 * show more than four buckets and cascaded one-poles reach the same visible
 * result without pulling CMSIS-DSP into the build. The shift amounts put the
 * corners near 170 Hz, 700 Hz and 1.8 kHz at 16 kHz: bass, low mid, presence
 * and air.
 *
 * Each filter keeps a scaled accumulator on purpose: a plain
 * y += (x - y) >> shift stalls once the difference falls below the shift and
 * leaves a residue large enough to hold a key lit on silence.
 */
struct keycap_audio_filters {
	int32_t dc_accumulator;
	int32_t low_accumulator;
	int32_t mid_accumulator;
	int32_t high_accumulator;
};

struct keycap_audio_energy {
	/* Mean absolute amplitude across the whole frame. */
	uint32_t overall;
	/* Mean absolute amplitude per band, lowest first. */
	uint32_t band[KEYCAP_AUDIO_BANDS];
};

void keycap_audio_filters_reset(struct keycap_audio_filters *filters);

/* Measure one frame. Both effects are fed from this single pass. */
void keycap_audio_filters_run(struct keycap_audio_filters *filters,
			      const int16_t *samples, size_t count,
			      struct keycap_audio_energy *energy);

/* One normalised channel: its own noise floor, its own peak, its own level.
 *
 * A fixed scale is the usual mistake: it reads as dead in a quiet room and
 * pinned at full next to a speaker. Tracking floor and peak per channel means
 * the display uses its whole range at any volume.
 */
struct keycap_audio_channel {
	uint32_t floor;
	uint32_t peak;
	uint8_t level;
};

struct keycap_audio_analyzer {
	struct keycap_audio_channel overall;
	struct keycap_audio_channel band[KEYCAP_AUDIO_BANDS];
	uint16_t pitch;
	uint32_t quiet_frames;
	uint32_t bass_average;
	uint32_t bass_previous;
	uint32_t beats;
	uint8_t beat_hold;
};

void keycap_audio_analyzer_init(struct keycap_audio_analyzer *analyzer);
void keycap_audio_analyzer_update(struct keycap_audio_analyzer *analyzer,
				  const struct keycap_audio_energy *energy);

/* Overall loudness, 0..255, for the level meter. */
uint8_t keycap_audio_analyzer_level(const struct keycap_audio_analyzer *analyzer);
/* One band's level, 0..255, for the spectrum. */
uint8_t keycap_audio_analyzer_band(const struct keycap_audio_analyzer *analyzer,
				   uint8_t band);

/* Where the sound currently sits in the spectrum, as a colour-wheel position
 * from red through green to violet.
 *
 * This is a centroid over raw band energy with a fixed tilt, not over the
 * normalised levels. Per-band auto-gain drives every band to full whenever it
 * sits near its own recent maximum, so the normalised levels reach 255 together
 * and preserve no balance to take a centroid of. The tilt compensates for the
 * steep falloff of musical energy with frequency, which would otherwise pin the
 * result at the bass end. A bass drop pulls it red, a cymbal crash pushes it
 * violet.
 *
 * Contributions are squared before the centroid is taken, so the loudest band
 * wins decisively. A plain mean over four bands drifts to the middle of the
 * wheel and every kind of music comes out green.
 *
 * Silence holds the last position rather than snapping back to red.
 */
uint8_t keycap_audio_analyzer_pitch(const struct keycap_audio_analyzer *analyzer);

/* Whether nothing has been playing for long enough to sleep the microphone.
 *
 * Silence is judged by how little dynamic range the overall channel has, as a
 * ratio rather than an absolute level: every room has its own noise, and a
 * fixed threshold would either never fire in one room or fire constantly in
 * another. Music keeps its peak many times its floor; a room's own noise stays
 * within a factor of two of it.
 */
bool keycap_audio_analyzer_is_quiet(const struct keycap_audio_analyzer *analyzer);

/* How many bass transients have been counted since the effect started.
 *
 * Measured on raw bass energy against its own rolling average, not on the
 * normalised level: per-band auto-gain pins a steady loud passage at full
 * scale, leaving a kick no headroom to stand out in. A transient is a property
 * of the signal, not of the display mapping.
 *
 * The count is what lets a colour advance with the music instead of with a
 * clock, so a slow track drifts and a fast one races.
 */
uint32_t keycap_audio_analyzer_beats(const struct keycap_audio_analyzer *analyzer);

/* How brightly one key burns for a given meter level, 0..255.
 *
 * The four keys are a single bar: each fills completely before the next begins,
 * and a key already full stays full. Louder lights more keys, never different
 * ones.
 */
uint8_t keycap_audio_key_fill(uint8_t level, uint8_t key);

#endif
