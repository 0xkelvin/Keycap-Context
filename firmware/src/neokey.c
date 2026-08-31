/* SPDX-License-Identifier: Apache-2.0 */
#include "neokey.h"

#include <errno.h>
#include <string.h>
#include <zephyr/drivers/i2c.h>
#include <zephyr/kernel.h>

#define SEESAW_GPIO_BASE 0x01
#define SEESAW_GPIO_DIRCLR_BULK 0x03
#define SEESAW_GPIO_BULK 0x04
#define SEESAW_GPIO_BULK_SET 0x05
#define SEESAW_GPIO_PULLENSET 0x0b

#define SEESAW_NEOPIXEL_BASE 0x0e
#define SEESAW_NEOPIXEL_PIN 0x01
#define SEESAW_NEOPIXEL_SPEED 0x02
#define SEESAW_NEOPIXEL_BUF_LENGTH 0x03
#define SEESAW_NEOPIXEL_BUF 0x04
#define SEESAW_NEOPIXEL_SHOW 0x05

#define NEOKEY_PIXEL_PIN 3
#define NEOKEY_BUTTON_MASK 0x000000f0u
#define NEOKEY_PIXEL_BYTES (KEYCAP_LED_COUNT * 3)

static int write_register(const struct neokey *device, uint8_t module,
			  uint8_t function, const uint8_t *payload, size_t length)
{
	uint8_t frame[2 + 2 + NEOKEY_PIXEL_BYTES];

	if (length > sizeof(frame) - 2) {
		return -EMSGSIZE;
	}
	frame[0] = module;
	frame[1] = function;
	if (length > 0) {
		memcpy(frame + 2, payload, length);
	}
	return i2c_write(device->i2c, frame, length + 2, device->address);
}

static int read_register(const struct neokey *device, uint8_t module,
			 uint8_t function, uint8_t *payload, size_t length)
{
	uint8_t selector[] = {module, function};
	int result = i2c_write(device->i2c, selector, sizeof(selector), device->address);
	if (result != 0) {
		return result;
	}

	/* Seesaw processes the selector after the write transaction completes. */
	k_busy_wait(250);
	return i2c_read(device->i2c, payload, length, device->address);
}

static int configure_buttons(const struct neokey *device)
{
	uint8_t mask[] = {0x00, 0x00, 0x00, 0xf0};
	int result = write_register(device, SEESAW_GPIO_BASE,
				    SEESAW_GPIO_DIRCLR_BULK, mask, sizeof(mask));
	if (result == 0) {
		result = write_register(device, SEESAW_GPIO_BASE,
					SEESAW_GPIO_PULLENSET, mask, sizeof(mask));
	}
	if (result == 0) {
		result = write_register(device, SEESAW_GPIO_BASE,
					SEESAW_GPIO_BULK_SET, mask, sizeof(mask));
	}
	return result;
}

static int configure_pixels(const struct neokey *device)
{
	uint8_t speed = 1;
	uint8_t pin = NEOKEY_PIXEL_PIN;
	uint8_t length[] = {0x00, NEOKEY_PIXEL_BYTES};

	int result = write_register(device, SEESAW_NEOPIXEL_BASE,
				    SEESAW_NEOPIXEL_SPEED, &speed, 1);
	if (result == 0) {
		result = write_register(device, SEESAW_NEOPIXEL_BASE,
					SEESAW_NEOPIXEL_BUF_LENGTH, length,
					sizeof(length));
	}
	if (result == 0) {
		result = write_register(device, SEESAW_NEOPIXEL_BASE,
					SEESAW_NEOPIXEL_PIN, &pin, 1);
	}
	return result;
}

int neokey_init(struct neokey *device, const struct device *i2c, uint8_t address)
{
	if (device == NULL || i2c == NULL || !device_is_ready(i2c)) {
		return -ENODEV;
	}
	device->i2c = i2c;
	device->address = address;

	int result = configure_pixels(device);
	if (result == 0) {
		result = configure_buttons(device);
	}
	if (result == 0) {
		const struct keycap_rgb off[KEYCAP_LED_COUNT] = {0};
		result = neokey_set_leds(device, off);
	}
	return result;
}

int neokey_read_buttons(const struct neokey *device, uint8_t *pressed_mask)
{
	uint8_t bytes[4];
	int result = read_register(device, SEESAW_GPIO_BASE, SEESAW_GPIO_BULK,
				   bytes, sizeof(bytes));
	if (result != 0) {
		return result;
	}

	uint32_t pins = ((uint32_t)bytes[0] << 24) |
			((uint32_t)bytes[1] << 16) |
			((uint32_t)bytes[2] << 8) | bytes[3];
	*pressed_mask = (uint8_t)(((pins ^ NEOKEY_BUTTON_MASK) &
				      NEOKEY_BUTTON_MASK) >> 4);
	return 0;
}

int neokey_set_leds(const struct neokey *device,
		    const struct keycap_rgb colors[KEYCAP_LED_COUNT])
{
	uint8_t payload[2 + NEOKEY_PIXEL_BYTES] = {0x00, 0x00};

	for (size_t index = 0; index < KEYCAP_LED_COUNT; ++index) {
		/* NeoKey pixels are GRB. Cap brightness at 25% for a desk device. */
		payload[2 + index * 3] = colors[index].green >> 2;
		payload[3 + index * 3] = colors[index].red >> 2;
		payload[4 + index * 3] = colors[index].blue >> 2;
	}

	int result = write_register(device, SEESAW_NEOPIXEL_BASE,
				    SEESAW_NEOPIXEL_BUF, payload, sizeof(payload));
	if (result == 0) {
		result = write_register(device, SEESAW_NEOPIXEL_BASE,
					SEESAW_NEOPIXEL_SHOW, NULL, 0);
	}
	return result;
}
