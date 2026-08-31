/* SPDX-License-Identifier: Apache-2.0 */
#include "protocol.h"

#include <stdio.h>
#include <string.h>

static int hex_value(char value)
{
	if (value >= '0' && value <= '9') {
		return value - '0';
	}
	if (value >= 'A' && value <= 'F') {
		return value - 'A' + 10;
	}
	if (value >= 'a' && value <= 'f') {
		return value - 'a' + 10;
	}
	return -1;
}

static bool parse_color(const char *text, struct keycap_rgb *color)
{
	uint8_t bytes[3];

	for (size_t byte = 0; byte < 3; ++byte) {
		int high = hex_value(text[byte * 2]);
		int low = hex_value(text[byte * 2 + 1]);
		if (high < 0 || low < 0) {
			return false;
		}
		bytes[byte] = (uint8_t)((high << 4) | low);
	}

	color->red = bytes[0];
	color->green = bytes[1];
	color->blue = bytes[2];
	return true;
}

static bool parse_colors(const char *text,
			 struct keycap_rgb colors[KEYCAP_LED_COUNT])
{
	if (strlen(text) != KEYCAP_LED_COUNT * 6u + KEYCAP_LED_COUNT - 1u) {
		return false;
	}
	for (size_t index = 0; index < KEYCAP_LED_COUNT; ++index) {
		if (!parse_color(text, &colors[index])) {
			return false;
		}
		text += 6;
		if (index + 1u < KEYCAP_LED_COUNT && *text++ != ',') {
			return false;
		}
	}
	return true;
}

static bool parse_lighting_mode(const char *text, enum keycap_lighting_mode *mode)
{
	static const char *const names[] = {
		"RAINBOW", "WAVE", "BREATHING", "REACTIVE", "STATIC", "OFF",
	};
	for (size_t index = 0; index < sizeof(names) / sizeof(names[0]); ++index) {
		if (strcmp(text, names[index]) == 0) {
			*mode = (enum keycap_lighting_mode)index;
			return true;
		}
	}
	return false;
}

static bool parse_agent_state(const char *text, size_t length,
			      enum keycap_agent_state *state)
{
	static const char *const names[] = {
		"EMPTY", "IDLE", "WORKING", "WAITING", "DONE", "ERROR", "RISK",
	};
	for (size_t index = 0; index < sizeof(names) / sizeof(names[0]); ++index) {
		if (strlen(names[index]) == length && strncmp(text, names[index], length) == 0) {
			*state = (enum keycap_agent_state)index;
			return true;
		}
	}
	return false;
}

static bool parse_agent_states(const char *text,
			       enum keycap_agent_state states[KEYCAP_LED_COUNT])
{
	for (size_t index = 0; index < KEYCAP_LED_COUNT; ++index) {
		const char *end = index + 1u == KEYCAP_LED_COUNT ? text + strlen(text) : strchr(text, ',');
		if (end == NULL || end == text || !parse_agent_state(text, (size_t)(end - text), &states[index])) {
			return false;
		}
		text = end + (index + 1u < KEYCAP_LED_COUNT ? 1 : 0);
	}
	return *text == '\0';
}

bool keycap_protocol_parse(const char *line, struct keycap_command *command)
{
	static const size_t color_length = 6;
	static const size_t payload_length = KEYCAP_LED_COUNT * color_length +
					     (KEYCAP_LED_COUNT - 1);

	memset(command, 0, sizeof(*command));
	if (strcmp(line, "PING") == 0) {
		command->type = KEYCAP_COMMAND_PING;
		return true;
	}
	if (strcmp(line, "KEEPALIVE") == 0) {
		command->type = KEYCAP_COMMAND_KEEPALIVE;
		return true;
	}
	if (strcmp(line, "STATUS IDLE") == 0) {
		command->type = KEYCAP_COMMAND_STATUS;
		command->status = KEYCAP_STATUS_IDLE;
		return true;
	}
	if (strcmp(line, "STATUS SUCCESS") == 0) {
		command->type = KEYCAP_COMMAND_STATUS;
		command->status = KEYCAP_STATUS_SUCCESS;
		return true;
	}
	if (strcmp(line, "STATUS ERROR") == 0) {
		command->type = KEYCAP_COMMAND_STATUS;
		command->status = KEYCAP_STATUS_ERROR;
		return true;
	}
	if (strcmp(line, "STATUS PAUSED") == 0) {
		command->type = KEYCAP_COMMAND_STATUS;
		command->status = KEYCAP_STATUS_PAUSED;
		return true;
	}
	if (strncmp(line, "AGENTS ", 7) == 0 &&
	    parse_agent_states(line + 7, command->agents)) {
		command->type = KEYCAP_COMMAND_AGENTS;
		return true;
	}
	char mode_text[16];
	char colors_text[32];
	char trailing;
	unsigned int brightness;
	unsigned int speed;
	if (sscanf(line, "LIGHTING %15s %u %u %31s%c", mode_text, &brightness,
		   &speed, colors_text, &trailing) == 4 && brightness <= 100u &&
	    speed >= 1u && speed <= 100u &&
	    parse_lighting_mode(mode_text, &command->lighting.mode) &&
	    parse_colors(colors_text, command->lighting.key_colors)) {
		command->type = KEYCAP_COMMAND_LIGHTING;
		command->lighting.brightness = (uint8_t)brightness;
		command->lighting.speed = (uint8_t)speed;
		return true;
	}
	unsigned int active_choices;
	char color_text[7];
	if (sscanf(line, "STATUS WAITING %u %6s%c", &active_choices,
		   color_text, &trailing) == 2 &&
	    active_choices >= 1 && active_choices <= KEYCAP_LED_COUNT &&
	    strlen(color_text) == 6 && parse_color(color_text, &command->status_color)) {
		command->type = KEYCAP_COMMAND_STATUS;
		command->status = KEYCAP_STATUS_WAITING;
		command->active_choices = (uint8_t)active_choices;
		command->has_status_color = true;
		return true;
	}
	if (sscanf(line, "STATUS WAITING %u%c", &active_choices, &trailing) == 1 &&
	    active_choices >= 1 && active_choices <= KEYCAP_LED_COUNT) {
		command->type = KEYCAP_COMMAND_STATUS;
		command->status = KEYCAP_STATUS_WAITING;
		command->active_choices = (uint8_t)active_choices;
		return true;
	}

	if (strncmp(line, "LEDS ", 5) != 0 || strlen(line + 5) != payload_length) {
		return false;
	}

	if (!parse_colors(line + 5, command->leds)) {
		return false;
	}

	command->type = KEYCAP_COMMAND_LEDS;
	return true;
}

int keycap_protocol_format_gesture(char *buffer, size_t capacity, uint8_t key,
				   const char *gesture, uint32_t sequence)
{
	if (key < 1 || key > KEYCAP_LED_COUNT || buffer == NULL || capacity == 0 ||
	    gesture == NULL ||
	    (strcmp(gesture, "SHORT") != 0 && strcmp(gesture, "LONG") != 0 &&
	     strcmp(gesture, "DOUBLE") != 0)) {
		return -1;
	}

	int written = snprintf(buffer, capacity, "GESTURE %u %s %u\n", key,
			       gesture, sequence);
	if (written < 0 || (size_t)written >= capacity) {
		return -1;
	}
	return written;
}

int keycap_protocol_format_button(char *buffer, size_t capacity, uint8_t key,
				  bool down, uint32_t sequence)
{
	if (key < 1 || key > KEYCAP_LED_COUNT || buffer == NULL || capacity == 0) {
		return -1;
	}

	int written = snprintf(buffer, capacity, "BUTTON %u %s %u\n", key,
			       down ? "DOWN" : "UP", sequence);
	if (written < 0 || (size_t)written >= capacity) {
		return -1;
	}
	return written;
}
