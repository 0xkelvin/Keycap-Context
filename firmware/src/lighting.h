/* SPDX-License-Identifier: Apache-2.0 */
#ifndef KEYCAP_LIGHTING_H
#define KEYCAP_LIGHTING_H

#include "protocol.h"

#include <stdbool.h>

#include <stdint.h>

#define KEYCAP_LIGHTING_FRAME_MS 24u

void keycap_lighting_default(struct keycap_lighting_profile *profile);
void keycap_lighting_render(const struct keycap_lighting_profile *profile,
			    uint8_t pressed_mask, uint32_t uptime_ms,
			    struct keycap_rgb colors[KEYCAP_LED_COUNT]);
void keycap_agent_render(const enum keycap_agent_state states[KEYCAP_LED_COUNT],
			 uint8_t pressed_mask, uint32_t uptime_ms,
			 struct keycap_rgb colors[KEYCAP_LED_COUNT]);

/* Render the meter as one bar across the four keys.
 *
 * Every lit key shares a single colour that walks the rainbow wheel over time
 * at the profile's speed. The level fills the keys in order, so louder sound
 * lights more of them rather than different ones, and silence leaves a dim
 * ember on the first key so the device never looks dead.
 */
void keycap_audio_render(const struct keycap_lighting_profile *profile,
			 uint8_t level, uint8_t pressed_mask, uint32_t uptime_ms,
			 struct keycap_rgb colors[KEYCAP_LED_COUNT]);

/* Render the four band levels as a spectrum, one key per band.
 *
 * Each key keeps its own colour from the profile and brightens with its band,
 * lowest frequency on key one. Unlike the meter the keys move independently, so
 * this shows what the music is made of rather than how loud it is.
 */
void keycap_spectrum_render(const struct keycap_lighting_profile *profile,
			    const uint8_t levels[KEYCAP_LED_COUNT], uint8_t pressed_mask,
			    struct keycap_rgb colors[KEYCAP_LED_COUNT]);

/* Render one colour chosen by what the music is made of.
 *
 * All four keys share a hue taken from where the sound's energy sits -- bass
 * red, mids green, treble violet -- and brighten together with its loudness.
 * Unlike the meter's rainbow the colour is not on a timer: it means something.
 */
void keycap_pitch_render(const struct keycap_lighting_profile *profile,
			 uint8_t level, uint8_t pitch, uint8_t pressed_mask,
			 struct keycap_rgb colors[KEYCAP_LED_COUNT]);

#endif
