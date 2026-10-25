# Quote of the day

These are downloadable **firmware sleep-screen data**, not a Lua application.
There is no App Store catalog entry or application version to update.

Each of PUNRI's 28 language identifiers has a UTF-8 CSV containing the same
20 short philosophical, literary and motivational selections in the same order.
`PT` means Brazilian Portuguese, `PT2` European Portuguese, `SI` Slovenian,
and `CAV` Valencian, matching firmware persistence identifiers.

## CSV contract

```csv
quote,author,date
"Text, including commas",Author,
Another quotation,,
```

- Exactly three columns; the header is required. Author and date are optional.
- UTF-8 with an optional BOM, LF/CRLF, quoted fields, escaped double quotes and
  quoted line breaks are supported. Do not add a fourth numeric column.
- Numbers are one-based row positions. Firmware stores the next row separately
  on the SD card and advances it **before each quote sleep**, wrapping to row 1.
- Limits: 128 KiB/file, 1,000 quotes, 1,024 UTF-8 bytes for the quotation,
  192 for the author and 32 for the optional date. Device screen space can
  impose a shorter practical quotation length. The shipped short selections
  are intended for enlarged text.
- `date` is the date of the quotation when known, not the speaker's lifetime
  or an inferred date. Only Lincoln's documented speech date is filled here.

Generate the exact byte sizes and SHA-256 values after editing CSVs:

```sh
python3 scripts/generate_quote_index.py --write
python3 scripts/generate_quote_index.py
```

The firmware resolves the official repository's `main` to an immutable commit,
then downloads `quotes/index.json` and the chosen `<LANGUAGE>.csv` from that
same commit. It verifies size, SHA-256 and CSV structure before replacing any
existing SD file. Manual SD files need no manifest.

## Sources and translation notes

The English selections are short extracts or conventional modern renderings
of public-domain works. Other files contain new translations/adaptations for
this collection, rather than copied modern published translations. They are
initial translations, not certified or independently reviewed by native editors.
Author names retain their original spelling except in the Arabic file.
Unknown authorship is left empty; the Delphic maxim is not assigned to Socrates.
These are familiar selections, not a claim of a measured worldwide popularity
ranking. Literary lines retain the named writer as author; they are not claims
that a fictional character's advice was the writer's personal philosophy.

| Rows | Primary work / text | Location |
| --- | --- | --- |
| 1 | [Plato, Charmides](https://www.gutenberg.org/ebooks/1580) | Discussion of the Delphic inscription, 164d–165a; anonymous maxim |
| 2 | [Plato, Apology](https://www.gutenberg.org/ebooks/1656) | Socrates, 38a |
| 3 | [Descartes, Discourse on the Method](https://www.gutenberg.org/ebooks/59) | Part IV |
| 4–5 | [Shakespeare, Hamlet](https://www.gutenberg.org/ebooks/1524) | III.i and I.iii |
| 6 | [Laozi, Tao Te Ching](https://www.gutenberg.org/ebooks/216) | Chapter 64; conventional rendering of “thousand li” |
| 7–8 | [Confucius, Analects](https://www.gutenberg.org/ebooks/3330) | II.15 and XV.24; numbering varies by edition |
| 9 | [Donne, Devotions upon Emergent Occasions](https://www.gutenberg.org/ebooks/23772) | Meditation XVII; modernized spelling |
| 10 | [Pope, An Essay on Man](https://www.poetryfoundation.org/poems/44899/an-essay-on-man-epistle-i) | Epistle I, line 95 |
| 11 | [Keats, Endymion](https://www.gutenberg.org/ebooks/24280) | Book I, opening line |
| 12–13 | [Tennyson, Ulysses](https://www.poetryfoundation.org/poems/45392/ulysses) | Last line and line 56 |
| 14–15 | [Longfellow, A Psalm of Life](https://www.poetryfoundation.org/poems/44644/a-psalm-of-life) | Stanzas 7 and 6; punctuation/case normalized |
| 16–17 | [Emerson, Essays](https://www.gutenberg.org/ebooks/16643) | Self-Reliance |
| 18–19 | [Thoreau, Walden](https://www.gutenberg.org/ebooks/205) | Where I Lived, and What I Lived For |
| 20 | [Lincoln, Second Inaugural Address](https://www.loc.gov/exhibits/lincoln/healing-the-nations-wounds.html) | March 4, 1865 |

Publishing these new data files requires the repository owner's explicit
release/push instruction. Local tests can serve this folder as a mock repository
without changing the public App Store or its catalog.
