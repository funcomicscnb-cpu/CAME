#!/usr/bin/env python3
"""
CAME-I2 orchestration sentinel.

Called after each external CEEG validator CLI exits. Validates that:
  - exit codes 0/1/2 (semantic CEEG results) are accompanied by the expected manifest;
  - any other exit code is propagated as a tooling/environment failure.

Does not reinterpret CEEG validator semantics. Does not modify output directories.
Exit 10 signals "recognized validator exit code but manifest missing" (orchestration error).
"""
import argparse
import sys
from pathlib import Path


def main() -> None:
    p = argparse.ArgumentParser(description="Check CEEG orchestration exit code and manifest.")
    p.add_argument("--out-dir",        required=True, help="Validator output directory")
    p.add_argument("--manifest-name",  required=True, help="Expected manifest filename")
    p.add_argument("--exit-code",      required=True, type=int, help="Exit code from external validator")
    p.add_argument("--validator-label",required=True, help="Label for error messages (e.g. r2_overlay)")
    args = p.parse_args()

    manifest = Path(args.out_dir) / args.manifest_name

    if args.exit_code in (0, 1, 2):
        if not manifest.exists():
            sys.stderr.write(
                f"CAME orchestration error: {args.validator_label} exited {args.exit_code} "
                f"but {args.manifest_name} was not found in {args.out_dir}. "
                "The validator produced no manifest; cannot proceed to artifact consumption. "
                "Inspect ceeg_command.log in the generated output directory.\n"
            )
            sys.exit(10)
        sys.exit(0)
    else:
        sys.stderr.write(
            f"CAME orchestration error: {args.validator_label} exited {args.exit_code} "
            f"(expected 0, 1, or 2). This indicates a tooling or command-invocation failure, "
            "not a CEEG validator semantic result. "
            "Inspect ceeg_command.log in the generated output directory.\n"
        )
        sys.exit(args.exit_code)


if __name__ == "__main__":
    main()
