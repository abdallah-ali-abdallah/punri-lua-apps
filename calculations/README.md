# Calculations 0.1.0

An offline scientific calculator for PUNRI's supported S3 readers, designed
first for the Xteink X4 Pro. It runs entirely in the existing Lua sandbox.

## Install

Open PUNRI's **App Store**, refresh the catalog, and install **Calculations**.
Alternatively, copy these files to `/.punri/applications/calculations/` on the SD card:

```text
manifest.json  main.lua       app.lua       ui.lua       i18n.lua
bigint.lua     decimal.lua    number.lua    parser.lua   engine.lua
editor.lua     storage.lua    tools.lua     icon.raw
```

Open **Applications → Calculations**. No firmware or SDK patch is needed.
PUNRI API 2 or later is required for orientation; optional text entry uses
`has_feature("keyboard")` and reports when a firmware update is needed.

## Five workspaces

- **Calculate:** large five-column keypad, natural fractions/roots/powers,
  scientific palette, DEG/RAD, decimal/exact-fraction/engineering display,
  Ans, 26 named variables, 20-step undo/redo, and 50 retained history items.
- **Functions:** four editable Cartesian definitions shared by Graph and Table.
  Use the calculator's natural keypad to edit a definition and `=` to save it.
  Clear followed by `=` removes a definition. Toggle Y1–Y4 without deleting it.
- **Graph:** solid/dash/dot/dash-dot curves, trace by touch or step buttons,
  zoom, pan, standard window, expanded view, and bracketed root/intersection
  analysis. Plot jobs are sliced and stop when leaving the view.
- **Table:** five rows with editable start/step, Y1–Y2 / Y3–Y4 columns,
  paging, full-value inspection, and a jump to the selected x on Graph.
- **Tools:** a numerical equation solver, one-variable statistics, matrices
  up to 4×4 (determinant/inverse/transpose), rectangular-to-polar complex
  conversion, unsigned 32-bit base conversion, exact length/mass/temperature
  conversions, and app settings.

Specialist tools perform the operations listed above; full CAS, general complex
expression arithmetic, regression, calculus, financial functions, and 3D plots
are future work. There are no placeholder buttons for those functions.

## Natural input

The template row keeps **fraction**, **square root**, **power**, and
**equation** keys visible. Empty fields are drawn as outlined boxes, independent
of the installed font's symbol coverage.

1. Fraction → `3` → Next field → `4` → `=` gives `0.75`.
2. Fraction → square root → `9` → Next field → `3` → `=` gives `1`.
3. Equation → `x` → power → `2` → Next field → `9` → `=` opens the solver.
   Choose lower/upper bounds that enclose one root, then Solve.

Tap a value to select it. Previous/Next field navigate numerator/denominator,
base/exponent, and function arguments. Applying a template wraps a selected
value; templates can nest. Next field after the last value exits the template,
so a following `+` continues the outer expression. An unfinished field is never evaluated as zero.
Text/Natural switches between the same expression and its structured display.
Incomplete expressions retain a readable linear view until their structure is
valid again. The selected field stays visible in a bounded editor viewport.

The scientific palette also has inverse/hyperbolic trig, log/ln/exp, log with a
chosen base, nth roots, absolute value, factorial, gcd/lcm, brackets, and powers
of ten. Multiplication must be explicit. Powers associate right to left:
`2^3^2 = 512`, `-2^2 = -4`, and `(-2)^2 = 4`.

Physical buttons reach every visible control: Left/Right move focus, Up/Down
move between rows, Page Back/Forward jump five controls, and Confirm activates.
Back closes a sheet, cancels a solver, returns to Calculate, then saves/exits.
Rotation preserves input and the selected field. Apps handle `on_tap` only, so
the compatibility `on_touch` callback cannot duplicate a key press.

## Accuracy and bounds

PUNRI's Lua has signed 32-bit integers and binary32 native floats. The primary
calculator does **not** use those floats for its decimal mantissa:

- Exact arithmetic uses reduced decimal-integer fractions, up to 90 digits in
  numerator and denominator. Decimal input is parsed directly into a fraction.
  `(10^8 + 1) - 10^8` therefore remains exactly `1`.
- Approximate square roots, powers, trig/inverse/hyperbolic trig, logarithms,
  and exponential functions use app-owned 24-significant-digit software
  decimal arithmetic. Display is rounded to 12 significant digits, ties to even.
  The approximation label distinguishes these results from exact fractions.
- Working unsigned integers are capped at 192 decimal digits; numeric literals
  at 96 bytes and exponents from -80 through 80. Approximate output magnitudes
  are bounded to `1e-96` through below `1e97`. Overflow and underflow report errors.
- Exact exponentiation handles integer exponents from -128 through 128.
  Other positive-base powers use the approximate log/exp path. Root degrees
  are nonzero integers within ±128. Factorial accepts 0–50.
- Trig reduction accepts at most 1,000,000 radians; exp accepts -200 through 200.
  Extreme, ill-conditioned inputs can lose relative accuracy despite guard
  digits. The independent oracle gate covers its stated tolerance and vectors,
  not a universal accuracy proof for every expression.
- Graph curves and trace use explicitly labeled **~6-digit native-float
  previews**, two-pixel x sampling, midpoint discontinuity checks and clipping.
  They are not precise measurements or a proof of continuity. Table uses the
  primary numeric backend; graph/table values agree to the preview precision.
- The solver uses bounded bisection with width and absolute residual checks
  (`1e-11*(1+abs(x))`, `1e-12`), a 100-iteration cap and cancellation between
  two-iteration slices. No bracket, invalid domains, poles and non-convergence
  produce an error. It does not find every root or prove uniqueness.

Expressions have at most 512 ASCII bytes, 256 tokens, and depth 20. The renderer
measures the real fonts; selection scrolls through bounded natural input rather
than shrinking it below readable font sizes. Long answers can be tapped to open
the full exact and decimal values. Matrix/list inputs use comma-separated values
and semicolons between matrix rows. Lists are limited to 200 values; the shared
keyboard accepts at most 4096 bytes per field.

## Saved data and resources

Private data is `/.punri/saved_data/calculations/session_v1.txt`. A versioned,
checksummed snapshot holds calculator input/answer, history, variables, functions,
angle/number/language modes, workspace, and orientation. Only the calculator
session is resumed; specialist form drafts and graph windows are temporary.
Writes use PUNRI's existing transactional storage, are debounced after edits,
and run on exit. Failed writes leave the prior snapshot intact, with Retry or
an explicit exit-without-saving choice. Unknown/corrupt schemas stay read-only
until **Tools → Settings → Reset saved session** is confirmed.

The app uses one bounded display command list (2400 commands), shared drawing/
hit-test rectangles, no extra framebuffer, and no background tasks or networking.
Graph storage is bounded by plot width and four curves. Command lists rebuild
on state changes; `on_draw` replays them. Native simulator readings and heap
receipts are measurements for that environment, not physical PSRAM/latency proof.
English/Arabic labels use an app string helper; untranslated explanatory errors
fall back to English. Mathematical input and numerical columns stay LTR.

## Validation

From the firmware checkout, use a temporary environment/output directory:

```sh
python3 -m venv /tmp/calculations-tests-venv
/tmp/calculations-tests-venv/bin/pip install -r apps/calculations/tests/requirements.txt
/tmp/calculations-tests-venv/bin/python apps/calculations/tests/run.py --output-dir /tmp/calculations-tests
pio run -e x4-pro-simulator
python3 scripts/test_calculations_simulator.py --program .pio/build/x4-pro-simulator/program
```

The host gate compiles the actual vendored Lua configuration, exercises engine,
editor, tools, controller, geometry, cancellation and persistence, and compares
against an 80-digit mpmath oracle. The simulator gate installs a disposable SD
fixture and drives real touch events through natural math, equations, graph/table,
rotation, reopening and blocked saves. Logs/screenshots/receipts go outside Git.
The test directory's C runner and Python oracle are never installed on the reader.

Hardware acceptance: repeat the three natural-input examples above on a physical
X4 Pro, test both orientations, inspect repeated trace/zoom ghosting, reopen the
session, and return to the reader to check page turns/sleep. Repeat controls with
buttons on X4 Classic before claiming physical button parity. No EPUB cache reset
is needed. X4 Pro simulator evidence does not establish physical-device behavior.

Regenerate `icon.raw`/`icon.svg` with `python3 tools/generate_icon.py` from this
folder. The bitmap is 32×32, 1-bit, rotated for the existing PUNRI icon convention.
