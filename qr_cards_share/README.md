# QR Cards Share

Offline PUNRI app for displaying static, scannable QR cards. It supports:

- Link or short text cards.
- Contact cards encoded as vCard 3.0 with CRLF line endings and escaped fields.
- Wi-Fi cards using the common `WIFI:` format (WPA, WEP, Open, and hidden).
- Emergency/return cards with a large on-screen message and an optional contact QR.

## Controls

- Library: **Confirm** opens the selected card; **Page back/forward** changes selection; **Up** opens actions; **Down** starts a new card; **Back** exits.
- Preview: **Confirm** shows the QR, **Left** edits, **Right/Up** opens actions, **Back** returns to the library.
- Forms: **Confirm** edits the highlighted field using the firmware keyboard; **Page back/forward** moves between fields; the last field's forward action saves; **Back** discards the draft.
- QR view: **Back/Confirm** closes it. Wi-Fi QR view also exposes **Delete Wi-Fi** after a confirmation whose default is **Keep**.

Touch devices use the visible card, action, form, and confirmation targets. The app intentionally defines only `on_tap`, because the current PUNRI activity bridge sends both `on_tap(x,y)` and `on_touch(x,y,"tap")` for a single touch.

## QR limits and privacy

The local Project Nayuki-derived encoder uses **Byte mode**, correction level
**M**, and versions **1–10**. Its maximum payload is **213 UTF-8 bytes**
(version 10/M); every generated vCard or Wi-Fi payload is checked after
escaping, and it is rejected rather than truncated if it exceeds that limit.
No ECI segment is emitted, so non-ASCII values are UTF-8 bytes but real-device
scanner compatibility still needs acceptance testing.

The selected QR is stored as 57 rows of module bytes at most. It is generated
only on entering QR view and released on exit; there is no background QR cache
or second framebuffer. QR drawing uses a four-module white quiet zone and an
integer module scale.

Cards are stored as readable, transactional `cards_v1.dat` data in the app's
private SD directory. This is not encrypted storage: a person with the SD card
or a view of the QR can read its contents. In particular, Wi-Fi passwords are
not logged or shown in the library but remain readable from the SD card.

## Local validation

`test/lua_apps/qr_cards_share_scenarios.lua` is exercised through production
`LuaRunner`. It checks known Project Nayuki matrices and masks, capacity edges,
Arabic UTF-8, Wi-Fi/vCard escaping, corrupt-file preservation, failed-save
retry behavior, input routes, measured text clipping, focused form paging,
portrait/landscape target geometry, and twenty version-10 generations.
The QR vectors do not replace scanning a physical e-ink panel with iOS and
Android phones.

To capture real renderer evidence on disposable simulator SD cards, run:

```sh
python3 scripts/test_qr_cards_share_simulator.py
```

It captures touch, physical-button, landscape, Wi-Fi privacy, and
default-safe deletion flows under `artifacts/qr_cards_share/`. Those are
simulator screenshots, not physical-device scan evidence.
