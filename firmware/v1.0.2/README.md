# PUNRI 1.0.2

Separate Latin and non-Latin reader font sizes, including remote web controls. X4 Pro publication; Sticky deferred.

[Firmware source base](https://github.com/abdallah-ali-abdallah/punri/tree/4585d77d9f976282816f0ba417f8ff839d3f7302) (`4585d77d9f976282816f0ba417f8ff839d3f7302`). FreeInk SDK: `b784446302c076b4b5a622627867f0c80905cc50`.

| Device | Firmware |
| --- | --- |
| x4-pro | [punri-x4-pro-1.0-4585d.bin](punri-x4-pro-1.0-4585d.bin) |

Filenames use source tag `1.0` and base SHA `4585d`. The `-v<version>.bin` files are byte-identical OTA compatibility aliases.

Verify with `shasum -a 256 -c SHA256SUMS` (macOS) or `sha256sum -c SHA256SUMS` (Linux) after downloading every BIN listed in that file. For one image, calculate its SHA-256 and compare its complete hash to its SHA256SUMS entry.

Install only the image for your exact board. See the [update instructions](../README.md) for SD, web upload and online updates. These are application images, not merged factory/bootloader images.

Build, host and simulator checks do not establish physical-device acceptance. On each device, install from SD, restart, check Settings > System, connect Wi-Fi and select Check for Updates. Confirm that the same version reports no newer update. Then check reading, SD access and the board's buttons/touch. No EPUB cache reset is needed.

This publication contains X4 Pro only. Sticky and X4 Classic are omitted. Tests were skipped at the user request.
