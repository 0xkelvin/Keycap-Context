/* SPDX-License-Identifier: Apache-2.0 */
#include "lighting.h"

#include <string.h>

static const struct keycap_rgb default_colors[KEYCAP_LED_COUNT] = {
	{.red = 0, .green = 255, .blue = 32},
	{.red = 0, .green = 112, .blue = 255},
	{.red = 220, .green = 0, .blue = 255},
	{.red = 255, .green = 72, .blue = 0},
};

static struct keycap_rgb scale_color(struct keycap_rgb color, uint8_t amount)
{
	return (struct keycap_rgb){
		.red = (uint8_t)((uint16_t)color.red * amount / 100u),
		.green = (uint8_t)((uint16_t)color.green * amount / 100u),
		.blue = (uint8_t)((uint16_t)color.blue * amount / 100u),
	};
}

void keycap_lighting_default(struct keycap_lighting_profile *profile)
{
	*profile = (struct keycap_lighting_profile){
		.mode = KEYCAP_LIGHTING_RAINBOW,
		.brightness = 70,
		.speed = 50,
	};
	memcpy(profile->key_colors, default_colors, sizeof(default_colors));
}

static struct keycap_rgb color_wheel(uint8_t position)
{
	if (position < 85u) {
		return (struct keycap_rgb){
			.red = (uint8_t)(255u - position * 3u),
			.green = (uint8_t)(position * 3u),
			.blue = 0,
		};
	}
	if (position < 170u) {
		position = (uint8_t)(position - 85u);
		return (struct keycap_rgb){
			.red = 0,
			.green = (uint8_t)(255u - position * 3u),
			.blue = (uint8_t)(position * 3u),
		};
	}

	position = (uint8_t)(position - 170u);
	return (struct keycap_rgb){
		.red = (uint8_t)(position * 3u),
		.green = 0,
		.blue = (uint8_t)(255u - position * 3u),
	};
}

void keycap_lighting_render(const struct keycap_lighting_profile *profile,
			    uint8_t pressed_mask, uint32_t uptime_ms,
			    struct keycap_rgb colors[KEYCAP_LED_COUNT])
{
	memset(colors, 0, sizeof(struct keycap_rgb) * KEYCAP_LED_COUNT);
	if (profile->mode == KEYCAP_LIGHTING_OFF || profile->brightness == 0u) {
		return;
	}
	if (pressed_mask != 0u) {
		for (uint8_t index = 0; index < KEYCAP_LED_COUNT; ++index) {
			if ((pressed_mask & (1u << index)) != 0u) {
				colors[index] = scale_color(profile->key_colors[index],
							  profile->brightness);
			}
		}
		return;
	}

	uint8_t phase = (uint8_t)(((uint64_t)uptime_ms * profile->speed) / 1200u);
	for (uint8_t index = 0; index < KEYCAP_LED_COUNT; ++index) {
		struct keycap_rgb color;
		uint8_t intensity = profile->brightness;
		switch (profile->mode) {
		case KEYCAP_LIGHTING_RAINBOW:
			color = color_wheel((uint8_t)(phase + index * 64u));
			break;
		case KEYCAP_LIGHTING_WAVE: {
			color = profile->key_colors[index];
			uint8_t wave = (uint8_t)(phase * 4u + index * 64u);
			uint8_t triangle = wave < 128u ? wave : (uint8_t)(255u - wave);
			intensity = (uint8_t)((uint16_t)profile->brightness *
					      (25u + (uint16_t)triangle * 75u / 127u) / 100u);
			break;
		}
		case KEYCAP_LIGHTING_BREATHING: {
			color = profile->key_colors[index];
			uint8_t wave = (uint8_t)(phase * 2u);
			uint8_t triangle = wave < 128u ? wave : (uint8_t)(255u - wave);
			intensity = (uint8_t)((uint16_t)profile->brightness *
					      (10u + (uint16_t)triangle * 90u / 127u) / 100u);
			break;
		}
		case KEYCAP_LIGHTING_REACTIVE:
			color = profile->key_colors[index];
			intensity = (uint8_t)(profile->brightness / 10u);
			break;
		case KEYCAP_LIGHTING_STATIC:
			color = profile->key_colors[index];
			break;
		case KEYCAP_LIGHTING_OFF:
			color = (struct keycap_rgb){0};
			break;
		}
		colors[index] = scale_color(color, intensity);
	}
}

void keycap_agent_render(const enum keycap_agent_state states[KEYCAP_LED_COUNT],
			 uint8_t pressed_mask, uint32_t uptime_ms,
			 struct keycap_rgb colors[KEYCAP_LED_COUNT])
{
	uint8_t wave = (uint8_t)(uptime_ms / 8u);
	uint8_t triangle = wave < 128u ? wave : (uint8_t)(255u - wave);
	uint8_t pulse = (uint8_t)(35u + (uint16_t)triangle * 65u / 127u);

	for (uint8_t index = 0; index < KEYCAP_LED_COUNT; ++index) {
		struct keycap_rgb color = {0};
		uint8_t intensity = 100u;
		switch (states[index]) {
		case KEYCAP_AGENT_EMPTY:
			break;
		case KEYCAP_AGENT_IDLE:
			color = (struct keycap_rgb){.red = 0, .green = 28, .blue = 80};
			break;
		case KEYCAP_AGENT_WORKING:
			color = (struct keycap_rgb){.red = 0, .green = 112, .blue = 255};
			intensity = pulse;
			break;
		case KEYCAP_AGENT_WAITING:
			color = (struct keycap_rgb){.red = 255, .green = 128, .blue = 0};
			intensity = pulse;
			break;
		case KEYCAP_AGENT_DONE:
			color = (struct keycap_rgb){.red = 0, .green = 255, .blue = 40};
			break;
		case KEYCAP_AGENT_ERROR:
			color = (struct keycap_rgb){.red = 255, .green = 0, .blue = 0};
			intensity = pulse;
			break;
		case KEYCAP_AGENT_RISK:
			color = (struct keycap_rgb){.red = 255, .green = 0, .blue = 96};
			intensity = pulse;
			break;
		}
		if ((pressed_mask & (1u << index)) != 0u) {
			intensity = 100u;
		}
		colors[index] = scale_color(color, intensity);
	}
}
