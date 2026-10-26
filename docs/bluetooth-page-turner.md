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
4. Use Up/Down/Left/Right, or the large **Enter** and **Space** buttons below the
   arrows. **Page turns** mode keeps Left/Right plus Enter/Space visible, while
   physical Page Back/Page Forward keys map to Left/Right.
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
The host chooses what each key means; verify its reader app or text field is
focused. Enter confirms or inserts a new line, and Space sends one spacebar press.
Enter and Space require `radio.capabilities().hid_keyboard_enter_space`; older
HID firmware keeps arrows usable and shows an update notice for the new keys.

## Hardware acceptance

On an X4 Pro, verify all of the following before relying on it:

1. Pair from a fresh host and confirm the host identifies it as a keyboard,
   rather than as a generic BLE service.
2. Confirm each arrow produces one reader action. In a focused text field, verify
   Enter inserts one new line and Space inserts one space in both app modes.
   Include rapid but deliberate taps and check for no stuck key after link loss.
3. Disconnect/reconnect within 30 seconds, then test Pair again after timeout.
4. Test Forget pairing for the currently connected host and confirm that only
   that host needs pairing again.
5. Exit the app and sleep/wake the reader while a host is connected; confirm
   advertising stops and normal device power behavior returns.
