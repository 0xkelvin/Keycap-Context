# Device protocol

USB transport is an 8-N-1 serial stream at 115200 baud. Messages are ASCII,
newline terminated, and limited to 160 bytes. Unknown messages are ignored and
reported with `ERROR` where practical.

## Device to host

```text
HELLO 1 keycap-fw xiao-nrf54l15-sense
ALIVE
BUTTON <1..4> <DOWN|UP> <sequence>
GESTURE <1..4> <SHORT|LONG|DOUBLE> <sequence>
ERROR <code>
```

Example:

```text
BUTTON 2 DOWN 41
BUTTON 2 UP 42
```

Protocol-v1 hosts resolve a request on `BUTTON … DOWN`. Protocol-v2 firmware
emits `GESTURE` instead, after classifying short, long, and double presses.

The host resolves on `BUTTON … DOWN` only for a single-page, single-select,
non-destructive request. Paginated, multi-select, and hold-to-confirm requests
wait for the gesture so the long press that pages or confirms is not consumed
by an immediate selection.

### Framing errors

| Code | Meaning |
| --- | --- |
| `bad-command <line>` | The line did not parse as a command |
| `line-too-long` | The line exceeded 160 bytes; the tail is discarded |
| `rx-overflow` | The receive ring dropped bytes; the device resynchronizes |
| `i2c-write` | The NeoKey did not accept an LED update |
| `neokey-init` | The NeoKey is not addressable yet; the device keeps retrying |

`line-too-long` and `rx-overflow` both discard every byte up to the next
newline. A dropped newline would otherwise splice two commands into one
unparsable line, so the device forfeits one command to keep the stream framed.

## Host to device

```text
PING
KEEPALIVE
LEDS <RRGGBB>,<RRGGBB>,<RRGGBB>,<RRGGBB>
STATUS <IDLE|SUCCESS|ERROR|PAUSED>
STATUS WAITING <1..4> [RRGGBB]
LIGHTING <RAINBOW|WAVE|BREATHING|REACTIVE|AUDIO|STATIC|OFF> <0..100> <1..100> <RRGGBB,RRGGBB,RRGGBB,RRGGBB>
AGENTS <EMPTY|IDLE|WORKING|WAITING|DONE|ERROR|RISK>,<state>,<state>,<state>
```

The device replies to discovery `PING` with its `HELLO` line. After discovery,
the host sends `KEEPALIVE` every two seconds and the device replies `ALIVE`.
If acknowledgements stop for six seconds, the host first probes the existing
descriptor with `PING` and grants one further reply window. This avoids treating
a macOS sleep interval as a dead link and reopening the board's fragile
CMSIS-DAP bridge. Only an unanswered recovery probe closes the descriptor. A
later unsolicited `HELLO` requests full LED-state reinitialization.
The firmware also emits a fresh `HELLO` after the NeoKey finishes initializing.
Status or lighting commands can arrive while the I2C peripheral is still being
retried; this second handshake tells the host to replay them once the LEDs are
actually writable.
The host treats only `ALIVE` and `HELLO` as proof that the device is still
reading. Button and gesture lines are unsolicited and prove only the
device-to-host direction, so they do not refresh the liveness deadline; a link
that has gone half-open is closed and reopened instead of being held open by
key presses.
Once a serial candidate emits a valid Keycap protocol event, the host remembers
that path and does not rotate to unrelated USB modems (for example, monitor
control interfaces) after a transient heartbeat failure.

After five seconds without any valid host command, the device resumes its last
configured standalone lighting effect and repeats `HELLO` every two seconds
until the host answers. Amber is reserved for an explicit `PAUSED` status. The
first valid command clears the timeout, and the device sends one further
`HELLO` so the host re-asserts its current state.
`000000` turns a pixel off.
Color components are reduced by firmware before being written to the NeoKey to
limit brightness and USB current.

`LIGHTING` configures the device-local renderer. Brightness and speed are
percentages, and the four colors map to buttons 1 through 4. Local key-press
feedback takes visual priority over transient semantic status frames.

Protocol v3 adds `AGENTS`. Each comma-separated state maps directly to a
physical key: blue pulses while working, orange while waiting, green when work
completes, red on failure, pink for a destructive approval, dim blue for idle,
and black for an unassigned key. Approval `STATUS` frames temporarily take
priority over the agent console.

Example with three active choices:

```text
LEDS FFFFFF,FFFFFF,FFFFFF,000000
```

## Compatibility

The first integer in `HELLO` is the protocol major version. The current host
supports versions 1 through 3. Version 2 adds gestures and semantic status LEDs;
version 3 adds four-session agent states. Version 1 retains raw button events
and explicit `LEDS` commands. Hosts must
reject an unsupported major version rather than guessing message semantics.

## Audio-reactive lighting

Three effects share one capture from the board's own PDM microphone:
`LIGHTING AUDIO`, `LIGHTING SPECTRUM` and `LIGHTING PITCH`.

### AUDIO: level meter

`LIGHTING AUDIO` turns the four keys into a single level meter. Analysis happens entirely on the device: the keypad
reports no audio, no level and no derived measurement to the host. The link
could not carry it in any case, since 16 kHz mono PCM is roughly 32 kB/s against
a 11.5 kB/s serial budget.

The command carries no new fields. Every lit key shares one colour that walks
the rainbow wheel at `speed`, the same rate the `RAINBOW` effect uses.
`brightness` caps the meter. The four `RRGGBB` values are unused by this effect.

Loudness fills the keys as one bar, so louder sound lights more keys rather than
different ones:

| Level | Key 1 | Key 2 | Key 3 | Key 4 |
| --- | --- | --- | --- | --- |
| silence | dim ember | off | off | off |
| quiet | rising | off | off | off |
| moderate | full | rising | off | off |
| loud | full | full | rising | off |
| peak | full | full | full | full |

The meter normalises against its own rolling noise floor and peak, so it uses
the whole bar at any volume while a room's noise floor holds it nearly closed.
Rise is immediate and the fall is eased over roughly 300 ms, so it reads like a
VU needle rather than a strobe. Silence leaves the dim ember on the first key,
still cycling colour, so the device never looks dead.

### SPECTRUM: four bands, four colours

`LIGHTING SPECTRUM` gives each key its own frequency band and its own colour
from the profile, so the keys move independently and show what the music is made
of rather than how loud it is. `speed` is unused; `brightness` caps the display.

| Key | Band | Content |
| --- | --- | --- |
| 1 | up to ~170 Hz | kick and bass |
| 2 | ~170-700 Hz | body, low vocals |
| 3 | ~700 Hz-1.8 kHz | presence |
| 4 | above ~1.8 kHz | cymbals and air |

Each band normalises against its own floor and peak, so a quiet treble band does
not sit dark merely because the bass is loud. Every key keeps the same dim ember
in silence.

### PITCH: colour from content

`LIGHTING PITCH` gives all four keys one hue chosen by where the sound's energy
sits, and brightens them together with its loudness. Red is bass, green the
mids, violet the treble, so the colour reflects what the music is made of rather
than advancing on a timer. `speed` and the key colours are unused;
`brightness` caps the display.

The hue is a centroid over raw band energy with a fixed tilt, not over the
normalised band levels: per-band auto-gain drives every band to full whenever it
is near its own recent maximum, so the normalised levels reach 255 together and
preserve no balance to take a centroid of. The tilt offsets the steep falloff of
musical energy with frequency, which would otherwise pin the hue at the bass
end. Silence holds the last hue rather than snapping back to red.

### Microphone power

The microphone is powered only while `AUDIO`, `SPECTRUM` or `PITCH` is the
selected effect and the standby lane is visible. Selecting a non-audio effect, an approval overlay, or agent
status all switch the microphone's regulator off, so an unselected microphone is
unpowered rather than merely ignored.
