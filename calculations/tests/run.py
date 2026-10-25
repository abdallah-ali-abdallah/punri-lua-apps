#!/usr/bin/env python3
"""Compile PUNRI Lua32, run behavior tests, and compare with an 80-digit oracle."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import platform
import random
import shutil
import subprocess
import tempfile


def main():
    import mpmath as mp
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--firmware", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--output-dir", type=Path)
    args = parser.parse_args()
    source = Path(__file__).resolve().parents[1]
    output = (args.output_dir or Path(tempfile.mkdtemp(prefix="punri-calculations-tests-"))).resolve()
    output.mkdir(parents=True, exist_ok=True)
    lua_source = args.firmware.resolve() / "lib/Lua/src"
    compiler = shutil.which("cc") or shutil.which("clang") or shutil.which("gcc")
    assert compiler and lua_source.is_dir(), "Pass the PUNRI firmware tree and install a C compiler"
    runner = output / "lua32"
    command = [compiler, "-O2", "-I", str(lua_source), str(source / "tests/runner.c"),
               *map(str, sorted(lua_source.glob("*.c"))), "-lm", "-o", str(runner)]
    if platform.system() == "Linux": command.append("-ldl")
    subprocess.run(command, check=True)
    for suite in ("precision.lua", "test.lua", "app_test.lua"):
        result = subprocess.run([str(runner), str(source / "tests" / suite), str(source)],
                                check=True, text=True, capture_output=True)
        print(result.stdout.strip())
        (output / f"{suite}.log").write_text(result.stdout + result.stderr)
    mp.mp.dps = 80
    cases = []

    def add(expression, expected):
        cases.append((expression, mp.mpf(expected)))

    for literal in ("1e-80", "0.000001", "0.1", "0.5", "1", "2", "10", "123456789", "1e80"):
        x = mp.mpf(literal)
        add(f"sqrt({literal})", mp.sqrt(x))
        add(f"ln({literal})", mp.log(x))
    for literal in ("-1", "-0.99999999", "-0.5", "0", "0.5", "0.99999999", "1"):
        x = mp.mpf(literal)
        add(f"asin({literal})", mp.asin(x)); add(f"acos({literal})", mp.acos(x))
    for literal in ("-30", "-10", "-1", "-0.01", "0", "0.01", "1", "10", "30"):
        add(f"exp({literal})", mp.exp(mp.mpf(literal)))
    for literal in ("-20", "-1", "-0.5", "1e-30", "0.5", "1", "20"):
        x = mp.mpf(literal)
        add(f"sinh({literal})", mp.sinh(x)); add(f"cosh({literal})", mp.cosh(x)); add(f"tanh({literal})", mp.tanh(x))
    rng = random.Random(261026)
    for _ in range(35):
        literal = f"{rng.uniform(-1000000, 1000000):.8f}"
        x = mp.mpf(literal)
        add(f"sin({literal})", mp.sin(x)); add(f"cos({literal})", mp.cos(x))
        literal = f"{rng.uniform(-100, 100):.10f}"
        x = mp.mpf(literal)
        add(f"atan({literal})", mp.atan(x))
    add("1/3+1/6", mp.mpf("0.5"))
    add("(10^8+1)-10^8", 1)
    add("0.1+0.2", mp.mpf("0.3"))
    add("1.234567890125", mp.mpf("1.23456789012"))
    add("1.234567890135", mp.mpf("1.23456789014"))
    expressions = output / "oracle.lua"
    lua = "\n".join([
        "local root=arg[1]", "local B=dofile(root..'/bigint.lua')", "local D=dofile(root..'/decimal.lua')(B)",
        "local N=dofile(root..'/number.lua')(B,D)", "local P=dofile(root..'/parser.lua')", "local E=dofile(root..'/engine.lua')(B,D,N,P)",
        "local cases={" + ",".join(json.dumps(item[0]) for item in cases) + "}",
        "for i,source in ipairs(cases) do local value,problem=E.run(source,{angle='RAD'}); assert(value,source..': '..tostring(problem)); print(i..'\\t'..N.format(value)) end",
    ])
    expressions.write_text(lua + "\n")
    result = subprocess.run([str(runner), str(expressions), str(source)], check=True, capture_output=True, text=True)
    rows = result.stdout.splitlines()
    assert len(rows) == len(cases), result.stdout
    maximum_relative = mp.mpf(0)
    for row, (expression, expected) in zip(rows, cases):
        actual = mp.mpf(row.split("\t")[1])
        error = abs(actual - expected)
        tolerance = max(mp.mpf("1e-20"), abs(expected) * mp.mpf("6e-12"))
        assert error <= tolerance, f"{expression}: {actual} vs {expected}; error {error}"
        if expected != 0: maximum_relative = max(maximum_relative, error / abs(expected))
    receipt = {"runtime": "PUNRI signed32/binary32 Lua", "oracle": "mpmath 1.3.0, 80 decimal digits",
               "vectors": len(cases), "maximum_relative_error": str(maximum_relative),
               "tolerance": "max(1e-20 absolute, 6e-12 relative)",
               "source_sha256": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in source.glob("*.lua")}}
    (output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(f"PASS {len(cases)} independent high-precision oracle vectors; receipt {output / 'receipt.json'}")
    return 0


if __name__ == "__main__": raise SystemExit(main())
