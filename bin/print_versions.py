#!/usr/bin/env python3
"""Record compact CAME runtime and dependency versions."""

from __future__ import annotations

import argparse
import csv
import os
import platform
import shutil
import subprocess
import sys
from importlib import metadata
from pathlib import Path


FIELDS = ["tool", "category", "status", "version", "path"]

CLI_TOOLS = [
    ("python", [sys.executable, "--version"]),
    ("java", ["java", "-version"]),
    ("nextflow", ["nextflow", "-version"]),
    ("Rscript", ["Rscript", "--version"]),
    ("fastqc", ["fastqc", "--version"]),
    ("multiqc", ["multiqc", "--version"]),
    ("bwa", ["bwa"]),
    ("samtools", ["samtools", "--version"]),
    ("bedtools", ["bedtools", "--version"]),
    ("STAR", ["STAR", "--version"]),
    ("featureCounts", ["featureCounts", "-v"]),
    ("HMMRATAC", ["HMMRATAC", "--version"]),
    ("hmmratac", ["hmmratac", "--version"]),
]

PYTHON_PACKAGES = [
    ("pyyaml", "PyYAML"),
    ("jsonschema", "jsonschema"),
    ("pandas", "pandas"),
    ("numpy", "numpy"),
    ("scipy", "scipy"),
]

R_PACKAGES = ["yaml", "ape", "nlme", "data.table", "DESeq2"]


def project_root() -> Path:
    return Path(__file__).resolve().parents[1]


def first_line(text: str) -> str:
    for line in text.splitlines():
        clean = line.strip()
        if clean:
            return clean
    return ""


def command_path(command: str) -> str:
    if command == sys.executable:
        return sys.executable
    return shutil.which(command) or ""


def run_command_version(name: str, command: list[str]) -> dict[str, str]:
    executable = command[0]
    path = command_path(executable)
    if not path:
        return {"tool": name, "category": "cli", "status": "missing", "version": "", "path": ""}
    try:
        result = subprocess.run(command, text=True, capture_output=True, timeout=20, check=False)
        combined = (result.stdout or "") + "\n" + (result.stderr or "")
        if name == "nextflow":
            version = next((line.strip() for line in combined.splitlines() if "version" in line.lower()), "")
        else:
            version = ""
        version = version or first_line(result.stdout) or first_line(result.stderr) or "present"
    except Exception as exc:
        version = f"present; version check failed: {exc}"
    return {"tool": name, "category": "cli", "status": "present", "version": version, "path": path}


def python_package_rows() -> list[dict[str, str]]:
    rows = []
    for label, dist_name in PYTHON_PACKAGES:
        try:
            version = metadata.version(dist_name)
            status = "present"
        except metadata.PackageNotFoundError:
            version = ""
            status = "missing"
        rows.append({"tool": label, "category": "python_package", "status": status, "version": version, "path": ""})
    return rows


def r_package_rows() -> list[dict[str, str]]:
    rscript = shutil.which("Rscript")
    if not rscript:
        return [
            {"tool": package, "category": "r_package", "status": "not_checked", "version": "", "path": ""}
            for package in R_PACKAGES
        ]
    package_expr = ",".join(f'"{package}"' for package in R_PACKAGES)
    code = (
        f"packages <- c({package_expr}); "
        "for (pkg in packages) { "
        'status <- if (requireNamespace(pkg, quietly=TRUE)) as.character(utils::packageVersion(pkg)) else "missing"; '
        'writeLines(paste(pkg, status, sep="|")) '
        "}"
    )
    try:
        result = subprocess.run([rscript, "-e", code], text=True, capture_output=True, timeout=60, check=False)
    except Exception:
        result = None
    versions: dict[str, str] = {}
    if result and result.returncode == 0:
        for line in result.stdout.splitlines():
            parts = line.split("|")
            if len(parts) == 2:
                versions[parts[0]] = parts[1]
    rows = []
    for package in R_PACKAGES:
        version = versions.get(package, "")
        if not version:
            status = "not_checked"
        elif version == "missing":
            status = "optional_missing" if package == "DESeq2" else "missing"
            version = ""
        else:
            status = "present"
        rows.append({"tool": package, "category": "r_package", "status": status, "version": version, "path": ""})
    return rows


def hmmratac_jar_rows(root: Path) -> list[dict[str, str]]:
    candidates = []
    env_path = os.environ.get("CAME_HMMRATAC_JAR", "").strip()
    if env_path:
        candidates.append(("CAME_HMMRATAC_JAR", Path(env_path)))
    for rel in ["HMMRATAC.jar", "hmmratac.jar", "tools/HMMRATAC.jar", "environment/tools/HMMRATAC.jar", "environment/HMMRATAC.jar"]:
        candidates.append((rel, root / rel))
    rows = []
    found = False
    for label, path in candidates:
        if path.is_file():
            found = True
            rows.append({"tool": "hmmratac_jar", "category": "jar", "status": "present", "version": "present", "path": str(path)})
            break
    if not found:
        rows.append({"tool": "hmmratac_jar", "category": "jar", "status": "optional_missing", "version": "", "path": ""})
    return rows


def write_tsv(path: Path, rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS, delimiter="\t", extrasaction="ignore", quoting=csv.QUOTE_NONE, escapechar="\\", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def summarize(rows: list[dict[str, str]]) -> str:
    counts: dict[tuple[str, str], int] = {}
    for row in rows:
        key = (row["category"], row["status"])
        counts[key] = counts.get(key, 0) + 1
    parts = [f"{category}:{status}={counts[(category, status)]}" for category, status in sorted(counts)]
    return "; ".join(parts)


def main(argv: list[str] | None = None) -> int:
    root = project_root()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", default=str(root / "environment" / "tool_versions.tsv"))
    args = parser.parse_args(argv)

    rows = []
    rows.append({"tool": "platform", "category": "system", "status": "present", "version": platform.platform(), "path": ""})
    for name, command in CLI_TOOLS:
        rows.append(run_command_version(name, command))
    rows.extend(python_package_rows())
    rows.extend(r_package_rows())
    rows.extend(hmmratac_jar_rows(root))

    output = Path(args.output)
    write_tsv(output, rows)
    print(f"Wrote {output}")
    print(summarize(rows))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
