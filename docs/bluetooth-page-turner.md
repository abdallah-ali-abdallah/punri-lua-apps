# Bluetooth Page Turner

`bluetooth_page_turner` is a local, unpublished PUNRI Lua app that makes a
supported X4 Pro build appear to another device as the BLE HID keyboard
`PUNRI Remote`. It is a foreground remote: leaving the app, a Lua error, sleep,
or selecting Disconnect stops advertising and releases the radio session.

## Hardware and compatibility

- Requires firmware Lua API 4 and `radio.capabilities().hid_keyboard_peripheral`.
- Requires an X4 Pro firmware build. Sticky and X4 Classic show an unavailable
  screen; the app does not attempt a fake GATT replacement or Wi-Fi fallback.
- The desktop simulator is a deterministic replay only. Its `SIMULATION` label
  is not evidence that a computer or e-reader actually paired.
- The app has no SD preferences or local host identifiers. Bluetooth bonding is
  managed by the firmware/host, not copied into application storage.

## Pairing and use

1. Open **Bluetooth Page Turner** and select **Pair / Advertise**.
2. On the host, select **PUNRI Remote** in its Bluetooth keyboard/device list.
3. Wait for **Connected. Keys are ready.** The app will not send a key until the
   host's encrypted, bonded HID input subscription is active.
4. Use Up/Down/Left/Right. **Page turns** mode keeps touch controls to Left and
   Right, while physical Page Back/Page Forward keys map to the same two keys.
5. Select **Disconnect** before pairing a different host.

The advertising window lasts at most 30 seconds. An already paired host can
reconnect while that window is active; after a timeout, start a new window.
There is no background page turning after exit.

## Security and recovery

The first release uses encrypted BLE Secure Connections Just Works bonding. It
has no passkey screen, no numeric-comparison claim, and no Bluetooth Classic
mode. `Forget pairing` only removes the paired host that connected during the
current open app session. It intentionally cannot enumerate or wipe other
system Bluetooth bonds, including unknown older hosts after reopening the app.

If a host rejects pairing or keys do not change pages, disconnect, remove
`PUNRI Remote` from the host's own Bluetooth settings if needed, then pair again.
The host chooses what arrow keys mean; verify its reader app is focused and uses
Left/Right or the needed arrow direction for page turns.

## Hardware acceptance

On an X4 Pro, verify all of the following before relying on it:

1. Pair from a fresh host and confirm the host identifies it as a keyboard,
   rather than as a generic BLE service.
2. Confirm each arrow produces one reader action, including rapid but deliberate
   taps; verify no stuck key after Bluetooth loss.
3. Disconnect/reconnect within 30 seconds, then test Pair again after timeout.
4. Test Forget pairing for the currently connected host and confirm that only
   that host needs pairing again.
5. Exit the app and sleep/wake the reader while a host is connected; confirm
   advertising stops and normal device power behavior returns.
