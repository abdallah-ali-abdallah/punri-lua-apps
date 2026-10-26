# PUNRI 1.0.1

Firmware updates now use the public apps repository catalog with SHA-256 verification.

[Firmware source](https://github.com/abdallah-ali-abdallah/punri/tree/745eebd62254ce3cec91d8e15f1faa7c1679f34d) (`745eebd62254ce3cec91d8e15f1faa7c1679f34d`). FreeInk SDK: `b784446302c076b4b5a622627867f0c80905cc50`.

| Device | Firmware |
| --- | --- |
| sticky | [punri-sticky-v1.0.1.bin](punri-sticky-v1.0.1.bin) |
| x4-pro | [punri-x4-pro-v1.0.1.bin](punri-x4-pro-v1.0.1.bin) |
| x4-classic | [punri-x4-classic-v1.0.1.bin](punri-x4-classic-v1.0.1.bin) |

Verify with `shasum -a 256 -c SHA256SUMS` (macOS) or `sha256sum -c SHA256SUMS` (Linux).

Install only the image for your exact board. See the [update instructions](../README.md) for SD, web upload and online updates. These are application images, not merged factory/bootloader images.

Build, host and simulator checks do not establish physical-device acceptance. On each device, install from SD, restart, check Settings > System, connect Wi-Fi and select Check for Updates. Confirm that the same version reports no newer update. Then check reading, SD access and the board's buttons/touch. No EPUB cache reset is needed.
