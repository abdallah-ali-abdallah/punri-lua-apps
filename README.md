# PUNRI Application Developer Guide

Welcome to the **PUNRI Application Platform**! PUNRI features a lightweight, sandboxed **Lua 5.4** application engine that enables anyone to build, share, and install custom e-paper applications directly from SD card storage—**no firmware compilation or flashing required**.

The public app repository is [punri-lua-apps](https://github.com/abdallah-ali-abdallah/punri-lua-apps).
It stores `catalog.json` and each `<app_id>/` directory at its root. The firmware
mounts this repository as its `apps/` submodule. Examples below using `apps/`
assume the firmware checkout; omit that prefix in a standalone app checkout.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Application Directory Structure](#application-directory-structure)
3. [Manifest Specification (`manifest.json`)](#manifest-specification-manifestjson)
4. [Application Icon (`icon.raw`)](#application-icon-iconraw)
5. [Application Lifecycle Callbacks](#application-lifecycle-callbacks)
6. [Hardware Button & Touch Mapping](#hardware-button--touch-mapping)
7. [The `punri.*` API Reference](#the-punri-api-reference)
   - [Display & Refresh Control](#display--refresh-control)
   - [Typography & Text Wrapping](#typography--text-wrapping)
   - [2D Graphics Primitives & Shapes](#2d-graphics-primitives--shapes)
   - [Hardware Queries & Utilities](#hardware-queries--utilities)
   - [Persistence & File I/O](#persistence--file-io)
8. [Multi-File Projects & Assets](#multi-file-projects--assets)
9. [Memory Discipline & E-Paper Best Practices](#memory-discipline--e-paper-best-practices)
10. [Complete "Hello World" Example](#complete-hello-world-example)
11. [Testing & Installing Apps](#testing--installing-apps)
12. [Submitting to the App Store](#submitting-to-the-app-store)
13. [Bundled Applications](#bundled-applications)

---

## Architecture Overview

- **Compatibility:** `punri.*` is the public API. Released `smudge.*` and `ink.*` scripts remain supported as aliases of the same table; existing applications and their saved data stay in place. The legacy SD directory names below are intentional.
- **Engine:** Sandboxed Lua 5.4 runtime embedded within PUNRI firmware.
- **Location on Device:** `/.crosssmudge/applications/<app_id>/` (fallback: `/.smudge/applications/<app_id>/`).
- **Dynamic Discovery:** PUNRI discovers all installed applications on SD card startup and populates the **Applications** menu automatically.
- **Zero-Flash Iteration:** Changes made to Lua scripts or assets on the SD card take effect immediately the next time the app is launched.

---

## Application Directory Structure

Every application lives in its own subdirectory inside `apps/` (or on device in `/.crosssmudge/applications/<app_id>/`):

```text
apps/
└── my_app/
    ├── manifest.json       # Required: Metadata, name, author, entry script
    ├── main.lua            # Required: Main Lua entry script
    ├── icon.raw            # Optional: 32x32 1-bit raw bitmap icon (128 bytes)
    ├── helper.lua          # Optional: Secondary Lua modules
    └── data.txt            # Optional: Text or read-only assets
```

---

## Manifest Specification (`manifest.json`)

The `manifest.json` file describes your application to PUNRI, the App Store, and the Web Manager:

```json
{
  "id": "my_app",
  "name": "My Custom App",
  "version": "1.0.0",
  "author": "YourName",
  "description": "A clean e-paper utility or game for PUNRI.",
  "entry": "main.lua"
}
```

### Manifest Fields

| Field | Type | Description |
| :--- | :--- | :--- |
| `id` | string | Unique identifier matching folder name (`[a-z0-9_-]+`). |
| `name` | string | User-facing display title shown in the Applications menu. |
| `version` | string | Semantic version (e.g. `"1.0.0"`). |
| `author` | string | Creator name or handle. |
| `description`| string | One-sentence summary displayed in the App Store / Web Viewer. |
| `entry` | string | Entry point script filename (default: `"main.lua"`). |
| `min_api` | integer | Optional: Minimum required PUNRI Lua API version (e.g. `2` for apps utilizing `prevent_sleep`, `set_orientation`, or `has_feature`). Firmware older than this version will prevent launching and show a clear update prompt rather than crashing. |
| `prevent_sleep` | boolean | Optional: If `true`, disables the device's automatic inactivity sleep timer while this app is running (e.g. for desk clocks, timers, dashboards). Standard auto-sleep resumes immediately when the app exits. |

---

## Application Icon (`icon.raw`)

Each application can provide an authentic 32x32 monochrome icon:

- **Format:** Raw 1-bit monochrome uncompressed bitmap, 32 pixels wide by 32 pixels high.
- **File Size:** Exactly **128 bytes** (`32 * 32 / 8 = 128`).
- **Bit Convention:** 
  - `0` bit = **Drawn / Black pixel**
  - `1` bit = **White / Transparent background**
- **Hardware Coordinate Alignment:** Because PUNRI operates in portrait mode on landscape e-ink hardware panels, the icon pixel stream is stored pre-rotated 90° counter-clockwise so the ESP32 can blit it directly into the screen framebuffer with zero rotation overhead.

### Managing and Editing `icon.raw` with `scripts/convert_icon.py`

The repository includes a helper utility at `scripts/convert_icon.py`:

```bash
# 1. View an icon directly in your terminal (ASCII art preview):
python scripts/convert_icon.py view apps/watertracker/icon.raw

# 2. Convert icon.raw to an editable PNG:
python scripts/convert_icon.py raw2png apps/watertracker/icon.raw icon.png

# 3. Convert an edited PNG/SVG back to icon.raw:
python scripts/convert_icon.py png2raw icon.png apps/watertracker/icon.raw

# 4. Generate a C header (for built-in system firmware icons):
python scripts/convert_icon.py header icon.png my_icon
```

### Editing Workflow

1. Export the icon to PNG: `python scripts/convert_icon.py raw2png apps/myapp/icon.raw my_icon.png`
2. Open `my_icon.png` in any image editor (Aseprite, Photoshop, GIMP, MS Paint, Piskel).
3. Draw your 32x32 black and white pixel art.
4. Convert back to `icon.raw`: `python scripts/convert_icon.py png2raw my_icon.png apps/myapp/icon.raw`

---

## Application Lifecycle Callbacks

PUNRI calls global functions defined in your `main.lua` at specific events:

### `on_init()`
Called once when your app is launched. Initialize your state, seed random numbers, and load saved preferences here:
```lua
function on_init()
    math.randomseed(os.time())
    score = tonumber(punri.load("high_score", "0")) or 0
end
```

### `on_draw()`
Called whenever the screen needs to be rendered. Clear the buffer and draw all UI elements here:
```lua
function on_draw()
    punri.clear()
    punri.header("My App", "v1.0")
    punri.centered_text(300, "Press Select to play!", "ui12", "bold", true)
    punri.button_hints("Back", "Select", "", "")
end
```

### `on_button(btn, pressed)`
Called on hardware button state changes. `btn` is a string identifier, and `pressed` is a boolean (`true` on button down, `false` on button release):
```lua
function on_button(btn, pressed)
    if not pressed then return end -- Act on release/press

    if btn == "back" then
        punri.exit()
    elseif btn == "confirm" then
        score = score + 1
        punri.request_update()
    end
end
```

### `on_touch(event, x, y)` *(Touch-Enabled Devices)*
Called on touch events on supported hardware (e.g. Seeed reTerminal Sticky, Xteink X4 Pro). `event` is `"down"`, `"move"`, or `"up"`:
```lua
function on_touch(event, x, y)
    if event == "up" then
        -- Check if touch landed inside a button rectangle
    end
end
```

### `on_update()` *(Optional Real-Time Loop)*
For games or animations requiring real-time gravity or ticking (e.g. *Block Drop* piece falling):
```lua
local last_tick = 0
function on_update()
    local now = punri.millis()
    if now - last_tick > 500 then
        last_tick = now
        drop_piece()
        punri.request_update()
    end
end
```

### `on_exit()` *(Optional)*
Called right before the app terminates. Save final state or flush data:
```lua
function on_exit()
    punri.save("high_score", tostring(score))
end
```

---

## Hardware Button & Touch Mapping

PUNRI standardizes button names across all hardware variations:

| Button String | Action / Convention | Default button role (board mapping may differ) |
| :--- | :--- | :--- |
| `"back"` | Exit / Cancel / Previous menu | Bottom Left Button |
| `"confirm"` | Select / Enter / OK / Action | Bottom Center-Left Button |
| `"left"` | Navigate Left / Decrease | Bottom Center-Right Button |
| `"right"` | Navigate Right / Increase | Bottom Right Button |
| `"up"` | Navigate Up / Menu | Top Left Button |
| `"down"` | Navigate Down / Submenu | Top Right Button |
| `"page_back"` | Page Previous | Top Left Button |
| `"page_forward"` | Page Next | Top Right Button |

### Menu Navigation Convention
In vertical menu lists (settings menus, grimoires, selection menus):
- **Bottom Left Button (`"left"`)**: Navigates **Up** (previous menu item).
- **Bottom Right Button (`"right"`)**: Navigates **Down** (next menu item).
- **Top Buttons (`"up"` / `"page_back"`, `"down"` / `"page_forward"`)**: Adjust values **Left** and **Right** (e.g. decrease/increase values, cycle options).
- **Confirm Button (`"confirm"`)**: Selects or cycles the highlighted row.
- **Back Button (`"back"`)**: Saves changes and exits/returns.
- **Button Hints Convention**: In menu screens, use `punri.button_hints("Back", "Select", "Up", "Down")`.

---

## The `punri.*` API Reference

### Display & Refresh Control

- **`punri.get_bounds()`**\
  Returns `w, h` integers for current screen dimensions (typically `480, 800`).
- **`punri.get_metrics()`**\
  Returns system layout metrics table:
  - `top_padding` (default ~4px)
  - `header_height` (standard top header height)
  - `button_hints_height` (bottom action bar height)
  - `content_side_padding` (bezel-safe margin)
- **`punri.clear([color])`**\
  Clears the screen buffer. Default is white (`color=false`).
- **`punri.request_update()`** *(or `punri.redraw()`)*\
  Schedules an e-paper screen refresh. Call this whenever state changes.
- **`punri.refresh([full])`**\
  Triggers a display refresh. If `full` is `true` or `"full"`, performs a full e-paper flashing refresh to clear ghosting.
- **`punri.full_refresh()`**\
  Forces a full hardware e-paper flashing refresh (`HalDisplay::RefreshMode::FULL_REFRESH`) immediately.
- **`punri.invert_rect(x, y, w, h)`**\
  Inverts the 1-bit pixel buffer inside the specified rectangular region (turns white pixels black and black pixels white).
- **`punri.invert()`** *(or `punri.invert_screen()`)*\
  Inverts the entire screen buffer.
- **`punri.set_orientation(mode)`**\
  Dynamically changes the display rotation at runtime. `mode` can be:
  - `"portrait"` (default, 0°)
  - `"landscape"` / `"landscape_cw"` (90° clockwise)
  - `"portrait_inverted"` (180° upside down)
  - `"landscape_ccw"` (270° counter-clockwise)  
  *Note:* When the application exits, PUNRI automatically restores the system's prior orientation.
- **`punri.get_orientation()`**\
  Returns the current display orientation string (`"portrait"`, `"landscape"`, `"portrait_inverted"`, or `"landscape_ccw"`).
- **`punri.popup(message)`** *(or `punri.draw_popup(message)`)*\
  Renders a standard system modal popup box centered on screen with the given message.
- **`punri.millis()`** *(or `punri.get_time_ms()`)*\
  Returns millisecond uptime counter.
- **`punri.time()`**\
  Returns UNIX epoch timestamp (seconds).
- **`punri.random(min, max)`**\
  Returns a random integer between `min` and `max`.
- **`punri.exit()`**\
  Closes the application and returns to the Applications menu.
- **`punri.log(message)`**\
  Outputs a debug log message to serial monitor (`[INF] [LUA] ...`).

---

### Typography & Text Wrapping

PUNRI includes high-quality embedded anti-aliased bitmap fonts:

- **Supported Fonts:**
  - `"small"`: 8pt compact UI font (rubrics, metadata)
  - `"ui10"`: 10pt standard UI font
  - `"ui12"`: 12pt prominent font (headings, cards, menu items)
  - `"bitter14"`: 14pt serif reader font
  - `"reader"`: Default user-selected reader font
- **Styles:** `"regular"`, `"bold"`

#### Functions:
- **`punri.text(x, y, text, [font], [style], [align], [color])`**\
  Renders text at `(x, y)`. `align` can be `"left"` (default), `"center"`, or `"right"`. `color` is boolean (`true` = black, `false` = white).
- **`punri.centered_text(y, text, [font], [style], [color])`**\
  Draws horizontally centered text across the entire display width at vertical position `y`.
- **`punri.text_width(text, [font], [style])`**\
  Returns the measured pixel width of the text.
- **`punri.line_height([font])`**\
  Returns the font's standard line height in pixels.
- **`punri.wrapped_text(text, maxWidth, [font], [style], [maxLines])`**\
  Performs pixel-perfect word wrapping. Returns a table:
  ```lua
  local res = punri.wrapped_text("A long sentence that wraps cleanly.", 400, "ui12", "regular")
  -- res.lines is an array of wrapped strings
  -- res.total_height is the total pixel height
  for i, line in ipairs(res.lines) do
      punri.text(20, y + (i - 1) * punri.line_height("ui12"), line, "ui12", "regular")
  end
  ```

---

### 2D Graphics Primitives & Shapes

All shape drawing functions support a customizable line **thickness** (stroke width in pixels):

- **`punri.pixel(x, y, [color])`**\
  Draws a single pixel.
- **`punri.line(x1, y1, x2, y2, [thickness], [color])`**\
  Draws a line between `(x1, y1)` and `(x2, y2)` with optional pixel thickness (default 1).
- **`punri.thick_line(x1, y1, x2, y2, thickness, [color])`**\
  Draws a line with specified pixel thickness.
- **`punri.rect(x, y, w, h, [filled], [thickness], [color])`**\
  Draws an outline or solid rectangle. For outlines, `thickness` specifies the border stroke width in pixels.
- **`punri.rounded_rect(x, y, w, h, radius, [filled], [thickness], [color])`**\
  Draws a rounded rectangle with corner radius. For outlines, `thickness` specifies border stroke width in pixels.
- **`punri.circle(x, y, radius, [filled], [thickness], [color])`**\
  Draws an outline or solid circle. For outlines, `thickness` specifies border stroke width in pixels.
- **`punri.triangle(x1, y1, x2, y2, x3, y3, [filled], [thickness], [color])`**\
  Draws an outline or filled triangle between three vertices `(x1, y1)`, `(x2, y2)`, and `(x3, y3)`.
- **`punri.rect_dither(x, y, w, h, [is_dark])`**\
  Fills a rectangle with an authentic e-paper dither pattern (checkerboard shade).
- **`punri.heart(x, y, size, [filled])`**\
  Draws a vector heart icon.
- **`punri.draw_sprite(x, y, w, h, data, [inverted], [dither])`** *(or `punri.sprite(...)`)*\
  Renders a 1-bit monochrome bitmap or sprite to the display:
  - `x, y`: Screen coordinates.
  - `w, h`: Pixel dimensions of the sprite.
  - `data`: Can be a relative file path (e.g. `"icon.raw"`, `"sprites/coin_heads.raw"`), a raw binary byte string (MSB-first, 1 bit per pixel, `0` = black, `1` = white/transparent), or a Lua table of byte values (`{ 0x00, 0xFF, ... }`).
  - `inverted`: Optional boolean (`true` renders white pixels on dark backgrounds).
  - `dither`: Optional boolean (`true` renders black pixels with e-paper light-gray checkerboard dithering).
- **`punri.in_rect(px, py, rx, ry, rw, rh)`** *(or `punri.point_in_rect(...)`)*\
  Hit-testing helper: returns `true` if coordinate `(px, py)` falls inside rectangle `(rx, ry, rw, rh)`.
- **`punri.header(title, [right_text])`**\
  Draws standard PUNRI system header with title, battery indicator, and divider.
- **`punri.button_hints(btn1, btn2, btn3, btn4)`**\
  Draws bottom navigation pills corresponding to hardware buttons.

---

### Hardware Queries & Utilities

- **`punri.has_touch()`** *(or `punri.has_touchscreen()`)*\
  Returns `true` if the current device has hardware touchscreen support (e.g. Seeed reTerminal Sticky, Xteink X4 Pro), or `false` on button-only devices (Xteink X4 Classic).
- **`punri.get_battery()`** *(or `punri.battery()`)*\
  Returns the current battery level as an integer percentage (`0`–`100`).
- **`punri.get_device()`**\
  Returns the hardware identifier: `"sticky"`, `"x4pro"`, `"x4"` (X4 Classic), or `"simulator"`. These are device identifiers, not the firmware product name.
- **`punri.get_date()`** *(or `punri.date()`)*\
  Returns a calendar date/time table from the device's hardware RTC clock:
  ```lua
  local d = punri.get_date()
  -- d.year (e.g. 2026), d.month (1-12), d.day (1-31),
  -- d.wday (1=Sun .. 7=Sat), d.hour (0-23), d.min (0-59), d.sec (0-59)
  ```
- **`punri.get_memory()`** *(or `punri.memory()`)*\
  Returns real-time heap metrics table for profiling embedded memory usage:
  - `lua_kb`: Kilobytes currently allocated by the Lua runtime.
  - `lua_max_kb`: Configured Lua heap ceiling (normally 2048 KB on the supported S3/PSRAM profiles; simulator fault injection may lower it).
  - `free_heap`: Total free ESP32 internal DRAM (in bytes).
  - `max_alloc`: Largest contiguous allocatable block in DRAM (in bytes).
- **`punri.is_button_down(btn)`**\
  Returns `true` if the specified hardware button (`"back"`, `"confirm"`, `"up"`, `"down"`, `"left"`, `"right"`) is currently pressed/held down.
- **`punri.prevent_sleep([enabled])`** *(or `punri.keep_awake([enabled])`)*\
  Controls the device's automatic inactivity sleep timer while the app is active. Pass `true` (default if omitted) to keep the display awake indefinitely (ideal for desk stands, live clocks, timers, and dashboards). Pass `false` to re-enable normal auto-sleep timeout. The device's physical Power button continues to enter deep sleep immediately on demand, and regular auto-sleep is automatically restored as soon as the user exits the app.
- **`punri.is_prevent_sleep()`** *(or `punri.is_keep_awake()`)*\
  Returns `true` if auto-sleep prevention is currently active, or `false` otherwise.
- **`punri.version()`** *(or `punri.get_version()`)*\
  Returns the current PUNRI firmware version string (e.g. `"1.6.5.3"`).
- **`punri.api_version`** *(or `punri.get_api_version()`)*\
  Returns the integer API level (currently `3`). API `1` was the initial app engine release; API `2` adds sleep prevention, dynamic orientation switching, full-refresh requests, and version/feature introspection. API `3` adds the functional `radio`, `ble`, `wifi`, and `net` modules; use `radio.capabilities()` to check their availability.
- **`punri.has_feature(name)`**\
  Returns `true` if a specific feature is supported (e.g. `"prevent_sleep"`, `"orientation"`, `"full_refresh"`, `"touch"`).

---

### Persistence & File I/O

PUNRI provides key-value persistence, full sandboxed file operations, and high-performance streaming file section readers:

- **`punri.save(key, value_string)`**\
  Persists a key-value string to the app's private SD storage
  (`/.smudge/saved_data/<app_id>/<key>.dat`). Replacing an existing value is
  transactional: write, sync and close complete in a temporary file before the
  previous value is backed up and the new value is published. An interrupted
  replacement is recovered on the next access.
- **`punri.load(key, [default_string])`**\
  Reads a previously saved string. Returns `default_string` if not found.
- **`punri.file_exists(relative_path)`**\
  Returns `true` if a file exists inside the application's directory.
- **`punri.read_file(relative_path, [maxBytes], [offset])`**\
  Reads and returns contents of a file inside the app folder as a string. Supports optional `maxBytes` (default 65536) and byte `offset` (default 0) for random access / binary seeks without loading entire files into memory.
- **`punri.write_file(relative_path, content_string, [append])`**\
  Writes `content_string` below the app's private save directory. The default
  overwrite/create mode uses the same transactional replacement and recovery
  as `punri.save`. If `append` is `true`, bytes are appended in place to retain
  streaming behavior; append is deliberately not atomic, and a short SD write
  can leave a partial suffix while returning `false`. Returns `true` only after
  the bytes are written, synced and the file is closed.
- **`punri.list_files([dir_relative_path])`**\
  Returns a Lua array of filenames present in the given subfolder (or app root directory if omitted).
- **`punri.delete_file(relative_path)`**\
  Deletes the specified file inside the app directory. Returns `true` on success.
- **`punri.find_section(path, tag, [endPrefix], [maxBytes], [callback])`**\
  *(Aliases: `punri.find_file_section`, `punri.read_lines`)*\
  High-performance section parser that reads directly from SD card storage using 512-byte stack buffers with **zero dynamic C++ heap allocation**:
  
  **Mode 1 — String Return:**
  ```lua
  -- Extracts text between "[SECTION_A]" and the next "[" marker:
  local text = punri.find_section("data.txt", "[SECTION_A]", "[", 4096)
  ```
  
  **Mode 2 — Zero-Allocation Line Streaming Callback (Recommended for Large Files):**
  ```lua
  -- Streams matching lines one-by-one directly into a Lua closure.
  -- Uses virtually zero Lua heap; does not load the file into memory!
  punri.find_section("psalter.txt", "[PSALM 23]", "[", function(line)
      -- Process line (e.g. draw on screen or paginate)
      -- Return false to stop reading early
  end)

  -- If tag is "", reads from line 1 of the file to end (or until callback returns false):
  punri.find_section("chapter1.txt", "", "", function(line)
      print(line)
  end)
  ```

---

## Multi-File Projects & Assets

To keep your codebase organized, you can split your logic into multiple Lua files and load them using `dofile()` with relative paths:

```lua
-- In main.lua:
dofile("constants.lua")
dofile("game_engine.lua")
```

Any extra assets (like `.txt`, `.json`, `.raw` sprites, or level definitions) placed in your app folder can be read using `punri.read_file("levels/level1.txt")` or streamed using `punri.find_section()`.

---

## Memory Discipline & E-Paper Best Practices

### Bounded Memory on Supported S3 Devices
PUNRI supports Sticky, X4 Pro and X4 Classic with ESP32-S3 and PSRAM. The Lua allocator has a configured heap ceiling; query `punri.get_memory()` for the current limit and use bounded, reusable data. PSRAM capacity does not remove internal-DRAM, stack or contiguous-allocation limits. Retired C3 hardware is not a PUNRI acceptance target.

Follow these proven patterns to ensure your app is rock-solid:

1. **Beware of Compiler Memory Spikes with `dofile()`:**  
   Compiling another Lua source module needs temporary compiler memory in addition to the live application state. Measure the peak with the actual package and device rather than assuming the source file size is its runtime cost.\
   *Rule of thumb:* Keep `main.lua` lean, or load modules only once at startup rather than repeatedly inside functions.

2. **The Zero-RAM-Page Disk Cache Pattern:**  
   If your app displays long multi-page text (e.g. books, daily office prayers, scripture, rules, logs):  
   - **Do NOT** store all formatted pages in an array of Lua strings in RAM (`pages = {"...", "..."}`). 30 pages of text can consume 20+ KB of precious heap.  
   - **Instead**, stream formatted lines directly to a cache file (`punri.write_file("cache.txt", ...)`).\
   - When displaying a page, use `punri.find_section("cache.txt", "[PAGE " .. cur .. "]", "[PAGE ", callback)` to stream only the active page's lines to screen. This keeps memory usage flat (~55–60 KB) regardless of whether the document has 5 pages or 100 pages!

3. **Use Top-Level Functions Instead of Deeply Nested Closures:**  
   Functions defined inside other functions create new closure and upvalue table objects every time the outer function runs. Define helpers (`emit`, `wrap`, `divider`, `draw_ui`) as file-level `local function`s so their prototypes are allocated only once.

4. **Offload Heavy Tables to SD Text Files:**  
   Static data (calendars, hymn stanzas, psalter schedules, monster stats, dialog trees) defined as large Lua tables consumes permanent Lua heap. Store them in `.txt` files in your app folder and stream them on-demand using `punri.find_section()`.

5. **Pace Garbage Collection:**  
   Call `collectgarbage("collect")` prior to starting heavy operations and immediately after freeing large tables. PUNRI configures an aggressive incremental garbage collector (`LUA_GCINC`), but explicit collection before page transitions ensures peak heap headroom.

6. **Avoid Allocations in `on_draw()`:**  
   Do not allocate tables or format heavy strings inside `on_draw()` or `on_update()`. Mutate existing tables in place.

7. **E-Paper Refresh Rate:**  
   E-ink screens have physical refresh latency (~200ms–400ms). Only call `punri.request_update()` when visual state actually changes—never call it on every millisecond tick.

8. **Debounce File Writes:**  
   Flash memory has wear limits. Call `punri.save()` when a game finishes or when exiting in `on_exit()`, rather than after every individual tap or score increment.

9. **Version Compatibility & Defensive Programming:**  
   As new firmware updates introduce newer Lua APIs (such as `punri.prevent_sleep`, `punri.set_orientation`, or `punri.full_refresh`), apps in the wild might be loaded on devices running older firmware.
   - **How Older Firmware Behaves:**  
     In Lua, accessing an unassigned table key (e.g. `punri.prevent_sleep`) safely evaluates to `nil` without raising an error. However, directly invoking `nil` as a function (`punri.prevent_sleep(true)`) throws a fatal Lua runtime exception (`attempt to call a nil value`), halting the app and displaying the e-ink "Application Error" crash screen.
   - **Best Practice — Feature Detection:**  
     Always guard newly added APIs with idiomatic Lua feature checks:
     ```lua
     if punri and punri.prevent_sleep then
         punri.prevent_sleep(true)
     end
     ```
   - **Declaring Minimum API Level in Manifest:**  
     If your application fundamentally depends on a newer capability to function (e.g. dynamic screen rotation), declare `"min_api": 2` in your `manifest.json`. PUNRI validates `min_api` before launching the script; if the device firmware is older, it gracefully displays an informative "Firmware update required" screen instead of executing and crashing.
   - **Querying API Version at Runtime:**  
     You can programmatically inspect the environment at runtime:
     ```lua
     local api_lvl = punri.api_version or 1
     if punri.has_feature and punri.has_feature("prevent_sleep") then
         punri.prevent_sleep(true)
     end
     ```

---

## Complete "Hello World" Example

Here is a complete, working counter application:

### `manifest.json`
```json
{
  "id": "counter",
  "name": "Clicker Counter",
  "version": "1.0.0",
  "author": "Mumfee",
  "description": "Simple demonstration counter app for PUNRI.",
  "entry": "main.lua"
}
```

### `main.lua`
```lua
local count = 0
local w, h = 480, 800

function on_init()
    w, h = punri.get_bounds()
    count = tonumber(punri.load("count", "0")) or 0
end

function on_draw()
    punri.clear()
    punri.header("Counter", string.format("Value: %d", count))

    -- Draw centered card box
    local cardW, cardH = 260, 160
    local cardX = math.floor((w - cardW) / 2)
    local cardY = 280
    punri.rounded_rect(cardX, cardY, cardW, cardH, 8, false, 2)

    -- Number readout
    punri.centered_text(cardY + 50, tostring(count), "ui12", "bold", true)
    punri.centered_text(cardY + 100, "Press Select to Count", "small", "regular", true)

    -- Bottom action buttons
    punri.button_hints("Back", "+ 1", "Reset", "")
end

function on_button(btn, pressed)
    if not pressed then return end

    if btn == "back" then
        punri.save("count", tostring(count))
        punri.exit()
    elseif btn == "confirm" then
        count = count + 1
        punri.request_update()
    elseif btn == "left" then
        count = 0
        punri.request_update()
    end
end

function on_exit()
    punri.save("count", tostring(count))
end
```

---

## Testing & Installing Apps

### Method 1: Web Viewer (Drag-and-Drop)
1. On your device, open **Web Transfer** (or enable Wi-Fi).
2. On your PC, navigate to `http://<device-ip>/applications`.
3. Drag and drop your application folder or `.zip` package directly onto the browser window.
4. Your application will appear immediately in the installed applications list!

### Method 2: Direct SD Card Copy / USB Drive Mode
1. Connect your device via USB Drive mode or insert the SD card into your PC.
2. Copy your application folder into `/.crosssmudge/applications/<app_id>/`.
3. Eject the drive. Open **Applications** on your device to launch!

### Method 3: In the Native Simulator
1. Place your application folder inside `apps/<app_id>/` in the repository (and mirror it to `fs_/.crosssmudge/applications/<app_id>/`).
2. Build and launch the simulator:
   ```bash
   pio run -e x4-classic-simulator
   .pio/build/x4-classic-simulator/program
   ```
3. Use `sticky-simulator` or `x4-pro-simulator` for touch/capability-specific behavior. For an optional allocation-failure check, inject a smaller Lua heap:
   ```bash
   PUNRI_SIMULATOR_LUA_HEAP_LIMIT_BYTES=76800 .pio/build/x4-classic-simulator/program
   ```
   This is deterministic fault injection, not the RAM model of a supported board. Normal acceptance uses the matching S3 simulator profile and physical hardware.
4. Open **Applications** from the simulator home menu to test keyboard inputs, button mappings, touch gestures, and rendering instantly.

---

## Submitting to the App Store

PUNRI features an on-device **App Store** accessible directly over Wi-Fi. New settings and **Reset App Store to official** use `abdallah-ali-abdallah/punri-lua-apps`, branch `main`, catalog `catalog.json` (`https://raw.githubusercontent.com/abdallah-ali-abdallah/punri-lua-apps/main/catalog.json`). The installer resolves the branch to an immutable commit before downloading. Saved settings matching the previous official firmware source migrate to this public repository; custom sources and the enabled/disabled choice remain unchanged. Installed applications and their data are not moved or deleted.

The following describes a separately authorized package publication workflow for the repository configured on the device. A local firmware rename does not authorize catalog edits, version bumps, commits or publication:

### Step 1: Prepare Your App Directory
Ensure your application is located in `apps/<app_id>/` with all required files:
- `manifest.json` (Valid JSON with `id`, `name`, `version`, `author`, `description`, `entry`)
- `main.lua` (Clean, working code)
- `icon.raw` (Optional but highly recommended 32x32 1-bit icon, exactly 128 bytes)
- Any supplementary modules or asset files

### Step 2: Validate Against Hardware Constraints
Before submitting, test the app in the supported simulator profile and on the target device. An optional failure-path run is:
```bash
PUNRI_SIMULATOR_LUA_HEAP_LIMIT_BYTES=76800 .pio/build/x4-classic-simulator/program
```
An expected injected out-of-memory failure is not a normal-device acceptance result.
Verify:
1. The app launches without out-of-memory errors.
2. Navigating through all menus, screens, and gameplay loops does not leak memory.
3. Exiting back to the Applications menu works smoothly.

### Step 3: Add to `catalog.json`
Open [`catalog.json`](./catalog.json) (`apps/catalog.json` in the firmware checkout) and add an entry under the `"apps"` array:

```json
{
  "id": "my_app",
  "name": "My Custom App",
  "version": "1.0.0",
  "author": "YourGitHubHandle",
  "description": "Short, catchy summary of what your application does.",
  "entry": "main.lua",
  "min_api": 1,
  "capabilities": ["buttons", "storage"],
  "files": [
    "manifest.json",
    "main.lua",
    "icon.raw"
  ]
}
```
Make sure all required modules and assets are listed. Then generate the
schema-v2 size and SHA-256 records and verify the checked-in result:

```bash
python3 scripts/generate_app_catalog.py --write
python3 scripts/generate_app_catalog.py --check
```

The generator preserves `files` as an ordered string array for already-released
clients and creates an exactly matching `file_integrity` array. Each integrity
record has this shape:

```json
{
  "path": "main.lua",
  "size": 1234,
  "sha256": "64 lowercase hexadecimal characters"
}
```

Schema v2 also binds the catalog to its configured GitHub source identity,
validates strict semantic versions, `min_api`, capabilities, manifest identity,
and every file before atomically promoting the staged package. Lua sources are
syntax-compiled without running them, and the installer writes `.install.json`
provenance into the same transaction.

Catalogs with omitted schema or schema `1` have no per-file integrity records.
For backwards compatibility, firmware accepts them **only from the built-in
official source** and records the install as `official-v1-unverified`.
Third-party/custom repositories must publish schema v2; SHA-256 protects the
resolved package contents but does not replace the on-device repository trust
warning.

### Step 4: Open a GitHub Pull Request
1. Use the repository selected as the catalog source. The default PUNRI destination is [abdallah-ali-abdallah/punri-lua-apps](https://github.com/abdallah-ali-abdallah/punri-lua-apps). Upstream author credits and installed Lua compatibility paths remain unchanged.
2. Commit your new application folder (`<app_id>/...`) and your edit to the root `catalog.json` in that repository. In the firmware checkout, commit and push changes inside the `apps/` submodule before advancing its pinned commit.
3. Submit a Pull Request with title `feat(apps): add <app_name>`.
4. Follow that repository's review and release process. Availability depends on the source configured on each device; no PUNRI catalog publication occurs from a local change.

---

## Radio APIs

Firmware API level 3 adds the functional `radio`, `ble`, `wifi`, and `net` globals.
See [radio API contracts and tests](docs/radio-api.md) before using them. Hardware
capabilities vary by build; desktop replay is explicitly marked as simulated.

## Bundled Applications

The following applications are included in this local repository. Published catalog packages remain separate release artifacts.
For the new offline apps, see [installation, controls, SD storage and verification](offline-apps.md).
For combined Wi-Fi scanning/channel/RSSI analysis, see [Wi-Fi Analyzer](wifi-tools.md).
For BLE discovery/advertisement/RSSI analysis, see [Bluetooth Analyzer](bluetooth-tools.md).
These local changes do not update the published catalog or application versions:

| App ID | Name | Category | Description |
|---|---|---|---|
| `dashboard` | **Desk Stand** | Productivity | Multi-style ambient desk clock with calendar, year progress, 12h/24h toggle, auto-sleep prevention, and 800×480 landscape stand. |
| `hourglass` | **Hourglass** | Productivity | Expressive countdown timer with dynamic parabolic sand funnel physics, full neck passage, bottom sand accumulation mound, and auto-sleep prevention. |
| `stopwatch` | **Stopwatch** | Productivity | Pixel cartoon stopwatch character with animated mechanical crown plunger, facial expressions, digital LCD window (`MM:SS.cc`), lap split recording, and auto-sleep prevention. |
| `solitaire` | **Solitaire** | Games | Classic 7-column Klondike Solitaire card game optimized for e-paper with draw-1 and draw-3 modes. |
| `wifi_analyzer` | **Wi-Fi Analyzer** | Utilities | Network discovery, channel charts, selected-BSSID RSSI meter, 60-scan graphs, statistics and SD-card CSV exports in one app. |
| `bluetooth_analyzer` | **Bluetooth Analyzer** | Utilities | BLE discovery, advertisement details/overview, selected-address/type RSSI meter, graphs and CSV exports; BLE-enabled firmware required. |
| `signal_meter` | **Signal Meter (legacy)** | Compatibility | Original standalone package retained for existing installs and saved data; its features now also live in Wi-Fi Analyzer. |
| `todo` | **To-do List** | Productivity | Offline tasks with a button/touch keyboard, completion filters and transactional SD saving. |
| `notepad` | **Notepad** | Productivity | Multiline notes with on-device editing, paged reading and SD-card plain-text exports. |
| `tictactoe` | **Tic-tac-toe** | Games | Unbeatable solo opponent or local two-player mode with session scores. |
| `watertracker` | **Water Tracker** | Health | Cute daily hydration companion with animated pixel cup expressions, 14-day history archive, and customizable volume units (`ml`, `cups`, `oz`, `gallons`, `L`). |
| `codex` | **Codex: Ink & Iron** | Games | Medieval illuminated manuscript roguelike deckbuilder with Couplet synergy, relic system, and page progression. |
| `wordle` | **Wordle** | Games | 5-letter word deduction puzzle with on-screen keyboard, guess evaluation, and local statistics. |
| `sudoku` | **Sudoku** | Games | Classic 9×9 Sudoku logic puzzle with on-device puzzle generator and conflict validation. |
| `blockdrop` | **Block Drop** | Games | Classic falling block puzzle with ghost piece guide and e-paper optimized refresh scheduling. |
| `2048` | **2048** | Games | Classic 4×4 sliding tile number puzzle with high scores and smooth e-paper rendering. |
| `dice` | **Dice Roller** | Utilities | Multi-polyhedral tabletop dice simulator (d4, d6, d8, d10, d12, d20, d100) with coin flipper and roll history. |
| `lifecounter` | **Life Counter** | Utilities | Magic: The Gathering & card game life tracker supporting multiplayer and commander damage tracking. |

