# Game Boy 0.1.0

Requires PUNRI Lua API 6 with `gameboy_dmg`. Install **Game Boy** from the App
Store, or copy this package to `/.punri/applications/gameboy/`. Add monochrome
`.gb` files to `/roms/gb/`, then open Apps > Game Boy and choose a game.

The library pages eight entries at a time and supports subfolders, touch and
physical buttons. Native gameplay provides larger held controls, pause/resume,
transactional battery saves, bounded CPU/PSRAM use and ordinary e-ink waveforms
with at most one game refresh starting per second and a completion cooldown.

ROMs are not included. Game Boy Color-only cartridges and audio are unsupported.
See the firmware's `docs/gameboy.md` for API details, supported cartridge limits
and physical-device verification. Simulator results do not certify panel life.
