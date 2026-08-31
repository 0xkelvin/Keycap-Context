/* SPDX-License-Identifier: Apache-2.0 */
#ifndef KEYCAP_PROTOCOL_H
#define KEYCAP_PROTOCOL_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define KEYCAP_LINE_MAX 160
#define KEYCAP_LED_COUNT 4

enum keycap_command_type {
	KEYCAP_COMMAND_INVALID = 0,
	KEYCAP_COMMAND_PING,
	KEYCAP_COMMAND_KEEPALIVE,
	KEYCAP_COMMAND_LEDS,
	KEYCAP_COMMAND_STATUS,
	KEYCAP_COMMAND_LIGHTING,
	KEYCAP_COMMAND_AGENTS,
};

enum keycap_agent_state {
	KEYCAP_AGENT_EMPTY,
	KEYCAP_AGENT_IDLE,
	KEYCAP_AGENT_WORKING,
	KEYCAP_AGENT_WAITING,
	KEYCAP_AGENT_DONE,
	KEYCAP_AGENT_ERROR,
	KEYCAP_AGENT_RISK,
};

enum keycap_status {
	KEYCAP_STATUS_IDLE,
	KEYCAP_STATUS_WAITING,
	KEYCAP_STATUS_SUCCESS,
	KEYCAP_STATUS_ERROR,
	KEYCAP_STATUS_PAUSED,
};

struct keycap_rgb {
	uint8_t red;
	uint8_t green;
	uint8_t blue;
};

enum keycap_lighting_mode {
	KEYCAP_LIGHTING_RAINBOW,
	KEYCAP_LIGHTING_WAVE,
	KEYCAP_LIGHTING_BREATHING,
	KEYCAP_LIGHTING_REACTIVE,
	KEYCAP_LIGHTING_STATIC,
	KEYCAP_LIGHTING_OFF,
	KEYCAP_LIGHTING_AUDIO,
	KEYCAP_LIGHTING_SPECTRUM,
	KEYCAP_LIGHTING_PITCH,
	KEYCAP_LIGHTING_TEMPO,
};

struct keycap_lighting_profile {
	enum keycap_lighting_mode mode;
	uint8_t brightness;
	uint8_t speed;
	struct keycap_rgb key_colors[KEYCAP_LED_COUNT];
};

struct keycap_command {
	enum keycap_command_type type;
	struct keycap_rgb leds[KEYCAP_LED_COUNT];
	enum keycap_status status;
	uint8_t active_choices;
	bool has_status_color;
	struct keycap_rgb status_color;
	struct keycap_lighting_profile lighting;
	enum keycap_agent_state agents[KEYCAP_LED_COUNT];
};

bool keycap_protocol_parse(const char *line, struct keycap_command *command);
int keycap_protocol_format_button(char *buffer, size_t capacity, uint8_t key,
				  bool down, uint32_t sequence);
int keycap_protocol_format_gesture(char *buffer, size_t capacity, uint8_t key,
				   const char *gesture, uint32_t sequence);

#endif
