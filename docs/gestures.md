# Hardware gestures

Firmware protocol v2 delays a short press for 280 ms so it can distinguish a
double press. A long press fires after 600 ms. Holding a key produces one event.

| Gesture | Action |
| --- | --- |
| Short press 1–4 | Select the visible choice, or toggle it in multi-select |
| Double press 1 | Previous page |
| Double press 4 | Next page |
| Long press 1 | Previous page |
| Long press 2 | Clear multi-select choices |
| Long press 3 | Hand the request back to the agent |
| Long press 4 | Submit multi-select, otherwise next page |

When no approval overlay is visible, protocol-v3 keys control their assigned
agent session:

| Gesture | Agent-console action |
| --- | --- |
| Short press | Focus the originating terminal application |
| Long press | Request an interrupt and cancel any queued approval |
| Double press | Mark completed work as read |

Agent focus begins immediately on the first physical button-down, before the
280 ms gesture-classification window. The later short event is consumed; a
continued hold or second press still performs its long/double action. On a
multi-monitor Mac, focusing raises the terminal's most recently used window on
the display where that window already lives—it does not move windows between
displays.

Single-page, single-choice approval overlays resolve from the debounced
`BUTTON DOWN` event immediately. The delayed gesture event is consumed by the
host so it cannot affect the next queued overlay or an Agent Console assignment.
Paginated, multi-select, and destructive hold-to-confirm requests wait for the
gesture instead, because an immediate selection would consume the long press
that pages or confirms.

Protocol-v1 firmware remains compatible and resolves on `BUTTON … DOWN`.

LED states are semantic in protocol v2: dim blue is idle, agent-colored keys
are waiting choices, green is success, red is error, and amber is paused. If no
host command arrives for five seconds, firmware resumes the last standalone
lighting effect while continuing to advertise for reconnection.

Protocol-v3 idle LEDs run the selected standby lighting effect by default.
Settings can instead show agent state: blue working, orange waiting, green
completed, red failed, pink destructive approval, dim blue idle, and off when
no session is assigned.
