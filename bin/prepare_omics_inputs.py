#!/usr/bin/env python3
"""Prepare Stage 5 bulk omics manifests for CAME."""

import argparse
import csv
import os
import sys
from collections import Counter


SUPPORTED_OMICS_TYPES = {"rnaseq", "atacseq"}
OMICS_TYPE_ALIASES = {
    "rna-seq": "rnaseq",
    "rna_seq": "rnaseq",
    "rna seq": "rnaseq",
    "atac-seq": "atacseq",
    "atac_seq": "atacseq",
    "atac seq": "atacseq",
}
PAIRED_LAYOUTS = {"paired", "paired-end", "paired_end", "pe"}
SINGLE_LAYOUTS = {"single", "single-end", "single_end", "se"}
MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}

REQUIRED_OMICS_COLUMNS = [
    "sample_id",
    "species",
    "individual_id",
    "replicate_id",
    "omics_type",
    "condition",
    "timepoint",
    "reference_id",
    "fastq_1",
    "read_layout",
]
REQUIRED_REFERENCE_COLUMNS = ["reference_id", "species", "genome_fasta"]
PATH_FIELDS = [
    "fastq_1",
    "fastq_2",
    "genome_fasta",
    "gtf",
    "transcript_fasta",
    "star_index",
    "bwa_index",
    "chrom_sizes",
    "blacklist_bed",
]
REFERENCE_JOIN_FIELDS = [
    "genome_fasta",
    "gtf",
    "transcript_fasta",
    "star_index",
    "bwa_index",
    "chrom_sizes",
    "blacklist_bed",
    "annotation_version",
]
OUTPUT_FIELDS = [
    "sample_id",
    "species",
    "individual_id",
    "replicate_id",
    "omics_type",
    "condition",
    "timepoint",
    "reference_id",
    "read_layout",
    "library_strategy",
    "strandedness",
    "batch",
    "perturbation",
    "dose",
    "dose_unit",
    "fastq_1",
    "fastq_2",
    "genome_fasta",
    "gtf",
    "transcript_fasta",
    "star_index",
    "bwa_index",
    "chrom_sizes",
    "blacklist_bed",
    "annotation_version",
    "reference_source",
]


def norm(value):
    text = str(value if value is not None else "").strip()
    return "" if text.lower() in MISSING_VALUES else text


def lower_norm(value):
    return norm(value).lower()


def parse_bool(value):
    return str(value).strip().lower() in {"1", "true", "t", "yes", "y"}


def normalize_omics_type(value):
    text = lower_norm(value)
    return OMICS_TYPE_ALIASES.get(text, text)


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


def check_required_values(row, columns, label, row_number, issues):
    sample_id = norm(row.get("sample_id"))
    for column in columns:
        if norm(row.get(column)) == "":
            add_issue(issues, "ERROR", label, column, row_number, sample_id, "Missing required value")


def parse_requested_types(value, issues):
    requested = []
    for raw in str(value or "").split(","):
        item = normalize_omics_type(raw)
        if not item:
            continue
        if item not in SUPPORTED_OMICS_TYPES:
            add_issue(
                issues,
                "ERROR",
                "parameters",
                "omics_types",
                "",
                "",
                f"Unsupported requested omics_type: {item}. Supported values: {', '.join(sorted(SUPPORTED_OMICS_TYPES))}",
            )
        elif item not in requested:
            requested.append(item)
    if not requested:
        add_issue(issues, "ERROR", "parameters", "omics_types", "", "", "No omics types were requested")
    return requested


def build_reference_index(reference_fields, reference_rows, reference_path, issues):
    require_columns(reference_fields, REQUIRED_REFERENCE_COLUMNS, "reference_manifest", issues)
    base_dir = os.path.dirname(os.path.abspath(reference_path))
    index = {}
    counts = Counter(norm(row.get("reference_id")) for row in reference_rows if norm(row.get("reference_id")))
    for ref_id, count in counts.items():
        if count > 1:
            add_issue(issues, "ERROR", "reference_manifest", "reference_id", "", "", f"Duplicate reference_id: {ref_id}")
    for row_number, row in enumerate(reference_rows, start=2):
        ref_id = norm(row.get("reference_id"))
        if not ref_id:
            add_issue(issues, "ERROR", "reference_manifest", "reference_id", row_number, "", "Missing required value")
            continue
        prepared = dict(row)
        for field in REFERENCE_JOIN_FIELDS:
            if field in PATH_FIELDS:
                prepared[field] = resolve_path(prepared.get(field), base_dir)
            else:
                prepared[field] = norm(prepared.get(field))
        prepared["reference_source"] = norm(row.get("source"))
        index[ref_id] = prepared
    return index


def real_mode_reference_requirements(omics_type):
    if omics_type == "rnaseq":
        return ["genome_fasta", "gtf", "star_index"]
    if omics_type == "atacseq":
        return ["genome_fasta", "bwa_index", "chrom_sizes"]
    return []


def prepare_rows(omics_rows, reference_index, requested_types, samplesheet_path, omics_stub, issues):
    base_dir = os.path.dirname(os.path.abspath(samplesheet_path))
    selected = []
    sample_ids = []
    for row_number, row in enumerate(omics_rows, start=2):
        sample_id = norm(row.get("sample_id"))
        check_required_values(row, REQUIRED_OMICS_COLUMNS, "omics_samplesheet", row_number, issues)
        omics_type = normalize_omics_type(row.get("omics_type"))
        if omics_type and omics_type not in SUPPORTED_OMICS_TYPES:
            add_issue(
                issues,
                "WARNING",
                "omics_samplesheet",
                "omics_type",
                row_number,
                sample_id,
                f"Unknown omics_type allowed for extension and skipped by Stage 5: {omics_type}",
            )
            continue
        if omics_type not in requested_types:
            continue

        reference_id = norm(row.get("reference_id"))
        reference = reference_index.get(reference_id)
        if reference is None:
            add_issue(
                issues,
                "ERROR",
                "omics_samplesheet",
                "reference_id",
                row_number,
                sample_id,
                f"Unknown reference_id: {reference_id}",
            )
            continue
        if norm(row.get("species")) != norm(reference.get("species")):
            add_issue(
                issues,
                "ERROR",
                "omics_samplesheet",
                "reference_id",
                row_number,
                sample_id,
                "reference_id species does not match omics sample species",
            )

        layout = normalize_layout(row.get("read_layout"))
        if layout not in {"paired_end", "single_end"}:
            add_issue(
                issues,
                "ERROR",
                "omics_samplesheet",
                "read_layout",
                row_number,
                sample_id,
                f"Unsupported read_layout for Stage 5: {row.get('read_layout')}",
            )
        fastq_1 = resolve_path(row.get("fastq_1"), base_dir)
        fastq_2 = resolve_path(row.get("fastq_2"), base_dir)
        if layout == "paired_end" and (not fastq_1 or not fastq_2):
            add_issue(issues, "ERROR", "omics_samplesheet", "fastq_1/fastq_2", row_number, sample_id, "Paired-end sample requires fastq_1 and fastq_2")
        if layout == "single_end" and not fastq_1:
            add_issue(issues, "ERROR", "omics_samplesheet", "fastq_1", row_number, sample_id, "Single-end sample requires fastq_1")
        if not omics_stub:
            for field, value in [("fastq_1", fastq_1), ("fastq_2", fastq_2 if layout == "paired_end" else "")]:
                if value and not path_exists(value, field):
                    add_issue(issues, "ERROR", "omics_samplesheet", field, row_number, sample_id, f"FASTQ file does not exist in real mode: {value}")
            for field in real_mode_reference_requirements(omics_type):
                value = norm(reference.get(field))
                if not value:
                    add_issue(issues, "ERROR", "reference_manifest", field, row_number, sample_id, f"{omics_type} real mode requires reference field: {field}")
                elif not path_exists(value, field):
                    add_issue(issues, "ERROR", "reference_manifest", field, row_number, sample_id, f"Reference path does not exist in real mode: {value}")

        prepared = {field: "" for field in OUTPUT_FIELDS}
        for field in [
            "sample_id",
            "species",
            "individual_id",
            "replicate_id",
            "condition",
            "timepoint",
            "reference_id",
            "library_strategy",
            "strandedness",
            "batch",
            "perturbation",
            "dose",
            "dose_unit",
        ]:
            prepared[field] = norm(row.get(field))
        prepared["omics_type"] = omics_type
        prepared["read_layout"] = layout
        prepared["fastq_1"] = fastq_1
        prepared["fastq_2"] = fastq_2
        for field in REFERENCE_JOIN_FIELDS + ["reference_source"]:
            prepared[field] = norm(reference.get(field))
        selected.append(prepared)
        sample_ids.append(sample_id)

    counts = Counter(sample_ids)
    for sample_id, count in counts.items():
        if sample_id and count > 1:
            add_issue(issues, "ERROR", "omics_samplesheet", "sample_id", "", sample_id, f"Duplicate selected sample_id: {sample_id}")
    for omics_type in requested_types:
        if not any(row.get("omics_type") == omics_type for row in selected):
            add_issue(issues, "WARNING", "omics_samplesheet", "omics_type", "", "", f"No rows matched requested omics_type: {omics_type}")
    if requested_types and not selected:
        add_issue(issues, "ERROR", "omics_samplesheet", "omics_type", "", "", "No omics samples matched requested omics_types")
    return selected


def write_tsv(path, fields, rows):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, delimiter="\t", extrasaction="ignore", quoting=csv.QUOTE_NONE, escapechar="\\", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def write_issues(path, issues):
    fields = ["severity", "source", "field", "row", "sample_id", "message"]
    write_tsv(path, fields, issues)


def parse_args():
    parser = argparse.ArgumentParser(description="Prepare CAME bulk omics input manifests.")
    parser.add_argument("--omics_samplesheet", required=True)
    parser.add_argument("--reference_manifest", required=True)
    parser.add_argument("--omics_types", default="rnaseq,atacseq")
    parser.add_argument("--omics_stub", default="true")
    parser.add_argument("--output_dir", default="results/omics/input")
    return parser.parse_args()


def main():
    args = parse_args()
    issues = []
    requested_types = parse_requested_types(args.omics_types, issues)
    omics_stub = parse_bool(args.omics_stub)

    omics_fields, omics_rows = read_table(args.omics_samplesheet, "omics_samplesheet", issues)
    reference_fields, reference_rows = read_table(args.reference_manifest, "reference_manifest", issues)
    require_columns(omics_fields, REQUIRED_OMICS_COLUMNS, "omics_samplesheet", issues)
    reference_index = build_reference_index(reference_fields, reference_rows, args.reference_manifest, issues)

    selected = []
    if not any(issue["severity"] == "ERROR" for issue in issues):
        selected = prepare_rows(omics_rows, reference_index, requested_types, args.omics_samplesheet, omics_stub, issues)

    output_dir = args.output_dir
    os.makedirs(output_dir, exist_ok=True)
    write_tsv(os.path.join(output_dir, "omics_manifest_prepared.tsv"), OUTPUT_FIELDS, selected)
    for omics_type in ["rnaseq", "atacseq"]:
        rows = [row for row in selected if row.get("omics_type") == omics_type]
        write_tsv(os.path.join(output_dir, f"{omics_type}_manifest.tsv"), OUTPUT_FIELDS, rows)
    write_issues(os.path.join(output_dir, "omics_input_warnings.tsv"), issues)

    counts = Counter(issue["severity"] for issue in issues)
    print(
        "CAME omics input preparation summary: "
        f"ERROR={counts.get('ERROR', 0)} WARNING={counts.get('WARNING', 0)} selected_samples={len(selected)}"
    )
    for issue in issues:
        if issue["severity"] == "ERROR":
            print(f"ERROR\t{issue['source']}\t{issue['field']}\t{issue['sample_id']}\t{issue['message']}", file=sys.stderr)
    return 1 if counts.get("ERROR", 0) else 0


if __name__ == "__main__":
    sys.exit(main())
