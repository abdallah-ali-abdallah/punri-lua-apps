# Daily Track

Daily Track is an offline app for daily habits and counters. It is listed in
the local `catalog.json`; publishing the updated catalog is a separate step.

## Install

Copy this entire `daily_track` folder to
`/.crosssmudge/applications/daily_track/` on the SD card, then open **Daily
Track** from Applications. Existing firmware also recognizes the legacy
`/.smudge` location.

## Controls

The app asks the person using it to confirm the displayed local date on every
launch because the current Lua clock API has no validity flag. If the clock goes
backward, Daily Track switches to a protected read-only screen; correct the
device clock and reopen it rather than adding a record to an older date. A
forward date or timezone change is also confirmed before it starts a new day.
Manually entered dates use a valid four-digit `YYYY-MM-DD` value. Date handling
keeps all 35 cells available around a year boundary rather than rejecting the
prior year's history.

On touch models, tap the card to toggle a Habit or add a Counter step; tap the
separate **Undo**, **Details**, **Manage**, **Export**, and **Exit** controls.
On X4 Classic, Back exits, Confirm performs the selected card action, Up opens
details, Down opens Manage, and Left/Right move the selection. Manage, Edit,
Details, and delete confirmation all have button navigation; deletion defaults
to **Keep tracker**.

Creating and editing names/numbers needs the firmware keyboard. Firmware that
does not provide it shows a clear unsupported message instead of a broken
editor.

## Storage and limits

`daily_track_v1.dat` is a versioned, validated file in the app's private save
folder. It is limited to 24 KiB, 12 trackers, 48 UTF-8 bytes per non-empty name,
35 stored display-day records per tracker, values/goals up to 1,000,000, and
counter steps from 1 to 100,000. A logged zero is retained as a record; it is
different from an empty day. Bad, truncated, oversized, or unreadable saved
files are protected and never replaced automatically.

The 35-day grid is only the visible history. Each tracker stores a settled
chain and all-time best chain separately, so streaks remain correct after old
grid cells age out. A counter's target is copied into its first record for that
day; changing a target later never rewrites past completion, and a changed
target affects the current day only if it has no recorded value yet.

Changes are debounced and saved transactionally. A failed write leaves the
in-memory change dirty and exposes **Save failed — Retry** while the app stays
open. Exit attempts a save first; it does not defer dirty writes to `on_exit`.

## CSV exports

**Export** creates the first unused `daily_track_export_###_partial.csv` file.
Rows are appended in small chunks, so a failed SD write can leave only a partial
file; the filename and the absence of the final `# COMPLETE` marker make that
state explicit. Cells are quoted and names beginning with spreadsheet formula
prefixes are apostrophe-protected.
