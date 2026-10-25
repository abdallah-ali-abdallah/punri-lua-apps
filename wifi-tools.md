# Wi-Fi Analyzer

One foreground Lua app combines Wi-Fi discovery, channel analysis and signal
monitoring. It runs on Sticky, X4 Pro and X4 Classic with **Lua API 3**. No Wi-Fi
connection, password, packet capture or firmware change is needed.

For the separate BLE companion, see [Bluetooth Analyzer](bluetooth-tools.md).
Version **1.1.0** is included in the official catalog with complete module lists
and integrity records. Local development still does not authorize future
catalog publication or version bumps.

## Install and use

Copy the complete `wifi_analyzer/` folder to:

```text
/.crosssmudge/applications/wifi_analyzer/
```

The new entry loads `radio_app.lua`, `radio_scan.lua` and `radio_ui.lua` once.
The previous `wifi_scan.lua`/`wifi_ui.lua` files are retained but not loaded by
the combined app. `icon.raw` is required for its icon; `icon.png` is editable
source. Apps cannot import another app's files across the sandbox.

1. Open **Applications → Wi-Fi Analyzer → Scan**. Results are strongest-first,
   deduplicated by **BSSID**, and show SSID, BSSID, RSSI in dBm and channel.
2. **Channels** graphs observed AP counts on channels 1–14. Counts are **not**
   RF congestion, airtime, interference, speed or spectrum measurements.
3. Select an AP to start its RSSI meter: large numeric readout, relative signal
   bar, a 60-scan graph and minimum/average/maximum over valid retained samples.
4. **Info** shows last-observed channel/authentication code; **Graph** returns
   to the meter. Both views belong to the same foreground measurement session.
5. **Pause** cancels an outstanding scan, consumes its terminal event, and
   releases the radio. **Start** resumes. **Back** from the meter returns to
   the list and stops monitoring; Back from Info returns to the meter.
6. **Resume: <name>** in the list opens the remembered target **paused**, keeping
   the current session's history. Relaunch also opens the saved target paused.
7. **Export** in the list/Channels saves `last_scan.csv`; Export in Graph/Info
   saves `signal.csv`. Both explicitly replace their previous snapshot on SD.

The list holds at most 32 APs. `PARTIAL` indicates dropped, capped or invalid
observations. A partial/empty list does not establish that other APs are absent.
Authentication codes are raw SDK values, not inferred security guarantees.

## If Scan does nothing

- **Desktop simulator:** radio replay is disabled unless `RADIO_SIMULATION=1` is
  set **before launching**. From the firmware repo, use
  `RADIO_SIMULATION=1 pio run -e x4-pro-simulator -t run_simulator` (or the matching
  Sticky/Classic profile). Replay shows **SIMULATED** and synthetic peers; it
  cannot scan the Mac's Wi-Fi or BLE hardware. Restart an already-running simulator.
- **Saved target:** reopening starts paused. Press **Start**, or **Back → Scan**
  to discover networks. Copy the complete app folder, including all three
  `radio_*.lua` modules; App Store version 1.1.0 includes them.
- **Wi-Fi unavailable:** check firmware Lua API 3 and whether this is the disabled
  simulator. Installing Lua files does not add a radio backend to older firmware.
- **Cannot scan: busy:** exit native network/BLE tools and retry. Another owner
  or a residual radio stack blocks acquisition; the app will not take it over.
- **Scan: failed/timeout** or **out_of_memory:** capture serial logs around the
  scan. Check internal heap/largest block as well as PSRAM; replay cannot validate
  physical RF or reader-memory headroom. Errors remain visible in Graph and Info.

## Signal interpretation and timing

Measurements wait three seconds **after** a scan completes. Wi-Fi scans may
last ten seconds; this is not a guaranteed three-second sampler. Graph X positions
represent completed scans, not uniformly spaced time. Each scan uses the last
received observation for the selected BSSID; equal SSIDs are not combined.

The most recent 60 completed scans are retained. Missing/error observations are
gaps, not fabricated `0 dBm`, and do not enter minimum/average/maximum:

- `ok`: selected BSSID observed in a scan with no known observation loss.
- `partial`: observed, but other observations were dropped/capped/invalid.
- `not_seen`: absent from the completed scan's received observations.
- `unknown`: not observed, with known observation loss.
- `error:<code>`: scan failed; monitoring pauses for an explicit retry.

`not_seen` is not an out-of-range or absence guarantee. RSSI is **not distance**.
The bar is an approximate scale (-100 dBm empty, -30 dBm full), not a calibrated
quality/throughput percentage. Graph Y values clip to -100..-20 dBm; numeric
readings and CSV preserve the actual measured values.

## SD persistence and compatibility

```text
/.smudge/saved_data/wifi_analyzer/last_scan.csv
/.smudge/saved_data/wifi_analyzer/target.dat
/.smudge/saved_data/wifi_analyzer/signal.csv
```

The original Analyzer app ID and `last_scan.csv` path remain unchanged. Target
preferences use the existing `PUNRI_SIGNAL_TARGET_1` format, followed by BSSID and
name on separate lines (128-byte maximum). Invalid preferences are logged and
ignored without rewriting them. Targets are written only on selection or an
explicit failed-write retry; history is session-only unless exported.

**Existing Signal Meter users:** its package, ID and files are retained. The
combined app cannot read another app's private SD directory. To migrate a target,
back up both directories and copy
`/.smudge/saved_data/signal_meter/target.dat` to the Analyzer's `target.dat` while
both apps are closed. This is optional; selecting the AP again works as well.
Old `signal_meter/signal.csv` exports are not moved or deleted. Installing the
combined Analyzer does not automatically uninstall an existing Signal Meter.

Writes use `punri.write_file()`'s transactional replace/sync/close operation.
Failures preserve the previous file and show a retry message. A failed target
write stays marked `TARGET NOT SAVED`; signal Export retries it first. Back up
exports before replacing a snapshot you need. Signal CSV timestamps are scan-
completion milliseconds of uptime, not UTC; replay rows mark `simulated=true`. Names are UTF-8 sanitized,
quotes escaped, and formula-like spreadsheet cells prefixed with an apostrophe.
No EPUB/reader cache reset is needed.

## Controls and resources

- Touch: visible toolbar/result rows; swipe up/down for lists and Info pages.
  Exit/Back do not depend on firmware swipe-to-back being enabled.
- Buttons: Confirm initially scans; Left/Right traverse toolbar/results;
  Confirm activates; page buttons move list/Info pages; Back returns/exits.
  Duplicate direction/page callbacks for one release are handled only once.
- Single surveys close their radio session after completion. Monitoring reuses
  the session between scans; pause/navigation/exit/error/physical sleep release
  it. A resident radio session inhibits automatic sleep, so pause when finished.
- Existing native radio owners are not taken over: `busy` is recoverable.
- Allocate 32 mutable observation records and 60 sample records once at startup;
  reuse them rather than adding records every scan. Poll at most eight events per
  update. `scan_complete` alone is not permission to reuse a pending request.
- The app adds no framebuffer or FreeRTOS task. SDK stacks/queues consume native
  memory outside the Lua budget; inspect internal heap and largest free blocks
  on hardware. Bluetooth's shared-controller copy remains standalone.

### Sampled replay costs

With one virtual peer and three signal samples, instrumented X4 Classic and
X4 Pro simulator runs reported:

| App | Package bytes | Lua at initialization | Sampled Lua during UI |
| --- | ---: | ---: | ---: |
| Combined Wi-Fi Analyzer | 47,213 (includes retained legacy modules) | 107 KB | 108–110 KB |
| Bluetooth Analyzer | 36,122 | 107 KB | 108–111 KB |

These are sampled live Lua allocations with a small logging wrapper, **not**
compiler peaks, 32-peer/512-byte payload peaks, hardware internal-RAM/PSRAM usage,
or largest-free-block measurements. Native tests exercise the bounded capacity
separately; hardware memory acceptance is still required.

## Verification

From the firmware checkout:

```bash
python3 test/lua_apps/test_packages.py
cmake -S test -B /tmp/punri-radio-analyzers-tests
cmake --build /tmp/punri-radio-analyzers-tests --parallel 4 --target \
  LuaRunnerNativeOomTest LuaSandboxTest RadioTest RadioPlatformLifetimeTest
/tmp/punri-radio-analyzers-tests/lua_sandbox/LuaRunnerNativeOomTest
/tmp/punri-radio-analyzers-tests/lua_sandbox/LuaSandboxTest
/tmp/punri-radio-analyzers-tests/radio/RadioTest
/tmp/punri-radio-analyzers-tests/radio/RadioPlatformLifetimeTest
pio run -e x4-pro-simulator
pio run -e x4-classic-simulator
python3 scripts/test_radio_analyzers_simulator.py
```

Package validation builds a temporary integrity-bound catalog without altering
`apps/catalog.json`. Full catalog checks (also included in the complete host-unit-tests
gate) verify the released package metadata and integrity records.
Native tests cover scan/history bounds, BSSID identity, terminal ordering,
cancellation, gaps/statistics, CSV safety, failed writes, saved targets, button
controls and landscape layouts. Simulator replay requires `RADIO_SIMULATION=1`
and displays **SIMULATED**; it is not RF validation.

### Hardware acceptance

1. On a supported device, compare a known router's SSID/BSSID/channel to the
   scan. With two same-SSID APs, verify only the selected BSSID enters history.
2. Change distance/orientation and check RSSI/graph responses without expecting
   precise distance or monotonic changes. Check Channels and Info as well.
3. Pause during a scan, resume, then leave and open a book. Verify scanning stops,
   normal sleep returns, and native Wi-Fi flows can acquire the radio.
4. Test visible controls with Back swipe disabled on touch hardware; repeat
   using only physical buttons/page keys on X4 Classic. Try normal and reversed
   side-button layouts: one release should cause only one menu page action.
5. Export and inspect SD CSVs; relaunch and verify the target opens paused.
   On a backed-up write-protected/full test card, verify retry messages and that
   old exports survive failures. Test optional legacy-target copying separately.
6. Inspect serial errors, task stack watermarks, internal heap/largest block and
   PSRAM/largest block during scans and after closing.

Native/simulator tests do not validate physical RF, SD durability, radio
coexistence, battery consumption or hardware memory headroom.
