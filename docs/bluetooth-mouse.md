# Bluetooth Mouse 0.1.0

Bluetooth Mouse turns an X4 Pro into a foreground Bluetooth LE HID mouse named
**PUNRI Mouse**. Its mobile-style interface has a central square touchpad with a
light dotted grid, large Left click and Right click buttons, Slow/Normal/Fast
pointer speeds, and pairing settings. Portrait and landscape share the same
layout and hit-test geometry.

## Requirements

- **X4 Pro with firmware Lua API 5**, `punri.get_touch()` and
  `radio.capabilities().hid_mouse_peripheral`. API 4 firmware only supports a
  keyboard and cannot run this package. Installing the Lua files does not add
  mouse support to older firmware.
- Sticky and X4 Classic lack this build's Bluetooth mouse capability; the app
  never substitutes generic GATT traffic for real HID reports.
- A host that supports a Bluetooth LE HID mouse. No companion host software or
  Wi-Fi connection is needed. Actual OS compatibility requires physical testing.
- The simulator always labels replay **SIMULATION**. It cannot transmit physical
  Bluetooth or establish real pairing/host pointer acceptance.

## Pair and use

1. Open Applications > Bluetooth Mouse and tap **Pair / Connect**.
2. Select **PUNRI Mouse** in the computer's Bluetooth device settings within
   30 seconds. Wait for **Connected** and the slide-to-move instruction.
3. Slide one finger inside the grid. Motion is relative: lift and start another
   stroke without jumping the host pointer to an absolute screen position.
4. Tap **Left click** or **Right click** for one complete click. Tap the left
   button twice for a host double-click. Touching the pad itself does not click.
   Holding a click button does not drag; drag/scroll gestures are not in v0.1.0.
5. Choose **Slow**, **Normal** or **Fast**. Physical Page Back/Left and
   Page Forward/Right also produce left/right clicks. Confirm pairs/disconnects;
   Back exits (or returns from Settings).
6. **Disconnect** stops the session immediately, including an in-flight move.
   Leaving the app, a Lua error or sleep invokes native radio cleanup and a
   best-effort all-buttons-up report. Bluetooth stays active only in this app.

The app only sends after the host is bonded, encrypted and subscribed. Link
loss clears queued motion and clicks so they cannot replay after reconnection.
Re-advertising after a lost link is limited by the original 30-second pairing
window; after it expires, select Pair again. Auto-sleep is held only during the
active pairing/connected session and restored on close.

**Settings > Forget current host** removes only the bonded host seen during the
current open session. It does not erase unrelated bonds. If switching between
Presenter Remote and Mouse leaves the computer using a cached keyboard report
map or name, remove the previous PUNRI device in the host's Bluetooth settings
and pair again; the applications use different HID report maps.

## Resources and verification

Touch samples return two integers without allocating a sample table. The app
reuses a move request table, limits queued clicks to four, limits unsent movement
to 1024 counts per axis, and splits it into signed -127..127 HID reports. It
submits at most one request per 25 ms; busy movement is retried, while failed
clicks are never retried automatically. Continuous motion does not request
screen refreshes. No extra framebuffer, network service or persisted store is
added. The native radio session uses the existing bounded queue and worker. The X4 Pro
simulator measured about 63 KiB of Lua heap after initialization; this excludes
the native radio stack and is not a physical-device heap measurement.

`tests/bluetooth_mouse/fixture.lua` and `scenarios.lua` exercise secure readiness,
relative movement, boundary exit/re-entry, fractional speeds, backpressure,
click order/capacity, failure handling, disconnect/reconnect, settings, display
refresh policy and repeated cleanup through the firmware's production Lua
runner. These files are test fixtures and are not installed by the catalog.

Physical acceptance on **X4 Pro** is still required: install an API 5 build,
pair PUNRI Mouse with a computer, drag within the grid in both orientations,
verify pointer direction/speed and both clicks, then disconnect/reconnect,
forget/re-pair, leave the app and re-open it. Confirm advertising stops on exit
and that no button remains pressed. Inspect serial radio errors and internal
heap/largest free block before and after repeated sessions; the desktop Lua
heap measurement does not model NimBLE's hardware allocations. No EPUB cache
reset is needed.
