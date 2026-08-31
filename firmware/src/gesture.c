/* SPDX-License-Identifier: Apache-2.0 */
#include "gesture.h"

#include <string.h>

static void emit(struct keycap_gesture_event *events, size_t capacity,
		 size_t *count, uint8_t key, enum keycap_gesture_type type)
{
	if (*count < capacity) {
		events[*count] = (struct keycap_gesture_event){.key = key, .type = type};
	}
	++(*count);
}

void keycap_gesture_init(struct keycap_gesture_detector *detector)
{
	memset(detector, 0, sizeof(*detector));
}

size_t keycap_gesture_update(struct keycap_gesture_detector *detector,
			     uint8_t pressed_mask, uint32_t now_ms,
			     struct keycap_gesture_event *events,
			     size_t event_capacity)
{
	size_t event_count = 0;

	for (uint8_t index = 0; index < KEYCAP_GESTURE_KEY_COUNT; ++index) {
		struct keycap_gesture_key_state *state = &detector->keys[index];
		bool down = (pressed_mask & (1u << index)) != 0;

		if (state->pending_short && !state->down &&
		    now_ms - state->released_at >= KEYCAP_DOUBLE_PRESS_MS) {
			state->pending_short = false;
			emit(events, event_capacity, &event_count, index + 1,
			     KEYCAP_GESTURE_SHORT);
		}

		if (down && !state->down) {
			state->down = true;
			state->down_at = now_ms;
			state->long_emitted = false;
			state->second_press = state->pending_short &&
				(now_ms - state->released_at < KEYCAP_DOUBLE_PRESS_MS);
			if (state->second_press) {
				state->pending_short = false;
			}
		} else if (!down && state->down) {
			state->down = false;
			if (state->long_emitted) {
				state->second_press = false;
			} else if (state->second_press) {
				state->second_press = false;
				emit(events, event_capacity, &event_count, index + 1,
				     KEYCAP_GESTURE_DOUBLE);
			} else if (now_ms - state->down_at >= KEYCAP_LONG_PRESS_MS) {
				emit(events, event_capacity, &event_count, index + 1,
				     KEYCAP_GESTURE_LONG);
			} else {
				state->pending_short = true;
				state->released_at = now_ms;
			}
		} else if (down && !state->long_emitted && !state->second_press &&
			   now_ms - state->down_at >= KEYCAP_LONG_PRESS_MS) {
			state->long_emitted = true;
			state->pending_short = false;
			emit(events, event_capacity, &event_count, index + 1,
			     KEYCAP_GESTURE_LONG);
		}
	}

	return event_count > event_capacity ? event_capacity : event_count;
}
