/* SPDX-License-Identifier: Apache-2.0 */
#include "audio.h"

#include <string.h>
#include <zephyr/audio/dmic.h>
#include <zephyr/device.h>
#include <zephyr/drivers/regulator.h>
#include <zephyr/kernel.h>

#define AUDIO_SAMPLE_RATE 16000u
#define AUDIO_FRAME_SAMPLES 256u
#define AUDIO_BLOCK_BYTES (AUDIO_FRAME_SAMPLES * sizeof(int16_t))
#define AUDIO_BLOCK_COUNT 4
#define AUDIO_READ_TIMEOUT_MS 250
#define AUDIO_THREAD_STACK 2048
/* Below the console and main loop: a dropped audio frame costs one LED update,
 * a delayed serial line costs an approval.
 */
#define AUDIO_THREAD_PRIORITY 10

static const struct device *const dmic = DEVICE_DT_GET(DT_NODELABEL(dmic_dev));
static const struct device *const mic_power =
	DEVICE_DT_GET_OR_NULL(DT_NODELABEL(pdm_imu_pwr));

K_MEM_SLAB_DEFINE_STATIC(audio_slab, AUDIO_BLOCK_BYTES, AUDIO_BLOCK_COUNT, 4);
static K_THREAD_STACK_DEFINE(audio_stack, AUDIO_THREAD_STACK);
static struct k_thread audio_thread;
static k_tid_t audio_tid;

/* Two aligned words, so a reader never needs a lock: the overall level in one
 * store and the four band levels packed into another.
 */
static volatile uint32_t published_level;
static volatile uint32_t published_bands;
static volatile uint32_t published_beats;
static volatile bool stop_requested;
static volatile bool running;

/* Visible to a debugger during bring-up, like the other probe words. */
volatile int keycap_audio_status = -1;
volatile uint32_t keycap_audio_frames;

static int configure(void)
{
	static struct pcm_stream_cfg stream = {
		.pcm_width = 16,
		.pcm_rate = AUDIO_SAMPLE_RATE,
		.block_size = AUDIO_BLOCK_BYTES,
		.mem_slab = &audio_slab,
	};
	struct dmic_cfg cfg = {
		.io = {
			.min_pdm_clk_freq = 1000000,
			.max_pdm_clk_freq = 3500000,
			.min_pdm_clk_dc = 40,
			.max_pdm_clk_dc = 60,
		},
		.streams = &stream,
		.channel = {
			.req_num_streams = 1,
			.req_num_chan = 1,
			.req_chan_map_lo = dmic_build_channel_map(0, 0, PDM_CHAN_LEFT),
		},
	};

	return dmic_configure(dmic, &cfg);
}

static void audio_entry(void *a, void *b, void *c)
{
	struct keycap_audio_filters filters;
	struct keycap_audio_analyzer analyzer;

	ARG_UNUSED(a);
	ARG_UNUSED(b);
	ARG_UNUSED(c);

	keycap_audio_filters_reset(&filters);
	keycap_audio_analyzer_init(&analyzer);

	keycap_audio_status = configure();
	if (keycap_audio_status != 0) {
		running = false;
		return;
	}

	keycap_audio_status = dmic_trigger(dmic, DMIC_TRIGGER_START);
	if (keycap_audio_status != 0) {
		running = false;
		return;
	}

	while (!stop_requested) {
		void *buffer;
		uint32_t size;

		int error = dmic_read(dmic, 0, &buffer, &size, AUDIO_READ_TIMEOUT_MS);
		if (error != 0) {
			keycap_audio_status = error;
			continue;
		}

		struct keycap_audio_energy energy;
		uint32_t bands = 0;

		keycap_audio_filters_run(&filters, (const int16_t *)buffer,
					 size / sizeof(int16_t), &energy);
		keycap_audio_analyzer_update(&analyzer, &energy);
		for (uint8_t band = 0; band < KEYCAP_AUDIO_BANDS; ++band) {
			bands |= (uint32_t)keycap_audio_analyzer_band(&analyzer, band)
				 << (band * 8u);
		}
		/* Level in the low byte, pitch in the next, so both still land in
		 * one aligned store.
		 */
		published_level = keycap_audio_analyzer_level(&analyzer) |
				  ((uint32_t)keycap_audio_analyzer_pitch(&analyzer) << 8u) |
				  (keycap_audio_analyzer_is_quiet(&analyzer) ? 1u << 16u : 0u);
		published_bands = bands;
		published_beats = keycap_audio_analyzer_beats(&analyzer);
		++keycap_audio_frames;
		k_mem_slab_free(&audio_slab, buffer);
	}

	(void)dmic_trigger(dmic, DMIC_TRIGGER_STOP);
	published_level = 0;
	published_bands = 0;
	running = false;
}

int keycap_audio_start(void)
{
	if (running) {
		return 0;
	}
	if (!device_is_ready(dmic)) {
		keycap_audio_status = -ENODEV;
		return -ENODEV;
	}
	if (mic_power != NULL && device_is_ready(mic_power)) {
		int error = regulator_enable(mic_power);
		if (error != 0) {
			keycap_audio_status = error;
			return error;
		}
	}

	stop_requested = false;
	running = true;
	audio_tid = k_thread_create(&audio_thread, audio_stack,
				    K_THREAD_STACK_SIZEOF(audio_stack), audio_entry,
				    NULL, NULL, NULL, AUDIO_THREAD_PRIORITY, 0,
				    K_NO_WAIT);
	k_thread_name_set(audio_tid, "keycap_audio");
	return 0;
}

void keycap_audio_stop(void)
{
	if (!running) {
		return;
	}
	stop_requested = true;
	if (audio_tid != NULL) {
		(void)k_thread_join(&audio_thread, K_MSEC(500));
		audio_tid = NULL;
	}
	running = false;
	published_level = 0;
	published_bands = 0;
	if (mic_power != NULL && device_is_ready(mic_power)) {
		(void)regulator_disable(mic_power);
	}
}

bool keycap_audio_is_running(void)
{
	return running;
}

void keycap_audio_get(struct keycap_audio_frame *frame)
{
	uint32_t bands = published_bands;
	uint32_t level = published_level;

	frame->level = (uint8_t)(level & 0xffu);
	frame->pitch = (uint8_t)((level >> 8u) & 0xffu);
	frame->quiet = (level & (1u << 16u)) != 0u;
	frame->beats = published_beats;
	for (uint8_t band = 0; band < KEYCAP_AUDIO_BANDS; ++band) {
		frame->band[band] = (uint8_t)((bands >> (band * 8u)) & 0xffu);
	}
}
