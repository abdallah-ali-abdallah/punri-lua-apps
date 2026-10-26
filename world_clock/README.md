# World Clock (local preview)

World Clock is an offline, minute-resolution reference app for answering
“what time is it in another city?”. It is deliberately not a desk clock,
alarm, weather app, or network client. This local package preview is listed in
`catalog.json`; publishing the updated catalog is a separate step.

## Install locally

Copy the runtime files below to
`/.punri/applications/world_clock/` on the SD card. Earlier installations
migrate automatically. Do not copy `tools/` or this
README to the device:

```text
manifest.json  main.lua  time_math.lua  zones.lua  cities.lua  map.lua
ui.lua  input.lua  zones.txt  world.raw  icon.raw
```

Launch **World Clock**, choose **Home city**, and ensure the device clock is
correct first. Home city is only a comparison/favorites preference. It never
changes, infers, or reverses the device timezone or DST setting.

## Controls

Touch devices use one tap: tap a map marker, city row, or labelled button.
Tapping an open map area or one of the four visible time-zone region cards
opens that region's common-city chooser. Nearby markers (New York/Toronto and
Delhi/Kathmandu) deliberately open a chooser instead of guessing. X4 Classic
works entirely with buttons:

- Map: Confirm opens details; Left/Right change selected city; Up opens
  Favorites; Down opens Cities; Back exits.
- Lists: Confirm opens details; Left/Up and Right/Down move selection;
  Page Forward moves through city pages.
- Details: Confirm adds/removes a favorite. Favorites → Manage lets Up/Down
  select a favorite; Left opens Manage and Right opens Cities. In Manage,
  Up/Down reorder, Confirm removes the selected favorite, and Right switches
  the persisted 12/24-hour display format.

The app intentionally defines `on_tap` only: current firmware also emits
`on_touch(x, y, "tap")` for the same physical contact, and handling both would
perform every action twice.

## Trusted time source

PUNRI's RTC is stored as UTC after NTP synchronization. `punri.get_date()`
keeps its legacy local presentation fields and reports the actual applied
`offset_minutes`; World Clock recovers UTC by subtracting that offset. It uses
this only when the additive `clock_validity` feature is present and
`get_date().valid` is true. The app never uses `punri.time()` as UTC.

If the RTC is invalid or an older firmware cannot prove validity, the app says
**Set device clock** or **Update PUNRI for verified clock status**, rather than
showing its fallback date as real time. A valid `source` is `rtc` or `system`;
the latter is a usable system-clock fallback but does not promise that a network
sync occurred during this app session.

UTC makes the current instant unambiguous. The app does not convert user-entered
local civil times, so nonexistent/repeated wall times at DST changes are not an
input ambiguity in v1. The displayed `DST`/`Standard` state and Home difference
are the current transition-table result, not permanent zone properties.

## Timezone data and limits

`zones.txt` is generated from **IANA tzdata 2026d** (released 2026-09-11) for
UTC civil dates 2024-01-01 through 2040-12-31. Source archive:
`https://data.iana.org/time-zones/releases/tzdata2026d.tar.gz`, SHA-256
`0cb2aa8e333c3dc049badc42a0c61f21987b8cd44e107fa900bad764aacc7767`.
IANA tz code/data are public domain; the archive `LICENSE` is the authoritative
notice. `tools/generate_tzdata.py` compiles an official release with `zic`,
then writes bounded transition-minute records and independent fixed test
vectors. For example:

```bash
zic -d /tmp/zoneinfo africa asia australasia europe northamerica southamerica
python3 tools/generate_tzdata.py --tzdir /tmp/zoneinfo --version 2026d \
  --vectors ../../test/lua_apps/world_clock_vectors.lua
```

The application stores all instants as minutes since 2000-01-01, so its Lua
calculations stay within signed 32-bit values beyond 2038. It supports minute
offsets, including +05:30, +05:45, and -03:30. It refuses to claim a result
outside the stated data range. `zones.txt` is 5.3 KiB on SD; only recently
visible zones (at most eight) are parsed, and the 400×200 1-bit map is one
9.8 KiB Lua string loaded once. This is a bounded 4.7 KiB increase over the
previous map, used to keep city pins legible and geographically aligned.
`world.raw` is generated from the editable, original CC0
`tools/world-map.json` by `tools/generate_assets.py`; it is drawn at its
intrinsic dimensions because `draw_sprite` has no general scaler.

## Storage and recovery

Settings are a versioned `world_clock_state.txt` file under the app's private
saved-data directory. Replacement writes are transactional through PUNRI. A
failed favorite, order, Home, or 12/24-hour change keeps the committed state,
leaves the app open, and shows **Retry**. A corrupt file or a removed city is
not silently replaced: the app runs with temporary settings but refuses to
overwrite that file until it is repaired externally.

## Hardware acceptance

The local test suite exercises pinned DST vectors, city/map selection, storage
failure/retry, corrupt state, missing map, portrait/landscape bounds, minute
redraw requests, and button-only flow. On each physical Sticky, X4 Pro, and X4
Classic, set the RTC and Home city, compare Cairo/London/New York/Delhi/
Kathmandu/Sydney against an independent reference at two times (including a
DST difference if possible), then test reboot, one minute rollover, sleep and
resume. No physical-device result is implied by simulator screenshots.
