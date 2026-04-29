#!/usr/bin/env python3
"""Validate Stage 27 WGS small-variant output contracts."""

from __future__ import annotations

import argparse
import csv
import gzip
import os
import sys
from pathlib import Path


MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}
ISSUE_FIELDS = ["severity", "source", "field", "sample_id", "message"]
REQUIRED_QC_COLUMNS = [
    "sample_id",
    "species",
    "reference_id",
    "mapped_reads",
    "duplicate_rate",
    "mean_coverage",
    "breadth_10x",
    "insert_size_median",
    "n_variants",
    "n_snps",
    "n_indels",
    "bqsr_applied",
    "calling_mode",
    "joint_genotyping",
    "mode",
]
SYNTHETIC_MARKERS = [b"CAME_WGS_STUB", b"mode=stub", b"stub contract"]


def norm(value: object) -> str:
    text = str(value if value is not None else "").strip()
    return "" if text.lower() in MISSING_VALUES else text


def add(issues: list[dict[str, str]], severity: str, source: str, field: str, sample_id: str, message: str) -> None:
    issues.append({"severity": severity, "source": source, "field": field or "", "sample_id": sample_id or "", "message": message})


def read_table(path: str, issues: list[dict[str, str]], source: str) -> tuple[list[str], list[dict[str, str]]]:
    if not path or not os.path.exists(path):
        add(issues, "ERROR", source, "path", "", f"File does not exist: {path}")
        return [], []
    if os.path.getsize(path) == 0:
        add(issues, "ERROR", source, "path", "", f"File is empty: {path}")
        return [], []
    try:
        with open(path, newline="") as handle:
            reader = csv.DictReader(handle, delimiter="\t")
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


def sample_key(row: dict[str, str]) -> str:
    return norm(row.get("sample_key")) or norm(row.get("sample_id"))


def manifest_rows(manifest: str, issues: list[dict[str, str]]) -> list[dict[str, str]]:
    _, rows = read_table(manifest, issues, "manifest")
    return [row for row in rows if norm(row.get("omics_type")) == "wgs" or norm(row.get("assay")) == "wgs"]


def has_synthetic_marker(path: Path) -> bool:
    if not path.exists():
        return False
    try:
        data = path.read_bytes()[:65536]
    except Exception:
        return False
    return any(marker in data for marker in SYNTHETIC_MARKERS)


def open_vcf(path: Path):
    if path.suffix == ".gz":
        return gzip.open(path, "rt")
    return path.open()


def vcf_has_synthetic_marker(path: Path) -> bool:
    try:
        with open_vcf(path) as handle:
            text = handle.read(65536)
    except Exception:
        return False
    return any(marker.decode("utf-8", errors="ignore") in text for marker in SYNTHETIC_MARKERS)


def validate_bam(row: dict[str, str], bam_dir: str, mode: str, issues: list[dict[str, str]]) -> None:
    sid = norm(row.get("sample_id"))
    skey = sample_key(row)
    bam = Path(bam_dir) / f"{skey}.bam"
    bai = Path(bam_dir) / f"{skey}.bam.bai"
    if not bam.exists():
        add(issues, "ERROR", "bam", "path", sid, f"Missing BAM: {bam}")
    elif bam.stat().st_size == 0:
        add(issues, "ERROR", "bam", "path", sid, f"Empty BAM: {bam}")
    elif mode == "real" and has_synthetic_marker(bam):
        add(issues, "ERROR", "bam", "mode", sid, f"Synthetic/stub BAM marker found in real mode: {bam}")
    if not bai.exists():
        add(issues, "ERROR", "bam", "index", sid, f"Missing BAM index: {bai}")
    elif bai.stat().st_size == 0:
        add(issues, "ERROR", "bam", "index", sid, f"Empty BAM index: {bai}")


def validate_vcf(row: dict[str, str], variants_dir: str, mode: str, issues: list[dict[str, str]]) -> None:
    sid = norm(row.get("sample_id"))
    skey = sample_key(row)
    vcf = Path(variants_dir) / f"{skey}.vcf.gz"
    tbi = Path(str(vcf) + ".tbi")
    idx = Path(str(vcf) + ".idx")
    if not vcf.exists():
        add(issues, "ERROR", "vcf", "path", sid, f"Missing VCF: {vcf}")
        return
    if vcf.stat().st_size == 0:
        add(issues, "ERROR", "vcf", "path", sid, f"Empty VCF: {vcf}")
        return
    if mode == "real" and (has_synthetic_marker(vcf) or vcf_has_synthetic_marker(vcf)):
        add(issues, "ERROR", "vcf", "mode", sid, f"Synthetic/stub VCF marker found in real mode: {vcf}")
    if not ((tbi.exists() and tbi.stat().st_size > 0) or (idx.exists() and idx.stat().st_size > 0)):
        add(issues, "ERROR", "vcf", "index", sid, f"Missing VCF index: {tbi} or {idx}")
    try:
        with open_vcf(vcf) as handle:
            first = handle.readline().rstrip("\n")
            if not first.startswith("##fileformat"):
                add(issues, "ERROR", "vcf", "header", sid, "VCF header does not begin with ##fileformat")
            header = ""
            for line in handle:
                if line.startswith("#CHROM"):
                    header = line.rstrip("\n")
                    break
            if not header:
                add(issues, "ERROR", "vcf", "header", sid, "VCF #CHROM header is absent")
            else:
                parts = header.split("\t")
                if len(parts) < 10:
                    add(issues, "ERROR", "vcf", "samples", sid, "VCF sample columns are absent")
                elif sid not in parts[9:]:
                    add(issues, "ERROR", "vcf", "samples", sid, f"VCF sample column is absent for sample_id: {sid}")
    except Exception as exc:
        add(issues, "ERROR", "vcf", "read", sid, f"Could not read VCF: {exc}")


def validate_qc(path: str, samples: list[str], mode: str, issues: list[dict[str, str]]) -> None:
    fields, rows = read_table(path, issues, "variant_qc")
    if not fields:
        return
    missing = [field for field in REQUIRED_QC_COLUMNS if field not in fields]
    if missing:
        add(issues, "ERROR", "variant_qc", "header", "", f"Missing required column(s): {', '.join(missing)}")
    rows_by_sample = {norm(row.get("sample_id")): row for row in rows if norm(row.get("sample_id"))}
    for sample_id in samples:
        if sample_id not in rows_by_sample:
            add(issues, "ERROR", "variant_qc", "sample_id", sample_id, f"variant_qc row is absent for sample: {sample_id}")
    if mode == "real":
        for row in rows:
            sid = norm(row.get("sample_id"))
            if norm(row.get("mode")) == "stub":
                add(issues, "ERROR", "variant_qc", "mode", sid, "variant_qc reports mode=stub during real-mode validation")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--bam_dir", required=True)
    parser.add_argument("--variants_dir", required=True)
    parser.add_argument("--variant_qc", required=True)
    parser.add_argument("--report", required=True)
    parser.add_argument("--mode", choices=["stub", "real"], default="real")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    issues: list[dict[str, str]] = []
    rows = manifest_rows(args.manifest, issues)
    samples = [norm(row.get("sample_id")) for row in rows if norm(row.get("sample_id"))]
    for row in rows:
        validate_bam(row, args.bam_dir, args.mode, issues)
        validate_vcf(row, args.variants_dir, args.mode, issues)
    validate_qc(args.variant_qc, samples, args.mode, issues)
    if not any(row["severity"] == "ERROR" for row in issues):
        add(issues, "INFO", "wgs_outputs", "", "", f"Validated WGS outputs for {len(samples)} sample(s)")
    write_tsv(args.report, issues)
    error_count = sum(1 for row in issues if row["severity"] == "ERROR")
    warning_count = sum(1 for row in issues if row["severity"] == "WARNING")
    print(f"CAME WGS output validation: ERROR={error_count} WARNING={warning_count}")
    return 1 if error_count else 0


if __name__ == "__main__":
    raise SystemExit(main())
