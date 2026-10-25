# Wi-Fi Analyzer and Signal Meter

Two standalone Lua apps for Sticky, X4 Pro and X4 Classic, registered in the local
`catalog.json` (`apps/catalog.json` in the firmware checkout). Both require **Lua API 3**, use the foreground radio API and
work without connecting to an access point or entering a password. They inspect
2.4 GHz Wi-Fi; they are not packet-capture or spectrum-analysis tools.

Catalog registration is local. These changes do not upload the packages to
GitHub or make them downloadable from an unchanged remote catalog.

## Install

Copy the complete app directories to the SD card:

```text
/.crosssmudge/applications/wifi_analyzer/
/.crosssmudge/applications/signal_meter/
```

Each package contains `manifest.json`, `main.lua`, `wifi_scan.lua`, `wifi_ui.lua`
and `icon.raw`. `icon.png` is the editable upright source and is not needed on
hardware. Keep the two packaged copies of `wifi_scan.lua` and `wifi_ui.lua`
identical; apps cannot import another app's files across the sandbox.

## Wi-Fi Analyzer

1. Open **Applications → Wi-Fi Analyzer → Scan**.
2. Results are ordered by RSSI, strongest first, and deduplicated by BSSID.
   Each row shows SSID, BSSID, RSSI in dBm and channel. Hidden SSIDs have a label.
3. Select a network to see its signal readout and raw SDK authentication code.
4. **Channels** shows the number of observed access points on each channel.
   These counts do **not** measure RF congestion, airtime, interference or speed.
5. **Export** saves/replaces `last_scan.csv` transactionally after a successful
   scan. Back up that file on your computer before replacing a snapshot you need.

The list holds at most 32 access points. The native radio queue can also drop
observations; the app shows `PARTIAL`, dropped, capped and invalid observations.
An empty or partial list must not be interpreted as proof that no other AP exists.

## Signal Meter

1. Open **Signal Meter → Scan**, wait for completion and select an access point.
2. Selection is by **BSSID**, so two access points sharing an SSID do not get
   mixed into the same measurement. The target is saved to SD.
3. The meter starts sequential scans and shows a large RSSI readout, a relative
   signal bar, a graph and minimum/average/maximum over valid retained samples.
4. There is a three-second idle interval **after** each completed scan. A scan
   can itself take up to ten seconds; this is not a 3 Hz or guaranteed 3-second
   sampler. The graph's horizontal axis is completed scans, not uniform time.
5. **Pause** cancels an outstanding scan and releases the radio after consuming
   its terminal event. **Start** resumes; **Choose/Back** stops automatic scans.
6. **Export** saves/replaces `signal.csv` on SD. Only the most recent 60 completed
   scans are retained, including missing/error samples as gaps. There are no
   automatic SD writes for every measurement.

The remembered target reopens **paused** after relaunch. Measurement history is
session-only unless exported. If saving the target fails, the footer stays marked
`TARGET NOT SAVED`; Export retries that write before exporting history.

Missing observations are not fabricated as `0 dBm`:

- `ok`: this BSSID was observed in a complete scan.
- `partial`: it was observed, but the overall scan lost/capped/invalidated observations.
- `not_seen`: it was not observed in a completed scan with no known loss.
- `unknown`: it was not observed, but the scan was incomplete.
- `error:<code>`: the scan failed; the app pauses for an explicit retry.

`not_seen` is **not** an out-of-range or absence guarantee. RSSI varies with walls,
antenna orientation and interference. It does not give an accurate distance.
The bar is an approximate visual scale (-100 dBm = empty, -30 dBm = full), not
throughput or a calibrated quality percentage. The graph clips vertically to
-100..-20 dBm while the numeric readout and CSV retain the measured value.

## Controls

- **Touch:** tap the visible toolbar and result rows; swipe up/down through long
  lists. Exit/Back remain available when firmware Back swipe is disabled.
- **X4 Classic:** initial Confirm activates Scan. Left/Right move through the
  toolbar and results, Confirm activates the selection, and page buttons move
  by a list page. Back returns or exits. The selected item is filled black.
- The firmware's reserved Back-edge swipe remains firmware-owned; there are no
  hidden footer hitboxes. Drawing never polls radio events.

## SD files

```text
/.smudge/saved_data/wifi_analyzer/last_scan.csv
/.smudge/saved_data/signal_meter/target.dat
/.smudge/saved_data/signal_meter/signal.csv
```

Exports use the runtime's transactional overwrite API: write, sync, close and
publish, with recovery after an interrupted replacement. Failed export writes
leave the old file intact and show a retry message. The target preference uses
`PUNRI_SIGNAL_TARGET_1`, then BSSID and SSID on separate lines; it is bounded to
128 bytes. Invalid preferences are ignored with a log message so another target
can be selected. No reader/EPUB cache reset is needed.

CSV signal timestamps are **milliseconds of uptime**, not UTC. Exports mark
`simulated=true` for replay. CSV quotes are escaped, unsafe SSID control/invalid
UTF-8 bytes are replaced for display/export, and potentially formula-like SSIDs
are prefixed with an apostrophe to protect spreadsheet imports. Authentication
codes are the SDK values, not inferred security guarantees.

## Radio ownership and resource bounds

- Wi-Fi Analyzer closes the radio after a single scan completes.
- Signal Meter reuses its session between automatic scans to avoid repeatedly
  allocating native session buffers. Pause, navigation, exit, script errors and
  physical sleep release the session. The resident foreground radio session
  inhibits automatic sleep; leave or pause the meter when finished.
- Native Wi-Fi activities are not taken over. If another activity owns Wi-Fi,
  `busy` is shown; leave that activity and retry.
- There are 32 reusable AP records and 60 reusable sample records, allocated at
  initialization because they are mutable, per-run state. A bounded SSID scratch
  table is reused. No extra framebuffer or application FreeRTOS task is added.
- Polling processes at most eight events per update. A new scan starts only after
  the reserved `complete/error` event is consumed; `scan_complete` alone is not
  sufficient. SDK observations can be dropped without losing that terminal event.
- Lua allocations are bounded by the existing VM. SDK radio stacks and buffers
  additionally consume native memory outside the Lua budget, so plentiful PSRAM
  does not prove internal-RAM or largest-free-block headroom.

### Sampled simulator memory

With the normal 2 MB Lua budget and a minimal measurement callback, X4 Classic
and X4 Pro replay runs reported:

| App | Package bytes | Lua after initialization | Lua during replay UI |
| --- | ---: | ---: | ---: |
| Wi-Fi Analyzer | 18,165 | 68 KB | 69–72 KB |
| Signal Meter | 22,866 | 81 KB | 82–89 KB |

The replay fixture has one AP and three signal samples. These are sampled live
Lua allocations, **not** compiler/search peaks, maximum-capacity data costs,
physical internal-RAM/PSRAM usage or largest-free-block measurements. Native
app tests separately exercise the 32-AP and 60-sample capacity bounds.

## Verification

Run these commands from the **PUNRI firmware checkout**. In a standalone app
checkout, use `python3 scripts/generate_app_catalog.py --check` for its root
catalog and use the firmware checkout for native/simulator tests.

```bash
python3 scripts/generate_app_catalog.py --check
python3 test/lua_apps/test_packages.py
pio run -e host-unit-tests -t unit-tests
pio run -e x4-classic-simulator
pio run -e x4-pro-simulator
```

For manual simulator use, copy the app directories under its `fs_` tree and set
`RADIO_SIMULATION=1` before starting the matching simulator binary. Without that
opt-in, Wi-Fi is unavailable in the simulator. Replay is visibly labelled
**SIMULATED** and produces a fixed virtual AP, not real RSSI or RF reception.

Native tests cover BSSID deduplication, bounded lists/polling/history, incomplete
scans, cancellation, scheduling, malformed SSIDs, CSV safety, save failures,
button-only controls and landscape layouts. Production radio tests also check
ownership, queue overflow, terminal-event ordering and valid replay BSSIDs.
See [radio API](docs/radio-api.md) for the underlying contract.

### Hardware acceptance

On a supported device with Lua API 3:

1. Use a known router; scan and compare its SSID/BSSID/channel to the router's
   configuration. If possible, use two APs with the same SSID and verify the
   meter follows the selected BSSID, not both of them.
2. Move nearer/farther and change orientation. Confirm the RSSI/readout/graph
   respond without expecting a precise distance or a guaranteed monotonic change.
3. Pause while scanning, resume, then leave the app and open a book. Confirm
   automatic scanning stops, normal sleep returns and another Wi-Fi flow works.
4. Disable Back swipe on Sticky/X4 Pro and verify all visible touch controls.
   On X4 Classic, complete the same flow using only physical buttons/page keys.
5. Export, mount the SD card and inspect CSV values. Reboot and confirm the
   remembered target opens paused. Use a full/write-protected test card to verify
   retry messages and preservation of the old export; back up data first.
6. Check serial errors, task stack high-water marks, internal heap/largest block
   and PSRAM/largest block while scanning and after closing the app.

Simulator/native results are not RF, physical SD durability, radio coexistence,
battery-consumption or hardware memory-headroom validation.
