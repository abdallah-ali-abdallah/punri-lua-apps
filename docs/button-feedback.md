# Button feedback

All 28 Lua apps package the same `press_feedback.lua` module. A successful
activation paints a light control black with white content; an already dark
control becomes light gray with black content. The app redraws its current
normal state after 500 ms. Selection, disabled state and operation state remain
separate from this temporary visual.

The timer starts after the first frame that paints the pressed control. It uses
short integer time differences compatible with the firmware's 32-bit Lua clock,
including signed and unsigned uptime rollover. No delay, additional framebuffer,
background task or network connection is needed. A panel's physical refresh
latency must still be checked on hardware.

## Integration

Load the module once with `punri.dofile("press_feedback.lua")`. Each draw calls
`begin(viewKey)`, registers the visible controls, paints their normal backgrounds,
calls `paint(id)` before their labels/icons, and ends with `finish()`. Use the
foreground returned by `paint` when it is not nil. Call `update()` on every
update, including when a clock is stopped, radio is disconnected, or settings
are open. Register stable IDs, the same bounds used for hit testing, and disabled
state. Preserve circles and rounded corners rather than inverting a large box.

`press(id)` starts a visual without delaying the action. `defer(id, callback)`
retains the current surface until the feedback finishes before opening a child
screen or leaving the app. Only one callback is retained; `busy()` prevents
duplicate navigation. A changed view or explicit `clear()` cancels it. HID
reports, pointer movement, stopwatch timing and game controls stay immediate.

Implement each touch action in `on_tap(x,y)` only. The firmware additionally
calls the compatibility `on_touch(x,y,"tap")` for that same physical tap.

The optional `footer(labels, ids)` draws explicit app-owned action buttons on
touch and button profiles. This replaces invisible old touch footer targets;
it does not restore a global firmware navigation bar. Physical inputs continue
to dispatch the same logical actions.

## Packaging and checks

`shared/press_feedback.lua` is the canonical source. The sandbox requires a copy
inside each independent app package; apps never load a neighboring app's files.

```sh
python3 scripts/sync_press_feedback.py
python3 scripts/sync_press_feedback.py --check
python3 scripts/generate_app_catalog.py --write
python3 scripts/generate_app_catalog.py --check
```

The module reuses at most 192 target records and one active visual/callback.
Targets are rebuilt into those records instead of allocating a new target list
on every draw. Do not load this module again per frame or add an unbounded input
queue. Tests and simulator receipts belong outside installed package file lists.

## Hardware acceptance

On X4 Pro and Sticky, open Applications and check each visible control by touch,
including repeated taps, disabled buttons, modals, keyboards and both supported
orientations. On X4 Classic, verify the corresponding Confirm/arrow actions and
restoration while clocks are stopped. Check Stopwatch Start/Stop/Lap/Reset and
saved-session recovery, and verify one HID report action per click on a paired
host. Simulator radio replay does not establish physical RF acceptance.
