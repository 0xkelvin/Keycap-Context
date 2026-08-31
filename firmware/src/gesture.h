/* SPDX-License-Identifier: Apache-2.0 */
#ifndef KEYCAP_GESTURE_H
#define KEYCAP_GESTURE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define KEYCAP_GESTURE_KEY_COUNT 4
#define KEYCAP_LONG_PRESS_MS 600u
#define KEYCAP_DOUBLE_PRESS_MS 280u

enum keycap_gesture_type {
	KEYCAP_GESTURE_SHORT,
	KEYCAP_GESTURE_LONG,
	KEYCAP_GESTURE_DOUBLE,
};

struct keycap_gesture_event {
	uint8_t key;
	enum keycap_gesture_type type;
};

struct keycap_gesture_key_state {
	bool down;
	bool long_emitted;
	bool second_press;
	bool pending_short;
	uint32_t down_at;
	uint32_t released_at;
};

struct keycap_gesture_detector {
	struct keycap_gesture_key_state keys[KEYCAP_GESTURE_KEY_COUNT];
};

void keycap_gesture_init(struct keycap_gesture_detector *detector);
size_t keycap_gesture_update(struct keycap_gesture_detector *detector,
			     uint8_t pressed_mask, uint32_t now_ms,
			     struct keycap_gesture_event *events,
			     size_t event_capacity);

#endif
