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
LIGHTING <RAINBOW|WAVE|BREATHING|REACTIVE|STATIC|OFF> <0..100> <1..100> <RRGGBB,RRGGBB,RRGGBB,RRGGBB>
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
