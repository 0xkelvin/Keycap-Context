# Security policy

Please report vulnerabilities privately to the maintainer rather than opening a
public issue. Include affected versions, reproduction steps, and potential
impact. Do not include real agent prompts, tokens, or credentials.

The broker binds only to `127.0.0.1`. Adapters must treat broker output as data,
must not execute it, and must fall back to the agent's native terminal when the
broker is unavailable. Release artifacts should be signed and checksummed.

Every broker request requires the per-install owner-readable token and requests
carrying browser fetch metadata are rejected. This protects against other local
accounts and browser pages, but not against an untrusted process already running
as the same macOS user, which can read that user's token file. Do not use the
approval surface as a security boundary between processes in one user account.

## Microphone

The optional `Audio Meter`, `Audio Spectrum`, `Pitch Colour` and `Tempo Colour`
lighting effects use the keypad's on-board PDM
microphone. Audio is converted to level values on the device and drives its
LEDs directly. No audio, band level, or derived measurement is sent to the host
or to any network; the USB serial link carries only the existing protocol.

The microphone's power regulator is enabled only while one of those effects is
selected and no approval is on screen, and is switched off otherwise, so an
unselected microphone is unpowered rather than software-muted. The effect is not
enabled by default.

The regulator is also switched off after roughly ten minutes with nothing
playing, and the keypad waits for a key press before listening again. Selecting
an audio effect therefore powers the microphone while there is music, not for as
long as the keypad is switched on.
