#!/usr/bin/env python3
"""Summarize a CAME end-to-end run from per-stage status files."""

import argparse
import csv
import os
from pathlib import Path


STAGE_ORDER = [
    "validation",
    "phenotype_response",
    "phylo_hypothesis",
    "bulk_omics",
    "differential_omics",
    "orthology_projection",
    "gra_analysis",
    "phenotype_omics_integration",
    "candidate_prioritization",
    "functional_interpretation",
    "final_report",
]

SUMMARY_FIELDS = ["record_type", "stage", "key", "status", "value", "message"]
MANIFEST_FIELDS = ["relative_path", "stage", "output_type", "size_bytes", "status"]

FINAL_ARTIFACTS = [
    "final/report/came_final_report.html",
    "final/report/came_final_report.md",
    "final/release_checks/came_release_checks.tsv",
    "final/release_checks/came_release_summary.tsv",
    "final/release_checks/came_release_status.txt",
]

PREFIX_STAGE = [
    ("validation/", "validation"),
    ("phenotype/", "phenotype_response"),
    ("phylo/", "phylo_hypothesis"),
    ("hypotheses/", "phylo_hypothesis"),
    ("omics/", "bulk_omics"),
    ("rnaseq/", "bulk_omics"),
    ("atacseq/", "bulk_omics"),
    ("differential_omics/", "differential_omics"),
    ("orthology/", "orthology_projection"),
    ("gra/", "gra_analysis"),
    ("integration/", "phenotype_omics_integration"),
    ("candidates/", "candidate_prioritization"),
    ("interpretation/", "functional_interpretation"),
    ("final/", "final_report"),
    ("all/stage_status/", "all_status"),
]


def norm(value):
    return str(value or "").strip()


def parse_bool(value):
    return str(value).strip().lower() in {"1", "true", "yes", "y"}


def read_tsv(path):
    if not path.is_file():
        return []
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle, delimiter="\t"))


def write_tsv(path, fields, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, delimiter="\t", extrasaction="ignore", quoting=csv.QUOTE_NONE, escapechar="\\", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def infer_stage_from_status_file(path):
    name = path.name
    if name.endswith("_status.tsv"):
        return name[: -len("_status.tsv")]
    return ""


def status_file_map(args, outdir):
    files = [Path(item) for item in args.status_file]
    if files:
        mapped = {}
        for path in files:
            rows = read_tsv(path)
            stage = norm(rows[0].get("stage")) if rows else infer_stage_from_status_file(path)
            if stage:
                mapped[stage] = path
        return {stage: mapped.get(stage) for stage in STAGE_ORDER}
    status_dir = Path(args.stage_status_dir) if args.stage_status_dir else outdir / "all" / "stage_status"
    return {stage: status_dir / f"{stage}_status.tsv" for stage in STAGE_ORDER}


def stage_from_path(relative_path):
    text = relative_path.as_posix()
    for prefix, stage in PREFIX_STAGE:
        if text.startswith(prefix):
            return stage
    return "unclassified"


def output_type_from_path(relative_path):
    text = relative_path.as_posix()
    if "/summary/" in text or text.endswith("_summary.tsv"):
        return "summary"
    if "/manifest/" in text or text.endswith("_manifest.tsv"):
        return "manifest"
    if "/report/" in text or text.endswith(".html") or text.endswith(".md"):
        return "report"
    if "/release_checks/" in text:
        return "release_check"
    if "/stage_status/" in text:
        return "stage_status"
    return "data"


def iter_manifest_files(outdir):
    skip_dirs = {".git", ".nextflow", "work", "__pycache__"}
    if not outdir.exists():
        return
    for root, dirs, files in os.walk(outdir):
        root_path = Path(root)
        dirs[:] = [dirname for dirname in dirs if dirname not in skip_dirs and not dirname.startswith(".")]
        for filename in files:
            if filename.startswith("."):
                continue
            path = root_path / filename
            if path.is_file():
                yield path


def collect_manifest(outdir):
    rows = []
    for path in sorted(iter_manifest_files(outdir) or []):
        rel = path.relative_to(outdir)
        rows.append(
            {
                "relative_path": rel.as_posix(),
                "stage": stage_from_path(rel),
                "output_type": output_type_from_path(rel),
                "size_bytes": str(path.stat().st_size),
                "status": "present",
            }
        )
    return rows


def release_counts(outdir):
    path = outdir / "final" / "release_checks" / "came_release_summary.tsv"
    counts = {}
    for row in read_tsv(path):
        status = norm(row.get("status"))
        count = norm(row.get("count"))
        if status:
            try:
                counts[status] = int(float(count or 0))
            except ValueError:
                counts[status] = 0
    return counts


def summarize(args):
    outdir = Path(args.outdir).resolve()
    rows = []
    all_complete = True
    status_paths = status_file_map(args, outdir)
    for stage in STAGE_ORDER:
        path = status_paths.get(stage)
        status_rows = read_tsv(path) if path else []
        if not status_rows:
            status = "MISSING"
            expected = "0"
            present = "0"
            missing = "0"
            all_complete = False
        else:
            first = status_rows[0]
            status = norm(first.get("overall_status")) or "MISSING"
            expected = norm(first.get("expected_count"))
            present = norm(first.get("present_count"))
            missing = norm(first.get("missing_count"))
            all_complete = all_complete and status == "COMPLETE"
        rows.append(
            {
                "record_type": "stage",
                "stage": stage,
                "key": "stage_status",
                "status": status,
                "value": f"{present}/{expected}",
                "message": f"missing={missing}",
            }
        )

    for rel_path in FINAL_ARTIFACTS:
        present = (outdir / rel_path).is_file() and (outdir / rel_path).stat().st_size > 0
        rows.append(
            {
                "record_type": "final_artifact",
                "stage": "final_report",
                "key": rel_path,
                "status": "present" if present else "missing",
                "value": str((outdir / rel_path).stat().st_size) if present else "0",
                "message": "",
            }
        )
        all_complete = all_complete and present

    counts = release_counts(outdir)
    for status in sorted(counts):
        rows.append(
            {
                "record_type": "release_check",
                "stage": "final_report",
                "key": status,
                "status": status,
                "value": str(counts[status]),
                "message": "count from came_release_summary.tsv",
            }
        )
    if counts.get("ERROR", 0) > 0:
        all_complete = False

    reuse_message = "stages are always scheduled; use Nextflow -resume for process-level reuse"
    if not parse_bool(args.resume_completed_stages):
        reuse_message = "resume_completed_stages=false requested; stage-level skipping is not implemented"
    rows.append(
        {
            "record_type": "overall",
            "stage": "all",
            "key": "all_run_status",
            "status": "COMPLETE" if all_complete else "ERROR",
            "value": "resume_completed_stages=" + str(args.resume_completed_stages).lower(),
            "message": reuse_message,
        }
    )
    return rows, collect_manifest(outdir)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--outdir", required=True)
    parser.add_argument("--stage_status_dir", default="")
    parser.add_argument("--status_file", action="append", default=[])
    parser.add_argument("--output_dir", required=True)
    parser.add_argument("--resume_completed_stages", default="true")
    args = parser.parse_args(argv)

    summary, manifest = summarize(args)
    output_dir = Path(args.output_dir)
    write_tsv(output_dir / "came_all_run_summary.tsv", SUMMARY_FIELDS, summary)
    write_tsv(output_dir / "came_all_outputs_manifest.tsv", MANIFEST_FIELDS, manifest)
    overall = next(row for row in summary if row["record_type"] == "overall")
    print(f"CAME all-run summary: status={overall['status']} outputs={len(manifest)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
