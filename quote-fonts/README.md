# Quote sleep fonts

Separate, downloadable firmware assets for quotation sleep screens. These files
are not reader-font packages and are not registered in fonts/fonts.json or the
Lua App Store catalog.

| Languages | Profile | Font |
| --- | --- | --- |
| AR | amiri | Amiri Regular |
| HE | frank-ruhl-libre | Frank Ruhl Libre Regular |
| Other 26 supported languages | noto-serif | Noto Serif Regular |

Each profile contains native 20- and 24-point CPFONT v4 files, with one Regular
style and uncompressed 2-bit glyphs. The firmware uses one size at a time. It
renders those glyphs directly rather than enlarging a small framebuffer image.
The point-size names use the existing converter's 150-DPI rasterization; actual
glyph dimensions and line metrics determine layout on each device.

Sources and variable-font axes are pinned in sources.json. Licenses remain in
licenses/<profile>/OFL.txt and must accompany redistributed copies. No TTF is
processed on the device. If a source face omits U+FFFD, its own question-mark
glyph supplies that mandatory replacement character before conversion.
Rebuild from the firmware converter with:

```sh
uv run --with fonttools --with freetype-py python apps/scripts/generate_quote_fonts.py --write --firmware-root .
python apps/scripts/generate_quote_fonts.py
```

The independent index maps all 28 quote languages to three shared profiles.
Every file records its exact byte size and SHA-256. CSV index version 1 remains
unchanged for existing firmware. Quote CSV files may contain custom text; font
subsets cover their scripts, not only the twenty bundled quotations.

The firmware installs only the selected profile under
`/.punri/quotes/fonts/<profile>/`, using a two-file directory transaction. A failed
or cancelled download keeps the previous family. Size/SHA-256 and complete
CPFONT structure are checked before promotion; local structure is checked before
use. Files are excluded from reader-font discovery under /.fonts and /fonts.
Missing font assets require foreground user consent and Wi-Fi. An existing valid
custom CSV is preserved by automatic setup. Sleep itself never starts a network
operation; unavailable assets use the built-in sleep fallback without advancing
the quotation cursor.
