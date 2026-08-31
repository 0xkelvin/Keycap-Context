/* SPDX-License-Identifier: Apache-2.0 */
#include "protocol.h"
#include "gesture.h"
#include "lighting.h"
#include "line_reader.h"

#include <string.h>
#include <zephyr/ztest.h>

ZTEST_SUITE(protocol, NULL, NULL, NULL, NULL, NULL);

ZTEST(protocol, test_ping)
{
	struct keycap_command command;
	zassert_true(keycap_protocol_parse("PING", &command), "PING should parse");
	zassert_equal(command.type, KEYCAP_COMMAND_PING, "wrong command type");
	zassert_true(keycap_protocol_parse("KEEPALIVE", &command),
		     "KEEPALIVE should parse");
	zassert_equal(command.type, KEYCAP_COMMAND_KEEPALIVE,
		      "wrong keepalive command type");
}

ZTEST(protocol, test_leds)
{
	struct keycap_command command;
	zassert_true(keycap_protocol_parse(
		"LEDS FF0000,00FF00,0000FF,102030", &command),
		"LEDS should parse");
	zassert_equal(command.leds[0].red, 255, "red component");
	zassert_equal(command.leds[1].green, 255, "green component");
	zassert_equal(command.leds[2].blue, 255, "blue component");
	zassert_equal(command.leds[3].green, 0x20, "mixed component");
}

ZTEST(protocol, test_rejects_bad_leds)
{
	struct keycap_command command;
	zassert_false(keycap_protocol_parse("LEDS FFFFFF", &command),
		      "must contain four colors");
	zassert_false(keycap_protocol_parse(
		"LEDS GG0000,00FF00,0000FF,102030", &command),
		"must contain hex colors");
}

ZTEST(protocol, test_button_format)
{
	char buffer[48];
	int length = keycap_protocol_format_button(buffer, sizeof(buffer), 4, true, 9);
	zassert_true(length > 0, "button event should format");
	zassert_equal(strcmp(buffer, "BUTTON 4 DOWN 9\n"), 0, "wrong event");
}

ZTEST(protocol, test_status)
{
	struct keycap_command command;
	zassert_true(keycap_protocol_parse("STATUS IDLE", &command),
		     "idle status should parse");
	zassert_true(keycap_protocol_parse("STATUS WAITING 3", &command),
		     "waiting status should parse");
	zassert_equal(command.type, KEYCAP_COMMAND_STATUS, "wrong command type");
	zassert_equal(command.active_choices, 3, "wrong active choice count");
	zassert_true(keycap_protocol_parse("STATUS WAITING 2 10A37F", &command),
		     "waiting status with accent should parse");
	zassert_true(command.has_status_color, "accent should be present");
	zassert_equal(command.status_color.green, 0xA3, "wrong accent color");
	zassert_false(keycap_protocol_parse("STATUS WAITING 5", &command),
		      "too many active choices must fail");
}

ZTEST(protocol, test_gesture_format)
{
	char buffer[48];
	zassert_true(keycap_protocol_format_gesture(buffer, sizeof(buffer), 2,
					     "DOUBLE", 11) > 0,
		     "gesture should format");
	zassert_equal(strcmp(buffer, "GESTURE 2 DOUBLE 11\n"), 0,
		      "wrong gesture event");
}

ZTEST(protocol, test_short_gesture_after_double_window)
{
	struct keycap_gesture_detector detector;
	struct keycap_gesture_event events[4];
	keycap_gesture_init(&detector);

	zassert_equal(keycap_gesture_update(&detector, 1, 0, events, 4), 0,
		      "press should wait");
	zassert_equal(keycap_gesture_update(&detector, 0, 80, events, 4), 0,
		      "release should wait for double press");
	zassert_equal(keycap_gesture_update(&detector, 0, 400, events, 4), 1,
		      "short press should emit after window");
	zassert_equal(events[0].type, KEYCAP_GESTURE_SHORT, "wrong gesture");
}

ZTEST(protocol, test_long_and_double_gestures)
{
	struct keycap_gesture_detector detector;
	struct keycap_gesture_event events[4];
	keycap_gesture_init(&detector);

	keycap_gesture_update(&detector, 1, 0, events, 4);
	zassert_equal(keycap_gesture_update(&detector, 1, 700, events, 4), 1,
		      "held key should emit long");
	zassert_equal(events[0].type, KEYCAP_GESTURE_LONG, "wrong long gesture");
	keycap_gesture_update(&detector, 0, 710, events, 4);

	keycap_gesture_init(&detector);
	keycap_gesture_update(&detector, 2, 0, events, 4);
	keycap_gesture_update(&detector, 0, 60, events, 4);
	keycap_gesture_update(&detector, 2, 160, events, 4);
	zassert_equal(keycap_gesture_update(&detector, 0, 220, events, 4), 1,
		      "second release should emit double");
	zassert_equal(events[0].type, KEYCAP_GESTURE_DOUBLE, "wrong double gesture");
}

ZTEST(protocol, test_pressed_keys_use_distinct_solid_colors)
{
	struct keycap_rgb colors[KEYCAP_LED_COUNT];
	struct keycap_lighting_profile profile;
	keycap_lighting_default(&profile);

	keycap_lighting_render(&profile, BIT(0), 0, colors);
	zassert_equal(colors[0].red, 0, "button 1 red component");
	zassert_equal(colors[0].green, 178, "button 1 should be brightness-scaled green");
	zassert_equal(colors[0].blue, 22, "button 1 blue component");
	zassert_equal(colors[1].red | colors[1].green | colors[1].blue, 0,
		      "unpressed button should be off");

	keycap_lighting_render(&profile, BIT(1) | BIT(3), 0, colors);
	zassert_equal(colors[1].blue, 178, "button 2 should be brightness-scaled blue");
	zassert_equal(colors[3].red, 178, "button 4 should be brightness-scaled orange");
	zassert_equal(colors[2].red | colors[2].green | colors[2].blue, 0,
		      "unpressed button should remain off");
}

ZTEST(protocol, test_idle_rainbow_animates_all_four_keys)
{
	struct keycap_rgb first[KEYCAP_LED_COUNT];
	struct keycap_rgb next[KEYCAP_LED_COUNT];
	struct keycap_lighting_profile profile;
	keycap_lighting_default(&profile);

	keycap_lighting_render(&profile, 0, 0, first);
	keycap_lighting_render(&profile, 0, 1200 / profile.speed, next);

	for (uint8_t index = 0; index < KEYCAP_LED_COUNT; ++index) {
		zassert_not_equal(first[index].red | first[index].green | first[index].blue,
				  0, "idle key %u should be illuminated", index + 1);
	}
	zassert_not_equal(memcmp(first, next, sizeof(first)), 0,
			  "rainbow should advance each frame");
}

ZTEST(protocol, test_lighting_profile_command)
{
	struct keycap_command command;
	zassert_true(keycap_protocol_parse(
		"LIGHTING BREATHING 70 50 00FF20,0070FF,DC00FF,FF4800", &command),
		"installed breathing profile should parse");
	zassert_true(keycap_protocol_parse(
		"LIGHTING REACTIVE 80 65 00FF20,0070FF,DC00FF,FF4800", &command),
		"valid lighting profile should parse");
	zassert_equal(command.type, KEYCAP_COMMAND_LIGHTING, "wrong command type");
	zassert_equal(command.lighting.mode, KEYCAP_LIGHTING_REACTIVE, "wrong mode");
	zassert_equal(command.lighting.brightness, 80, "wrong brightness");
	zassert_equal(command.lighting.speed, 65, "wrong speed");
	zassert_equal(command.lighting.key_colors[1].blue, 255, "wrong key color");
	zassert_false(keycap_protocol_parse(
		"LIGHTING RAINBOW 101 50 00FF20,0070FF,DC00FF,FF4800", &command),
		"brightness over 100 should fail");
}

ZTEST(protocol, test_agent_status_command)
{
	struct keycap_command command;
	zassert_true(keycap_protocol_parse(
		"AGENTS WORKING,EMPTY,EMPTY,EMPTY", &command),
		"installed agent state should parse");
	zassert_true(keycap_protocol_parse(
		"AGENTS WORKING,WAITING,DONE,ERROR", &command),
		"agent command should parse");
	zassert_equal(command.type, KEYCAP_COMMAND_AGENTS, "wrong command type");
	zassert_equal(command.agents[0], KEYCAP_AGENT_WORKING, "wrong first state");
	zassert_equal(command.agents[1], KEYCAP_AGENT_WAITING, "wrong second state");
	zassert_equal(command.agents[2], KEYCAP_AGENT_DONE, "wrong third state");
	zassert_equal(command.agents[3], KEYCAP_AGENT_ERROR, "wrong fourth state");
	zassert_false(keycap_protocol_parse("AGENTS WORKING,WAITING,DONE", &command),
		      "agent command must contain four states");
}

ZTEST(protocol, test_agent_status_render)
{
	enum keycap_agent_state states[KEYCAP_LED_COUNT] = {
		KEYCAP_AGENT_WORKING, KEYCAP_AGENT_WAITING,
		KEYCAP_AGENT_DONE, KEYCAP_AGENT_ERROR,
	};
	struct keycap_rgb colors[KEYCAP_LED_COUNT];
	keycap_agent_render(states, 0, 1000, colors);
	zassert_true(colors[0].blue > 0, "working state should be blue");
	zassert_true(colors[1].red > 0 && colors[1].green > 0,
		     "waiting state should be orange");
	zassert_true(colors[2].green > colors[2].red,
		     "done state should be green");
	zassert_true(colors[3].red > 0 && colors[3].green == 0,
		     "error state should be red");
}


static enum keycap_line_status push_text(struct keycap_line_reader *reader,
					 const char *text)
{
	enum keycap_line_status status = KEYCAP_LINE_NONE;

	for (const char *cursor = text; *cursor != '\0'; ++cursor) {
		status = keycap_line_reader_push(reader, (uint8_t)*cursor);
	}
	return status;
}

ZTEST(protocol, test_line_reader_frames_commands)
{
	struct keycap_line_reader reader;

	keycap_line_reader_init(&reader);
	zassert_equal(push_text(&reader, "PING\n"), KEYCAP_LINE_READY,
		      "a terminated command should be ready");
	zassert_str_equal(reader.line, "PING", "unexpected command text");

	/* Carriage returns and empty lines must not produce commands. */
	zassert_equal(push_text(&reader, "\r\n"), KEYCAP_LINE_NONE,
		      "an empty line is not a command");
	zassert_equal(push_text(&reader, "STATUS IDLE\r\n"), KEYCAP_LINE_READY,
		      "CRLF should terminate a command");
	zassert_str_equal(reader.line, "STATUS IDLE", "CR must be stripped");
}

ZTEST(protocol, test_line_reader_resynchronizes_after_dropped_bytes)
{
	struct keycap_line_reader reader;

	keycap_line_reader_init(&reader);
	/* "PING\nPING\n" with the first newline dropped by a full receive ring
	 * previously spliced into the unparsable command "PIPING".
	 */
	zassert_equal(push_text(&reader, "PI"), KEYCAP_LINE_NONE, "partial line");
	keycap_line_reader_resynchronize(&reader);
	zassert_equal(push_text(&reader, "PING"), KEYCAP_LINE_NONE,
		      "the damaged remainder must be discarded");
	zassert_equal(push_text(&reader, "\n"), KEYCAP_LINE_NONE,
		      "the newline only ends the discarded region");
	zassert_equal(push_text(&reader, "KEEPALIVE\n"), KEYCAP_LINE_READY,
		      "the next whole command must be delivered");
	zassert_str_equal(reader.line, "KEEPALIVE", "unexpected command text");
}

ZTEST(protocol, test_line_reader_discards_overlong_command_tail)
{
	struct keycap_line_reader reader;
	char overlong[KEYCAP_LINE_MAX + 8];

	keycap_line_reader_init(&reader);
	memset(overlong, 'A', sizeof(overlong) - 1);
	overlong[sizeof(overlong) - 1] = '\0';
	zassert_equal(push_text(&reader, overlong), KEYCAP_LINE_NONE,
		      "only the first overflowing byte reports overflow");

	keycap_line_reader_init(&reader);
	memset(overlong, 'A', KEYCAP_LINE_MAX);
	overlong[KEYCAP_LINE_MAX] = '\0';
	zassert_equal(push_text(&reader, overlong), KEYCAP_LINE_OVERFLOW,
		      "exceeding the buffer must report overflow");
	/* The tail must not be parsed as a second command. */
	zassert_equal(push_text(&reader, "BBB\nPING\n"), KEYCAP_LINE_READY,
		      "framing resumes at the next newline");
	zassert_str_equal(reader.line, "PING", "the tail must be discarded");
}
