"""Copy a bounded, text-only diagnostic selection from an owned fixture scratch dir."""

import json
import os
from pathlib import Path
import sys


def retain(source, destination, status):
    source, destination = Path(source).resolve(), Path(destination)
    candidates = [source / "fixture_resources.config", source / "tool_check/tool_check.tsv"]
    # Failed tasks can redirect causal tool errors away from .command.err.
    for work in sorted(source.glob("*_work")):
        for command in sorted(work.glob("*/*/.command.sh")):
            task = command.parent
            exitcode = task / ".exitcode"
            if exitcode.is_file() and exitcode.read_text().strip() == "0":
                continue
            candidates.extend(task / name for name in (
                ".exitcode", ".command.sh", ".command.run", ".command.err",
                ".command.out", ".command.log",
            ))
            candidates.extend(sorted(task.glob("logs/**/*.log")))
            candidates.extend(sorted(task.glob("logs/**/*.out")))
            # STAR alignment logs remain here if it fails before moving logs;
            # genomeGenerate can leave its default Log.out at the task root.
            candidates.extend(sorted(task.glob("star/*.out")))
            candidates.extend(sorted(task.glob("Log*.out")))
    # Top-level harness/Nextflow logs, traces, and published validation tables.
    candidates.extend(sorted(source.glob("*.out")))
    candidates.extend(sorted(source.glob("*.log")))
    candidates.extend(sorted(source.glob("*.tsv")))
    for directory in sorted(source.iterdir()):
        if directory.is_dir() and not directory.name.endswith("_work"):
            candidates.extend(sorted(directory.rglob("*validation*.tsv")))
            candidates.extend(sorted(directory.rglob("*summary.tsv")))
            candidates.extend(sorted(directory.rglob("tool_check.tsv")))
            candidates.extend(sorted(directory.rglob("variant_qc.tsv")))

    records, seen, total, omitted = [], set(), 0, 0
    for path in candidates:
        if path in seen:
            continue
        seen.add(path)
        # Never follow staged assets or output symlinks into arbitrary source files.
        if not path.is_file() or any(p.is_symlink() for p in (path, *path.parents)):
            continue
        if len(records) >= 200 or total >= 16 * 1024 * 1024:
            omitted += 1
            continue
        size = path.stat().st_size
        limit = min(256 * 1024, 16 * 1024 * 1024 - total)
        # Log tails retain the final error; table/config heads retain headers.
        tail = path.suffix in (".out", ".log", ".err") or path.name == ".command.out"
        with path.open("rb") as handle:
            if tail and size > limit:
                handle.seek(-limit, os.SEEK_END)
            data = handle.read(limit)
        relative = path.relative_to(source)
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        records.append(dict(path=str(relative), original_bytes=size,
                            retained_bytes=len(data), selection="tail" if tail else "head"))
        total += len(data)
    (destination / "retention.json").write_text(json.dumps(dict(
        fixture_exit_status=int(status), files=records, omitted_files=omitted,
        max_files=200, max_file_bytes=256 * 1024, max_total_bytes=16 * 1024 * 1024,
    ), indent=2) + "\n")


if __name__ == "__main__":
    retain(*sys.argv[1:])
