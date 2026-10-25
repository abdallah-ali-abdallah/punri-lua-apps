# Screen Ruler

`screen_ruler` is an offline on-screen ruler for PUNRI. X4 Pro and X4 Classic
start automatically with their manufacturer's nominal physical scale. Optional
real-ruler calibration lets you fine-tune each axis independently.

## Install

Copy the complete `screen_ruler/` folder to:

```text
/.punri/applications/screen_ruler/
```

It is listed in the local `catalog.json`; publishing the updated catalog is a
separate step. The firmware also discovers its `manifest.json` when the package
is copied directly to the SD card.

## Automatic X4 Pro / X4 Classic calibration

Open the app on either device and the ruler is immediately ready. The app
recognizes PUNRI's `x4pro` and `x4` hardware IDs, with a 480×800 portrait panel.
Here `x4` means the supported ESP32-S3 X4 Classic; it does not add firmware
support for retired ESP32-C3 devices. Unknown devices and other panel sizes
continue to use manual calibration.

Xteink specifies **219 PPI** for both the
[X4 Pro](https://www.xteink.com/products/xteink-x4-pro-pocket-ereader) and
[X4 Classic](https://www.xteink.com/products/xteink-x4-classic-pocket-ereader).
The app converts this to the exact ratio `1095/127 px/mm` on both axes, using
25.4 mm per inch, rather than deriving a scale from the rounded 4.3-inch size.
This is automatic selection of the documented device scale, not a sensor
measurement of an individual panel. The ruler footer marks it **(auto)**.

An existing manual calibration for the same device and portrait dimensions
takes priority. A missing or foreign-device calibration uses the current
device's own profile; it never copies the other board's scale. A corrupt or
unreadable record is not trusted or rewritten merely by opening the app.
Preset selection does not write to SD; changing preferences or manually
calibrating still uses the existing transactional save and Retry flow.

**Reset calibration** restores the automatic profile on these two devices
while keeping Mode, Units and Orientation. On other devices it clears the
manual scale and returns to setup.

## Optional manual calibration / other devices

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
different size does **not** reuse its scale: supported X4 hardware selects its
own automatic profile, while other hardware requires fresh X/Y verification.

The app draws its zero marker at the visible L-origin, insets labels using the
available layout margin, and computes each tick directly from that origin.
When landscape is active, a horizontal ruler uses the stored physical Y scale
and a vertical ruler uses X; this keeps the physical axes correct after rotation.

## Controls

Touch devices have seven bottom controls: **Mode**, the current unit (**mm**,
**cm**, or **inch**), **Calibrate**,
**Rotate**, **Grid**, **Clean**, and **Exit**. Clean mode hides setup controls but keeps
an Exit target and supports touch measurements. Tapping the current unit cycles **mm → cm → inch**.
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
- The menu also exposes **Grid: on/off** and **Clear measurement**. All eight
  menu actions stay visible, using two columns in landscape.

## Inch ticks, touch measurements and grid

In inch mode, the long labelled marks are real **1, 2, 3… inches**, with
shorter marks at **½, ¼, ⅛ and ¹⁄₁₆ inch**. Positions use exactly 25.4 mm per
inch, calculated directly from zero. On the 219-PPI X4 presets, the 1-inch mark
is 219 pixels from zero and the 2-inch mark is 438 pixels from zero. Inch mode
does not reuse centimetre or millimetre tick spacing.

On touch devices, tap anywhere inside the measurement area to place a vertical
and horizontal guide through that point. The footer shows **X** and **Y**
distances from the ruler's zero corner in the selected unit. Tap another point
to move both guides. Changing units keeps the zero corner and the point fixed;
changing orientation or ruler mode clears the point. Use **Clear measurement**
in the menu to remove the guides. Clean mode also supports new measurements.

Tap **Grid** to enable or disable the dotted grid. The button is filled when
enabled. Grid spacing is 1 cm in metric mode and ¼ inch in inch mode, with a
coarser whole multiple when necessary to avoid crowded pixels. It stays aligned
to the calibrated zero and scales correctly after rotation. X4 Classic users
can toggle it through the menu with the physical buttons.

The grid and touched point reset when the app is restarted. Neither moving a
guide nor toggling the grid writes to SD or changes saved calibration. Input
requests a redraw; stationary guides do not create a periodic refresh loop.

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
fake ticks. Inch marks use exact sixteenths of an inch; metric marks use whole
millimetres. The underlying X/Y calibration remains in pixels per millimetre.
Touch readouts are rounded to two decimal places of the selected unit and
remain limited by the physical pixel size and calibration accuracy.

`write_file` replacement is transactional, but an SD write can still fail. In
that case the former saved calibration remains active and the app keeps an
explicit **Retry** screen open. It does not rely on `on_exit()` for a last save.
A corrupt or unreadable record is never used as a scale. Supported X4 hardware
uses its own nominal profile; other hardware returns to calibration setup.

## Hardware acceptance still required

The desktop simulator has no physical millimetres and cannot approve accuracy.
On X4 Pro and X4 Classic, first open Screen Ruler without saved calibration and
confirm it immediately shows **(auto)**. Check the 10, 30 and 50 mm marks against
a real ruler in portrait and landscape. Manual calibration remains available
if the nominal profile needs refinement. On Sticky, calibrate X and Y first.
Then record the error near the usable screen edge. Test Horizontal, Vertical and
Both in portrait and landscape, confirm the zero corner is visible, check normal lighting, leave the
ruler open long enough to verify auto-sleep suppression, then exit and confirm
both orientation and normal auto-sleep return. A standard 85.60 mm card may be
an extra reference only if its dimensions are independently known.

In inch mode, compare the **1** and **2** marks to a real inch ruler and check
the half/quarter/sixteenth subdivisions. Tap those intersections and check the
X/Y readings, move the point, toggle Grid twice, and repeat after rotation.
Check the menu's Grid control on X4 Classic. Existing calibration files should
remain unchanged when moving guides or toggling the grid.

The firmware's Screen Ruler LuaRunner fixture also runs the app-repository
regressions in `tests/screen_ruler/interaction.lua`, covering inch positions,
32-bit arithmetic bounds, measurements, grid toggles, and Clean-mode controls.

For real-renderer touch/button captures from a firmware checkout, first build
the matching supported simulator and run:

```sh
python3 apps/tests/screen_ruler/simulator.py --profile x4-pro-simulator \
  --program .pio/build/x4-pro-simulator/program
```

Repeat with `x4-classic-simulator` and its matching program for button controls.
The script creates a disposable virtual SD card and does not touch installed data.
