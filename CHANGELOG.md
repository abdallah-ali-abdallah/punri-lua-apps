# Changelog

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
