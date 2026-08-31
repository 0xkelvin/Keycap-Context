/* SPDX-License-Identifier: Apache-2.0 */
#include "neokey.h"
#include "protocol.h"
#include "gesture.h"
#include "lighting.h"
#include "line_reader.h"
#include "audio.h"

#include <errno.h>
#include <string.h>
#include <zephyr/device.h>
#include <zephyr/devicetree.h>
#include <zephyr/drivers/uart.h>
#include <zephyr/irq.h>
#include <zephyr/kernel.h>
#include <zephyr/sys/ring_buffer.h>

#define NEOKEY_ADDRESS 0x30
#define DEBOUNCE_SAMPLES 2
#define HOST_WATCHDOG_MS 5000u
#define HOST_HELLO_RETRY_MS 2000u
#define NEOKEY_RETRY_SLICE_MS 50u
#define NEOKEY_RETRY_SLICES 20u

static const struct device *const console = DEVICE_DT_GET(DT_CHOSEN(zephyr_console));
static const struct device *const i2c = DEVICE_DT_GET(DT_ALIAS(neokey_i2c));
RING_BUF_DECLARE(serial_rx, 512);

/* Set from the receive interrupt when the ring cannot hold an incoming chunk.
 * The dropped bytes may include a newline, so the main loop must discard the
 * damaged region rather than parse two spliced commands as one.
 */
static volatile bool serial_rx_overflow;
static struct keycap_line_reader line_reader;

/* Set once the microphone has been powered down for want of anything to
 * listen to. Cleared by a key press or by the host changing the lighting.
 */
static bool audio_asleep;

/* Kept visible for probe-based bring-up and field diagnostics.
 *
 * When the console does not come up there is no way to report a fault, so
 * bring-up state is recorded in RAM where a debugger can read it:
 *
 *   arm-zephyr-eabi-nm build/zephyr/zephyr.elf | grep keycap_
 *   openocd ... -c "halt" -c "mdw <address> 1" -c "resume"
 *
 * keycap_console_ready  1 once the console device reports ready
 * keycap_serial_error   0 once the receive callback is installed
 * keycap_neokey_status  0 once the NeoKey answers on I2C
 */
volatile int keycap_neokey_status = -EINPROGRESS;
volatile int keycap_console_ready = -1;
volatile int keycap_serial_error = -EINPROGRESS;

static void serial_rx_callback(const struct device *device, void *user_data)
{
	ARG_UNUSED(user_data);
	uint8_t bytes[32];

	uart_irq_update(device);
	if (!uart_irq_rx_ready(device)) {
		return;
	}

	int count;
	while ((count = uart_fifo_read(device, bytes, sizeof(bytes))) > 0) {
		if (ring_buf_put(&serial_rx, bytes, (uint32_t)count) <
		    (uint32_t)count) {
			serial_rx_overflow = true;
		}
	}
}

static bool take_rx_overflow(void)
{
	unsigned int key = irq_lock();
	bool overflowed = serial_rx_overflow;

	serial_rx_overflow = false;
	irq_unlock(key);
	return overflowed;
}

static int serial_rx_start(void)
{
	keycap_console_ready = device_is_ready(console) ? 1 : 0;
	if (keycap_console_ready != 1) {
		return -ENODEV;
	}

	int error = uart_irq_callback_user_data_set(console, serial_rx_callback, NULL);
	keycap_serial_error = error;
	if (error != 0) {
		return error;
	}
	uart_irq_rx_enable(console);
	return 0;
}

static void serial_write(const char *text)
{
	while (*text != '\0') {
		uart_poll_out(console, *text++);
	}
}

static void send_hello(void)
{
	serial_write("HELLO 3 keycap-fw xiao-nrf54l15-sense\n");
}

static int show_status(struct neokey *keys, enum keycap_status status,
		       uint8_t active_choices, const struct keycap_rgb *accent)
{
	struct keycap_rgb colors[KEYCAP_LED_COUNT] = {0};
	struct keycap_rgb color = {0};
	uint8_t count = KEYCAP_LED_COUNT;

	switch (status) {
	case KEYCAP_STATUS_IDLE:
		color = (struct keycap_rgb){.red = 0, .green = 12, .blue = 28};
		break;
	case KEYCAP_STATUS_WAITING:
		color = accent != NULL ? *accent :
			(struct keycap_rgb){.red = 90, .green = 120, .blue = 255};
		count = active_choices;
		break;
	case KEYCAP_STATUS_SUCCESS:
		color = (struct keycap_rgb){.red = 0, .green = 255, .blue = 40};
		break;
	case KEYCAP_STATUS_ERROR:
		color = (struct keycap_rgb){.red = 255, .green = 0, .blue = 0};
		break;
	case KEYCAP_STATUS_PAUSED:
		color = (struct keycap_rgb){.red = 255, .green = 80, .blue = 0};
		break;
	}

	for (uint8_t index = 0; index < count && index < KEYCAP_LED_COUNT; ++index) {
		colors[index] = color;
	}
	return neokey_set_leds(keys, colors);
}

static bool process_line(struct neokey *keys, bool keys_ready,
			 struct keycap_lighting_profile *lighting,
			 enum keycap_agent_state agents[KEYCAP_LED_COUNT],
			 bool *agents_active, bool *status_active, char *line)
{
	struct keycap_command command;
	if (!keycap_protocol_parse(line, &command)) {
		serial_write("ERROR bad-command ");
		serial_write(line);
		serial_write("\n");
		return false;
	}

	if (command.type == KEYCAP_COMMAND_PING) {
		send_hello();
		return true;
	}
	if (command.type == KEYCAP_COMMAND_KEEPALIVE) {
		/* The acknowledgement lets the host detect a stale macOS serial
		 * descriptor after the board has been unplugged and reconnected.
		 */
		serial_write("ALIVE\n");
		return true;
	}
	if (!keys_ready) {
		/* The NeoKey is not addressable yet. Keep the framing healthy and
		 * stay silent; the host resends state after the next HELLO.
		 */
		return true;
	}

	if (command.type == KEYCAP_COMMAND_LEDS) {
		if (neokey_set_leds(keys, command.leds) != 0) {
			serial_write("ERROR i2c-write\n");
		}
	} else if (command.type == KEYCAP_COMMAND_STATUS) {
		if (show_status(keys, command.status, command.active_choices,
				command.has_status_color ? &command.status_color
							 : NULL) != 0) {
			serial_write("ERROR i2c-write\n");
		} else {
			*agents_active = false;
			*status_active = command.status != KEYCAP_STATUS_IDLE;
		}
	} else if (command.type == KEYCAP_COMMAND_LIGHTING) {
		*lighting = command.lighting;
		/* Choosing an effect is an explicit request to listen again. */
		audio_asleep = false;
	} else if (command.type == KEYCAP_COMMAND_AGENTS) {
		memcpy(agents, command.agents, sizeof(command.agents));
		*agents_active = true;
		*status_active = false;
	}
	return true;
}

static void pump_serial(struct neokey *keys, bool keys_ready,
			struct keycap_lighting_profile *lighting,
			enum keycap_agent_state agents[KEYCAP_LED_COUNT],
			bool *agents_active, bool *status_active,
			uint32_t *last_host_command, bool *host_timed_out)
{
	uint8_t byte;

	if (take_rx_overflow()) {
		keycap_line_reader_resynchronize(&line_reader);
		serial_write("ERROR rx-overflow\n");
	}

	while (ring_buf_get(&serial_rx, &byte, 1) == 1) {
		switch (keycap_line_reader_push(&line_reader, byte)) {
		case KEYCAP_LINE_READY:
			if (process_line(keys, keys_ready, lighting, agents,
					 agents_active, status_active,
					 line_reader.line)) {
				*last_host_command = k_uptime_get_32();
				*host_timed_out = false;
			}
			break;
		case KEYCAP_LINE_OVERFLOW:
			serial_write("ERROR line-too-long\n");
			break;
		case KEYCAP_LINE_NONE:
			break;
		}
	}
}

int main(void)
{
	struct neokey keys;
	char event_line[48];
	uint8_t stable = 0;
	uint8_t candidate = 0;
	uint8_t candidate_count = 0;
	uint32_t sequence = 0;
	uint32_t last_host_command = k_uptime_get_32();
	uint32_t last_hello_retry = k_uptime_get_32();
	bool host_timed_out = false;
	uint32_t last_lighting_frame = UINT32_MAX;
	struct keycap_gesture_detector gestures;
	struct keycap_lighting_profile lighting;
	enum keycap_agent_state agent_states[KEYCAP_LED_COUNT] = {
		KEYCAP_AGENT_EMPTY, KEYCAP_AGENT_EMPTY, KEYCAP_AGENT_EMPTY, KEYCAP_AGENT_EMPTY,
	};
	bool agents_active = false;
	bool status_active = true;
	keycap_gesture_init(&gestures);
	keycap_lighting_default(&lighting);
	keycap_line_reader_init(&line_reader);

	/* Console bring-up can fail after a debugger reset, before the board's
	 * serial bridge has re-enumerated. Returning here ends the main thread:
	 * the device goes permanently silent with the NeoKey holding whatever
	 * frame it last received, and only a power cycle recovers it. Retry
	 * instead, so a transient failure costs a moment rather than the session.
	 */
	while (serial_rx_start() != 0) {
		k_sleep(K_MSEC(250));
	}
	send_hello();
	while ((keycap_neokey_status =
			neokey_init(&keys, i2c, NEOKEY_ADDRESS)) != 0) {
		serial_write("ERROR neokey-init\n");
		/* Keep draining the receive ring between attempts. A blocking
		 * sleep here overflows the ring with the host's PING and
		 * KEEPALIVE traffic and desynchronizes the line protocol.
		 */
		for (uint32_t slice = 0; slice < NEOKEY_RETRY_SLICES; ++slice) {
			pump_serial(&keys, false, &lighting, agent_states,
				    &agents_active, &status_active,
				    &last_host_command, &host_timed_out);
			k_sleep(K_MSEC(NEOKEY_RETRY_SLICE_MS));
		}
	}
	serial_write("READY neokey 0x30\n");
	show_status(&keys, KEYCAP_STATUS_PAUSED, 0, NULL);
	/* Commands received while NeoKey was unavailable were deliberately
	 * acknowledged but could not be rendered. Re-announce readiness now so
	 * the host pushes the current status and lighting profile again. Without
	 * this handshake, a normal slow I2C start can leave all keys stuck on the
	 * paused/orange frame until the next unrelated UI state change.
	 */
	send_hello();

	while (true) {
		bool was_timed_out = host_timed_out;

		pump_serial(&keys, true, &lighting, agent_states, &agents_active,
			    &status_active, &last_host_command, &host_timed_out);
		if (was_timed_out && !host_timed_out) {
			/* The host is back. It only sends STATUS on a state change, so
			 * announce ourselves to make it push its current state instead of
			 * waiting for one that may never come.
			 */
			send_hello();
		}

		uint8_t sample;
		if (neokey_read_buttons(&keys, &sample) == 0) {
			if (sample != candidate) {
				candidate = sample;
				candidate_count = 1;
			} else if (candidate_count < DEBOUNCE_SAMPLES) {
				++candidate_count;
			}

			if (candidate_count == DEBOUNCE_SAMPLES && candidate != stable) {
				uint8_t changed = candidate ^ stable;
				stable = candidate;
				for (uint8_t key = 0; key < KEYCAP_LED_COUNT; ++key) {
					uint8_t bit = BIT(key);
					if ((changed & bit) != 0 &&
					    keycap_protocol_format_button(
						    event_line, sizeof(event_line), key + 1,
						    (stable & bit) != 0, ++sequence) > 0) {
						serial_write(event_line);
					}
				}
			}
		}

		uint32_t now = k_uptime_get_32();
		struct keycap_gesture_event events[KEYCAP_GESTURE_KEY_COUNT];
		size_t event_count = keycap_gesture_update(
			&gestures, stable, now, events, ARRAY_SIZE(events));
		for (size_t index = 0; index < event_count; ++index) {
			const char *name = events[index].type == KEYCAP_GESTURE_SHORT ? "SHORT" :
					   events[index].type == KEYCAP_GESTURE_LONG ? "LONG" :
					   "DOUBLE";
			if (keycap_protocol_format_gesture(event_line, sizeof(event_line),
						   events[index].key, name, ++sequence) > 0) {
				serial_write(event_line);
			}
		}

		/* The microphone is powered only while its effect is selected and the
		 * standby lane is actually visible. An approval overlay or agent
		 * status takes the keys back, and the microphone with them.
		 */
		bool audio_effect = lighting.mode == KEYCAP_LIGHTING_AUDIO ||
				    lighting.mode == KEYCAP_LIGHTING_SPECTRUM ||
				    lighting.mode == KEYCAP_LIGHTING_PITCH;

		/* Touching the keypad is the wake gesture. The microphone is off
		 * while asleep, so it cannot hear its own way back.
		 */
		if (audio_asleep && stable != 0u) {
			audio_asleep = false;
		}

		bool wants_audio = audio_effect && !status_active && !agents_active &&
				   !audio_asleep;
		if (wants_audio != keycap_audio_is_running()) {
			if (wants_audio) {
				(void)keycap_audio_start();
			} else {
				keycap_audio_stop();
			}
		}
		uint32_t lighting_frame = now / KEYCAP_LIGHTING_FRAME_MS;
		if (lighting_frame != last_lighting_frame && !status_active) {
			struct keycap_rgb colors[KEYCAP_LED_COUNT];
			if (agents_active) {
				keycap_agent_render(agent_states, stable, now, colors);
			} else if (audio_effect && audio_asleep) {
				/* Nothing to visualise and no microphone running, so
				 * show a plain dim standby rather than a dark keypad.
				 */
				struct keycap_lighting_profile standby = lighting;

				standby.mode = KEYCAP_LIGHTING_RAINBOW;
				standby.brightness = lighting.brightness / 4u;
				keycap_lighting_render(&standby, stable, now, colors);
			} else if (audio_effect) {
				struct keycap_audio_frame frame;

				keycap_audio_get(&frame);
				if (frame.quiet) {
					/* Silent long enough that holding the microphone
					 * powered serves no one. Sleep until touched.
					 */
					audio_asleep = true;
				}
				if (lighting.mode == KEYCAP_LIGHTING_AUDIO) {
					keycap_audio_render(&lighting, frame.level, stable,
							    now, colors);
				} else if (lighting.mode == KEYCAP_LIGHTING_PITCH) {
					keycap_pitch_render(&lighting, frame.level,
							    frame.pitch, stable, colors);
				} else {
					keycap_spectrum_render(&lighting, frame.band,
							       stable, colors);
				}
			} else {
				keycap_lighting_render(&lighting, stable, now, colors);
			}
			if (neokey_set_leds(&keys, colors) != 0) {
				keycap_neokey_status = -EIO;
			}
			last_lighting_frame = lighting_frame;
		}

		/* The fail-safe is held by host_timed_out alone. Latching
		 * status_active here would survive the host's return, because only a
		 * STATUS command clears it and the host sends those on state changes
		 * only -- leaving the keys amber on a healthy link.
		 */
		if (!host_timed_out &&
		    now - last_host_command >= HOST_WATCHDOG_MS) {
			host_timed_out = true;
			agents_active = false;
			/* Continue the last configured standalone lighting effect while
			 * asking the host to reconnect. Amber is reserved for an explicit
			 * PAUSED command; a sleeping Mac must not latch the keyboard there.
			 */
			status_active = false;
			send_hello();
			last_hello_retry = now;
		} else if (host_timed_out &&
			   now - last_hello_retry >= HOST_HELLO_RETRY_MS) {
			/* The first HELLO was emitted during the outage that tripped the
			 * watchdog, so it is the line most likely to have been lost.
			 * Keep asking until the host answers.
			 */
			send_hello();
			last_hello_retry = now;
		}
		k_sleep(K_MSEC(10));
	}
	return 0;
}
