/* SPDX-License-Identifier: Apache-2.0 */
#include "audio_bands.h"

#include <string.h>

#define DC_SHIFT 8
#define LOW_SHIFT 4
#define MID_SHIFT 2
#define HIGH_SHIFT 1

/* Below this span between floor and peak the signal is indistinguishable from
 * the room's own noise, so the meter stays down rather than amplifying hiss
 * into a light show.
 */
#define MINIMUM_SPAN 64u

/* Dynamic range, as a multiple of the floor, below which the room counts as
 * silent for the purpose of sleeping the microphone.
 *
 * A ratio rather than a fixed span, because the right absolute threshold
 * differs by room and by microphone gain: measured here, music holds its peak
 * around 28 times its floor while a quiet room stays within 1.6 times. The
 * additive term keeps the test meaningful when both values sit near zero.
 *
 * Note the peak cannot simply decay to the floor: a steady tone re-arms it
 * every frame, so "no sound" is a narrow range, not a vanishing one.
 */
#define QUIET_RATIO 2u

/* A beat is bass rising clear of its own recent average. The ratio is a
 * compromise: lower and a sustained bassline retriggers constantly, higher and
 * a soft kick is missed.
 */
#define BEAT_RATIO_NUM 7u
#define BEAT_RATIO_DEN 5u
#define BEAT_MINIMUM_MARGIN 64u
/* A beat must also be a rise, as a fraction of the previous frame. Being loud
 * is not the same as being a transient: a sustained bass note sits above its
 * own average for as long as it lasts and would otherwise retrigger endlessly.
 */
#define BEAT_RISE_SHIFT 2u
/* Frames a beat stays latched, which also debounces the next one. */
#define BEAT_HOLD_FRAMES 4u

/* Colour-wheel span used by the pitch effect: 0 is red, 85 green, 170 blue, so
 * stopping short of a full turn runs red -> green -> blue -> violet without
 * wrapping back to red at the treble end.
 */
#define PITCH_MAX_HUE 200u
/* Percent of the gap closed per frame. Low enough that the colour drifts rather
 * than flickering between hues on every transient.
 */
#define PITCH_SMOOTHING 6u

/* Tilt applied to each band before taking the centroid.
 *
 * Musical energy falls away with frequency, so an untilted centroid sits
 * pinned at the bass end. These weights lift the upper bands back toward
 * comparable magnitude. They are deliberately gentle: an aggressive tilt lets a
 * near-silent treble band outvote a loud kick, which keeps bass-heavy music off
 * the red end where it belongs.
 */
static const uint8_t pitch_tilt[KEYCAP_AUDIO_BANDS] = {1u, 2u, 3u, 4u};

void keycap_audio_filters_reset(struct keycap_audio_filters *filters)
{
	memset(filters, 0, sizeof(*filters));
}

static uint32_t absolute(int32_t value)
{
	return value < 0 ? (uint32_t)-value : (uint32_t)value;
}

void keycap_audio_filters_run(struct keycap_audio_filters *filters,
			      const int16_t *samples, size_t count,
			      struct keycap_audio_energy *energy)
{
	uint64_t total = 0;
	uint64_t sums[KEYCAP_AUDIO_BANDS] = {0};

	memset(energy, 0, sizeof(*energy));
	if (count == 0u) {
		return;
	}

	for (size_t index = 0; index < count; ++index) {
		int32_t sample = samples[index];

		/* PDM output carries a DC offset that would otherwise read as a
		 * constant loud signal and hold the display open on silence.
		 */
		filters->dc_accumulator += sample - (filters->dc_accumulator >> DC_SHIFT);
		sample -= filters->dc_accumulator >> DC_SHIFT;

		filters->low_accumulator += sample - (filters->low_accumulator >> LOW_SHIFT);
		filters->mid_accumulator += sample - (filters->mid_accumulator >> MID_SHIFT);
		filters->high_accumulator += sample - (filters->high_accumulator >> HIGH_SHIFT);

		int32_t low = filters->low_accumulator >> LOW_SHIFT;
		int32_t mid = filters->mid_accumulator >> MID_SHIFT;
		int32_t high = filters->high_accumulator >> HIGH_SHIFT;

		total += absolute(sample);
		sums[0] += absolute(low);
		sums[1] += absolute(mid - low);
		sums[2] += absolute(high - mid);
		sums[3] += absolute(sample - high);
	}

	energy->overall = (uint32_t)(total / count);
	for (uint8_t band = 0; band < KEYCAP_AUDIO_BANDS; ++band) {
		energy->band[band] = (uint32_t)(sums[band] / count);
	}
}

static void channel_init(struct keycap_audio_channel *channel)
{
	memset(channel, 0, sizeof(*channel));
	channel->peak = MINIMUM_SPAN;
}

static void channel_update(struct keycap_audio_channel *channel, uint32_t energy)
{
	/* The floor drops quickly onto a new minimum but creeps back up, so a
	 * quiet passage does not instantly rescale the display.
	 */
	if (energy < channel->floor) {
		channel->floor -= (channel->floor - energy) / 2u;
	} else {
		channel->floor += (energy - channel->floor) / 256u;
	}

	/* The peak jumps to a new maximum and decays back toward the floor, which
	 * is what stops a fading track from leaving the display pinned.
	 */
	if (energy > channel->peak) {
		channel->peak = energy;
	} else if (channel->peak > channel->floor) {
		channel->peak -= (channel->peak - channel->floor) / 128u;
	}

	uint8_t target = 0u;
	if (channel->peak > channel->floor + MINIMUM_SPAN && energy > channel->floor) {
		uint64_t span = channel->peak - channel->floor;
		uint64_t scaled = ((uint64_t)(energy - channel->floor) * 255u) / span;
		target = scaled > 255u ? 255u : (uint8_t)scaled;
	}

	if (target >= channel->level) {
		channel->level = target;
	} else {
		uint16_t drop =
			(uint16_t)(channel->level - target) * KEYCAP_AUDIO_RELEASE / 100u;
		channel->level = (uint8_t)(channel->level - (drop == 0u ? 1u : drop));
	}
}

void keycap_audio_analyzer_init(struct keycap_audio_analyzer *analyzer)
{
	/* Clear the whole struct, not only the channels: the analyzer lives on
	 * the audio thread's stack, so beats, pitch, the quiet countdown and the
	 * bass history would otherwise start from whatever was there before.
	 */
	memset(analyzer, 0, sizeof(*analyzer));
	channel_init(&analyzer->overall);
	for (uint8_t band = 0; band < KEYCAP_AUDIO_BANDS; ++band) {
		channel_init(&analyzer->band[band]);
	}
}

void keycap_audio_analyzer_update(struct keycap_audio_analyzer *analyzer,
				  const struct keycap_audio_energy *energy)
{
	uint64_t weighted = 0;
	uint64_t total = 0;

	channel_update(&analyzer->overall, energy->overall);
	if (analyzer->overall.peak >
	    analyzer->overall.floor * QUIET_RATIO + MINIMUM_SPAN) {
		analyzer->quiet_frames = 0u;
	} else if (analyzer->quiet_frames < KEYCAP_AUDIO_SLEEP_FRAMES) {
		++analyzer->quiet_frames;
	}

	for (uint8_t band = 0; band < KEYCAP_AUDIO_BANDS; ++band) {
		channel_update(&analyzer->band[band], energy->band[band]);

		/* The centroid reads raw energy, not the normalised level. Each
		 * band's auto-gain drives it to full whenever it is near its own
		 * recent maximum, so normalised levels sit at 255 together and
		 * carry no balance between bands to take a centroid of.
		 *
		 * Only energy *above* the band's own noise floor votes. The tilt
		 * multiplies the top band eightfold, so without this the room's
		 * hiss alone is enough to drag bass-heavy music away from red.
		 */
		uint32_t floor = analyzer->band[band].floor;
		uint32_t excess = energy->band[band] > floor
					  ? energy->band[band] - floor
					  : 0u;
		uint64_t tilted = (uint64_t)excess * pitch_tilt[band];

		/* Squared, so the loudest band wins decisively instead of being
		 * averaged against three quieter ones. A plain mean drifts to the
		 * middle of the wheel and every kind of music comes out green.
		 */
		uint64_t sharpened = tilted * tilted;

		weighted += sharpened * band;
		total += sharpened;
	}

	uint32_t bass = energy->band[0];
	uint32_t previous = analyzer->bass_previous;
	bool clear_of_noise = bass > analyzer->band[0].floor + BEAT_MINIMUM_MARGIN;
	bool above_average = (uint64_t)bass * BEAT_RATIO_DEN >
			     (uint64_t)analyzer->bass_average * BEAT_RATIO_NUM;
	/* Requiring previous > 0 also suppresses a spurious beat on the very
	 * first frame, when there is no history to rise from.
	 */
	bool rising = previous > 0u && bass > previous + (previous >> BEAT_RISE_SHIFT);

	if (analyzer->beat_hold > 0u) {
		--analyzer->beat_hold;
	} else if (clear_of_noise && above_average && rising) {
		analyzer->beat_hold = BEAT_HOLD_FRAMES;
		++analyzer->beats;
	}
	analyzer->bass_previous = bass;
	analyzer->bass_average +=
		((int32_t)bass - (int32_t)analyzer->bass_average) / 8;

	if (total > 0u) {
		uint32_t target = (uint32_t)((weighted * PITCH_MAX_HUE) /
					     (total * (KEYCAP_AUDIO_BANDS - 1u)));
		analyzer->pitch = (uint16_t)((int32_t)analyzer->pitch +
					     ((int32_t)target - (int32_t)analyzer->pitch) *
						     (int32_t)PITCH_SMOOTHING / 100);
	}
}

uint8_t keycap_audio_analyzer_level(const struct keycap_audio_analyzer *analyzer)
{
	return analyzer->overall.level;
}

uint8_t keycap_audio_analyzer_band(const struct keycap_audio_analyzer *analyzer,
				   uint8_t band)
{
	return band < KEYCAP_AUDIO_BANDS ? analyzer->band[band].level : 0u;
}

uint8_t keycap_audio_analyzer_pitch(const struct keycap_audio_analyzer *analyzer)
{
	return analyzer->pitch > 255u ? 255u : (uint8_t)analyzer->pitch;
}

bool keycap_audio_analyzer_is_quiet(const struct keycap_audio_analyzer *analyzer)
{
	return analyzer->quiet_frames >= KEYCAP_AUDIO_SLEEP_FRAMES;
}

uint32_t keycap_audio_analyzer_beats(const struct keycap_audio_analyzer *analyzer)
{
	return analyzer->beats;
}

uint8_t keycap_audio_key_fill(uint8_t level, uint8_t key)
{
	if (key >= KEYCAP_LED_COUNT) {
		return 0u;
	}

	/* Stretch 0..255 across the four keys, then take this key's slice: the
	 * bar is continuous, so key n starts only once key n-1 is full.
	 */
	uint32_t stretched = (uint32_t)level * KEYCAP_LED_COUNT;
	uint32_t start = (uint32_t)key * 255u;

	if (stretched <= start) {
		return 0u;
	}
	uint32_t fill = stretched - start;
	return fill > 255u ? 255u : (uint8_t)fill;
}
