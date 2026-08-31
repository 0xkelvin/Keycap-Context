# Firmware

The firmware targets the XIAO nRF54L15 Sense application core and talks to the
NeoKey's onboard seesaw controller at I2C address `0x30`.

## Build and flash

Use a recent Zephyr tree containing the XIAO nRF54L15 board definition, or the
corresponding nRF Connect SDK release:

```sh
west build -p always -b xiao_nrf54l15/nrf54l15/cpuapp firmware
west flash
```

The board's onboard SAMD11 debugger exposes the application console as a USB
CDC ACM serial port. The host opens that port at 115200 baud.

## Physical validation

1. Power the NeoKey from XIAO 3V3 and connect the common ground.
2. Connect NeoKey D/SDA to XIAO D4 and C/SCL to XIAO D5.
3. Flash firmware and open the CDC port at 115200 baud.
4. Confirm the `HELLO 3` line appears after reset.

### XIAO CMSIS-DAP serial recovery

The XIAO's onboard SAMD11 debug probe can leave its CDC serial bridge half-open
after flashing or resetting the nRF54L15: firmware output and button events
still reach the Mac, but commands sent to the board do not. The firmware then
correctly enters its amber host-watchdog state. Stop the host and fully unplug
and reconnect the board's USB cable to power-cycle the SAMD11 before testing.
If `KEEPALIVE` still does not produce `ALIVE`, diagnose or update the SAMD11
bridge rather than reflashing the nRF application repeatedly.
5. Send `LEDS FF0000,00FF00,0000FF,FFFFFF` and inspect the four pixels.
6. Press each key and confirm immediate ordered `BUTTON 1..4 DOWN`/`UP` events,
   followed by `GESTURE 1..4 SHORT`; also verify long and double presses.

## Local lighting

When no key is held, the four LEDs play a moving rainbow wave. Held keys take
immediate local priority: key 1 is green, key 2 blue, key 3 magenta, and key 4
orange. Multiple held keys light together, while unpressed keys turn off. The
local renderer refreshes at about 40 frames per second and therefore takes
visual priority over transient host LED commands.

The firmware intentionally uses the debugger's serial bridge for the first
prototype. A production PCB can expose native USB CDC from the application MCU
without changing the v1 protocol.
