# Unit Convert

`unit_convert` is an offline PUNRI utility for length, mass, temperature, US
volume, speed and data conversions. It needs no network and does not keep the
screen awake.

## Install and control

Copy the complete `unit_convert/` folder to
`/.crosssmudge/applications/unit_convert/` on the SD card (or the documented
legacy application path). It is deliberately a local package: it is not added
to `catalog.json` by this change.

On a touch device, tap a category, **From**, **To**, **Swap**, or a key. The
keypad includes a visible **Exit** key, and each picker includes a visible
**Back** button. A touch tap is handled through `on_tap` only, which avoids
duplicate conversion input in the current PUNRI activity bridge.

On X4 Classic, use **Up/Down** (or page buttons) to move between Category,
From, To, Swap and the keypad. **Left/Right** change the highlighted category
or unit, move across keypad keys, or perform Swap. **Confirm** opens a unit
picker or presses the selected keypad key. **Back** exits. The picker uses
Back, Confirm, Previous and Next in the same way.

Changing category, From, To or Swap saves the selected units immediately using
transactional `write_file`. If that save fails, the app stays open and shows a
Retry action; press Confirm or tap the result card after fixing the SD issue.
The input text is intentionally not saved on every key press, so a failed exit
does not discard an already-committed unit selection.

## Units and numeric limits

| Category | Units |
| --- | --- |
| Length | mm, cm, m, km, inch, foot, yard, mile |
| Mass | mg, g, kg, metric tonne, ounce, pound |
| Temperature | Celsius, Fahrenheit, Kelvin |
| Volume | ml, L, **US** teaspoon, tablespoon, fluid ounce, cup, pint, quart, gallon |
| Speed | m/s, km/h, mph, knot |
| Data | byte, KiB, MiB, GiB, kB, MB, GB |

US volume units are not Imperial units. KiB/MiB/GiB use 1024, while
kB/MB/GB use 1000. Temperature below absolute zero and negative data values
are rejected.

PUNRI's Lua build uses 32-bit integers and 32-bit floating-point numbers. To
keep ratios and multiplication intermediates safe, each input is limited by its
unit's scale so the category base value never exceeds **1.1e15** (for example,
the GiB input cap is a little over one million, while byte input can be much
larger). Results are shown with **six significant digits**; large or very small
non-zero values use editable scientific notation. Values at or above 16,777,216
bytes are not claimed to be byte-by-byte integer exact, even though the app
prevents overflowing or changing a positive GiB value into a negative byte
result. Swap puts the displayed six-significant-digit result back into Input,
so a swap-back round trip is subject to that documented rounding.

Only one decimal point is accepted. One unambiguous decimal comma is accepted
and normalized; grouping such as `12,345` is rejected. Empty input, malformed
scientific notation, underflow to zero, `nan`, `inf`, and numbers outside the
input cap display an error rather than a fabricated zero.

## Hardware acceptance

On Sticky/X4 Pro, enter `-40`, select Celsius/Fahrenheit and Swap twice; then
choose US gallon and enter `1`, and verify the picker and keypad stay inside
the screen in portrait and landscape. On X4 Classic, repeat the same flow with
buttons only, navigate the full US-volume picker, then remove or write-protect
a test SD card while changing a unit and verify Retry remains visible. Restart
after a successful unit change and confirm that the last category and From/To
choices restore. Hardware e-ink refresh timing, physical touch calibration and
real SD-card failure recovery still require those device checks.
