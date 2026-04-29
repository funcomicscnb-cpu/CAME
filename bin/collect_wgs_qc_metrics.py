#!/usr/bin/env python3
"""Collect Stage 27 WGS alignment and variant QC metrics."""

from __future__ import annotations

import argparse
import csv
import gzip
import os
import sys
from pathlib import Path


MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}
NA = "NA"
WARNING_FIELDS = ["severity", "source", "metric", "sample_id", "message"]
ALIGNMENT_FIELDS = [
    "sample_id",
    "species",
    "reference_id",
    "bam",
    "bai",
    "bam_exists",
    "bam_nonempty",
    "total_reads",
    "mapped_reads",
    "duplicate_reads",
    "duplicate_rate",
    "mean_coverage",
    "breadth_10x",
    "insert_size_median",
    "mode",
    "status",
    "warnings",
]
VARIANT_FIELDS = [
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
    "status",
    "warnings",
]


def norm(value: object) -> str:
    text = str(value if value is not None else "").strip()
    return "" if text.lower() in MISSING_VALUES else text


def read_table(path: str) -> tuple[list[str], list[dict[str, str]]]:
    with open(path, newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        fields = reader.fieldnames or []
        return fields, [dict(row) for row in reader]


def write_tsv(path: str, fields: list[str], rows: list[dict[str, str]]) -> None:
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, delimiter="\t", extrasaction="ignore", quoting=csv.QUOTE_NONE, escapechar="\\", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def add_warning(rows: list[dict[str, str]], source: str, metric: str, sample_id: str, message: str) -> None:
    rows.append({"severity": "WARNING", "source": source, "metric": metric, "sample_id": sample_id, "message": message})


def to_int(value: object) -> int | None:
    text = norm(value).replace(",", "")
    if not text:
        return None
    try:
        return int(float(text))
    except ValueError:
        return None


def to_float(value: object) -> float | None:
    text = norm(value).replace("%", "")
    if not text:
        return None
    try:
        return float(text)
    except ValueError:
        return None


def fmt_fraction(numerator: int | None, denominator: int | None) -> str:
    if numerator is None or denominator in (None, 0):
        return NA
    return f"{numerator / denominator:.6f}"


def sample_key(row: dict[str, str]) -> str:
    return norm(row.get("sample_key")) or norm(row.get("sample_id"))


def sample_rows(manifest: str) -> list[dict[str, str]]:
    _, rows = read_table(manifest)
    return [row for row in rows if norm(row.get("omics_type")) == "wgs" or norm(row.get("assay")) == "wgs"]


def parse_flagstat(path: Path, sample_id: str, warnings: list[dict[str, str]]) -> dict[str, str]:
    metrics = {"total_reads": NA, "mapped_reads": NA, "duplicate_reads": NA}
    if not path.exists():
        add_warning(warnings, "samtools", "flagstat", sample_id, "samtools flagstat not found")
        return metrics
    for line in path.read_text(errors="replace").splitlines():
        value = to_int(line.split("+", 1)[0])
        if value is None:
            continue
        if " in total " in line:
            metrics["total_reads"] = str(value)
        elif " mapped (" in line and "mate" not in line:
            metrics["mapped_reads"] = str(value)
        elif "duplicates" in line:
            metrics["duplicate_reads"] = str(value)
    for key, value in metrics.items():
        if value == NA:
            add_warning(warnings, "samtools", key, sample_id, f"{key} unavailable from flagstat")
    return metrics


def parse_stats(path: Path, sample_id: str, warnings: list[dict[str, str]]) -> dict[str, str]:
    metrics = {"insert_size_median": NA}
    if not path.exists():
        add_warning(warnings, "samtools", "stats", sample_id, "samtools stats not found")
        return metrics
    for line in path.read_text(errors="replace").splitlines():
        if not line.startswith("SN\t"):
            continue
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        label = parts[1].rstrip(":")
        value = norm(parts[2])
        if label == "insert size average":
            metrics["insert_size_median"] = value or NA
    if metrics["insert_size_median"] == NA:
        add_warning(warnings, "samtools", "insert_size_median", sample_id, "insert size unavailable from samtools stats")
    return metrics


def parse_coverage(path: Path, sample_id: str, warnings: list[dict[str, str]]) -> dict[str, str]:
    metrics = {"mean_coverage": NA, "breadth_10x": NA}
    if not path.exists():
        add_warning(warnings, "samtools", "coverage", sample_id, "samtools coverage not found")
        return metrics
    total_length = 0
    weighted_depth = 0.0
    breadth_lengths = []
    with path.open() as handle:
        reader = csv.DictReader((line for line in handle if line.strip()), delimiter="\t")
        if reader.fieldnames:
            reader.fieldnames = [field.lstrip("#") for field in reader.fieldnames]
        for row in reader:
            start = to_int(row.get("startpos"))
            end = to_int(row.get("endpos"))
            length = (end - start + 1) if start is not None and end is not None and end >= start else 0
            depth = to_float(row.get("meandepth"))
            coverage_pct = to_float(row.get("coverage"))
            if length and depth is not None:
                total_length += length
                weighted_depth += depth * length
            if coverage_pct is not None:
                breadth_lengths.append(coverage_pct / 100.0)
    if total_length:
        metrics["mean_coverage"] = f"{weighted_depth / total_length:.6f}"
    else:
        add_warning(warnings, "samtools", "mean_coverage", sample_id, "mean coverage unavailable")
    if breadth_lengths:
        # samtools coverage reports breadth at >=1x. Stage 27 does not infer 10x breadth without depth histograms.
        metrics["breadth_10x"] = NA
        add_warning(warnings, "samtools", "breadth_10x", sample_id, "breadth_10x unavailable from samtools coverage output")
    else:
        add_warning(warnings, "samtools", "breadth_10x", sample_id, "breadth_10x unavailable")
    return metrics


def open_vcf(path: Path):
    if path.suffix == ".gz":
        return gzip.open(path, "rt")
    return path.open()


def variant_counts(path: Path, sample_id: str, warnings: list[dict[str, str]]) -> dict[str, str]:
    counts = {"n_variants": NA, "n_snps": NA, "n_indels": NA}
    if not path.exists() or path.stat().st_size == 0:
        add_warning(warnings, "gatk", "vcf", sample_id, f"VCF not found or empty: {path}")
        return counts
    n_variants = 0
    n_snps = 0
    n_indels = 0
    try:
        with open_vcf(path) as handle:
            for line in handle:
                if not line or line.startswith("#"):
                    continue
                parts = line.rstrip("\n").split("\t")
                if len(parts) < 5:
                    continue
                ref = parts[3]
                alts = [alt for alt in parts[4].split(",") if alt and alt != "."]
                if not alts:
                    continue
                n_variants += 1
                if all(len(ref) == 1 and len(alt) == 1 for alt in alts):
                    n_snps += 1
                elif any(len(ref) != len(alt) for alt in alts):
                    n_indels += 1
    except Exception as exc:
        add_warning(warnings, "gatk", "vcf", sample_id, f"Could not parse VCF: {exc}")
        return counts
    return {"n_variants": str(n_variants), "n_snps": str(n_snps), "n_indels": str(n_indels)}


def collect(args: argparse.Namespace) -> int:
    warnings: list[dict[str, str]] = []
    alignment_rows: list[dict[str, str]] = []
    variant_rows: list[dict[str, str]] = []
    for row in sample_rows(args.manifest):
        sid = norm(row.get("sample_id"))
        skey = sample_key(row)
        mode = norm(row.get("wgs_mode")) or args.mode
        bam = Path(args.bam_dir) / f"{skey}.bam"
        bai = Path(args.bam_dir) / f"{skey}.bam.bai"
        vcf = Path(args.variants_dir) / f"{skey}.vcf.gz"
        flagstat = parse_flagstat(Path(args.logs_dir) / "samtools" / f"{skey}.flagstat.txt", sid, warnings)
        stats = parse_stats(Path(args.logs_dir) / "samtools" / f"{skey}.stats.txt", sid, warnings)
        coverage = parse_coverage(Path(args.logs_dir) / "samtools" / f"{skey}.coverage.tsv", sid, warnings)
        variants = variant_counts(vcf, sid, warnings)
        add_warning(
            warnings,
            "wgs",
            "bqsr_applied",
            sid,
            "BQSR is not applied in v0.1; variants use hard-filtering/no-BQSR fallback",
        )
        add_warning(
            warnings,
            "wgs",
            "joint_genotyping",
            sid,
            "Joint genotyping is not performed in v0.1; calling_mode is per_sample",
        )
        total_reads = to_int(flagstat["total_reads"])
        duplicate_reads = to_int(flagstat["duplicate_reads"])
        duplicate_rate = fmt_fraction(duplicate_reads, total_reads)
        sample_warnings = [item["message"] for item in warnings if item["sample_id"] == sid]
        common = {
            "sample_id": sid,
            "species": norm(row.get("species")),
            "reference_id": norm(row.get("reference_id")),
            "mapped_reads": flagstat["mapped_reads"],
            "duplicate_rate": duplicate_rate,
            "mean_coverage": coverage["mean_coverage"],
            "breadth_10x": coverage["breadth_10x"],
            "insert_size_median": stats["insert_size_median"],
            "bqsr_applied": "false",
            "calling_mode": "per_sample",
            "joint_genotyping": "false",
            "mode": mode,
            "status": "WARNING" if sample_warnings else "OK",
            "warnings": "; ".join(dict.fromkeys(sample_warnings)),
        }
        alignment_rows.append(
            {
                **common,
                "bam": str(bam),
                "bai": str(bai),
                "bam_exists": str(bam.exists()).lower(),
                "bam_nonempty": str(bam.exists() and bam.stat().st_size > 0).lower(),
                "total_reads": flagstat["total_reads"],
                "duplicate_reads": flagstat["duplicate_reads"],
            }
        )
        variant_rows.append({**common, **variants})
    write_tsv(args.alignment_output, ALIGNMENT_FIELDS, alignment_rows)
    write_tsv(args.variant_output, VARIANT_FIELDS, variant_rows)
    if args.warnings_output:
        write_tsv(args.warnings_output, WARNING_FIELDS, warnings)
    print(f"CAME WGS QC metrics: samples={len(alignment_rows)} warnings={len(warnings)}")
    return 0


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--bam_dir", required=True)
    parser.add_argument("--variants_dir", required=True)
    parser.add_argument("--logs_dir", required=True)
    parser.add_argument("--alignment_output", required=True)
    parser.add_argument("--variant_output", required=True)
    parser.add_argument("--warnings_output", default="")
    parser.add_argument("--mode", choices=["stub", "real"], default="real")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    try:
        return collect(parse_args(argv))
    except Exception as exc:
        print(f"ERROR\tcollect_wgs_qc_metrics\t{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
