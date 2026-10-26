# Changelog

## Native quote fonts — 2026-10-26

### Added

- Add a separate quote-font catalog with Amiri, Noto Serif and Frank Ruhl Libre
  Regular at native 20/24-point sizes, shared across all 28 quotation languages.
  Include pinned sources, licenses, generation tooling and exact download hashes.

## Presenter Remote 0.2.0 — 2026-10-26

### Changed

- Replace Bluetooth Page Turner with Presenter Remote (`presenter_remote`) in
  the App Store, removing the old package and catalog entry.
- Redesign the app as a monochrome presentation clicker with prominent Next/Back
  circles, smaller Up/Down keys, Enter/Space and a responsive landscape layout.
- Move Forget pairing to Settings, keep pairing and connection state visible,
  and prevent Settings navigation from sending keys to the connected host.


## Bluetooth Page Turner 0.1.2 — 2026-10-26

### Added

- Add large Enter and Space buttons below the arrows in both modes and
  orientations, with standard HID press/release reports on compatible firmware.
- Keep arrow controls usable on older firmware and explain when Enter/Space
  need a firmware update. Refresh the App Store package integrity records.

## Firmware 1.0.1 — 2026-10-26

### Added

- Add clean one-command firmware publication with validated replacement,
  main-tag/source-hash download names and commit-pinned OTA URLs.

- Publish Sticky, X4 Pro and X4 Classic firmware under `firmware/v1.0.1/`,
  with a firmware catalog, SHA-256 checksums, source provenance and update
  instructions. PUNRI online updates now use `firmware/catalog.json`.
- Add a real HTTPS simulator acceptance path that downloads and verifies the
  published image before writing only simulated flash.

## World Clock 0.1.2 — 2026-10-26

### Changed

- Expand the World Clock map to use nearly the full portrait width and place
  its four regional city selectors in one large, touch-friendly column.

## Downloadable fonts 1.0.1 — 2026-10-26 (local, unpublished)

### Added

- Add the 34-family, 146-package open-source Midad-compatible CrossPoint font
  collection, with Noto Sans Arabic retained as an additional Arabic family.
  Every package is size- and SHA-256-indexed with upstream release/source
  provenance.

### Fixed

- Flatten the published CPFONT assets beneath `fonts/files/`. The reader
  downloads `baseUrl + filename`, so the previous per-family folders produced
  a 404 reported incorrectly as an interrupted network download.

## Screen Ruler 0.2.0 — 2026-10-26

### Added

- Tap the measurement area to move horizontal and vertical guides with X/Y
  distance readings in the selected unit, including in Clean mode.
- Add a Grid toggle with calibrated metric or quarter-inch spacing, plus
  physical-button menu controls for Grid and Clear measurement.

### Fixed

- Draw true whole-inch marks and half/quarter/eighth/sixteenth-inch divisions,
  rather than relabelling metric ticks as inches.
- Keep the physical zero corner fixed when switching units, and keep every
  menu action visible in portrait and landscape. Measuring and toggling the
  grid leave saved calibration untouched and require no periodic redraws.

## Quote sleep data — 2026-10-26

### Added

- Add 20 sourced quotations in each of the firmware's 28 languages, plus a
  size/SHA-256 manifest for optional firmware sleep-screen downloads. These
  data files are independent of the Lua application catalog and versions.

## Screen Ruler 0.1.2 — 2026-10-26

### Added

- Automatically select the manufacturer's 219-PPI physical scale on X4 Pro
  and X4 Classic, so the ruler opens ready without a calibration wizard.

### Fixed

- Preserve matching manual calibration and saved preferences; reject scales
  copied from other devices. Reset restores the automatic X4 profile, and
  unsupported devices retain the manual calibration workflow.
- Return to the ruler or menu after a successful save retry instead of leaving
  the SD-save error screen visible after the data was already saved.

## QR Cards Share — 2026-10-26 (unreleased fix)

### Fixed

- Add visible Add card / Save changes, Cancel, Previous and Next controls to
  card forms, with readable highlighted fields and a retryable save error.
- Make card creation, saved-card navigation, editing, Back and Exit reachable
  through both touch controls and physical buttons. Wi-Fi options toggle
  directly and sharing offers a visible Delete Wi-Fi action.
- Keep library rows and long action lists clear of navigation controls in
  portrait and landscape.

## App icons 0.1.1 — 2026-10-26

### Fixed

- Add missing monochrome icons for Screen Ruler, Bluetooth Page Turner and
  Radio Scanner, and include them in their App Store packages. Patch versions
  let existing installations receive the icons through Update.
- Audit all 26 Lua applications: each now provides a nonblank 32×32 icon,
  and all 26 catalog packages include the icon with its size and SHA-256.

## Calculations 0.1.0 — 2026-10-26

### Added

- Offline scientific calculator with natural fraction, root, power and equation
  fields, exact rational arithmetic, 12-digit software decimal calculations,
  scientific functions, variables, history, undo/redo and saved sessions.
- Linked Functions, Graph and Table workspaces with portrait/landscape layouts,
  approximate graph previews, tracing, zoom/pan and bracketed equation solving.
- Statistics, small-matrix operations, complex polar conversion, unsigned base
  conversion and exact unit ratios, with retryable saves and protected future schemas.
- Register Calculations in the App Store catalog with all runtime modules and
  its icon, including verified package sizes and SHA-256 hashes.

### Fixed

- Render each measured natural-input value directly so narrow numerator,
  denominator and exponent fields show their digits instead of ellipses.

## Screen Ruler 0.1.0 — 2026-10-25 (local, unpublished)

### Added

- Offline screen ruler with independent X/Y calibration, mm/cm/inch controls,
  orientation modes, and retryable saves tied to the device and screen size.

### Fixed

- Place horizontal numbers above the scale and vertical numbers to its left,
  using bold measured labels, a shared baseline, compact margins and one zero
  at the corner to keep measurements readable without overlapping numbers.

## Unreleased

### Downloadable font catalog (local, unpublished)

- Add version-2 manifest and CPFONT v4 packages for the open-source Bitter and
  Noto Sans Arabic families. Every package is SHA-256 indexed and retains its
  SIL Open Font License 1.1 attribution and upstream source URL.

### Changed

- Document canonical PUNRI installation and private-save paths. Firmware moves
  existing applications and saved data automatically; application IDs, versions
  and Lua compatibility aliases are preserved.

### Added

- Add large, bold Enter and Space controls below the Bluetooth Page Turner
  arrows in both modes and orientations. Older firmware keeps arrow controls
  usable and explains when the new keys need a firmware update.

- Register Daily Track, QR Cards Share, Unit Convert, Screen Ruler, World Clock,
  and Bluetooth Page Turner in the local catalog with their runtime modules,
  assets and current API requirements. QR Cards Share includes its license notice.

### Fixed

- Daily Track now opens directly from a valid device date, displays each
  month as a weekday-labelled calendar, provides larger month/navigation
  controls, and keeps counter metadata clear of its action button.
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
- Category controls use two larger rows for easier touch and button navigation.

## World Clock 0.1.1 — 2026-10-26

### Changed

- Replace the hand-drawn land silhouette with a black-and-white raster from real Natural Earth 1:110m public-domain land data; city dots remain visible over land and ocean.

## World Clock 0.1.0 — 2026-10-25

### Added

- Local-only offline World Clock preview with a marker map, 16 cities, Home comparison, favorites, city details, and X4 Classic button controls.
- Bounded IANA tzdata 2026d transitions for 2024–2040, including independent DST vectors and explicit trusted-clock handling.

### Fixed

- Failed preference writes remain retryable without replacing the prior saved settings; corrupt saved state remains untouched.
- Use font-measured, UTF-8-safe control labels and dynamic two-line row heights so selected cities, offset values, retry actions, and long storage-recovery actions remain visible in portrait and landscape.
- Align map markers and touch targets through one shared layout frame, enlarge the map for legible geography, and add visual common-time-zone city selectors.

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
