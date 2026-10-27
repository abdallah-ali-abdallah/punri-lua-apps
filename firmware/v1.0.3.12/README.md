# PUNRI 1.0.3.12

Firmware updates now use the public apps repository catalog with SHA-256 verification.

[Firmware source base](https://github.com/abdallah-ali-abdallah/punri/tree/d4b06cb638b4ade63a8a2d173b9521c8c4dc00a3) (`d4b06cb638b4ade63a8a2d173b9521c8c4dc00a3`). FreeInk SDK: `b784446302c076b4b5a622627867f0c80905cc50`.

| Device | Firmware |
| --- | --- |
| x4-pro | [punri-x4-pro-1.0-d4b06.bin](punri-x4-pro-1.0-d4b06.bin) |

Filenames use source tag `1.0` and base SHA `d4b06`. The `-v<version>.bin` files are byte-identical OTA compatibility aliases.

Verify with `shasum -a 256 -c SHA256SUMS` (macOS) or `sha256sum -c SHA256SUMS` (Linux) after downloading every BIN listed in that file. For one image, calculate its SHA-256 and compare its complete hash to its SHA256SUMS entry.

Install only the image for your exact board. See the [update instructions](../README.md) for SD, web upload and online updates. These are application images, not merged factory/bootloader images.

Build, host and simulator checks do not establish physical-device acceptance. On each device, install from SD, restart, check Settings > System, connect Wi-Fi and select Check for Updates. Confirm that the same version reports no newer update. Then check reading, SD access and the board's buttons/touch. No EPUB cache reset is needed.
