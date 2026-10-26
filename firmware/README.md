# PUNRI firmware updates

Download the latest board-specific firmware using [catalog.json](catalog.json).
Each release folder contains its `.bin` application images, `catalog.json`,
`SHA256SUMS`, `build.json` and a README describing the update and source commit.

The initial release is [PUNRI 1.0.1](v1.0.1/README.md):

| Device | Download |
| --- | --- |
| Seeed reTerminal Sticky (ESP32-S3) | [punri-sticky-v1.0.1.bin](v1.0.1/punri-sticky-v1.0.1.bin) |
| Xteink X4 Pro (ESP32-S3) | [punri-x4-pro-v1.0.1.bin](v1.0.1/punri-x4-pro-v1.0.1.bin) |
| Xteink X4 Classic (ESP32-S3) | [punri-x4-classic-v1.0.1.bin](v1.0.1/punri-x4-classic-v1.0.1.bin) |

Select your exact board. X4 Pro and X4 Classic images are different. Retired
ESP32-C3 X3/X4 hardware is unsupported. These are application images for an
existing compatible installation; they do not include a bootloader or partition
table and are not merged factory images.

## Verify the download

Download the release's [SHA256SUMS](v1.0.1/SHA256SUMS) beside its binaries and run:

```bash
# macOS (download every BIN listed in SHA256SUMS for a complete check):
shasum -a 256 -c SHA256SUMS
# Linux:
sha256sum -c SHA256SUMS
```

For one image, run `shasum -a 256 punri-x4-pro-v1.0.1.bin` (macOS) or
`sha256sum punri-x4-pro-v1.0.1.bin` (Linux) and compare the complete 64-character
hash to its catalog/checksum entry. Never install a file whose digest differs.

## First installation of this update channel

Older firmware points at another update feed. Install the first release manually
once; inherited 1.6.x firmware also compares higher than PUNRI's new 1.0.x
numbering. Saved books, settings and application data remain on the SD card;
keep a backup before any firmware change.

**SD update:** copy the matching `.bin` to the card. In PUNRI, open Settings >
System > SD Card Firmware Update, select the image, confirm its identity and
install. Compatible older firmware can use its own SD update screen.

**Web upload:** start PUNRI's web transfer portal, open its firmware page, upload
the matching `.bin`, review the identified board/version and confirm installation.
Some older firmware has no web update page; use SD instead.

Keep the device powered while it writes and restarts. After restart, verify
Settings > System, open a book and check SD access and button/touch controls.
This channel change needs no EPUB cache reset.

## Later online updates

In firmware using this channel, connect Wi-Fi and open Settings > System >
Check for Updates. PUNRI reads the latest catalog, selects the exact board and
stages the download on SD. It verifies the whole-file SHA-256, declared size,
ESP32-S3 chip, board marker, PUNRI identity and embedded version before writing
an OTA slot. The same installed version reports no newer update. Keep free SD
space at least as large as the selected image.

Catalog URL:
<https://raw.githubusercontent.com/abdallah-ali-abdallah/punri-lua-apps/main/firmware/catalog.json>

The catalog and SHA-256 protect download integrity. Trust comes from the official
HTTPS repository; these are not separately signed firmware packages.

## Maintainers

Use the firmware repository's
[publication guide](https://github.com/abdallah-ali-abdallah/punri/blob/main/docs/development/firmware-publication.md).
Build and test all three boards, commit validated source, then build the final
versioned images. `scripts/publish_firmware.py` prepares release files and
`--check` verifies them before publication. `make firmware-publish` performs the
complete clean-build, test and publication flow, replacing the current version
through new Git commits. Download filenames contain the latest main tag and
first five source-commit characters, for example
`punri-x4-pro-1.0.1-45abc.bin`. OTA aliases retain the old filename convention.
Catalog URLs pin the image commit, so older catalogs keep their matching bytes
after replacement. Increasing the OTA version is required for installed devices
to offer another update; replacing the same version only refreshes its download.
Publish the apps commit before advancing the firmware's apps submodule. Never
force push history, change application versions or regenerate the root app
catalog for a firmware release. Hardware acceptance remains a separate check.
