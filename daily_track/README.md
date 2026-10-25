# Daily Track

Daily Track is an offline app for daily habits and counters. It is listed in
the local `catalog.json`; publishing the updated catalog is a separate step.

## Install

Copy this entire `daily_track` folder to
`/.punri/applications/daily_track/` on the SD card, then open **Daily
Track** from Applications. Earlier installations migrate automatically.

## Controls

Daily Track uses the device's valid local date automatically when it opens and
when the date moves forward, so normal launches do not need a confirmation
screen. If the device cannot provide a valid date, the app asks for a manual
four-digit `YYYY-MM-DD` value. If the clock goes backward, Daily Track switches
to a protected read-only screen; correct the device clock and reopen it rather
than adding a record to an older date. Date handling keeps all 35 stored days
available around a year boundary rather than rejecting the prior year's history.

On touch models, tap the card to toggle a Habit or add a Counter step; tap the
separate **Undo**, **Details**, **Manage**, **Export**, and **Exit** controls.
Details starts at the current calendar month, labels Sunday through Saturday,
and has large **Prev** and **Today** buttons. It can browse the stored 35-day
history window. On X4 Classic, Back exits, Confirm performs the selected card
action, Up opens details, Down opens Manage, and Left/Right move the selection.
Within Details, Left/Up goes to the previous month and Right/Down moves toward
the current month. Manage, Edit, Details, and delete confirmation all have
button navigation; deletion defaults to **Keep tracker**.

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
