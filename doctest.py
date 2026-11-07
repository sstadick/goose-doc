#!/usr/bin/env python3
"""Extract doc examples with goose-doc, then compile and run each in isolation.

Examples are trusted executable code, not sandboxed. All Goose fences run
unless explicitly marked `goose ignore`. The optional preamble supplies
imports and helpers; example bodies are wrapped in fn main().
"""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("files", nargs="+", help="source paths relative to --root")
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--symbols", type=Path)
    parser.add_argument("--preamble", type=Path, help="imports/helpers to prepend to every example")
    parser.add_argument("--require-examples", action="store_true")
    parser.add_argument("--goose", default=os.environ.get("GOOSE", "goose"))
    parser.add_argument("--cc", help="build and run natively with this C compiler instead of TinyCC")
    parser.add_argument("--timeout", type=float, default=60, help="seconds per compiler/run command")
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    goose = shutil.which(args.goose)
    if not goose:
        parser.error(f"Goose compiler not found: {args.goose}")
    goose = str(Path(goose).resolve())
    root = args.root.resolve()
    preamble = args.preamble.read_text() if args.preamble else "import std;\n"
    command = [goose, "run", str(Path(__file__).with_name("main.goose")), "--",
               "--examples", "--root", str(root)]
    if args.symbols:
        command += ["--symbols", str(args.symbols.resolve())]
    if args.require_examples:
        command.append("--require-examples")
    command += ["--", *args.files]
    extracted = subprocess.run(command, capture_output=True, text=True, timeout=args.timeout)
    if extracted.returncode:
        sys.stderr.write(extracted.stderr)
        return 1
    examples = [json.loads(line) for line in extracted.stdout.splitlines()]
    if not examples:
        print("goose-doc: no executable examples selected", file=sys.stderr)
        return 1
    failed = 0
    # A direct child of the source root lets preambles import the checkout
    # with `from ".."`, including its build file and native headers.
    with tempfile.TemporaryDirectory(prefix=".goose-doc-", dir=root) as directory:
        temporary = Path(directory)
        for number, example in enumerate(examples, 1):
            label = f"{example['path']}:{example['line']} ({example['name']})"
            source = temporary / f"example-{number}.goose"
            source.write_text(preamble + "\nfn main() {\n" + example["code"] + "}\n")
            if args.cc:
                exe = temporary / (f"example-{number}.exe" if os.name == "nt" else f"example-{number}")
                commands = [[goose, "build", str(source), "--debug", "-O2", "--cc", args.cc, "-o", str(exe)],
                            [str(exe)]]
            else:
                commands = [[goose, "run", str(source), "--debug"]]
            try:
                for command in commands:
                    result = subprocess.run(command, cwd=root, capture_output=True, text=True, timeout=args.timeout)
                    if result.returncode:
                        print(f"FAIL {label}", file=sys.stderr)
                        sys.stderr.write(result.stdout + result.stderr)
                        failed += 1
                        break
                else:
                    print(f"PASS {label}")
            except subprocess.TimeoutExpired:
                print(f"FAIL {label}: exceeded {args.timeout:g}s", file=sys.stderr)
                failed += 1
    print(f"{len(examples) - failed}/{len(examples)} documentation examples passed")
    return 1 if failed else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        print(f"goose-doc: {error}", file=sys.stderr)
        sys.exit(1)
