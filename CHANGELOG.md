# Changelog

## Unreleased

### Added

- Added an `AUDIO` lighting effect: the four keys become one level meter driven
  by the board's PDM microphone, sharing a single colour that cycles the rainbow
  at the profile speed. Loudness fills the keys in order, normalised against a
  rolling noise floor so the whole bar is used at any volume, with an immediate
  rise, an eased fall, and a dim ember left on the first key in silence.
  Analysis runs entirely on the device; no audio or derived measurement crosses
  the serial link, and the microphone's regulator is switched off whenever
  neither audio effect is selected.
- Added a `SPECTRUM` lighting effect sharing the same capture: each key takes
  its own frequency band and its own colour, bass on key one through treble on
  key four, with each band normalised independently.
- Added a `PITCH` lighting effect sharing the same capture: all four keys take
  one hue from where the sound's energy sits, red for bass through violet for
  treble, brightening together with loudness. The hue holds through silence
  rather than resetting between tracks.
- Raised the NeoKey I2C bus to fast mode, quartering the time the main loop
  spends blocking on each LED frame.

### Fixed

- An unrecognised lighting effect in the settings file no longer discards every
  other preference. A strict decoder failed the whole file, so a host without a
  newer effect silently reverted brightness, colours, gestures and profiles to
  their defaults.

### Fixed

- A slow NeoKey/I2C startup no longer leaves all four LEDs stuck on the amber
  paused frame. The firmware announces itself again after LED initialization,
  causing the host to replay status and the selected standby lighting profile.
- Serial configuration failures now close their file descriptor, and stale
  immediate-press gesture state is cleared across device reconnects.
- Serial autodetection now rotates through every USB modem candidate after a
  failed handshake instead of retrying the same unrelated debug port forever.
- Malformed persisted lighting values are normalized before the four-key
  settings UI reads them, avoiding an out-of-range crash on edited settings.
- Idle agent switching now focuses on the initial button-down instead of after
  the double-press delay, and no longer raises every terminal window across a
  multi-monitor desktop.
- The macOS serial host now clears inherited modem/flow-control flags and
  flushes stale bytes before discovery. A CMSIS-DAP port could otherwise remain
  half-open: buttons reached the host, but lighting and heartbeat commands did
  not reach the board. Device health now becomes connected only after a valid
  firmware `HELLO`, so an LG monitor-control modem cannot report as a Keycap.
- After any valid Keycap event, serial discovery now remains affined to that
  device and will not rotate onto an external monitor's control modem during a
  one-way CMSIS-DAP bridge failure.
- Wake recovery now probes the existing serial descriptor before closing it,
  avoiding the SAMD11 reopen path that wedges after macOS sleep. If the host is
  unavailable, firmware continues the last standby effect instead of latching
  all four LEDs amber.
- Reinstalling or packaging now replaces adapter directories instead of
  merging stale files, and excludes generated Python caches and test fixtures.
- Multi-select requests now offer a Submit control. The button had been placed
  in the hold-to-confirm branch, so a multi-select question could only be
  answered with a hardware long press, and destructive requests showed a
  redundant disabled `Submit 0` beside `Confirm selection`.
- Paginated single-select requests no longer resolve from `BUTTON … DOWN`. The
  immediate press consumed the long press that pages, so requests with five to
  sixteen choices exposed only their first four options on hardware.
- The firmware resynchronizes the serial stream after the receive ring drops
  bytes, and keeps draining the ring while the NeoKey is still initializing.
  Blocking retries had overflowed the ring and spliced host commands together
  (`PING` + `PING` arriving as `PIPING`).
- Overlay choices accept the first mouse click while another application is
  frontmost.
- The keys no longer stay amber after the host watchdog fires. The fail-safe
  had latched the flag that suppresses the standby effect, and only a `STATUS`
  command cleared it -- which the host sends on state changes only, so a
  recovered link stayed amber until the board was unplugged.
- The device repeats `HELLO` every two seconds while the host is unreachable.
  The single announcement was emitted during the outage that triggered it, so
  losing that one line left both sides waiting for each other.
- Added `keycap_console_ready` and `keycap_serial_error` beside the existing
  `keycap_neokey_status` probe word, so a board whose console never comes up can
  still report where bring-up stopped over SWD.
- A failed console bring-up no longer ends `main()`. Returning left the device
  permanently silent with the NeoKey holding its last frame, recoverable only by
  a power cycle; the device now retries until the console is ready.
- The host no longer treats unsolicited button and gesture traffic as proof the
  device is still listening. Only replies to its own `PING`/`KEEPALIVE` count,
  so a half-open link is now detected and reconnected within six seconds
  instead of being held open by the user pressing keys.

### Security

- The local HTTP API authenticates every request with a per-install token
  written owner-readable to Application Support, and refuses requests carrying
  browser fetch metadata. A loopback `Host` header alone had been sufficient to
  read the approval history or raise a spoofed approval overlay.
- Token permission changes now fail closed, browser `Origin: null` requests are
  rejected, and the installer refuses unsafe root/home removal targets.

### Added

- Added the Agent Console with four persistent agent/session slots, status LEDs,
  terminal focus, interrupts, resume/cancel commands, and local audit history.
- Added protocol v3 `AGENTS` rendering and two additional firmware Ztests.
- Added firmware framing tests and a CI job that runs the Zephyr ztests.
- Added an Antigravity CLI plugin with native fallback and lifecycle reporting.
- Added context-aware application/project profiles and workflow preview.
- Added session status, control, command-polling, session-list, and history APIs.
- Added persisted lighting profiles and a macOS settings window.
- Added rainbow, wave, breathing, reactive, static, and off lighting modes.
- Added adjustable brightness, speed, and per-key colors.
- Added hold-to-confirm behavior for requests marked destructive.
- Added a diagnostics export and connected firmware/protocol information.

## 0.4.0

- Added protocol-v2 gestures, semantic LEDs, richer Codex/Claude adapters,
  cancellation cleanup, pagination, multi-select, installer, and CI.
