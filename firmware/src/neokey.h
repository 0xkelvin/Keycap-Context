/* SPDX-License-Identifier: Apache-2.0 */
#ifndef KEYCAP_NEOKEY_H
#define KEYCAP_NEOKEY_H

#include "protocol.h"

#include <stdint.h>
#include <zephyr/device.h>

struct neokey {
	const struct device *i2c;
	uint8_t address;
};

int neokey_init(struct neokey *device, const struct device *i2c, uint8_t address);
int neokey_read_buttons(const struct neokey *device, uint8_t *pressed_mask);
int neokey_set_leds(const struct neokey *device,
		    const struct keycap_rgb colors[KEYCAP_LED_COUNT]);

#endif
