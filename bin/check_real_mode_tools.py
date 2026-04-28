#!/usr/bin/env python3
"""Check optional real-mode omics tools for CAME smoke tests."""

from __future__ import annotations

import argparse
import csv
import os
import shutil
import subprocess
import sys
from pathlib import Path


FIELDS = ["tool", "scope", "status", "severity", "path", "version", "message"]
SUPPORTED_OMICS_TYPES = {"rnaseq", "atacseq"}
TOOL_COMMANDS = {
    "fastqc": ["fastqc", "--version"],
    "multiqc": ["multiqc", "--version"],
    "STAR": ["STAR", "--version"],
    "featureCounts": ["featureCounts", "-v"],
    "bwa": ["bwa"],
    "samtools": ["samtools", "--version"],
    "bedtools": ["bedtools", "--version"],
    "java": ["java", "-version"],
    "HMMRATAC": ["HMMRATAC", "--version"],
    "hmmratac": ["hmmratac", "--version"],
}


def project_root() -> Path:
    return Path(__file__).resolve().parents[1]


def parse_omics_types(value: str) -> list[str]:
    requested: list[str] = []
    aliases = {
        "rna-seq": "rnaseq",
        "rna_seq": "rnaseq",
        "atac-seq": "atacseq",
        "atac_seq": "atacseq",
    }
    for raw in str(value or "").split(","):
        item = aliases.get(raw.strip().lower(), raw.strip().lower())
        if not item:
            continue
        if item not in SUPPORTED_OMICS_TYPES:
            raise ValueError(f"Unsupported omics type for smoke checks: {item}")
        if item not in requested:
            requested.append(item)
    if not requested:
        raise ValueError("At least one omics type is required")
    return requested


def first_line(text: str) -> str:
    for line in text.splitlines():
        clean = line.strip()
        if clean:
            return clean
    return ""


def version_for(tool: str, command: list[str]) -> str:
    try:
        result = subprocess.run(command, text=True, capture_output=True, timeout=20, check=False)
    except Exception as exc:
        return f"present; version check failed: {exc}"
    combined = (result.stdout or "") + "\n" + (result.stderr or "")
    if tool == "STAR":
        return first_line(combined) or "present"
    if tool == "multiqc":
        return first_line(result.stdout) or first_line(result.stderr) or "present"
    return first_line(result.stdout) or first_line(result.stderr) or "present"


def check_command(tool: str) -> dict[str, str]:
    command = TOOL_COMMANDS[tool]
    executable = command[0]
    path = shutil.which(executable)
    if not path:
        return {
            "tool": tool,
            "scope": "",
            "status": "missing",
            "severity": "",
            "path": "",
            "version": "",
            "message": f"{tool} was not found on PATH.",
        }
    return {
        "tool": tool,
        "scope": "",
        "status": "found",
        "severity": "PASS",
        "path": path,
        "version": version_for(tool, command),
        "message": f"{tool} detected.",
    }


def resolve_hmmratac_jar(root: Path, cli_jar: str) -> tuple[str, str]:
    candidates: list[tuple[str, Path]] = []
    env_jar = os.environ.get("CAME_HMMRATAC_JAR", "").strip()
    if env_jar:
        candidates.append(("CAME_HMMRATAC_JAR", Path(env_jar)))
    if cli_jar:
        candidates.append(("--hmmratac-jar", Path(cli_jar)))
    for rel in [
        "HMMRATAC.jar",
        "hmmratac.jar",
        "tools/HMMRATAC.jar",
        "environment/tools/HMMRATAC.jar",
        "environment/HMMRATAC.jar",
    ]:
        candidates.append((rel, root / rel))
    for source, path in candidates:
        if path.is_file():
            return source, str(path)
    return "", ""


def row(tool: str, scope: str, status: str, severity: str, path: str, version: str, message: str) -> dict[str, str]:
    return {
        "tool": tool,
        "scope": scope,
        "status": status,
        "severity": severity,
        "path": path,
        "version": version,
        "message": message,
    }


def required_tools(requested: list[str]) -> set[str]:
    tools = {"fastqc"}
    if "rnaseq" in requested:
        tools.update({"STAR", "featureCounts"})
    if "atacseq" in requested:
        tools.update({"bwa", "samtools", "bedtools", "hmmratac_resolver"})
    return tools


def scope_for(tool: str, requested: list[str]) -> str:
    scopes: list[str] = []
    if tool in {"fastqc"}:
        scopes.extend(requested)
    if tool in {"STAR", "featureCounts"}:
        scopes.append("rnaseq")
    if tool in {"bwa", "samtools", "bedtools", "hmmratac_resolver"}:
        scopes.append("atacseq")
    if tool in {"HMMRATAC", "hmmratac", "hmmratac_jar"}:
        scopes.append("atacseq")
    if tool in {"multiqc", "java"}:
        scopes.append("optional")
    return ",".join(dict.fromkeys(scopes))


def assign_severity(records: list[dict[str, str]], requested: list[str], mode: str) -> None:
    required = required_tools(requested)
    for record in records:
        tool = record["tool"]
        record["scope"] = scope_for(tool, requested)
        if record["status"] == "found":
            record["severity"] = "PASS"
            continue
        if tool in required:
            record["severity"] = "ERROR" if mode == "strict" else "WARNING"
        else:
            record["severity"] = "WARNING"


def write_tsv(path: Path, records: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS, delimiter="\t", extrasaction="ignore", quoting=csv.QUOTE_NONE, escapechar="\\", lineterminator="\n")
        writer.writeheader()
        writer.writerows(records)


def build_records(args: argparse.Namespace) -> list[dict[str, str]]:
    root = Path(args.project_dir).resolve()
    requested = parse_omics_types(args.omics_types)
    records = [check_command(tool) for tool in ["fastqc", "multiqc", "STAR", "featureCounts", "bwa", "samtools", "bedtools", "java"]]
    records.extend(check_command(tool) for tool in ["HMMRATAC", "hmmratac"])

    jar_source, jar_path = resolve_hmmratac_jar(root, args.hmmratac_jar or "")
    if jar_path:
        records.append(row("hmmratac_jar", "", "found", "PASS", jar_path, "present", f"HMMRATAC jar detected from {jar_source}."))
    else:
        records.append(row("hmmratac_jar", "", "missing", "", "", "", "No HMMRATAC jar was found."))

    command_rows = {record["tool"]: record for record in records}
    command_path = ""
    command_version = ""
    message = "No HMMRATAC command or jar was found."
    resolver_status = "missing"
    for tool in ["HMMRATAC", "hmmratac"]:
        if command_rows[tool]["status"] == "found":
            resolver_status = "found"
            command_path = command_rows[tool]["path"]
            command_version = command_rows[tool]["version"]
            message = f"HMMRATAC resolved through {tool} on PATH."
            break
    if resolver_status != "found" and jar_path:
        java_row = command_rows["java"]
        if java_row["status"] == "found":
            resolver_status = "found"
            command_path = jar_path
            command_version = "jar"
            message = "HMMRATAC resolved through a jar and Java."
        else:
            message = "HMMRATAC jar was found, but Java was not found on PATH."
    records.append(row("hmmratac_resolver", "", resolver_status, "", command_path, command_version, message))
    assign_severity(records, requested, args.mode)
    return records


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--outdir", default="results/real_mode_smoke")
    parser.add_argument("--mode", choices=["soft", "strict"], default="soft")
    parser.add_argument("--omics-types", "--omics_types", dest="omics_types", default="rnaseq,atacseq")
    parser.add_argument("--hmmratac-jar", "--hmmratac_jar", dest="hmmratac_jar", default="")
    parser.add_argument("--project-dir", default=str(project_root()))
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    try:
        args = parse_args(argv)
        records = build_records(args)
    except Exception as exc:
        print(f"ERROR\tcheck_real_mode_tools\t{exc}", file=sys.stderr)
        return 2

    output = Path(args.outdir) / "tool_check.tsv"
    write_tsv(output, records)
    counts: dict[str, int] = {}
    for record in records:
        counts[record["severity"]] = counts.get(record["severity"], 0) + 1
    print(
        f"CAME real-mode tool check: PASS={counts.get('PASS', 0)} "
        f"WARNING={counts.get('WARNING', 0)} ERROR={counts.get('ERROR', 0)} output={output}"
    )
    return 1 if counts.get("ERROR", 0) else 0


if __name__ == "__main__":
    raise SystemExit(main())
