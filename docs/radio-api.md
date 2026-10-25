# Lua radio API

PUNRI (Pocket Utilities, Notes & Reading Interface) provides these modules with
functional names independent of the firmware identity. Its BLE GAP device name is
`PUNRI`. Lua apps select their own Wi-Fi AP SSID and raw advertising payload;
those values are not rewritten by the runtime.

The functional globals `radio`, `ble`, `wifi`, and `net` are available in firmware
Lua API level 3. New apps should declare `"min_api": 3`. Existing drawing and
input APIs remain compatible. These modules do not expose raw SDK pointers.

## Availability and ownership

Call `radio.capabilities()` before requesting an operation. It returns `ble`,
`wifi`, `http`, `simulated`, `bluetooth_classic` (always false), and the radio API's
own `api_version` (1). BLE is enabled for `x4-pro` and `x4-pro-debug`; other hardware
profiles return `unsupported` for BLE until explicitly enabled and validated.

The desktop simulator enables deterministic radio replay by default when
`RADIO_SIMULATION` is unset. Explicit `1` also enables it; `0`, empty and invalid
values disable it for unavailable-radio tests. Set the variable before launching
and restart after changes. `simulated` remains true: replay is not live scanning,
and these defaults do not change hardware radio capabilities.

The first valid request lazily acquires an exclusive native session. An existing
native Wi-Fi activity or initialized BLE host causes `busy`; the API never takes
over that activity's radios. Wi-Fi and BLE can coexist inside the acquired session.
`radio.close()` releases it. App exit, script errors and physical sleep also close
the session. While a session is resident, automatic sleep/CPU throttling is inhibited.
Background monitoring after leaving an app is not implemented.

## Requests and events

Operations return a positive request ID, or `nil, error_code`. Invalid Lua types,
oversized fields, embedded NUL in textual options and out-of-range numbers raise
an ordinary Lua argument error. Binary `data` strings preserve NUL and high bytes.

Only one operation may be pending. Consume its terminal `complete` or `error`
event before starting another. `radio.poll()` returns one event or nil; call it
from `on_update`, never from rendering. Poll a bounded batch each update.

```lua
local request_id, error_code = ble.scan_start {
  timeout_ms = 5000, active = false, interval_ms = 100, window_ms = 50
}
if not request_id then print(error_code) end

function on_update()
  for i = 1, 8 do
    local event = radio.poll()
    if not event then break end
    if event.kind == "advertisement" then
      print(event.address, event.rssi, ble.classify(event.data))
    elseif event.kind == "complete" or event.kind == "error" then
      radio.close()
    end
  end
end
function on_exit() radio.close() end
```

Events contain `kind`, `id`, `error`, `timestamp_ms`, `status`, `rssi`, `channel`,
`address`, `address_type`, `name`, `connectable`, `truncated`, `service`,
`characteristic`, and binary `data`. Advertisement events also include
`advertisement_type` and `advertisement_length`: NimBLE may append scan-response
data after that offset. UUIDs may be normalized by the backend. GATT characteristic
`status` is a property bitmask (read=2, write=8, notify=16).

The queue holds eight observations of at most 512 bytes each. Excess observations
are dropped and counted by `radio.stats().dropped`. Completion has a reserved slot
and is never lost to observation overflow. Payloads exceeding 512 bytes are marked
`truncated`; never classify truncated data as conclusive evidence.

The queue/native session is allocated once on first use and freed on close. SDK
stacks and their discovery caches allocate additional native memory; the Lua heap
limit does not cover those allocations. Inspect internal free heap and largest
allocatable block during hardware acceptance.

`radio.cancel()` requests cancellation; poll until completion before reuse.
`radio.stats()` reports `open`, `resident`, `busy` and `dropped`. `radio.close()` is idempotent
and joins native producers before releasing their buffers. SDK calls already in
progress may delay cancellation until their timeout/disconnection.
If SDK teardown fails, callbacks are detached, the remaining stack is kept alive
and new sessions are refused until restart (`resident` true with `open` false).

## BLE operations

| Function | Options / behavior |
| --- | --- |
| `ble.scan_start` | `timeout_ms` 100..30000, `active` boolean, `interval_ms` 5..10240, `window_ms` 5..interval; duplicates delivered, bounded by queue |
| `ble.connect` | `address` canonical MAC and `address_type` 0..3; connection timeout capped at 5 seconds |
| `ble.discover` | Connected peer's services and characteristics |
| `ble.read` | `service`, `characteristic` UUIDs; emits `value` |
| `ble.write` | UUIDs, binary `data` <=512, `response` boolean |
| `ble.subscribe` | UUIDs; emits subsequent `notification` events |
| `ble.disconnect` | Disconnect the client connection |
| `ble.advertise_start` | Raw legacy advertisement `data` <=31 bytes; continues until stop/close |
| `ble.advertise_stop` | Stop advertising |
| `ble.server_start` | One `service` and `characteristic`, initial binary `data`; exposes read/write/notify and advertises the service |
| `ble.server_notify` | Update server characteristic with binary `data`, notify subscribers |
| `ble.parse(data)` | AD fields as `{type, data}` records; malformed input returns `nil, "invalid_argument"` |
| `ble.classify(data)` | `apple_findmy_candidate`, `unknown`, or `malformed` |

UUIDs accept 4, 8, or canonical 36 hexadecimal characters. Server writes arrive as
`notification` events. One client, one server characteristic and one active
subscription identifier are supported per session. Secure connections use the
stack's normal behavior; application-controlled passkey/bond management and
extended advertising are not exposed in this version.

`apple_findmy_candidate` requires a complete offline-finding manufacturer
structure. It does not establish an AirTag model, owner, persistent identity, or
that an accessory followed someone. Other Apple advertisements and Samsung
company IDs alone are not treated as trackers. Bluetooth Classic and UWB precision
finding are outside the S3 radio's capabilities.

## Wi-Fi and HTTP

| Function | Options / behavior |
| --- | --- |
| `wifi.scan_start` | Asynchronous scan, including hidden networks; emits `network` and `scan_complete` |
| `wifi.connect` | `ssid` <=32 bytes, `password` <=64; transient credentials, no NVS persistence |
| `wifi.disconnect` | Disconnect station |
| `wifi.ap_start` | `ssid`, optional password >=8 bytes, channel 1..11 |
| `wifi.ap_stop` | Stop AP |
| `net.http_request` | `url` <=255 bytes, `method` GET/POST, `data` <=512; connected station required |

HTTP(S) emits `http_response` with HTTP `status`, up to 512 response bytes, and
`truncated` if more arrived. Redirects are not automatically followed. HTTPS uses
the ESP-IDF CA bundle and normal hostname/certificate verification; the system
clock must be valid. HTTP socket timeout is capped at five seconds. No insecure
TLS switch is exposed. TCP/UDP socket APIs, ESP-NOW and packet capture are separate
future extensions, not advertised capabilities of this API version.

## Validation

Native tests compile the production service, parser, bindings and vendored Lua.
They exercise the 75 KB Lua allocation limit, queue overflow/completion ordering,
concurrent producers, cancellation, invalid data and lifecycle cleanup.

```sh
cmake -S test/radio -B /tmp/radio-tests -DRADIO_SANITIZE=ON -DCMAKE_BUILD_TYPE=Debug
cmake --build /tmp/radio-tests --parallel 4
ctest --test-dir /tmp/radio-tests --output-on-failure
```

The local `apps/radio_scanner` folder can be copied to the SD applications directory
to exercise BLE/Wi-Fi scanning and protocol inspection. It is not published to the
App Store catalog. The simulated backend is visibly labelled in its header.

See [firmware emulation](../test/radio_emulation/README.md) for a distinct S3 test
using real firmware code and virtual peers. Neither test layer verifies RF
reception, real-world RSSI, physical coexistence, controller privacy or battery
consumption. Hardware acceptance requires an S3 and known BLE/Wi-Fi peers, followed
by testing app exit, forced errors, sleep/wake and reading on the actual reader.
To verify the identity on an X4 Pro, start a Lua BLE server, connect from a phone,
and read the Device Name characteristic (`0x2A00`) in Generic Access (`0x1800`);
the expected value is `PUNRI`.
