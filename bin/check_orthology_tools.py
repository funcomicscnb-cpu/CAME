#!/usr/bin/env python3
"""Preflight check for the external lift-over tools used by orthology real mode.

Verifies that the binaries required by the selected ``orthology_lift_tool`` are on
PATH and reports their resolved location/version. This mirrors
``check_real_mode_tools.py`` for the orthology stage: in strict mode a missing
required tool is an error; in soft mode it is a warning so callers can skip
real-tool work cleanly. CAME does not install these tools.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys


REQUIRED = {
    "liftover": ["liftOver", "chainSwap"],
    "halliftover": ["halLiftover"],
}


def best_effort_version(tool: str) -> str:
    """Return a short version/usage line for a tool, or '' if unavailable."""
    for args in ([tool, "--version"], [tool]):
        try:
            completed = subprocess.run(
                args,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                timeout=10,
            )
        except (OSError, subprocess.TimeoutExpired):
            continue
        for line in (completed.stdout or "").splitlines():
            line = line.strip()
            if line:
                return line[:200]
    return ""


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lift-tool", "--lift_tool", default="liftover", choices=sorted(REQUIRED))
    parser.add_argument("--mode", default="strict", choices=["strict", "soft"])
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    required = REQUIRED[args.lift_tool]
    missing = []
    for tool in required:
        path = shutil.which(tool)
        if path:
            version = best_effort_version(tool)
            print(f"OK\t{tool}\t{path}\t{version}")
        else:
            missing.append(tool)
            print(f"MISSING\t{tool}\t-\t-", file=sys.stderr)

    if not missing:
        print(f"CAME orthology tools: lift_tool={args.lift_tool} status=OK")
        return 0
    severity = "ERROR" if args.mode == "strict" else "WARNING"
    print(
        f"{severity}\tcheck_orthology_tools\tMissing required tool(s) for "
        f"orthology_lift_tool={args.lift_tool}: {', '.join(missing)}",
        file=sys.stderr,
    )
    print(f"CAME orthology tools: lift_tool={args.lift_tool} status={severity} missing={','.join(missing)}")
    return 1 if args.mode == "strict" else 0


if __name__ == "__main__":
    sys.exit(main())
