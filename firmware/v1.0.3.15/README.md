# PUNRI 1.0.3.15

Firmware updates now use the public apps repository catalog with SHA-256 verification.

[Firmware source base](https://github.com/abdallah-ali-abdallah/punri/tree/9aedaaddcad2e12470b2e5e00d195207901d4f6e) (`9aedaaddcad2e12470b2e5e00d195207901d4f6e`). FreeInk SDK: `29dfdc72c6bd1951ec12235daaf19284befcf51d`.

Built from a working-source snapshot, including local changes. Source tree: `20a66c280ee0fcd77ff29ac2d5b3f7949cbffb0c`. The base commit alone does not describe these inputs; `build.json` records the source and submodule tree fingerprints.

| Device | Firmware |
| --- | --- |
| x4-pro | [punri-x4-pro-1.0-9aeda.bin](punri-x4-pro-1.0-9aeda.bin) |

Filenames use source tag `1.0` and base SHA `9aeda`. The `-v<version>.bin` files are byte-identical OTA compatibility aliases.

Verify with `shasum -a 256 -c SHA256SUMS` (macOS) or `sha256sum -c SHA256SUMS` (Linux) after downloading every BIN listed in that file. For one image, calculate its SHA-256 and compare its complete hash to its SHA256SUMS entry.

Install only the image for your exact board. See the [update instructions](../README.md) for SD, web upload and online updates. These are application images, not merged factory/bootloader images.

Build, host and simulator checks do not establish physical-device acceptance. On each device, install from SD, restart, check Settings > System, connect Wi-Fi and select Check for Updates. Confirm that the same version reports no newer update. Then check reading, SD access and the board's buttons/touch. No EPUB cache reset is needed.
