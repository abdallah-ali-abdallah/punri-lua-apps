# Presenter Remote

`presenter_remote` is a PUNRI Lua app available in the App Store that makes a
supported X4 Pro build appear to another device as the BLE HID keyboard
`PUNRI Remote`. It is a foreground remote: leaving the app, a Lua error, sleep,
or selecting Disconnect stops advertising and releases the radio session.

## Interface and replacement

Version 0.2.0 replaces the old `bluetooth_page_turner` package and catalog entry.
Install **Presenter Remote** from the App Store. If the old app is already on an
SD card, uninstall **Bluetooth Page Turner** from Applications separately; a
catalog replacement cannot erase an installed app on an offline device.
The Bluetooth keyboard name remains **PUNRI Remote**.

The portrait screen uses a tall capsule, a filled Next key, an outlined Back
key, and large Enter/Space buttons. Landscape places the clicker beside its
connection and mode controls. Pairing/Disconnect remains on the main screen;
Forget pairing is in Settings. The header always shows connection state and
labels simulator replay as **SIMULATION**.

Version 0.2.2 restores touch handling independently of the press animation's
last drawn targets. The whole arrow control, including its label, accepts taps;
arrows, Enter and Space work as soon as pairing is ready, even before the next
screen refresh. Unpaired taps show a connection notice. Unsupported Enter/Space
commands still show the firmware-update notice.

## Hardware and compatibility

- Requires firmware Lua API 4 and `radio.capabilities().hid_keyboard_peripheral`.
- Requires an X4 Pro firmware build. Sticky and X4 Classic show an unavailable
  screen; the app does not attempt a fake GATT replacement or Wi-Fi fallback.
- The desktop simulator is a deterministic replay only. Its `SIMULATION` label
  is not evidence that a computer or e-reader actually paired.
- The app has no SD preferences or local host identifiers. Bluetooth bonding is
  managed by the firmware/host, not copied into application storage.

## Pairing and use

1. Open **Presenter Remote** and select **Pair / Advertise**.
2. On the host, select **PUNRI Remote** in its Bluetooth keyboard/device list.
3. Wait for **Connected. Keys are ready.** The app will not send a key until the
   host's encrypted, bonded HID input subscription is active.
4. Use the large **Next** (Right) and **Back** (Left) circles, the smaller
   Up/Down controls, or **Enter** and **Space** at the bottom of the clicker. **Page turns** mode keeps Left/Right plus Enter/Space visible, while
   physical Page Back/Page Forward keys map to Left/Right.
5. Select **Disconnect** before pairing a different host. Open **Settings**
   for **Forget pairing**; Back returns from Settings to the remote without
   exiting or sending a host key. The hardware Confirm key selects the
   highlighted Settings action, with **Back to remote** selected by default.

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
   Tap arrow labels as well as their circles. Try a key immediately after
   pairing and after returning from Settings, without waiting for a refresh.
   Include rapid but deliberate taps and check for no stuck key after link loss.
3. Disconnect/reconnect within 30 seconds, then test Pair again after timeout.
4. Test Forget pairing for the currently connected host and confirm that only
   that host needs pairing again.
5. Exit the app and sleep/wake the reader while a host is connected; confirm
   advertising stops and normal device power behavior returns.
