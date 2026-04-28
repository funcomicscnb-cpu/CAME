#!/usr/bin/env python3
"""Prepare optional reference/WGS metadata for CAME reference preparation."""

import argparse
import csv
import os
import sys
from collections import Counter


MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}
PAIRED_LAYOUTS = {"paired", "paired-end", "paired_end", "pe"}
SINGLE_LAYOUTS = {"single", "single-end", "single_end", "se"}
ALLOWED_MASKING_STRATEGIES = {"label_only", "mask_problematic", "exclude_for_mutation_calling"}

REQUIRED_WGS_COLUMNS = [
    "sample_id",
    "species",
    "individual_id",
    "reference_id",
    "fastq_1",
    "read_layout",
]
REQUIRED_REFERENCE_COLUMNS = ["reference_id", "species", "genome_fasta"]
REQUIRED_CONFIG_COLUMNS = ["reference_id", "species", "masking_strategy"]

REFERENCE_PATH_FIELDS = [
    "genome_fasta",
    "gtf",
    "transcript_fasta",
    "star_index",
    "bwa_index",
    "chrom_sizes",
    "blacklist_bed",
    "repeatmasker_bed",
    "mappability_bed",
]
CONFIG_PATH_FIELDS = [
    "known_repeats_bed",
    "mappability_bed",
    "problematic_sites_bed",
    "cnv_regions_bed",
]
OUTPUT_FIELDS = [
    "sample_id",
    "species",
    "individual_id",
    "reference_id",
    "read_layout",
    "fastq_1",
    "fastq_2",
    "batch",
    "platform",
    "library_id",
    "coverage_estimate",
    "reference_genome_fasta",
    "reference_gtf",
    "reference_transcript_fasta",
    "reference_bwa_index",
    "reference_chrom_sizes",
    "reference_blacklist_bed",
    "reference_repeatmasker_bed",
    "reference_mappability_bed",
    "reference_annotation_version",
    "reference_source",
    "masking_strategy",
    "known_repeats_bed",
    "config_mappability_bed",
    "problematic_sites_bed",
    "cnv_regions_bed",
    "retain_coverage_deviation_labels",
    "reference_notes",
    "config_notes",
    "sample_notes",
]
ISSUE_FIELDS = ["severity", "source", "field", "row", "sample_id", "message"]


def norm(value):
    text = str(value if value is not None else "").strip()
    return "" if text.lower() in MISSING_VALUES else text


def lower_norm(value):
    return norm(value).lower()


def parse_bool(value):
    return str(value).strip().lower() in {"1", "true", "t", "yes", "y"}


def normalize_layout(value):
    text = lower_norm(value)
    if text in PAIRED_LAYOUTS:
        return "paired_end"
    if text in SINGLE_LAYOUTS:
        return "single_end"
    return text


def infer_delimiter(path):
    ext = os.path.splitext(path)[1].lower()
    if ext == ".tsv":
        return "\t"
    if ext == ".csv":
        return ","
    with open(path, newline="") as handle:
        sample = handle.read(min(65536, os.path.getsize(path)))
    return "\t" if sample.count("\t") > sample.count(",") else ","


def add_issue(issues, severity, source, field, row, sample_id, message):
    issues.append(
        {
            "severity": severity,
            "source": source,
            "field": field or "",
            "row": str(row or ""),
            "sample_id": sample_id or "",
            "message": message,
        }
    )


def read_table(path, label, issues):
    if not path:
        add_issue(issues, "ERROR", label, "", "", "", "File path was not provided")
        return [], []
    if not os.path.exists(path):
        add_issue(issues, "ERROR", label, "", "", "", f"File does not exist: {path}")
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
        add_issue(issues, "ERROR", label, "", "", "", f"Could not read table: {exc}")
        return [], []
    if not fields:
        add_issue(issues, "ERROR", label, "", "", "", "Table has no header")
    if len(fields) != len(set(fields)):
        add_issue(issues, "ERROR", label, "", "", "", "Table has duplicate column names")
    return fields, rows


def require_columns(fields, required, label, issues):
    present = set(fields)
    for column in required:
        if column not in present:
            add_issue(issues, "ERROR", label, column, "", "", "Missing required column")


def resolve_path(value, base_dir):
    path = norm(value)
    if not path or "://" in path or os.path.isabs(path):
        return path
    return os.path.normpath(os.path.join(base_dir, path))


def path_exists(path, field):
    if not path:
        return False
    if os.path.exists(path):
        return True
    if field == "bwa_index":
        return any(os.path.exists(path + suffix) for suffix in [".amb", ".ann", ".bwt", ".pac", ".sa"])
    return False


def write_tsv(path, fields, rows):
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


def check_required_values(row, columns, label, row_number, issues, sample_id=""):
    for column in columns:
        if norm(row.get(column)) == "":
            add_issue(issues, "ERROR", label, column, row_number, sample_id, "Missing required value")


def build_index(rows, id_field, label, issues):
    counts = Counter(norm(row.get(id_field)) for row in rows if norm(row.get(id_field)))
    for item_id, count in counts.items():
        if count > 1:
            add_issue(issues, "ERROR", label, id_field, "", "", f"Duplicate {id_field}: {item_id}")
    return {norm(row.get(id_field)): row for row in rows if norm(row.get(id_field))}


def prepare_reference_rows(reference_rows, reference_path):
    base_dir = os.path.dirname(os.path.abspath(reference_path))
    prepared = []
    for row in reference_rows:
        item = dict(row)
        for field in REFERENCE_PATH_FIELDS:
            item[field] = resolve_path(item.get(field), base_dir)
        prepared.append(item)
    return prepared


def prepare_config_rows(config_rows, config_path):
    base_dir = os.path.dirname(os.path.abspath(config_path))
    prepared = []
    for row in config_rows:
        item = dict(row)
        for field in CONFIG_PATH_FIELDS:
            item[field] = resolve_path(item.get(field), base_dir)
        prepared.append(item)
    return prepared


def validate_reference_rows(reference_rows, issues):
    for row_number, row in enumerate(reference_rows, start=2):
        ref_id = norm(row.get("reference_id"))
        check_required_values(row, REQUIRED_REFERENCE_COLUMNS, "reference_manifest", row_number, issues)
        if not ref_id:
            continue


def validate_config_rows(config_rows, issues, reference_index):
    for row_number, row in enumerate(config_rows, start=2):
        ref_id = norm(row.get("reference_id"))
        check_required_values(row, REQUIRED_CONFIG_COLUMNS, "reference_prepare_config", row_number, issues)
        if not ref_id:
            continue
        if ref_id not in reference_index:
            add_issue(
                issues,
                "ERROR",
                "reference_prepare_config",
                "reference_id",
                row_number,
                "",
                f"Unknown reference_id in reference_prepare_config: {ref_id}",
            )
        strategy = lower_norm(row.get("masking_strategy"))
        if strategy and strategy not in ALLOWED_MASKING_STRATEGIES:
            add_issue(
                issues,
                "ERROR",
                "reference_prepare_config",
                "masking_strategy",
                row_number,
                "",
                f"Unsupported masking_strategy: {row.get('masking_strategy')}",
            )
        reference = reference_index.get(ref_id)
        if reference and norm(reference.get("species")) != norm(row.get("species")):
            add_issue(
                issues,
                "ERROR",
                "reference_prepare_config",
                "species",
                row_number,
                "",
                "reference_prepare_config species does not match reference_manifest species",
            )


def validate_real_mode_paths(row, reference, config, row_number, sample_id, layout, issues):
    for field in ["fastq_1", "fastq_2"]:
        value = norm(row.get(field))
        if field == "fastq_2" and layout != "paired_end":
            continue
        if value and not path_exists(value, field):
            add_issue(
                issues,
                "ERROR",
                "wgs_samplesheet",
                field,
                row_number,
                sample_id,
                f"FASTQ file does not exist in real mode: {value}",
            )
    for field in ["genome_fasta", "bwa_index"]:
        value = norm(reference.get(field))
        if not value:
            add_issue(
                issues,
                "ERROR",
                "reference_manifest",
                field,
                row_number,
                sample_id,
                f"reference_prepare real mode requires reference field: {field}",
            )
        elif not path_exists(value, field):
            add_issue(
                issues,
                "ERROR",
                "reference_manifest",
                field,
                row_number,
                sample_id,
                f"Reference path does not exist in real mode: {value}",
            )
    for field in CONFIG_PATH_FIELDS:
        value = norm(config.get(field))
        if value and not path_exists(value, field):
            add_issue(
                issues,
                "ERROR",
                "reference_prepare_config",
                field,
                row_number,
                sample_id,
                f"Mask/config path does not exist in real mode: {value}",
            )


def prepare_rows(wgs_rows, reference_index, config_index, samplesheet_path, reference_stub, issues):
    base_dir = os.path.dirname(os.path.abspath(samplesheet_path))
    selected = []
    sample_ids = []
    for row_number, raw_row in enumerate(wgs_rows, start=2):
        row = dict(raw_row)
        sample_id = norm(row.get("sample_id"))
        check_required_values(row, REQUIRED_WGS_COLUMNS, "wgs_samplesheet", row_number, issues, sample_id)

        ref_id = norm(row.get("reference_id"))
        reference = reference_index.get(ref_id)
        config = config_index.get(ref_id)
        if ref_id and reference is None:
            add_issue(
                issues,
                "ERROR",
                "wgs_samplesheet",
                "reference_id",
                row_number,
                sample_id,
                f"Unknown reference_id: {ref_id}",
            )
        if ref_id and config is None:
            add_issue(
                issues,
                "ERROR",
                "wgs_samplesheet",
                "reference_id",
                row_number,
                sample_id,
                f"reference_id missing from reference_prepare_config: {ref_id}",
            )
        if reference is None or config is None:
            continue

        if norm(row.get("species")) != norm(reference.get("species")):
            add_issue(
                issues,
                "ERROR",
                "wgs_samplesheet",
                "reference_id",
                row_number,
                sample_id,
                "reference_id species does not match WGS sample species",
            )
        if norm(row.get("species")) != norm(config.get("species")):
            add_issue(
                issues,
                "ERROR",
                "wgs_samplesheet",
                "reference_id",
                row_number,
                sample_id,
                "reference_prepare_config species does not match WGS sample species",
            )

        layout = normalize_layout(row.get("read_layout"))
        if layout not in {"paired_end", "single_end"}:
            add_issue(
                issues,
                "ERROR",
                "wgs_samplesheet",
                "read_layout",
                row_number,
                sample_id,
                f"Unsupported read_layout for reference_prepare: {row.get('read_layout')}",
            )
        row["fastq_1"] = resolve_path(row.get("fastq_1"), base_dir)
        row["fastq_2"] = resolve_path(row.get("fastq_2"), base_dir)
        if layout == "paired_end" and (not row["fastq_1"] or not row["fastq_2"]):
            add_issue(issues, "ERROR", "wgs_samplesheet", "fastq_1/fastq_2", row_number, sample_id, "Paired-end WGS sample requires fastq_1 and fastq_2")
        if layout == "single_end" and not row["fastq_1"]:
            add_issue(issues, "ERROR", "wgs_samplesheet", "fastq_1", row_number, sample_id, "Single-end WGS sample requires fastq_1")
        if layout == "single_end" and row["fastq_2"]:
            add_issue(issues, "WARNING", "wgs_samplesheet", "fastq_2", row_number, sample_id, "fastq_2 is ignored for single-end WGS samples")

        if not reference_stub:
            validate_real_mode_paths(row, reference, config, row_number, sample_id, layout, issues)

        prepared = {field: "" for field in OUTPUT_FIELDS}
        for field in [
            "sample_id",
            "species",
            "individual_id",
            "reference_id",
            "fastq_1",
            "fastq_2",
            "batch",
            "platform",
            "library_id",
            "coverage_estimate",
        ]:
            prepared[field] = norm(row.get(field))
        prepared["read_layout"] = layout
        prepared["reference_genome_fasta"] = norm(reference.get("genome_fasta"))
        prepared["reference_gtf"] = norm(reference.get("gtf"))
        prepared["reference_transcript_fasta"] = norm(reference.get("transcript_fasta"))
        prepared["reference_bwa_index"] = norm(reference.get("bwa_index"))
        prepared["reference_chrom_sizes"] = norm(reference.get("chrom_sizes"))
        prepared["reference_blacklist_bed"] = norm(reference.get("blacklist_bed"))
        prepared["reference_repeatmasker_bed"] = norm(reference.get("repeatmasker_bed"))
        prepared["reference_mappability_bed"] = norm(reference.get("mappability_bed"))
        prepared["reference_annotation_version"] = norm(reference.get("annotation_version"))
        prepared["reference_source"] = norm(reference.get("source"))
        prepared["masking_strategy"] = lower_norm(config.get("masking_strategy"))
        prepared["known_repeats_bed"] = norm(config.get("known_repeats_bed"))
        prepared["config_mappability_bed"] = norm(config.get("mappability_bed"))
        prepared["problematic_sites_bed"] = norm(config.get("problematic_sites_bed"))
        prepared["cnv_regions_bed"] = norm(config.get("cnv_regions_bed"))
        prepared["retain_coverage_deviation_labels"] = lower_norm(config.get("retain_coverage_deviation_labels"))
        prepared["reference_notes"] = norm(reference.get("notes"))
        prepared["config_notes"] = norm(config.get("notes"))
        prepared["sample_notes"] = norm(row.get("notes"))
        selected.append(prepared)
        sample_ids.append(sample_id)

    counts = Counter(sample_ids)
    for sample_id, count in counts.items():
        if sample_id and count > 1:
            add_issue(issues, "ERROR", "wgs_samplesheet", "sample_id", "", sample_id, f"Duplicate sample_id: {sample_id}")
    if not selected:
        add_issue(issues, "ERROR", "wgs_samplesheet", "sample_id", "", "", "No WGS samples were selected for reference preparation")
    return selected


def parse_args():
    parser = argparse.ArgumentParser(description="Prepare CAME reference preparation inputs.")
    parser.add_argument("--wgs_samplesheet", required=True)
    parser.add_argument("--reference_manifest", required=True)
    parser.add_argument("--reference_prepare_config", required=True)
    parser.add_argument("--reference_stub", default="true")
    parser.add_argument("--output_dir", default="results/reference/input")
    return parser.parse_args()


def main():
    args = parse_args()
    issues = []
    reference_stub = parse_bool(args.reference_stub)

    wgs_fields, wgs_rows = read_table(args.wgs_samplesheet, "wgs_samplesheet", issues)
    reference_fields, raw_reference_rows = read_table(args.reference_manifest, "reference_manifest", issues)
    config_fields, raw_config_rows = read_table(args.reference_prepare_config, "reference_prepare_config", issues)
    require_columns(wgs_fields, REQUIRED_WGS_COLUMNS, "wgs_samplesheet", issues)
    require_columns(reference_fields, REQUIRED_REFERENCE_COLUMNS, "reference_manifest", issues)
    require_columns(config_fields, REQUIRED_CONFIG_COLUMNS, "reference_prepare_config", issues)

    reference_rows = prepare_reference_rows(raw_reference_rows, args.reference_manifest)
    config_rows = prepare_config_rows(raw_config_rows, args.reference_prepare_config)
    reference_index = build_index(reference_rows, "reference_id", "reference_manifest", issues)
    config_index = build_index(config_rows, "reference_id", "reference_prepare_config", issues)
    validate_reference_rows(reference_rows, issues)
    validate_config_rows(config_rows, issues, reference_index)

    selected = []
    if not any(issue["severity"] == "ERROR" for issue in issues):
        selected = prepare_rows(wgs_rows, reference_index, config_index, args.wgs_samplesheet, reference_stub, issues)

    os.makedirs(args.output_dir, exist_ok=True)
    write_tsv(os.path.join(args.output_dir, "reference_prepare_manifest.tsv"), OUTPUT_FIELDS, selected)
    write_tsv(os.path.join(args.output_dir, "reference_prepare_warnings.tsv"), ISSUE_FIELDS, issues)

    counts = Counter(issue["severity"] for issue in issues)
    print(
        "CAME reference input preparation summary: "
        f"ERROR={counts.get('ERROR', 0)} WARNING={counts.get('WARNING', 0)} selected_samples={len(selected)}"
    )
    for issue in issues:
        if issue["severity"] == "ERROR":
            print(f"ERROR\t{issue['source']}\t{issue['field']}\t{issue['sample_id']}\t{issue['message']}", file=sys.stderr)
    return 1 if counts.get("ERROR", 0) else 0


if __name__ == "__main__":
    sys.exit(main())
