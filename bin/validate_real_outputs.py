#!/usr/bin/env python3
"""Validate Stage 25 real-mode RNA-seq and ATAC-seq outputs."""

from __future__ import annotations

import argparse
import csv
import os
import sys
from pathlib import Path


MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}
ISSUE_FIELDS = ["severity", "source", "field", "sample_id", "message"]
QC_REQUIRED_FIELDS = {
    "rnaseq": [
        "sample_id",
        "strandedness",
        "total_reads",
        "uniquely_mapped_reads",
        "multi_mapped_reads",
        "assigned_reads",
        "assigned_fraction",
        "status",
        "warnings",
    ],
    "atacseq": [
        "sample_id",
        "read_layout",
        "total_reads",
        "mapped_reads",
        "mitochondrial_reads",
        "mitochondrial_fraction",
        "duplicate_reads",
        "usable_reads",
        "n_peaks",
        "reads_in_peaks",
        "frip",
        "tss_reads",
        "tss_enrichment",
        "status",
        "warnings",
    ],
}
QC_NUMERIC_FIELDS = {
    "rnaseq": [
        "total_reads",
        "uniquely_mapped_reads",
        "unique_mapping_rate",
        "multi_mapped_reads",
        "multi_mapping_rate",
        "assigned_reads",
        "assigned_fraction",
        "mapping_rate",
        "n_features",
        "total_counts",
    ],
    "atacseq": [
        "total_reads",
        "mapped_reads",
        "total_aligned_reads",
        "mitochondrial_reads",
        "mitochondrial_fraction",
        "duplicate_reads",
        "duplicate_fraction",
        "usable_reads",
        "n_peaks",
        "n_consensus_peaks",
        "reads_in_peaks",
        "frip",
        "tss_reads",
        "tss_enrichment",
        "fragment_mean",
        "fragment_sd",
    ],
}


def norm(value: object) -> str:
    text = str(value if value is not None else "").strip()
    return "" if text.lower() in MISSING_VALUES else text


def add(issues: list[dict[str, str]], severity: str, source: str, field: str, sample_id: str, message: str) -> None:
    issues.append(
        {
            "severity": severity,
            "source": source,
            "field": field or "",
            "sample_id": sample_id or "",
            "message": message,
        }
    )


def infer_delimiter(path: str) -> str:
    ext = os.path.splitext(path)[1].lower()
    if ext == ".tsv":
        return "\t"
    if ext == ".csv":
        return ","
    with open(path, newline="") as handle:
        sample = handle.read(min(65536, os.path.getsize(path)))
    return "\t" if sample.count("\t") > sample.count(",") else ","


def read_table(path: str, issues: list[dict[str, str]], source: str) -> tuple[list[str], list[dict[str, str]]]:
    if not path or not os.path.exists(path):
        add(issues, "ERROR", source, "path", "", f"File does not exist: {path}")
        return [], []
    if os.path.getsize(path) == 0:
        add(issues, "ERROR", source, "path", "", f"File is empty: {path}")
        return [], []
    try:
        delimiter = infer_delimiter(path)
        with open(path, newline="") as handle:
            reader = csv.DictReader(handle, delimiter=delimiter)
            raw_fields = reader.fieldnames or []
            fields = [norm(field) for field in raw_fields]
            rows = []
            for row in reader:
                cleaned = {}
                for raw_field, field in zip(raw_fields, fields):
                    cleaned[field] = norm(row.get(raw_field))
                rows.append(cleaned)
    except Exception as exc:
        add(issues, "ERROR", source, "read", "", f"Could not read table: {exc}")
        return [], []
    if not fields:
        add(issues, "ERROR", source, "header", "", "Table has no header")
    return fields, rows


def write_tsv(path: str, rows: list[dict[str, str]]) -> None:
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=ISSUE_FIELDS, delimiter="\t", extrasaction="ignore", quoting=csv.QUOTE_NONE, escapechar="\\", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def manifest_rows(manifest: str, omics_type: str, issues: list[dict[str, str]]) -> list[dict[str, str]]:
    _, rows = read_table(manifest, issues, "manifest")
    return [row for row in rows if norm(row.get("omics_type")) == omics_type and norm(row.get("sample_id"))]


def sample_ids(rows: list[dict[str, str]]) -> list[str]:
    return [norm(row.get("sample_id")) for row in rows]


def sample_key(row: dict[str, str]) -> str:
    return norm(row.get("sample_key")) or norm(row.get("sample_id"))


def validate_count_matrix(
    path: str,
    required_fields: list[str],
    samples: list[str],
    assay: str,
    issues: list[dict[str, str]],
) -> int:
    fields, rows = read_table(path, issues, "count_matrix")
    if not fields:
        return 0
    missing = [field for field in required_fields if field not in fields]
    if missing:
        add(issues, "ERROR", "count_matrix", "header", "", f"Missing required column(s): {', '.join(missing)}")
    for sample_id in samples:
        if sample_id not in fields:
            add(issues, "ERROR", "count_matrix", "sample_id", sample_id, f"Sample column is absent: {sample_id}")
    sample_fields = [field for field in fields if field not in required_fields]
    for row_number, row in enumerate(rows, start=2):
        for sample_id in sample_fields:
            value = norm(row.get(sample_id)) or "0"
            try:
                parsed = float(value)
            except ValueError:
                add(issues, "ERROR", "count_matrix", sample_id, sample_id, f"Non-numeric count at row {row_number}: {value}")
                continue
            if parsed < 0 or parsed != int(parsed):
                add(issues, "ERROR", "count_matrix", sample_id, sample_id, f"Non-integer count at row {row_number}: {value}")
    if assay == "rnaseq" and len(rows) == 0 and samples:
        add(issues, "ERROR", "count_matrix", "rows", "", "RNA gene count matrix has no feature rows")
    return len(rows)


def validate_bams(samples: list[dict[str, str]], bam_dir: str, issues: list[dict[str, str]]) -> None:
    for row in samples:
        sample_id = norm(row.get("sample_id"))
        skey = sample_key(row)
        bam = Path(bam_dir) / f"{skey}.bam"
        bai = Path(bam_dir) / f"{skey}.bam.bai"
        if not bam.exists():
            add(issues, "ERROR", "bam", "path", sample_id, f"Missing BAM: {bam}")
        elif bam.stat().st_size == 0:
            add(issues, "ERROR", "bam", "path", sample_id, f"Empty BAM: {bam}")
        if not bai.exists():
            add(issues, "ERROR", "bam", "index", sample_id, f"Missing BAM index: {bai}")


def validate_bed(path: str, source: str, issues: list[dict[str, str]], require_nonempty: bool = True) -> int:
    if not path or not os.path.exists(path):
        add(issues, "ERROR", source, "path", "", f"BED file does not exist: {path}")
        return 0
    count = 0
    with open(path) as handle:
        for line_number, line in enumerate(handle, start=1):
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) < 3:
                add(issues, "ERROR", source, "interval", "", f"Malformed BED row {line_number}: fewer than 3 columns")
                continue
            try:
                start = int(parts[1])
                end = int(parts[2])
            except ValueError:
                add(issues, "ERROR", source, "interval", "", f"Malformed BED row {line_number}: non-integer start/end")
                continue
            if start < 0 or end <= start:
                add(issues, "ERROR", source, "interval", "", f"Malformed BED row {line_number}: invalid interval")
            count += 1
    if require_nonempty and count == 0:
        add(issues, "ERROR", source, "rows", "", f"BED file has no intervals: {path}")
    return count


def validate_optional_table(path: str, source: str, required_fields: list[str], numeric_fields: list[str], issues: list[dict[str, str]]) -> None:
    if not path:
        return
    fields, rows = read_table(path, issues, source)
    if not fields:
        return
    missing = [field for field in required_fields if field not in fields]
    if missing:
        add(issues, "ERROR", source, "header", "", f"Missing required column(s): {', '.join(missing)}")
    for row_number, row in enumerate(rows, start=2):
        sample_id = norm(row.get("sample_id"))
        for field in numeric_fields:
            if field not in fields:
                continue
            value = norm(row.get(field))
            if not value:
                continue
            try:
                float(value)
            except ValueError:
                add(issues, "ERROR", source, field, sample_id, f"Non-numeric QC value at row {row_number}: {value}")


def validate_qc_table(path: str, assay: str, samples: list[str], issues: list[dict[str, str]]) -> None:
    if not path:
        return
    fields, rows = read_table(path, issues, "qc_table")
    if not fields:
        return
    missing = [field for field in QC_REQUIRED_FIELDS[assay] if field not in fields]
    if missing:
        add(issues, "ERROR", "qc_table", "header", "", f"Missing required column(s): {', '.join(missing)}")
    rows_by_sample = {norm(row.get("sample_id")): row for row in rows if norm(row.get("sample_id"))}
    for sample_id in samples:
        if sample_id not in rows_by_sample:
            add(issues, "ERROR", "qc_table", "sample_id", sample_id, f"QC row is absent for sample: {sample_id}")
    for row_number, row in enumerate(rows, start=2):
        sample_id = norm(row.get("sample_id"))
        status = norm(row.get("status"))
        if status and status not in {"OK", "WARNING", "ERROR"}:
            add(issues, "ERROR", "qc_table", "status", sample_id, f"Invalid QC status at row {row_number}: {status}")
        for field in QC_NUMERIC_FIELDS[assay]:
            if field not in fields:
                continue
            value = norm(row.get(field))
            if not value:
                continue
            try:
                float(value)
            except ValueError:
                add(issues, "ERROR", "qc_table", field, sample_id, f"Non-numeric QC value at row {row_number}: {value}")


def validate_peaks(samples: list[dict[str, str]], peaks_dir: str, consensus: str, issues: list[dict[str, str]]) -> None:
    total_peaks = 0
    for row in samples:
        path = os.path.join(peaks_dir, f"{sample_key(row)}_peaks.narrowPeak")
        total_peaks += validate_bed(path, "narrowPeak", issues, require_nonempty=False)
    if samples and total_peaks == 0:
        add(issues, "ERROR", "narrowPeak", "rows", "", "MACS3 emitted no peaks for all ATAC samples")
    validate_bed(consensus, "consensus_peaks", issues, require_nonempty=bool(samples))


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assay", required=True, choices=["rnaseq", "atacseq"])
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--counts", required=True)
    parser.add_argument("--bam_dir", required=True)
    parser.add_argument("--peaks_dir", default="")
    parser.add_argument("--consensus_peaks", default="")
    parser.add_argument("--qc", default="")
    parser.add_argument("--featurecounts_summary", default="")
    parser.add_argument("--library_complexity", default="")
    parser.add_argument("--report", required=True)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    issues: list[dict[str, str]] = []
    omics_type = args.assay
    sample_rows = manifest_rows(args.manifest, omics_type, issues)
    samples = sample_ids(sample_rows)
    if omics_type == "rnaseq":
        validate_count_matrix(args.counts, ["feature_id", "feature_type", "annotation_id"], samples, omics_type, issues)
    else:
        validate_count_matrix(args.counts, ["feature_id", "feature_type", "chrom", "start", "end"], samples, omics_type, issues)
    validate_bams(sample_rows, args.bam_dir, issues)
    if omics_type == "atacseq":
        validate_peaks(sample_rows, args.peaks_dir, args.consensus_peaks, issues)
    validate_qc_table(args.qc, omics_type, samples, issues)
    if omics_type == "rnaseq":
        validate_optional_table(
            args.featurecounts_summary,
            "featurecounts_summary",
            ["sample_id", "status", "reads"],
            ["reads"],
            issues,
        )
    if omics_type == "atacseq":
        validate_optional_table(
            args.library_complexity,
            "library_complexity",
            ["sample_id", "total_reads", "mapped_reads", "duplicate_reads", "duplicate_fraction", "status", "warnings"],
            ["total_reads", "mapped_reads", "duplicate_reads", "duplicate_fraction", "nrf", "pbc1", "pbc2"],
            issues,
        )
    if not any(row["severity"] == "ERROR" for row in issues):
        add(issues, "INFO", "real_outputs", "", "", f"Validated {omics_type} outputs for {len(samples)} sample(s)")
    write_tsv(args.report, issues)
    error_count = sum(1 for row in issues if row["severity"] == "ERROR")
    warning_count = sum(1 for row in issues if row["severity"] == "WARNING")
    print(f"CAME {omics_type} real-output validation: ERROR={error_count} WARNING={warning_count}")
    return 1 if error_count else 0


if __name__ == "__main__":
    raise SystemExit(main())
