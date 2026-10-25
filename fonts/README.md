# PUNRI downloadable fonts

`fonts.json` is the production manifest used by **Settings → Reader → Font
Options → Manage Fonts**. The firmware loads it from the raw GitHub URL below
and obtains package files from the `files/` base URL it declares:

```text
https://raw.githubusercontent.com/abdallah-ali-abdallah/punri-lua-apps/main/fonts/fonts.json
```

Only open-source fonts may be added. Record the upstream source and license in
`metadata.yaml`, include the corresponding attribution in `LICENSES.md`, then
generate `.cpfont` assets and their SHA-256 manifest with PUNRI's converter:

```sh
# From the PUNRI firmware checkout, with the font-tool requirements installed.
python3 lib/EpdFont/scripts/fontconvert_sdcard.py --help
python3 scripts/generate-font-manifest.py \
  --input apps/fonts/files \
  --base-url "https://raw.githubusercontent.com/abdallah-ali-abdallah/punri-lua-apps/main/fonts/files/" \
  --descriptions-from apps/fonts/metadata.yaml \
  --output apps/fonts/fonts.json
```

Do not hand-edit `fonts.json`, `files/*.cpfont`, their sizes, or SHA-256
digests. The app-store `catalog.json` intentionally does not list font assets:
they are firmware data, not installable Lua applications.
