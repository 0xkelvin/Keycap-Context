/* SPDX-License-Identifier: Apache-2.0 */
#ifndef KEYCAP_LIGHTING_H
#define KEYCAP_LIGHTING_H

#include "protocol.h"

#include <stdint.h>

#define KEYCAP_LIGHTING_FRAME_MS 24u

void keycap_lighting_default(struct keycap_lighting_profile *profile);
void keycap_lighting_render(const struct keycap_lighting_profile *profile,
			    uint8_t pressed_mask, uint32_t uptime_ms,
			    struct keycap_rgb colors[KEYCAP_LED_COUNT]);
void keycap_agent_render(const enum keycap_agent_state states[KEYCAP_LED_COUNT],
			 uint8_t pressed_mask, uint32_t uptime_ms,
			 struct keycap_rgb colors[KEYCAP_LED_COUNT]);

#endif
