# Stopwatch (local development build)

This is an in-place improvement of the existing `stopwatch` app. Its ID,
`stopwatch.dat` filename and legacy file grammar remain unchanged. It is a
local development build: `catalog.json` includes all required Lua modules,
while the version remains unchanged. Remote publication is a separate step.

## Install locally

Copy the complete directory, including every Lua module, to:

```text
/.punri/applications/stopwatch/
```

Keep `manifest.json`, `main.lua`, `stopwatch.lua`, `ui.lua`, `input.lua`, and
`icon.raw` together. Start it from **Applications** after safely ejecting the
SD card. No network connection, cache reset or firmware setting is required.

## Controls

The same visible targets are used for drawing and touch hit-testing.

| Visible action | X4 Classic button | Touch devices |
|---|---|---|
| Start / Stop | Confirm | Tap Start / Stop |
| Lap | Left | Tap Lap |
| Reset | Right | Tap Reset, then choose Keep or Reset now |
| Exit / Retry save | Back | Tap Exit or Retry save |
| Earlier lap page | Up / Page Back | Tap Prev |
| Newer lap page | Down / Page Forward | Tap Next |

The Reset dialog defaults to **Keep**. Back, Left, Up and Page Back keep the
session; Right, Down and Page Forward select and perform **Reset now**;
Confirm performs the currently selected default. A completed touch invokes
`on_tap` only in this app, preventing the compatibility `on_touch(..., "tap")`
callback from applying the action twice.

## Limits, timing and sleep

- A session is bounded to **99:59:59.99**. The `HH:MM:SS.cc` readout keeps its
  width at minute/hour boundaries and avoids 32-bit Lua integer overflow.
- Up to **50 laps** are retained. At the limit, Lap is disabled and the app
  reports `Lap limit reached (50)`; it does not grow the in-memory list or
  rewrite the SD file.
- The live display asks for a redraw no more than once every 250 ms while the
  stopwatch is running. Time is derived from `punri.millis()`, not from draw
  count or e-paper refresh timing. A signed-32-bit `millis()` wrap is handled
  for a bounded running session.
- The app disables auto-sleep only while the stopwatch is actively running.
  The released manifest's startup default is cleared during `on_init()` and
  restored dynamically via `punri.prevent_sleep`; a physical power action can
  still sleep the device immediately.

## Saved session and failures

`/.punri/saved_data/stopwatch/stopwatch.dat` retains the existing format:

```text
<was-running:0-or-1>;<elapsed-ms>
<lap-ms>;<total-ms>
...
```

Stop, Lap, confirmed Reset and a changed session on exit use transactional
`punri.write_file` replacement. A failed write leaves the previous SD file in
place, shows **Save failed. Retry before exit.**, and changes Exit to **Retry
save**. The visible exit action does not leave until retry succeeds. A forced
activity exit can only make one best-effort attempt because `on_exit()` is
followed by Lua teardown.

If an old file says it was running, the app restores its elapsed snapshot as
**Stopped after restart**. It never claims to count time while the device was
asleep or off. Invalid, empty, oversized, or truncated data does not crash the
app and is not overwritten merely by launching then leaving it. Legacy files
with more than 50 laps show their most recent 50; the old file is untouched
until a user makes and saves a new change.

## Verification and hardware acceptance

Run the focused local checks from the firmware root:

```bash
python3 test/lua_apps/test_packages.py
pio run -e host-unit-tests -t unit-tests
pio run -e x4-classic-simulator
pio run -e x4-pro-simulator
pio run -e sticky-simulator
```

On X4 Classic, complete Start, 10 laps, both lap pages, Stop, Reset/Keep,
Reset now and an SD write-failure/retry using buttons only. On Sticky and X4
Pro, repeat with visible touch controls and Back swipe disabled. Check both
orientations, sleep/resume behavior and the return of auto-sleep after Stop.
Compare a 10-minute run with a reference clock; e-paper refresh frequency does
not establish centisecond accuracy. Hardware durability, display latency and
actual power behavior still require those device checks.
