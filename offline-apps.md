# To-do List, Notepad and Tic-tac-toe

These are new, local Lua 5.4 packages for Sticky, X4 Pro and X4 Classic.
They require no network connection or firmware changes. Their initial manifests
are `1.0.0`; they have **not been added to the published catalog or pushed**.

## Install from SD

Copy these complete directories to the card:

```text
/.crosssmudge/applications/todo/
/.crosssmudge/applications/notepad/
/.crosssmudge/applications/tictactoe/
```

Keep `manifest.json`, the entry script, every Lua module and `icon.raw` together.
`icon.png` is the editable upright icon source; it is not needed on the device.
Safely eject the card, then open **Applications**. The legacy directory names
are intentional PUNRI compatibility paths, not a different firmware product.

## To-do List

- Select **+ Add task**, enter a title and activate the keyboard's **Save** key.
- Select a task to mark it done/open, edit its title or delete it.
- Deleting asks for confirmation; **Keep it** is selected by default.
- Change **All / Open / Done** using the side/page buttons, or tap the filter
  label on touch devices. An open task added in the Done view remains in All/Open.
- Limits: 80 tasks; 160 UTF-8 bytes per title.

Tasks are saved transactionally after each committed addition, edit, completion
change or deletion. There are no writes while navigating or typing.

## Notepad

- Select **+ New note**, save its title, then enter and save its text.
- A note's title is saved before its text editor opens. Canceling that first
  text editor leaves a saved empty note, rather than deleting the new title.
- Select a note to read it. Use **Actions** to edit, rename, export or delete it.
- Previous/next buttons turn pages. On touch, tap the left/right half of the
  text or swipe horizontally. Swipe vertically through the note list.
- **Export .txt** writes a UTF-8 plain-text file including the title. Exports
  use the first unused name `exports/note_001.txt` through `note_999.txt`;
  repeated exports never overwrite an older export. Deleting a note does not
  delete its exports. Remove old export files with a computer if all 999 names
  are occupied.
- Limits: 24 notes; 80 UTF-8 bytes per title; 4,096 bytes of text per note;
  32,768 bytes for the complete saved collection, including format overhead.

The current page is wrapped on demand; the app does not retain an array of
all formatted pages. Text supports explicit newlines. The keyboard currently
provides English letters, numbers and punctuation; existing valid UTF-8 text
is preserved and Delete removes a complete code point. This is not a full
Arabic/RTL input editor or a grapheme-aware cursor editor.

## Keyboard and controls

| Control | Action |
| --- | --- |
| Confirm | Activate selected row/key |
| Left / Right | Previous/next list item or keyboard key |
| Up / Down or page buttons | Keyboard row; task filter; note list page |
| Back | Return; cancel editor; exit from the main screen |
| `Aa` / `123` keys | Lower/uppercase; numbers/punctuation |
| `Enter` key | Newline in note text only |
| `Save` key | Commit the text to the SD card |

Touch devices have visible **Exit / Back / Cancel / Actions** targets and
selectable keyboard keys. They do not depend on a hidden firmware footer.
Reserved Back-edge swipes remain owned by the firmware.

**Save is explicit.** Cancel leaves the previous committed text unchanged.
Leaving the app or sleeping while a text editor is open does not commit the
unfinished editor; save it first. Sudden power loss before Save can lose that
uncommitted text. A failed write keeps the old saved value and the editor open
with the typed value for another Save attempt. Do not exit before retrying.

## Where SD data lives

```text
/.smudge/saved_data/todo/items.dat
/.smudge/saved_data/notepad/items.dat
/.smudge/saved_data/notepad/exports/note_001.txt
```

Use `punri.write_file`, rather than `punri.save`, because only `write_file`
returns a success boolean. The firmware syncs and closes a temporary file
before replacing the previous value and recovers interrupted replacements.
The collection is a versioned, length-prefixed UTF-8 format:

```text
PUNRI_ORGANIZER_1\n
<record-count>\n
<done:0-or-1>:<title-byte-count>:<body-byte-count>\n
<title><body>\n
... repeated records ...
```

Todo bodies are empty; Notepad completion flags are always zero. Delimiters,
quotes and newlines in bodies do not confuse the parser. Invalid, oversized
or unreadable existing files cause a read-error screen and are **never
replaced with an empty collection**. Back up the file before repairing it or
removing it to start over. No EPUB cache reset is needed.

## Tic-tac-toe

Choose **Play the device** or **Two players**. X starts. In solo play the device
plays O using exhaustive minimax and cannot be beaten. In two-player mode,
pass the reader between turns. Select a square by touch or navigate with
buttons and Confirm. **New game** starts another round; **Change mode** returns
to opponent selection. The grid rejects occupied squares and marks a winning
line. Scores are session-only and reset when changing opponent mode or
relaunching the app; the game deliberately does not write to SD during play.

## Package verification and store preparation

```bash
python3 test/lua_apps/test_packages.py
pio run -e host-unit-tests -t unit-tests
pio run -e x4-classic-simulator
# For touch verification, use x4-pro-simulator or sticky-simulator.
```

The package test generates and checks a temporary schema-v2 catalog, including
SHA-256 and size records, without modifying `apps/catalog.json`. It also checks
that the two independent copies of `organizer.lua` and `text_editor.lua` match.
Keep those copies identical when making shared changes: the sandbox cannot
import modules from another installed application's directory.

When a store publication is **separately authorized**, use each manifest's
metadata and these exact file lists in the real catalog, then follow the
[App Store submission guide](README.md#submitting-to-the-app-store):

| App | Catalog `files` |
| --- | --- |
| `todo` | `manifest.json`, `main.lua`, `organizer.lua`, `text_editor.lua`, `icon.raw` |
| `notepad` | `manifest.json`, `main.lua`, `organizer.lua`, `text_editor.lua`, `icon.raw` |
| `tictactoe` | `manifest.json`, `main.lua`, `engine.lua`, `icon.raw` |

## Resource measurements

The apps add **no compiled firmware code or always-on task**: scripts, icons
and save files live on SD, and their Lua state is released by the existing app
lifecycle. Package sizes exclude the editable `icon.png` sources.

A freshly built X4 Classic simulator, using the normal 2 MB Lua budget and a
small measurement callback, reported these live Lua allocations:

| App | Package bytes | Fixture | After init | After first draw |
| --- | ---: | --- | ---: | ---: |
| Todo | 25,844 | 80 titles of 160 bytes; 13,541-byte save | 104 KB | 107 KB |
| Notepad | 25,839 | 24 notes; 31,005-byte save | 140 KB | 110 KB |
| Tic-tac-toe | 8,902 | Opponent-selection screen | 45 KB | 47 KB |

These are **sampled simulator Lua allocations**, not compiler/search peaks,
physical internal-RAM/PSRAM usage or largest-free-block measurements. The
native suite additionally exercises maximum editor and collection limits.
No performance or hardware memory-headroom claim follows from these samples.

## Hardware acceptance

- **X4 Classic:** create/edit tasks and notes using buttons only; move between
  keyboard rows with page buttons; check filters, long lists and note pages.
- **Sticky / X4 Pro:** perform the same flows with touch only, including visible
  Cancel/Back/Exit when Back swipe is disabled, and both orientations.
- Create a task, mark it done, restart the device and confirm it remains done.
  Save a multiline note, restart, and confirm its title and text remain intact.
- Export twice, mount the SD card and inspect both `.txt` files. Delete the note
  and confirm the exports still exist.
- With a write-protected or full test card, confirm Save reports an SD error,
  keeps the old data, and succeeds after restoring write access and retrying.
  Back up data before testing deliberate power interruption or corruption.
- Play two-player X/O wins and a draw; verify New game and occupied-square
  rejection. Try all opening moves against the device.
- Inspect serial errors, internal heap/largest block, PSRAM/largest block and
  task stack high-water marks. Host tests establish logic and file handling,
  not physical SD durability, device latency or hardware memory headroom.
