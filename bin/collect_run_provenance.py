#!/usr/bin/env python3
"""Collect compact CAME run provenance for the final report."""

from __future__ import annotations

import argparse
import csv
import json
import os
import platform
import shlex
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path


PROVENANCE_FIELDS = ["section", "key", "value", "status", "source", "message"]
PARAMETER_FIELDS = ["parameter", "value", "status", "source", "message"]
VERSION_TOOLS = {
    "python",
    "nextflow",
    "Rscript",
    "fastqc",
    "multiqc",
    "bwa",
    "samtools",
    "bedtools",
    "STAR",
    "featureCounts",
    "HMMRATAC",
    "hmmratac",
    "pyyaml",
    "jsonschema",
    "pandas",
    "numpy",
    "scipy",
}


def norm(value: object) -> str:
    return str(value if value is not None else "").strip()


def write_tsv(path: Path, fields: list[str], rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, delimiter="\t", extrasaction="ignore", quoting=csv.QUOTE_NONE, escapechar="\\", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def add_provenance(rows: list[dict[str, str]], section: str, key: str, value: str, status: str = "OK", source: str = "", message: str = "") -> None:
    rows.append(
        {
            "section": section,
            "key": key,
            "value": value,
            "status": status,
            "source": source,
            "message": message,
        }
    )


def run_command(command: list[str], cwd: Path | None = None, timeout: int = 20) -> tuple[int, str, str]:
    try:
        result = subprocess.run(command, cwd=str(cwd) if cwd else None, text=True, capture_output=True, timeout=timeout, check=False)
        return result.returncode, result.stdout.strip(), result.stderr.strip()
    except Exception as exc:
        return 1, "", str(exc)


def command_version(command: list[str], timeout: int = 20) -> tuple[str, str]:
    if not shutil.which(command[0]):
        return "", "missing"
    code, stdout, stderr = run_command(command, timeout=timeout)
    text = "\n".join(part for part in [stdout, stderr] if part)
    first = next((line.strip() for line in text.splitlines() if line.strip()), "")
    return first or ("present" if code == 0 else ""), "OK" if code == 0 or first else "WARNING"


def normalize_path_text(value: str, project_dir: Path, results_dir: Path) -> str:
    text = norm(value)
    if not text:
        return ""
    parts = []
    for token in text.split(","):
        clean = token.strip()
        if not clean:
            parts.append(clean)
            continue
        path = Path(clean).expanduser()
        if not path.is_absolute():
            parts.append(clean)
            continue
        resolved = path.resolve()
        for base, label in [(project_dir, "."), (results_dir, "results")]:
            try:
                rel = resolved.relative_to(base)
                parts.append(str(Path(label) / rel) if label != "." else rel.as_posix())
                break
            except ValueError:
                continue
        else:
            parts.append(f"[external]/{resolved.name}")
    return ",".join(parts)


def flatten_json(prefix: str, value: object) -> list[tuple[str, str]]:
    if isinstance(value, dict):
        pairs: list[tuple[str, str]] = []
        for key in sorted(value):
            child = f"{prefix}.{key}" if prefix else str(key)
            pairs.extend(flatten_json(child, value[key]))
        return pairs
    if isinstance(value, list):
        return [(prefix, ",".join(norm(item) for item in value))]
    return [(prefix, norm(value))]


def read_parameter_snapshot(path: Path, project_dir: Path, results_dir: Path) -> list[dict[str, str]]:
    if not path.is_file():
        return [
            {
                "parameter": "params_snapshot",
                "value": "",
                "status": "WARNING",
                "source": str(path),
                "message": "Parameter snapshot was supplied but could not be read.",
            }
        ]

    rows: list[dict[str, str]] = []
    if path.suffix.lower() == ".json":
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            for key, value in flatten_json("", data):
                rows.append(
                    {
                        "parameter": key,
                        "value": normalize_path_text(value, project_dir, results_dir),
                        "status": "OK",
                        "source": path.name,
                        "message": "",
                    }
                )
        except Exception as exc:
            rows.append({"parameter": "params_snapshot", "value": "", "status": "WARNING", "source": path.name, "message": f"Could not parse JSON snapshot: {exc}"})
        return rows

    try:
        with path.open(newline="") as handle:
            sample = handle.read(min(65536, os.path.getsize(path)))
            handle.seek(0)
            delimiter = "\t" if sample.count("\t") >= sample.count(",") else ","
            reader = csv.DictReader(handle, delimiter=delimiter)
            fields = reader.fieldnames or []
            key_field = "parameter" if "parameter" in fields else ("key" if "key" in fields else (fields[0] if fields else ""))
            value_field = "value" if "value" in fields else (fields[1] if len(fields) > 1 else "")
            for row in reader:
                key = norm(row.get(key_field))
                if not key:
                    continue
                rows.append(
                    {
                        "parameter": key,
                        "value": normalize_path_text(row.get(value_field, ""), project_dir, results_dir),
                        "status": norm(row.get("status")) or "OK",
                        "source": path.name,
                        "message": norm(row.get("message")),
                    }
                )
    except Exception as exc:
        rows.append({"parameter": "params_snapshot", "value": "", "status": "WARNING", "source": path.name, "message": f"Could not parse parameter snapshot: {exc}"})
    return rows


def parse_workflow_command(path: Path, project_dir: Path, results_dir: Path) -> list[dict[str, str]]:
    if not path.is_file():
        return []
    try:
        lines = [line.strip() for line in path.read_text(encoding="utf-8", errors="ignore").splitlines() if line.strip()]
        command = lines[-1] if lines else ""
        if "\t" in command:
            command = command.split("\t")[-1]
        tokens = shlex.split(command)
    except Exception:
        return []
    rows = []
    idx = 0
    while idx < len(tokens):
        token = tokens[idx]
        if token.startswith("--"):
            key = token[2:]
            value = "true"
            if idx + 1 < len(tokens) and not tokens[idx + 1].startswith("--"):
                value = tokens[idx + 1]
                idx += 1
            rows.append(
                {
                    "parameter": key,
                    "value": normalize_path_text(value, project_dir, results_dir),
                    "status": "OK",
                    "source": path.name,
                    "message": "",
                }
            )
        idx += 1
    return rows


def version_rows(project_dir: Path) -> list[dict[str, str]]:
    script = project_dir / "bin" / "print_versions.py"
    if not script.is_file():
        return []
    with tempfile.TemporaryDirectory(prefix="came_versions_") as tmp:
        output = Path(tmp) / "tool_versions.tsv"
        code, _, _ = run_command([sys.executable, str(script), "--output", str(output)], cwd=project_dir, timeout=90)
        if code != 0 or not output.is_file():
            return []
        with output.open(newline="") as handle:
            reader = csv.DictReader(handle, delimiter="\t")
            return [
                row
                for row in reader
                if norm(row.get("tool")) in VERSION_TOOLS
            ]


def collect(project_dir: Path, results_dir: Path, args: argparse.Namespace) -> tuple[list[dict[str, str]], list[dict[str, str]]]:
    provenance: list[dict[str, str]] = []
    parameters: list[dict[str, str]] = []
    now = datetime.now(timezone.utc).replace(microsecond=0).isoformat()

    version_path = project_dir / "VERSION"
    add_provenance(provenance, "run", "timestamp_utc", now, source="system")
    add_provenance(provenance, "run", "outdir", normalize_path_text(str(results_dir), project_dir, results_dir), source="argument")
    if version_path.is_file():
        add_provenance(provenance, "came", "version", norm(version_path.read_text(encoding="utf-8")), source="VERSION")
    else:
        add_provenance(provenance, "came", "version", "", "WARNING", "VERSION", "VERSION file was not found.")

    code, stdout, stderr = run_command(["git", "-C", str(project_dir), "rev-parse", "--short", "HEAD"], timeout=15)
    if code == 0 and stdout:
        add_provenance(provenance, "git", "commit", stdout, source="git")
        status_code, status_stdout, status_stderr = run_command(["git", "-C", str(project_dir), "status", "--porcelain"], timeout=20)
        if status_code == 0:
            add_provenance(provenance, "git", "dirty", "true" if status_stdout else "false", source="git")
        else:
            add_provenance(provenance, "git", "dirty", "", "WARNING", "git", status_stderr or "Could not collect git dirty status.")
    else:
        add_provenance(provenance, "git", "commit", "", "WARNING", "git", stderr or "Git metadata unavailable.")
        add_provenance(provenance, "git", "dirty", "", "WARNING", "git", "Git dirty status unavailable.")

    add_provenance(provenance, "runtime", "python", platform.python_version(), source="platform")
    nextflow_version, nextflow_status = command_version(["nextflow", "-version"])
    add_provenance(provenance, "runtime", "nextflow", nextflow_version, nextflow_status, "nextflow", "Nextflow unavailable." if nextflow_status != "OK" else "")
    r_version, r_status = command_version(["Rscript", "--version"])
    add_provenance(provenance, "runtime", "R", r_version, r_status if r_version else "WARNING", "Rscript", "Rscript unavailable." if not r_version else "")

    for row in version_rows(project_dir):
        tool = norm(row.get("tool"))
        status = norm(row.get("status")) or "unknown"
        version = norm(row.get("version"))
        add_provenance(provenance, "dependency", tool, version, "OK" if status == "present" else "WARNING", "print_versions.py", status)

    if args.params_snapshot:
        parameters.extend(read_parameter_snapshot(Path(args.params_snapshot), project_dir, results_dir))
    if args.workflow_command_file:
        parsed = parse_workflow_command(Path(args.workflow_command_file), project_dir, results_dir)
        existing = {row["parameter"] for row in parameters}
        parameters.extend(row for row in parsed if row["parameter"] not in existing)
    if not parameters:
        parameters.append(
            {
                "parameter": "params_snapshot",
                "value": "",
                "status": "WARNING",
                "source": "parameters",
                "message": "No parameter snapshot or workflow command file was available.",
            }
        )
        add_provenance(provenance, "parameters", "snapshot", "", "WARNING", "parameters", "No parameter snapshot was available.")
    else:
        add_provenance(provenance, "parameters", "snapshot_rows", str(len(parameters)), source="parameters")

    return provenance, parameters


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project_dir", required=True)
    parser.add_argument("--results_dir", required=True)
    parser.add_argument("--output_dir", required=True)
    parser.add_argument("--params_snapshot")
    parser.add_argument("--workflow_command_file")
    args = parser.parse_args(argv)

    project_dir = Path(args.project_dir).resolve()
    results_dir = Path(args.results_dir).resolve()
    output_dir = Path(args.output_dir).resolve()
    provenance, parameters = collect(project_dir, results_dir, args)
    write_tsv(output_dir / "came_run_provenance.tsv", PROVENANCE_FIELDS, provenance)
    write_tsv(output_dir / "came_parameters_snapshot.tsv", PARAMETER_FIELDS, parameters)
    warnings = sum(1 for row in provenance + parameters if row.get("status") == "WARNING")
    print(f"CAME run provenance: records={len(provenance)} parameters={len(parameters)} warnings={warnings}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
