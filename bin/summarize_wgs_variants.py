#!/usr/bin/env python3
"""Summarize Stage 27 WGS small-variant outputs."""

from __future__ import annotations

import argparse
import csv
import os
import sys
from pathlib import Path


MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}
SUMMARY_FIELDS = [
    "sample_id",
    "species",
    "reference_id",
    "mode",
    "status",
    "n_variants",
    "n_snps",
    "n_indels",
    "bqsr_applied",
    "calling_mode",
    "joint_genotyping",
    "bam",
    "bai",
    "vcf",
    "vcf_index",
    "warnings",
]
MANIFEST_FIELDS = ["sample_id", "output_type", "path", "exists", "mode", "description"]


def norm(value: object) -> str:
    text = str(value if value is not None else "").strip()
    return "" if text.lower() in MISSING_VALUES else text


def read_table(path: str) -> tuple[list[str], list[dict[str, str]]]:
    if not path or not os.path.exists(path):
        return [], []
    with open(path, newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        return reader.fieldnames or [], [dict(row) for row in reader]


def write_tsv(path: Path, fields: list[str], rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, delimiter="\t", extrasaction="ignore", quoting=csv.QUOTE_NONE, escapechar="\\", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def sample_key(row: dict[str, str]) -> str:
    return norm(row.get("sample_key")) or norm(row.get("sample_id"))


def rows_by_sample(rows: list[dict[str, str]]) -> dict[str, dict[str, str]]:
    return {norm(row.get("sample_id")): row for row in rows if norm(row.get("sample_id"))}


def existing_index(vcf: Path) -> Path:
    tbi = Path(str(vcf) + ".tbi")
    idx = Path(str(vcf) + ".idx")
    if tbi.exists():
        return tbi
    return idx


def warning_text(warnings: list[dict[str, str]], sample_id: str) -> str:
    messages = []
    for row in warnings:
        sid = norm(row.get("sample_id"))
        if sid and sid != sample_id:
            continue
        message = norm(row.get("message"))
        if message:
            messages.append(message)
    return "; ".join(dict.fromkeys(messages))


def add_manifest(rows: list[dict[str, str]], sample_id: str, output_type: str, path: Path, mode: str, description: str) -> None:
    rows.append(
        {
            "sample_id": sample_id,
            "output_type": output_type,
            "path": str(path),
            "exists": "true" if path.exists() and path.stat().st_size > 0 else "false",
            "mode": mode,
            "description": description,
        }
    )


def summarize(args: argparse.Namespace) -> int:
    _, manifest_rows = read_table(args.manifest)
    _, alignment_qc = read_table(args.alignment_qc)
    _, variant_qc = read_table(args.variant_qc)
    _, warning_rows = read_table(args.warnings)
    alignment_by_sample = rows_by_sample(alignment_qc)
    variant_by_sample = rows_by_sample(variant_qc)
    summary_rows: list[dict[str, str]] = []
    output_rows: list[dict[str, str]] = []
    errors = 0
    for row in manifest_rows:
        if norm(row.get("omics_type")) != "wgs" and norm(row.get("assay")) != "wgs":
            continue
        sid = norm(row.get("sample_id"))
        skey = sample_key(row)
        mode = norm(row.get("wgs_mode")) or args.mode
        bam = Path(args.bam_dir) / f"{skey}.bam"
        bai = Path(args.bam_dir) / f"{skey}.bam.bai"
        vcf = Path(args.variants_dir) / f"{skey}.vcf.gz"
        vcf_index = existing_index(vcf)
        sample_warnings = warning_text(warning_rows, sid)
        variant_row = variant_by_sample.get(sid, {})
        status = norm(variant_row.get("status")) or norm(alignment_by_sample.get(sid, {}).get("status")) or "OK"
        for path in [bam, bai, vcf, vcf_index]:
            if not path.exists() or path.stat().st_size == 0:
                status = "ERROR"
                errors += 1
        summary_rows.append(
            {
                "sample_id": sid,
                "species": norm(row.get("species")),
                "reference_id": norm(row.get("reference_id")),
                "mode": mode,
                "status": status,
                "n_variants": norm(variant_row.get("n_variants")) or "NA",
                "n_snps": norm(variant_row.get("n_snps")) or "NA",
                "n_indels": norm(variant_row.get("n_indels")) or "NA",
                "bqsr_applied": norm(variant_row.get("bqsr_applied")) or "false",
                "calling_mode": norm(variant_row.get("calling_mode")) or "per_sample",
                "joint_genotyping": norm(variant_row.get("joint_genotyping")) or "false",
                "bam": str(bam),
                "bai": str(bai),
                "vcf": str(vcf),
                "vcf_index": str(vcf_index),
                "warnings": sample_warnings or norm(variant_row.get("warnings")),
            }
        )
        add_manifest(output_rows, sid, "bam", bam, mode, "Coordinate-sorted WGS alignment BAM")
        add_manifest(output_rows, sid, "bai", bai, mode, "BAM index")
        add_manifest(output_rows, sid, "vcf", vcf, mode, "WGS SNP/indel VCF")
        add_manifest(output_rows, sid, "vcf_index", vcf_index, mode, "VCF index")
    write_tsv(Path(args.output_dir) / "wgs_variant_summary.tsv", SUMMARY_FIELDS, summary_rows)
    write_tsv(Path(args.output_dir) / "wgs_outputs_manifest.tsv", MANIFEST_FIELDS, output_rows)
    print(f"CAME WGS variant summary: ERROR={errors} samples={len(summary_rows)}")
    return 1 if errors else 0


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--bam_dir", required=True)
    parser.add_argument("--variants_dir", required=True)
    parser.add_argument("--alignment_qc", required=True)
    parser.add_argument("--variant_qc", required=True)
    parser.add_argument("--warnings", default="")
    parser.add_argument("--output_dir", required=True)
    parser.add_argument("--mode", choices=["stub", "real"], default="real")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    try:
        return summarize(parse_args(argv))
    except Exception as exc:
        print(f"ERROR\tsummarize_wgs_variants\t{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
