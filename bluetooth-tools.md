# Bluetooth Analyzer

A separate foreground **Bluetooth LE** app for nearby-device discovery,
advertisement analysis, selected-device RSSI measurement, graphs and CSV export.
It requires **Lua API 3** and `radio.capabilities().ble == true`. BLE is currently
enabled on **X4 Pro** firmware (`x4-pro`/`x4-pro-debug`), not Sticky or X4 Classic.
Those builds show `BLE unavailable`; the app never silently scans Wi-Fi instead.
Bluetooth Classic, UWB, connections, writes and background tracking are not used.

For the combined Wi-Fi tool, see [Wi-Fi Analyzer](wifi-tools.md). Version
**1.0.0** is included in the official catalog. Future versions/catalog
publication still require a separate explicit release instruction.

## Installation and controls

Copy the complete folder to:

```text
/.punri/applications/bluetooth_analyzer/
```

Required files are `manifest.json`, `main.lua`, `radio_app.lua`, `radio_scan.lua`,
`radio_ui.lua` and `icon.raw`; `icon.png` is its editable upright source. Keep the
three shared radio modules identical to the Wi-Fi Analyzer copies. Each app is
self-contained because the Lua sandbox cannot import another app's code.

1. **Scan** performs a passive five-second BLE scan (100 ms interval, 50 ms
   window). Names available only in scan responses can be absent in passive mode.
2. The list shows name/address, RSSI and address type, strongest first. Select
   a result to begin repeated scans of that **address + address type** pair.
3. **Adverts** shows connectable, named and public/public-identity counts as
   proportions of the received address/type pairs. This is a snapshot, not an
   exhaustive inventory or an advertising-rate measurement.
4. The meter shows RSSI, a relative signal bar, a 60-scan graph and valid-sample
   minimum/average/maximum. **Info** shows last-observed connectability, raw
   advertisement type, received observation count and parsed AD fields. Use page
   buttons or vertical swipes for more fields; **Graph** returns to the meter.
5. **Pause/Start**, **Back**, and the remembered **Resume: <name>** row behave
   like Wi-Fi Analyzer. Returning from the meter to the list stops monitoring.
   Returning from Info to Graph keeps the same foreground measurement session.
6. **Export** in Devices/Adverts saves `last_scan.csv`; in Graph/Info it saves
   `signal.csv`. Relaunch opens a remembered target paused, never auto-scanning.

Touch and physical buttons both work. All navigation has visible toolbar
controls; firmware edge-Back gestures remain firmware-owned. X4 Classic simulator
button tests exercise UI portability, not Classic hardware BLE support.

## If Scan does nothing

Desktop radio replay is enabled by default with `RADIO_SIMULATION` unset. From
the firmware repo use `pio run -e x4-pro-simulator -t run_simulator`.
Explicit `1` enables it too; `0`, empty and invalid values disable it. Clear any
inherited disable value and restart; older simulator binaries need rebuilding.
This produces **SIMULATED** peers, not live Bluetooth reception from the Mac. See the
[Wi-Fi troubleshooting checklist](wifi-tools.md#if-scan-does-nothing) for saved
paused targets, complete-folder installation and radio ownership errors.

For live scanning, use BLE-enabled **X4 Pro** firmware with API 3. Sticky and
X4 Classic hardware are deliberately unavailable, even though their simulator
may replay BLE. Scan-start and completion errors stay visible in Graph and Info;
`busy` must be resolved by releasing the other radio owner, not by forcing takeover.

## Honest limits

- **No RF channel chart:** the current BLE API does not report which BLE
  channel received an advertisement. Adverts is an advertisement overview,
  not a fake channel/interference/spectrum measurement.
- Address type 0 = public, 1 = random, 2 = public identity, 3 = random identity.
  Rotating private addresses can make one physical accessory appear multiple
  times or make a selected target disappear. No identity-resolution tracking is
  implemented. Counts are address/type pairs, not guaranteed distinct devices.
- Repeated advertisements update the same row; the last received RSSI in each
  scan becomes its measurement. Received observation counts exclude native queue
  drops and are not a calibrated advertising rate.
- AD fields show type labels and up to 16 bytes of hexadecimal data per field;
  at most 16 fields are displayed. Manufacturer fields expose a little-endian
  company ID, **not** a guaranteed product/vendor identity. Malformed/truncated
  payloads are explicitly labelled and not decoded as conclusive evidence.
- There is no AirTag/owner/following detection. A company identifier alone is
  not proof of a particular device or a tracker.
- Scans wait three seconds after completion; the graph is indexed by completed
  scans, not uniform time. RSSI is not calibrated distance, speed or connection
  quality. The graph clips Y to -100..-20 dBm; CSV/numbers preserve actual values.
- Missing/error samples are gaps, excluded from statistics. `not_seen` is not
  proof that the device is absent; `unknown` marks known observation loss;
  `error:<code>` pauses for a retry. See the [Wi-Fi signal statuses](wifi-tools.md#signal-interpretation-and-timing).

## SD and bounded resource use

```text
/.punri/saved_data/bluetooth_analyzer/last_scan.csv
/.punri/saved_data/bluetooth_analyzer/target.dat
/.punri/saved_data/bluetooth_analyzer/signal.csv
```

Target format is `PUNRI_BLE_TARGET_1`, address, type 0–3, then sanitized name on
separate lines, bounded to 128 bytes. CSV signal rows include the target's address
**type even when RSSI is missing**, so random/public targets remain distinguishable.
Snapshot CSVs include name/address/type, RSSI, connectability, raw advert type,
received observations and truncation flag. Both CSVs include simulation/loss
metadata. Timestamps are uptime milliseconds, not UTC. Raw advertisement payloads
are not automatically persisted.

Only selection/explicit retry writes preferences. History stays in memory unless
explicitly exported. Transactional file replacement preserves old exports on
write failure; the UI shows a retry message. Names are sanitized for UTF-8/display,
CSV quotes escaped and spreadsheet formula prefixes neutralized.

Allocate/reuse 32 observation records and 60 history samples once. Retained BLE
payloads are capped at 512 bytes per observation (16 KiB maximum payload content);
old payload references are dropped before the next scan. Detail parsing happens
only at selection/completed measurements, not during drawing. Cached detail text
is bounded to 16 fields plus metadata; temporary parser output is bounded by the
512-byte API payload limit. Export strings are built only for explicit SD actions.
No new framebuffer, native activity or application task is added.

Polling consumes at most eight events per update and waits for the reserved
terminal event before reusing requests. Surveys release the radio after a scan;
monitoring reuses its foreground session until pause/navigation/exit/error/sleep.
Resident sessions inhibit auto-sleep. SDK BLE stacks/queues additionally allocate
native memory outside the Lua budget; abundant PSRAM is not proof of native heap
or largest-free-block headroom. A `busy` owner is never taken over.

## Verification

Use the firmware native package/tests and simulator command in
[Wi-Fi verification](wifi-tools.md#verification). Desktop scans default to replay
with `RADIO_SIMULATION` unset and visibly display **SIMULATED**. Set
`RADIO_SIMULATION=0` for unavailable-radio tests. Replay is not real RF or
controller/privacy validation. Native app tests use the production `ble.parse`
binding and cover address/type identity, malformed/truncated data, unsupported
builds, bounded observations/history, missing samples, scheduling, cancellation,
CSV/write failures, paused restoration, touch/landscape and button-only controls.

### Hardware acceptance (X4 Pro)

1. Use a known BLE beacon/peripheral and compare its address/type, name, RSSI
   and advertised company/service bytes with a phone BLE scanner. Test unnamed
   and non-connectable beacons. Names may be missing in passive mode.
2. Select the beacon, move/change antenna orientation, and inspect RSSI/stats/
   graph. Power off the beacon and verify gaps rather than artificial zeroes.
   Do not assume a rotating private address is a stable physical identity.
3. Compare Adverts counts and paged Info against the observations; verify no
   RF channel chart or conclusive device classification is implied.
4. Pause during a scan; resume; return to the list; exit and open a book. Verify
   scanning stops, normal sleep returns and native Wi-Fi/BLE flows still work.
   Test physical sleep/wake and visible Back controls with Back swipe disabled.
   Check Info pages with normal/reversed side-button layouts: one action per release.
5. Export and inspect both CSVs on SD; relaunch the target paused. On a backed-up
   full/write-protected test card, verify retries and preservation of old data.
6. Check serial errors, task stack watermarks, internal heap/largest block and
   PSRAM/largest block during scans and after teardown. No reader-cache reset.
7. On Sticky/X4 Classic builds, verify `BLE unavailable` and no radio requests.

Physical RF, controller coexistence/privacy, SD durability, battery consumption
and hardware-native memory headroom still require device testing.
