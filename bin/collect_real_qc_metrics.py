#!/usr/bin/env python3
"""Collect Stage 25 real-mode RNA-seq and ATAC-seq QC metrics."""

from __future__ import annotations

import argparse
import csv
import os
import sys
from pathlib import Path


MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}
WARNING_FIELDS = ["severity", "source", "metric", "sample_id", "message"]
RNA_QC_FIELDS = [
    "sample_id",
    "species",
    "omics_type",
    "condition",
    "timepoint",
    "reference_id",
    "strandedness",
    "bam",
    "bai",
    "bam_exists",
    "bam_nonempty",
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
    "status",
    "warnings",
]
FEATURECOUNTS_FIELDS = ["sample_id", "status", "reads"]
ATAC_QC_FIELDS = [
    "sample_id",
    "species",
    "omics_type",
    "condition",
    "timepoint",
    "reference_id",
    "read_layout",
    "bam",
    "bai",
    "bam_exists",
    "bam_nonempty",
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
    "fragment_mean",
    "fragment_sd",
    "status",
    "warnings",
]
LIBRARY_COMPLEXITY_FIELDS = [
    "sample_id",
    "total_reads",
    "mapped_reads",
    "duplicate_reads",
    "duplicate_fraction",
    "nrf",
    "pbc1",
    "pbc2",
    "status",
    "warnings",
]


def norm(value: object) -> str:
    text = str(value if value is not None else "").strip()
    return "" if text.lower() in MISSING_VALUES else text


def infer_delimiter(path: str) -> str:
    ext = os.path.splitext(path)[1].lower()
    if ext == ".tsv":
        return "\t"
    if ext == ".csv":
        return ","
    with open(path, newline="") as handle:
        sample = handle.read(min(65536, os.path.getsize(path)))
    return "\t" if sample.count("\t") > sample.count(",") else ","


def read_table(path: str) -> tuple[list[str], list[dict[str, str]]]:
    if not path or not os.path.exists(path):
        return [], []
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
    return fields, rows


def write_tsv(path: str, fields: list[str], rows: list[dict[str, str]]) -> None:
    if not path:
        return
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=fields,
            delimiter="\t",
            extrasaction="ignore",
            quoting=csv.QUOTE_NONE,
            escapechar="\\",
            lineterminator="\n",
        )
        writer.writeheader()
        writer.writerows(rows)


def add_warning(rows: list[dict[str, str]], source: str, metric: str, sample_id: str, message: str) -> None:
    rows.append(
        {
            "severity": "WARNING",
            "source": source,
            "metric": metric,
            "sample_id": sample_id,
            "message": message,
        }
    )


def to_int(value: object) -> int | None:
    text = norm(value).replace(",", "")
    if not text:
        return None
    try:
        return int(float(text))
    except ValueError:
        return None


def parse_percent(value: object) -> str:
    text = norm(value).replace("%", "")
    if not text:
        return ""
    try:
        return f"{float(text):.6f}"
    except ValueError:
        return ""


def format_fraction(numerator: int | None, denominator: int | None) -> str:
    if numerator is None or denominator in (None, 0):
        return ""
    return f"{numerator / denominator:.6f}"


def count_totals(counts_path: str, metadata_fields: set[str]) -> tuple[dict[str, int], int]:
    fields, rows = read_table(counts_path)
    sample_fields = [field for field in fields if field not in metadata_fields]
    totals = {field: 0 for field in sample_fields}
    for row in rows:
        for sample in sample_fields:
            value = norm(row.get(sample)) or "0"
            try:
                totals[sample] += int(float(value))
            except ValueError:
                pass
    return totals, len(rows)


def sample_rows(manifest: str, omics_type: str) -> list[dict[str, str]]:
    _, rows = read_table(manifest)
    return [row for row in rows if norm(row.get("omics_type")) == omics_type]


def sample_key(row: dict[str, str]) -> str:
    return norm(row.get("sample_key")) or norm(row.get("sample_id"))


def first_existing(paths: list[Path]) -> Path | None:
    for path in paths:
        if path.exists():
            return path
    return None


def parse_star_log(path: Path, sample_id: str, warnings: list[dict[str, str]]) -> dict[str, int | str]:
    metrics: dict[str, int | str] = {
        "total_reads": "",
        "uniquely_mapped_reads": "",
        "unique_mapping_rate": "",
        "multi_mapped_reads": "",
        "multi_mapping_rate": "",
    }
    if not path.exists():
        add_warning(warnings, "star", "star_log", sample_id, "STAR Log.final.out not found")
        return metrics
    for line in path.read_text(errors="replace").splitlines():
        parts = [part.strip() for part in line.split("|", 1)]
        if len(parts) != 2:
            continue
        label, value = parts
        if label == "Number of input reads":
            metrics["total_reads"] = str(to_int(value) or "")
        elif label == "Uniquely mapped reads number":
            metrics["uniquely_mapped_reads"] = str(to_int(value) or "")
        elif label == "Uniquely mapped reads %":
            metrics["unique_mapping_rate"] = parse_percent(value)
        elif label == "Number of reads mapped to multiple loci":
            metrics["multi_mapped_reads"] = str(to_int(value) or "")
        elif label == "% of reads mapped to multiple loci":
            metrics["multi_mapping_rate"] = parse_percent(value)
    rate = metrics.get("unique_mapping_rate")
    if rate:
        try:
            if float(str(rate)) < 50:
                add_warning(warnings, "star", "unique_mapping_rate", sample_id, "low unique mapping rate")
        except ValueError:
            pass
    return metrics


def parse_featurecounts_summary(path: Path) -> dict[str, int]:
    if not path.exists():
        return {}
    with path.open(newline="") as handle:
        reader = csv.reader(handle, delimiter="\t")
        try:
            header = next(reader)
        except StopIteration:
            return {}
        if len(header) < 2:
            return {}
        result: dict[str, int] = {}
        for row in reader:
            if len(row) < 2:
                continue
            value = to_int(row[1])
            if value is not None:
                result[norm(row[0])] = value
    return result


def collect_rna(args: argparse.Namespace) -> int:
    totals, n_features = count_totals(args.counts, {"feature_id", "feature_type", "annotation_id"})
    warnings: list[dict[str, str]] = []
    qc_rows: list[dict[str, str]] = []
    featurecounts_rows: list[dict[str, str]] = []
    for row in sample_rows(args.manifest, "rnaseq"):
        sid = row["sample_id"]
        skey = sample_key(row)
        bam = Path(args.bam_dir) / f"{skey}.bam"
        bai = Path(args.bam_dir) / f"{skey}.bam.bai"
        star_log = Path(args.logs_dir) / "star" / f"{skey}.Log.final.out"
        star_metrics = parse_star_log(star_log, sid, warnings)
        summary_path = first_existing(
            [
                Path(args.logs_dir) / "featurecounts" / f"{skey}.featureCounts.summary.tsv",
                Path(args.logs_dir) / "featurecounts" / f"{skey}.featureCounts.txt.summary",
                Path(args.counts).parent / f"{skey}.featureCounts.txt.summary",
            ]
        )
        fc_metrics: dict[str, int] = {}
        if summary_path:
            fc_metrics = parse_featurecounts_summary(summary_path)
        else:
            add_warning(warnings, "featurecounts", "summary", sid, "featureCounts summary not found")
        for status, reads in sorted(fc_metrics.items()):
            featurecounts_rows.append({"sample_id": sid, "status": status, "reads": str(reads)})
        assigned_reads = fc_metrics.get("Assigned")
        if assigned_reads is None:
            assigned_reads = totals.get(sid, 0)
        total_reads = to_int(star_metrics.get("total_reads"))
        assigned_fraction = format_fraction(assigned_reads, total_reads)
        if assigned_fraction:
            try:
                if float(assigned_fraction) < 0.05:
                    add_warning(warnings, "featurecounts", "assigned_fraction", sid, "low assigned fraction")
            except ValueError:
                pass
        elif assigned_reads == 0:
            add_warning(warnings, "featurecounts", "assigned_reads", sid, "low assigned reads")
        sample_warnings = [item["message"] for item in warnings if item["sample_id"] == sid]
        qc_rows.append(
            {
                "sample_id": sid,
                "species": norm(row.get("species")),
                "omics_type": "rnaseq",
                "condition": norm(row.get("condition")),
                "timepoint": norm(row.get("timepoint")),
                "reference_id": norm(row.get("reference_id")),
                "strandedness": norm(row.get("strandedness")),
                "bam": str(bam),
                "bai": str(bai),
                "bam_exists": str(bam.exists()).lower(),
                "bam_nonempty": str(bam.exists() and bam.stat().st_size > 0).lower(),
                "total_reads": str(star_metrics.get("total_reads", "")),
                "uniquely_mapped_reads": str(star_metrics.get("uniquely_mapped_reads", "")),
                "unique_mapping_rate": str(star_metrics.get("unique_mapping_rate", "")),
                "multi_mapped_reads": str(star_metrics.get("multi_mapped_reads", "")),
                "multi_mapping_rate": str(star_metrics.get("multi_mapping_rate", "")),
                "assigned_reads": str(assigned_reads if assigned_reads is not None else ""),
                "assigned_fraction": assigned_fraction,
                "mapping_rate": str(star_metrics.get("unique_mapping_rate", "")),
                "n_features": str(n_features),
                "total_counts": str(totals.get(sid, 0)),
                "status": "WARNING" if sample_warnings else "OK",
                "warnings": "; ".join(dict.fromkeys(sample_warnings)),
            }
        )
    write_tsv(args.output, RNA_QC_FIELDS, qc_rows)
    if args.featurecounts_summary_output:
        write_tsv(args.featurecounts_summary_output, FEATURECOUNTS_FIELDS, featurecounts_rows)
    if args.warnings_output:
        write_tsv(args.warnings_output, WARNING_FIELDS, warnings)
    return 0


def count_peak_rows(path: Path) -> int:
    if not path.exists():
        return 0
    return sum(1 for line in path.read_text(errors="replace").splitlines() if line.strip() and not line.startswith("#"))


def parse_flagstat(path: Path, sample_id: str, warnings: list[dict[str, str]]) -> dict[str, int | str]:
    metrics: dict[str, int | str] = {
        "total_reads": "",
        "mapped_reads": "",
        "duplicate_reads": "",
    }
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
    return metrics


def parse_idxstats(path: Path, mito_name: str, sample_id: str, warnings: list[dict[str, str]]) -> tuple[str, str]:
    if not path.exists():
        add_warning(warnings, "samtools", "idxstats", sample_id, "samtools idxstats not found")
        return "", ""
    if not mito_name:
        add_warning(warnings, "samtools", "mitochondrial_contig", sample_id, "mitochondrial contig unavailable")
        return "", ""
    total = 0
    mito = 0
    seen_mito = False
    for line in path.read_text(errors="replace").splitlines():
        parts = line.split("\t")
        if len(parts) < 4:
            continue
        chrom = parts[0]
        mapped = to_int(parts[2]) or 0
        total += mapped
        if chrom == mito_name:
            seen_mito = True
            mito += mapped
    if not seen_mito:
        add_warning(warnings, "samtools", "mitochondrial_contig", sample_id, f"mitochondrial contig not found in idxstats: {mito_name}")
        return "", ""
    fraction = mito / total if total else 0
    if fraction > 0.2:
        add_warning(warnings, "samtools", "mitochondrial_fraction", sample_id, "high mitochondrial fraction")
    return str(mito), f"{fraction:.6f}"


def parse_samtools_stats(path: Path) -> dict[str, str]:
    metrics = {"fragment_mean": "", "fragment_sd": ""}
    if not path.exists():
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
            metrics["fragment_mean"] = value
        elif label == "insert size standard deviation":
            metrics["fragment_sd"] = value
    return metrics


def collect_atac(args: argparse.Namespace) -> int:
    totals, n_features = count_totals(args.counts, {"feature_id", "feature_type", "chrom", "start", "end"})
    warnings: list[dict[str, str]] = []
    add_warning(warnings, "atacseq", "no_idr", "run", "IDR replicate concordance is not computed in v0.1")
    add_warning(warnings, "atacseq", "no_tss_enrichment", "run", "TSS enrichment is not computed in v0.1")
    add_warning(warnings, "atacseq", "bedtools_merge_consensus", "run", "Consensus peaks are generated with bedtools merge and should be treated as exploratory")
    qc_rows: list[dict[str, str]] = []
    complexity_rows: list[dict[str, str]] = []
    for row in sample_rows(args.manifest, "atacseq"):
        sid = row["sample_id"]
        skey = sample_key(row)
        bam = Path(args.bam_dir) / f"{skey}.bam"
        bai = Path(args.bam_dir) / f"{skey}.bam.bai"
        peaks = Path(args.peaks_dir) / f"{skey}_peaks.narrowPeak"
        flagstat = parse_flagstat(Path(args.logs_dir) / "samtools" / f"{skey}.flagstat.txt", sid, warnings)
        mito_reads, mito_fraction = parse_idxstats(
            Path(args.logs_dir) / "samtools" / f"{skey}.idxstats.tsv",
            norm(row.get("mitochondrial_name")),
            sid,
            warnings,
        )
        stats_metrics = parse_samtools_stats(Path(args.logs_dir) / "samtools" / f"{skey}.stats.txt")
        read_layout = norm(row.get("read_layout"))
        if read_layout == "single_end":
            add_warning(warnings, "atacseq", "read_layout", sid, "single-end ATAC")
        total_reads = to_int(flagstat.get("total_reads"))
        mapped_reads = to_int(flagstat.get("mapped_reads"))
        duplicate_reads = to_int(flagstat.get("duplicate_reads"))
        reads_in_peaks = totals.get(sid, 0)
        usable_reads = mapped_reads if mapped_reads is not None else reads_in_peaks
        if not usable_reads:
            add_warning(warnings, "atacseq", "usable_reads", sid, "low usable reads")
        duplicate_fraction = format_fraction(duplicate_reads, total_reads)
        frip = format_fraction(reads_in_peaks, usable_reads)
        if duplicate_reads is None:
            add_warning(warnings, "samtools", "duplicate_proxy", sid, "duplicate proxy unavailable")
        add_warning(warnings, "atacseq", "no_nrf_pbc", sid, "NRF/PBC metrics unavailable without position-level duplicate complexity output")
        sample_warnings = [item["message"] for item in warnings if item["sample_id"] == sid]
        qc_rows.append(
            {
                "sample_id": sid,
                "species": norm(row.get("species")),
                "omics_type": "atacseq",
                "condition": norm(row.get("condition")),
                "timepoint": norm(row.get("timepoint")),
                "reference_id": norm(row.get("reference_id")),
                "read_layout": read_layout,
                "bam": str(bam),
                "bai": str(bai),
                "bam_exists": str(bam.exists()).lower(),
                "bam_nonempty": str(bam.exists() and bam.stat().st_size > 0).lower(),
                "total_reads": str(total_reads if total_reads is not None else ""),
                "mapped_reads": str(mapped_reads if mapped_reads is not None else ""),
                "total_aligned_reads": str(mapped_reads if mapped_reads is not None else ""),
                "mitochondrial_reads": mito_reads,
                "mitochondrial_fraction": mito_fraction,
                "duplicate_reads": str(duplicate_reads if duplicate_reads is not None else ""),
                "duplicate_fraction": duplicate_fraction,
                "usable_reads": str(usable_reads if usable_reads is not None else ""),
                "n_peaks": str(count_peak_rows(peaks)),
                "n_consensus_peaks": str(n_features),
                "reads_in_peaks": str(reads_in_peaks),
                "frip": frip,
                "fragment_mean": stats_metrics["fragment_mean"],
                "fragment_sd": stats_metrics["fragment_sd"],
                "status": "WARNING" if sample_warnings else "OK",
                "warnings": "; ".join(dict.fromkeys(sample_warnings)),
            }
        )
        complexity_rows.append(
            {
                "sample_id": sid,
                "total_reads": str(total_reads if total_reads is not None else ""),
                "mapped_reads": str(mapped_reads if mapped_reads is not None else ""),
                "duplicate_reads": str(duplicate_reads if duplicate_reads is not None else ""),
                "duplicate_fraction": duplicate_fraction,
                "nrf": "",
                "pbc1": "",
                "pbc2": "",
                "status": "WARNING" if duplicate_reads is None else "OK",
                "warnings": "NRF/PBC metrics unavailable without position-level duplicate complexity output",
            }
        )
    write_tsv(args.output, ATAC_QC_FIELDS, qc_rows)
    if args.library_complexity_output:
        write_tsv(args.library_complexity_output, LIBRARY_COMPLEXITY_FIELDS, complexity_rows)
    if args.warnings_output:
        write_tsv(args.warnings_output, WARNING_FIELDS, warnings)
    return 0


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assay", required=True, choices=["rnaseq", "atacseq"])
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--counts", required=True)
    parser.add_argument("--bam_dir", required=True)
    parser.add_argument("--logs_dir", required=True)
    parser.add_argument("--peaks_dir", default="")
    parser.add_argument("--output", required=True)
    parser.add_argument("--featurecounts_summary_output", default="")
    parser.add_argument("--library_complexity_output", default="")
    parser.add_argument("--warnings_output", default="")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        if args.assay == "rnaseq":
            return collect_rna(args)
        return collect_atac(args)
    except Exception as exc:
        print(f"ERROR\tcollect_real_qc_metrics\t{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
