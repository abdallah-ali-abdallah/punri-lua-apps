#!/usr/bin/env python3
"""Exercise real Screen Ruler inputs using a supported firmware simulator.

Only disposable virtual-SD copies receive identity/observation hooks. This
checks software geometry and input, not physical inch accuracy on a panel.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

APPS = Path(__file__).resolve().parents[2]

OBSERVER = r'''
local qa_init, qa_draw = on_init, UI.draw_ruler
local qa_write, qa_line, qa_text = punri.write_file, punri.line, punri.text
local qa_writes = 0
punri.write_file = function(...) qa_writes = qa_writes + 1; return qa_write(...) end
function on_init()
    qa_init()
    assert(not punri.file_exists(Calibration.FILE), "Startup wrote a calibration file")
    assert(on_touch == nil and on_update == nil)
end
UI.draw_ruler = function(state, clean, grid, x, y)
    local left, top, right = UI.ruler_bounds(state, clean)
    local one = Ruler.tick_position(left, 16, UI.axis_scale(state, true), "in")
    local found, count, reading = false, 0, false
    punri.line = function(x1, y1, x2, y2, thickness, ink)
        count = count + 1
        if x1 == one and x2 == one and y1 == top and y2 == top + 18 and thickness == 2 then found = true end
        return qa_line(x1, y1, x2, y2, thickness, ink)
    end
    punri.text = function(tx, ty, value, ...)
        if value:match("^X .+  Y ") then reading = true end
        return qa_text(tx, ty, value, ...)
    end
    qa_draw(state, clean, grid, x, y)
    punri.line, punri.text = qa_line, qa_text
    if state.units == "in" and one < right then assert(found, "Missing real 1-inch major tick") end
    if x then assert(reading, "Touched point has no X/Y measurement") end
    if grid then assert(count > 200, "Grid toggle did not add a rendered grid") end
    punri.log(string.format("RULER_TOOLS_QA|%s|%s|%d|%d|%d|%d|%d",
        state.units, punri.get_orientation(), grid and 1 or 0, x and 1 or 0,
        qa_writes, count, punri.get_memory().lua_kb))
end
'''


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--program', type=Path, required=True)
    parser.add_argument('--profile', choices=('x4-pro-simulator', 'x4-classic-simulator'), required=True)
    parser.add_argument('--output-dir', type=Path)
    args = parser.parse_args()
    program = args.program.resolve()
    if not program.is_file():
        parser.error(f'Missing supported simulator binary: {program}')
    output = (args.output_dir or Path(tempfile.mkdtemp(prefix='punri-ruler-tools-'))).resolve()
    output.mkdir(parents=True, exist_ok=True)
    work = output / 'virtual-device'
    package = work / 'fs_/.punri/applications/screen_ruler'
    package.mkdir(parents=True, exist_ok=False)
    for source in (APPS / 'screen_ruler').iterdir():
        if source.is_file() and (source.suffix == '.lua' or source.name in ('manifest.json', 'icon.raw')):
            shutil.copy2(source, package / source.name)
    touch = args.profile == 'x4-pro-simulator'
    device = 'x4pro' if touch else 'x4'
    entry = package / 'main.lua'
    entry.write_text(f'punri.get_device = function() return "{device}" end\n' + entry.read_text() + OBSERVER)
    settings = work / 'fs_/.punri'
    (settings / 'state.json').write_text('{"showBootScreen":false}\n')
    (settings / 'settings.json').write_text('{"autoSleep":0,"orientation":0,"language":"EN"}\n')
    if touch:
        events = [
            '5200:TAP:0.2142857,0.975,80', '5600:TAP:0.2142857,0.975,80',
            '6500:TAP:0.55,0.35,80', '7000:TAP:0.6428571,0.975,80',
            '8000:TAP:0.85,0.65,80', '9000:TAP:0.6428571,0.975,80',
            '10000:TAP:0.0714286,0.975,80', '11000:TAP:0.65,0.4,80',
            '11500:TAP:0.6428571,0.975,80', '12600:TAP:0.7857143,0.975,80',
            '14000:TAP:0.5,0.5,80',
        ]
        captures = [(4500, 'metric'), (6200, 'inches'), (7600, 'grid-measurement'),
                    (8600, 'moved-point'), (9600, 'grid-off'), (10700, 'landscape-inches'),
                    (12200, 'landscape-grid'), (14800, 'clean-measurement')]
    else:
        events = ['5200:LEFT', '6500:ENTER', '6800:RIGHT', '7000:RIGHT', '7200:RIGHT',
                  '7400:RIGHT', '7600:RIGHT', '7800:ENTER', '8600:RIGHT', '8800:RIGHT',
                  '9000:ENTER', '10000:DOWN', '11000:ENTER', '11200:LEFT', '11400:LEFT',
                  '11600:ENTER', '11800:RIGHT', '12000:RIGHT', '12200:ENTER']
        captures = [(4500, 'metric'), (6200, 'inches'), (8300, 'grid-menu'),
                    (9500, 'grid-on'), (10700, 'landscape-inches'), (13000, 'grid-off')]
    finish = max(at for at, _ in captures) + 1200
    actions = ['2000:DOWN', '2800:ENTER', *events, f'{finish}:QUIT']
    env = {key: value for key, value in os.environ.items()
           if not key.startswith(('CROSSPOINT_SIM_', 'PUNRI_SIM_', 'PUNRI_SIMULATOR_'))}
    env.update(PUNRI_SIM_NAVIGATION_QA='apps', CROSSPOINT_SIM_WAKE_REASON='power',
               CROSSPOINT_SIM_INPUT_SCRIPT=';'.join(actions),
               CROSSPOINT_SIM_SCREENSHOTS=';'.join(f'{at}:{output / (name + ".bmp")}' for at, name in captures))
    result = subprocess.run([str(program)], cwd=work, env=env, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True, timeout=35)
    log = output / 'simulator.log'
    log.write_text(result.stdout)
    assert result.returncode == 0 and '[ERR] [LUA]' not in result.stdout, result.stdout[-5000:]
    observations = re.findall(r'RULER_TOOLS_QA\|([^\r\n]+)', result.stdout)
    rows = [row.split('|') for row in observations]
    assert rows and any(row[0] == 'in' for row in rows), result.stdout[-4000:]
    assert any(row[1] == 'landscape' for row in rows) and any(row[2] == '1' for row in rows), rows
    if touch:
        assert any(row[3] == '1' for row in rows), rows
        assert max(int(row[4]) for row in rows) == 3, 'Moving guides or toggling grid caused an SD write'
    else:
        assert max(int(row[4]) for row in rows) == 2, 'Grid menu caused an SD write'
    saved = settings / 'saved_data/screen_ruler/screen_ruler_v1.txt'
    assert 'units=in\n' in saved.read_text() and 'mode=horizontal\n' in saved.read_text()
    for _, name in captures:
        bitmap = output / (name + '.bmp')
        assert bitmap.is_file() and bitmap.stat().st_size > 10000, bitmap
        if shutil.which('sips'):
            subprocess.run(['sips', '-s', 'format', 'png', str(bitmap), '--out', str(bitmap.with_suffix('.png'))],
                           check=True, stdout=subprocess.DEVNULL)
    receipt = {'profile': args.profile, 'physical_accuracy_tested': False, 'log': str(log),
               'observations': rows, 'max_observed_lua_kb': max(int(row[6]) for row in rows)}
    (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(f'PASS: {args.profile}, {len(rows)} observed frames; {output / "receipt.json"}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
