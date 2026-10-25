# Changelog

## Screen Ruler 0.1.0 — 2026-10-25 (local, unpublished)

### Added

- Offline screen ruler with independent X/Y calibration, mm/cm/inch controls,
  orientation modes, and retryable saves tied to the device and screen size.

### Fixed

- Place horizontal numbers above the scale and vertical numbers to its left,
  using bold measured labels, a shared baseline, compact margins and one zero
  at the corner to keep measurements readable without overlapping numbers.

## Unreleased

### Added

- Register Daily Track, QR Cards Share, Unit Convert, Screen Ruler, World Clock,
  and Bluetooth Page Turner in the local catalog with their runtime modules,
  assets and current API requirements. QR Cards Share includes its license notice.

### Fixed

- Include all Stopwatch modules and refresh package sizes and SHA-256 records
  for every catalog entry. Existing application versions are preserved.

### Removed

- Remove Life Counter from the source collection and local catalog. Existing
  device installations and saved data are unaffected.

## Stopwatch 1.0.0 — 2026-10-25 (local, unpublished)

### Changed

- Rework Stopwatch around clear Start/Stop/Lap/Reset controls, bounded paged
  laps, a reset confirmation, retryable saves and running-only auto-sleep
  prevention. Existing `stopwatch.dat` snapshots remain readable.

### Fixed

- Keep measured labels inside their controls in portrait and landscape; prevent
  the page indicator from overlapping Prev/Next, and make touch Reset now
  perform the selected reset exactly once.

## Bluetooth Page Turner 0.1.0 — 2026-10-25 (local, unpublished)

### Added

- Local-only X4 Pro Bluetooth HID page-turn remote with encrypted bonded arrow-key reports, pairing/connection feedback, a current-host Forget pairing action, and touch/button controls.

### Verification limits

- Desktop replay is explicitly simulated. Physical pairing, reconnect, reader mappings, sleep/wake and Bluetooth range require X4 Pro hardware acceptance. The app is listed in the local catalog and requires firmware API 4; remote publication is a separate step.

## QR Cards Share 0.1.0 — 2026-10-25 (local, unpublished)

### Added

- Offline QR cards for links/text, vCard contacts, Wi-Fi credentials, and large-print emergency/return messages.
- Version 1–10/M byte-mode QR encoding with a four-module quiet zone, structured editable storage, touch targets, and X4 Classic button controls.

### Fixed

- Payloads that exceed the 213-byte version-10/M limit are rejected rather than truncated; Wi-Fi and vCard delimiters are escaped before capacity checking.
- Failed saves leave the previous SD data intact and keep the draft available to retry; corrupt saved data is not overwritten.

## Unit Convert 1.0.0 — 2026-10-25

### Added

- Local-only unit conversion for length, mass, temperature, US customary volume, speed and binary/decimal data units.
- Touch and X4 Classic button controls, an editable numeric keypad, unit pickers, Swap, and transactional restoration of unit choices.

### Fixed

- Rejects below-absolute-zero temperatures, negative data values, malformed or underflowing input, and unsafe 32-bit Lua conversion ranges instead of presenting a fabricated result.
- Failed settings writes remain visible and retryable while the app is open.
- Measured font alignment keeps labels, results and keypad text inside their controls in portrait and landscape layouts.
- Touch devices expose visible Exit and picker Back controls; X4 Classic continues to use its physical footer.

## World Clock 0.1.0 — 2026-10-25

### Added

- Local-only offline World Clock preview with a marker map, 16 cities, Home comparison, favorites, city details, and X4 Classic button controls.
- Bounded IANA tzdata 2026d transitions for 2024–2040, including independent DST vectors and explicit trusted-clock handling.

### Fixed

- Failed preference writes remain retryable without replacing the prior saved settings; corrupt saved state remains untouched.
- Use font-measured, UTF-8-safe control labels and dynamic two-line row heights so selected cities, offset values, retry actions, and long storage-recovery actions remain visible in portrait and landscape.

## To-do List 1.1.0 — 2026-10-25

### Added

- Quick actions to mark all tasks complete or in progress, or clear the list after confirmation.
- Completion percentage and checked/unchecked counts across all tasks, including filtered views.
- Preserve the concurrently published firmware-keyboard integration, with the existing text-entry fallback on older firmware.

### Fixed

- Failed bulk saves keep the previous task data and allow retrying.

## Wi-Fi Analyzer 1.1.0 — 2026-10-25

### Changed

- Combined network discovery, channel charts, selected-BSSID RSSI monitoring, a 60-scan history graph and CSV exports in one foreground app.
- Saved targets reopen paused; leaving monitoring releases the radio.

### Fixed

- The catalog now includes all required radio modules and current package integrity records.

## Bluetooth Analyzer 1.0.0 — 2026-10-25

### Added

- Passive BLE discovery, advertisement details, address/type-specific RSSI monitoring, a 60-scan history graph and CSV exports.
- Capability checks show BLE unavailable on firmware without BLE support. Physical BLE support currently requires X4 Pro firmware with Lua API 3.

## Catalog maintenance — 2026-10-25

### Fixed

- Refreshed integrity records for the already-published organizer and text-editor helpers in Notepad; its version remains unchanged. The concurrent firmware-keyboard source update is preserved rather than overwritten.

### Verification limits

- Desktop radio replay is simulated, not live RF reception or hardware validation. RSSI is not a distance measurement, and channel counts do not measure interference or airtime.
- Physical radio coexistence, SD failures, battery use and internal-heap/PSRAM/stack headroom still require the hardware acceptance steps in the Wi-Fi and Bluetooth guides.
