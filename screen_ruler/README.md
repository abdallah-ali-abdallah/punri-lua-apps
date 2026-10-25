# Screen Ruler

`screen_ruler` is an offline, calibrated on-screen ruler for PUNRI. It does
not use a panel-size preset: screen resolution alone cannot establish a
physical length.

## Install

Copy the complete `screen_ruler/` folder to:

```text
/.crosssmudge/applications/screen_ruler/
```

It is listed in the local `catalog.json`; publishing the updated catalog is a
separate step. The firmware also discovers its `manifest.json` when the package
is copied directly to the SD card.

## First calibration

1. Open **Screen Ruler** and choose **Calibrate X and Y**.
2. Put a real ruler against the two endpoint markers for portrait **X**. Use
   Left/Right for one pixel and Up/Down for ten pixels, then enter the known
   length in millimetres. The current firmware keyboard is text rather than
   numeric-only, so enter a positive decimal with at most two fractional digits.
3. Repeat with a different real-world length. A disagreement of more than 5%
   restarts that axis instead of silently accepting it.
4. Repeat both references for portrait **Y**. The app stores rational
   `px/mm` values and uses the verified (second) reference as its scale.

The calibrated values are attached to `punri.get_device()` plus the portrait
screen dimensions. Moving an SD card to a different board or a screen of a
different size does **not** reuse its scale: the app displays a confirmation
and requires a fresh X/Y verification.

The app draws its zero marker at the visible L-origin, insets labels using the
available layout margin, and computes each tick directly from that origin.
When landscape is active, a horizontal ruler uses the stored physical Y scale
and a vertical ruler uses X; this keeps the physical axes correct after rotation.

## Controls

Touch devices have six bottom controls: **Mode**, the current unit (**mm**,
**cm**, or **inch**), **Calibrate**,
**Rotate**, **Clean**, and **Exit**. Clean mode hides setup controls but keeps
an Exit target. Tapping the current unit cycles **mm → cm → inch**.
Only `on_tap` is implemented; the activity also emits a legacy
`on_touch(..., "tap")` callback, and responding to both would apply a tap twice.

On X4 Classic:

- **Back** exits.
- **Confirm** opens the menu.
- **Up/Down** (or page buttons) change Mode on the ruler and make coarse
  adjustments during calibration.
- **Left** cycles units in reverse (**mm → inch → cm**); **Right** starts calibration.
- During calibration, **Left/Right** adjust one pixel and **Confirm** opens
  the length-entry keyboard.

The app only prevents automatic sleep while a valid ruler is actually visible.
It never requests periodic redraws; input and explicit state changes request a
new frame. PUNRI restores the prior orientation when the app exits.

## Accuracy and limits

This is an approximate physical ruler. Accuracy depends on the real reference,
endpoint alignment, usable bezel area, display rotation and the e-ink panel.
It is not a laboratory instrument. The app has no API for a physical bezel-safe
rectangle or rotated glyphs, so it uses the documented content margin and
horizontal labels rather than claiming an unavailable primitive.

Supported reference lengths are 1.00–500.00 mm; scales must be 0.25–20 px/mm.
All persisted numerators, denominators and tick intermediates remain below the
signed 32-bit Lua limit. Marks are 1 mm where pixels permit; if not, the app
shows the smallest representable whole-mm subdivision rather than overlapping
fake ticks. Millimetres, centimetres, and rounded inch labels are display
units—the underlying calibration remains millimetres.

`write_file` replacement is transactional, but an SD write can still fail. In
that case the former saved calibration remains active and the app keeps an
explicit **Retry** screen open. It does not rely on `on_exit()` for a last save.
A corrupt or unreadable record is treated as uncalibrated, never as a trusted
default.

## Hardware acceptance still required

The desktop simulator has no physical millimetres and cannot approve accuracy.
On Sticky, X4 Pro, and X4 Classic, use the same real ruler to calibrate X and Y,
then record the error at a short length, a medium length, and as near the usable
screen edge as practical. Test Horizontal, Vertical and Both in portrait and
landscape, confirm the zero corner is visible, check normal lighting, leave the
ruler open long enough to verify auto-sleep suppression, then exit and confirm
both orientation and normal auto-sleep return. A standard 85.60 mm card may be
an extra reference only if its dimensions are independently known.
