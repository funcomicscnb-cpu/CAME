#!/usr/bin/env python3
"""Prepare Stage 25 real-mode RNA-seq and ATAC-seq manifests."""

from __future__ import annotations

import argparse
import csv
import os
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path


MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}
SUPPORTED_OMICS_TYPES = {"rnaseq", "atacseq"}
ASSAY_ALIASES = {
    "rna": "rnaseq",
    "rnaseq": "rnaseq",
    "rna-seq": "rnaseq",
    "rna_seq": "rnaseq",
    "rna seq": "rnaseq",
    "atac": "atacseq",
    "atacseq": "atacseq",
    "atac-seq": "atacseq",
    "atac_seq": "atacseq",
    "atac seq": "atacseq",
}
PAIRED_LAYOUTS = {"paired", "paired-end", "paired_end", "pe"}
SINGLE_LAYOUTS = {"single", "single-end", "single_end", "se"}
RNA_STRANDEDNESS = {"forward", "reverse", "unstranded", "unknown"}

PREPARED_FIELDS = [
    "sample_id",
    "sample_key",
    "study_id",
    "species",
    "individual_id",
    "replicate_id",
    "biological_replicate",
    "omics_type",
    "assay",
    "tissue",
    "condition",
    "timepoint",
    "reference_id",
    "reference_key",
    "read_layout",
    "library_strategy",
    "library_protocol",
    "platform",
    "strandedness",
    "batch",
    "fastq_1",
    "fastq_2",
    "genome_fasta",
    "fasta",
    "gtf",
    "annotation_file",
    "annotation_format",
    "star_index",
    "bowtie2_index",
    "chrom_sizes",
    "mitochondrial_name",
    "blacklist_bed",
    "annotation_version",
    "annotation_release",
    "reference_source",
]
REFERENCE_FIELDS = [
    "reference_id",
    "reference_key",
    "species",
    "fasta",
    "annotation_file",
    "annotation_format",
    "star_index",
    "bowtie2_index",
    "chrom_sizes",
    "mitochondrial_name",
    "blacklist_bed",
]
ISSUE_FIELDS = ["severity", "source", "field", "row", "sample_id", "message"]


def norm(value: object) -> str:
    text = str(value if value is not None else "").strip()
    return "" if text.lower() in MISSING_VALUES else text


def lower_norm(value: object) -> str:
    return norm(value).lower()


def filesystem_key(value: object, prefix: str) -> str:
    """Return a stable key safe for process-local filenames."""
    text = norm(value)
    key = re.sub(r"[^A-Za-z0-9._-]+", "_", text).strip("._-")
    key = re.sub(r"_+", "_", key)
    return key or prefix


def add_issue(
    issues: list[dict[str, str]],
    severity: str,
    source: str,
    field: str,
    row: int | str,
    sample_id: str,
    message: str,
) -> None:
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


def infer_delimiter(path: str) -> str:
    ext = os.path.splitext(path)[1].lower()
    if ext == ".tsv":
        return "\t"
    if ext == ".csv":
        return ","
    with open(path, newline="") as handle:
        sample = handle.read(min(65536, os.path.getsize(path)))
    return "\t" if sample.count("\t") > sample.count(",") else ","


def read_table(path: str, label: str, issues: list[dict[str, str]]) -> tuple[list[str], list[dict[str, str]]]:
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
            rows: list[dict[str, str]] = []
            for row_number, row in enumerate(reader, start=2):
                if None in row:
                    add_issue(issues, "ERROR", label, "", row_number, "", "Row has more fields than the header")
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


def resolve_path(value: object, base_dir: str) -> str:
    path = norm(value)
    if not path or "://" in path or os.path.isabs(path):
        return path
    return os.path.normpath(os.path.join(base_dir, path))


def resolve_config_path(value: str, launch_dir: str) -> str:
    text = norm(value)
    if not text:
        return text
    if os.path.isabs(text):
        return text
    return os.path.normpath(os.path.join(launch_dir, text))


def path_exists(path: str) -> bool:
    return bool(path) and os.path.exists(path)


def star_index_exists(path: str) -> bool:
    return bool(path) and os.path.isdir(path) and os.path.exists(os.path.join(path, "SA"))


def bowtie2_index_exists(prefix: str) -> bool:
    if not prefix:
        return False
    return any(os.path.exists(prefix + suffix) for suffix in [".1.bt2", ".1.bt2l"])


def normalize_omics_type(value: object) -> str:
    text = lower_norm(value)
    return ASSAY_ALIASES.get(text, text)


def normalize_layout(value: object) -> str:
    text = lower_norm(value)
    if text in PAIRED_LAYOUTS:
        return "paired_end"
    if text in SINGLE_LAYOUTS:
        return "single_end"
    return text


def parse_requested_types(raw: str, issues: list[dict[str, str]]) -> list[str]:
    requested: list[str] = []
    for item in str(raw or "").split(","):
        omics_type = normalize_omics_type(item)
        if not omics_type:
            continue
        if omics_type not in SUPPORTED_OMICS_TYPES:
            add_issue(issues, "ERROR", "parameters", "omics_types", "", "", f"Unsupported requested omics_type: {item}")
            continue
        if omics_type not in requested:
            requested.append(omics_type)
    if not requested:
        add_issue(issues, "ERROR", "parameters", "omics_types", "", "", "No supported omics types were requested")
    return requested


def parse_bool(value: object) -> bool:
    return str(value).strip().lower() in {"1", "true", "t", "yes", "y"}


def choose_reference_path(row: dict[str, str], *fields: str) -> str:
    for field in fields:
        value = norm(row.get(field))
        if value:
            return value
    return ""


def build_reference_index(
    reference_path: str,
    cache_dir: str,
    reference_base_dir: str,
    issues: list[dict[str, str]],
) -> dict[str, dict[str, str]]:
    fields, rows = read_table(reference_path, "reference_manifest", issues)
    present = set(fields)
    for column in ["reference_id", "species"]:
        if column not in present:
            add_issue(issues, "ERROR", "reference_manifest", column, "", "", "Missing required column")
    base_dir = reference_base_dir or os.path.dirname(os.path.abspath(reference_path))
    index: dict[str, dict[str, str]] = {}
    counts = Counter(norm(row.get("reference_id")) for row in rows if norm(row.get("reference_id")))
    for reference_id, count in sorted(counts.items()):
        if count > 1:
            add_issue(issues, "ERROR", "reference_manifest", "reference_id", "", "", f"Duplicate reference_id: {reference_id}")
    key_to_refs: dict[str, set[str]] = defaultdict(set)
    for row_number, row in enumerate(rows, start=2):
        reference_id = norm(row.get("reference_id"))
        if not reference_id:
            add_issue(issues, "ERROR", "reference_manifest", "reference_id", row_number, "", "Missing required value")
            continue
        reference_key = filesystem_key(reference_id, "reference")
        key_to_refs[reference_key].add(reference_id)
        fasta = resolve_path(choose_reference_path(row, "fasta", "genome_fasta"), base_dir)
        annotation_file = resolve_path(choose_reference_path(row, "annotation_file", "gtf"), base_dir)
        chrom_sizes = resolve_path(row.get("chrom_sizes"), base_dir)
        blacklist_bed = resolve_path(row.get("blacklist_bed"), base_dir)
        star_index_raw = resolve_path(row.get("star_index"), base_dir)
        bowtie2_index_raw = resolve_path(row.get("bowtie2_index"), base_dir)
        if not bowtie2_index_raw:
            bowtie2_index_raw = resolve_path(row.get("bwa_index"), base_dir)
        cache_ref = os.path.join(cache_dir, reference_key)
        star_index = star_index_raw if star_index_exists(star_index_raw) else os.path.join(cache_ref, "star")
        bowtie2_index = bowtie2_index_raw if bowtie2_index_exists(bowtie2_index_raw) else os.path.join(cache_ref, "bowtie2", "genome")
        index[reference_id] = {
            "reference_id": reference_id,
            "reference_key": reference_key,
            "species": norm(row.get("species")),
            "fasta": fasta,
            "genome_fasta": fasta,
            "annotation_file": annotation_file,
            "gtf": annotation_file,
            "annotation_format": lower_norm(row.get("annotation_format")) or ("gtf" if annotation_file.endswith(".gtf") else ""),
            "star_index": star_index,
            "bowtie2_index": bowtie2_index,
            "chrom_sizes": chrom_sizes,
            "mitochondrial_name": norm(row.get("mitochondrial_name")),
            "blacklist_bed": blacklist_bed,
            "annotation_version": norm(row.get("annotation_version")),
            "annotation_release": norm(row.get("annotation_release")),
            "reference_source": norm(row.get("source") or row.get("assembly_source")),
        }
    for reference_key, reference_ids in sorted(key_to_refs.items()):
        if len(reference_ids) > 1:
            add_issue(
                issues,
                "ERROR",
                "reference_manifest",
                "reference_id",
                "",
                "",
                f"reference_id values collide after filesystem-safe normalization ({reference_key}): {', '.join(sorted(reference_ids))}",
            )
    return index


def require(value: str, issues: list[dict[str, str]], source: str, field: str, row: int, sample_id: str) -> None:
    if not norm(value):
        add_issue(issues, "ERROR", source, field, row, sample_id, "Missing required value")


def stage23_row(
    row: dict[str, str],
    row_number: int,
    references: dict[str, dict[str, str]],
    metadata_base: str,
    requested: list[str],
    require_paired_atac: bool,
    issues: list[dict[str, str]],
) -> dict[str, str] | None:
    sample_id = norm(row.get("sample_id"))
    assay = lower_norm(row.get("assay"))
    omics_type = normalize_omics_type(assay)
    if omics_type not in requested:
        return None
    for field in [
        "sample_id",
        "species",
        "individual_id",
        "biological_replicate",
        "assay",
        "condition",
        "read_layout",
        "fastq_1",
        "reference_id",
    ]:
        require(row.get(field, ""), issues, "real_mode_metadata", field, row_number, sample_id)
    if omics_type not in SUPPORTED_OMICS_TYPES:
        add_issue(issues, "ERROR", "real_mode_metadata", "assay", row_number, sample_id, f"Unsupported real-mode assay for Stage 25: {assay}")
        return None
    layout = normalize_layout(row.get("read_layout"))
    if layout not in {"paired_end", "single_end"}:
        add_issue(issues, "ERROR", "real_mode_metadata", "read_layout", row_number, sample_id, f"Unsupported read_layout: {row.get('read_layout')}")
    fastq_1 = resolve_path(row.get("fastq_1"), metadata_base)
    fastq_2 = resolve_path(row.get("fastq_2"), metadata_base)
    if layout == "paired_end" and not fastq_2:
        add_issue(issues, "ERROR", "real_mode_metadata", "fastq_2", row_number, sample_id, "Paired-end sample requires fastq_2")
    if layout == "single_end" and fastq_2:
        add_issue(issues, "ERROR", "real_mode_metadata", "fastq_2", row_number, sample_id, "Single-end sample must not provide fastq_2")
    if omics_type == "rnaseq":
        strandedness = lower_norm(row.get("strandedness"))
        if strandedness not in RNA_STRANDEDNESS:
            add_issue(issues, "ERROR", "real_mode_metadata", "strandedness", row_number, sample_id, f"Invalid RNA strandedness: {row.get('strandedness')}")
    else:
        strandedness = ""
        if layout == "single_end":
            severity = "ERROR" if require_paired_atac else "WARNING"
            add_issue(issues, severity, "real_mode_metadata", "read_layout", row_number, sample_id, "ATAC single-end libraries are allowed but paired-end is preferred")
    reference_id = norm(row.get("reference_id"))
    reference = references.get(reference_id)
    if not reference:
        add_issue(issues, "ERROR", "real_mode_metadata", "reference_id", row_number, sample_id, f"Unknown reference_id: {reference_id}")
        return None
    if norm(row.get("species")) != reference.get("species"):
        add_issue(issues, "ERROR", "real_mode_metadata", "reference_id", row_number, sample_id, "reference_id species does not match metadata species")
    return prepared_row(row, omics_type, layout, fastq_1, fastq_2, strandedness, reference)


def legacy_row(
    row: dict[str, str],
    row_number: int,
    references: dict[str, dict[str, str]],
    metadata_base: str,
    requested: list[str],
    require_paired_atac: bool,
    issues: list[dict[str, str]],
) -> dict[str, str] | None:
    sample_id = norm(row.get("sample_id"))
    omics_type = normalize_omics_type(row.get("omics_type"))
    if omics_type not in requested:
        return None
    for field in ["sample_id", "species", "individual_id", "replicate_id", "omics_type", "condition", "read_layout", "fastq_1", "reference_id"]:
        require(row.get(field, ""), issues, "omics_samplesheet", field, row_number, sample_id)
    layout = normalize_layout(row.get("read_layout"))
    fastq_1 = resolve_path(row.get("fastq_1"), metadata_base)
    fastq_2 = resolve_path(row.get("fastq_2"), metadata_base)
    if layout == "paired_end" and not fastq_2:
        add_issue(issues, "ERROR", "omics_samplesheet", "fastq_2", row_number, sample_id, "Paired-end sample requires fastq_2")
    if omics_type == "rnaseq":
        strandedness = lower_norm(row.get("strandedness")) or "unknown"
        if strandedness not in RNA_STRANDEDNESS:
            add_issue(issues, "ERROR", "omics_samplesheet", "strandedness", row_number, sample_id, f"Invalid RNA strandedness: {row.get('strandedness')}")
    else:
        strandedness = ""
        if layout == "single_end":
            severity = "ERROR" if require_paired_atac else "WARNING"
            add_issue(issues, severity, "omics_samplesheet", "read_layout", row_number, sample_id, "ATAC single-end libraries are allowed but paired-end is preferred")
    reference_id = norm(row.get("reference_id"))
    reference = references.get(reference_id)
    if not reference:
        add_issue(issues, "ERROR", "omics_samplesheet", "reference_id", row_number, sample_id, f"Unknown reference_id: {reference_id}")
        return None
    if norm(row.get("species")) != reference.get("species"):
        add_issue(issues, "ERROR", "omics_samplesheet", "reference_id", row_number, sample_id, "reference_id species does not match sample species")
    return prepared_row(row, omics_type, layout, fastq_1, fastq_2, strandedness, reference)


def prepared_row(
    row: dict[str, str],
    omics_type: str,
    layout: str,
    fastq_1: str,
    fastq_2: str,
    strandedness: str,
    reference: dict[str, str],
) -> dict[str, str]:
    out = {field: "" for field in PREPARED_FIELDS}
    out.update(reference)
    out["sample_id"] = norm(row.get("sample_id"))
    out["sample_key"] = filesystem_key(row.get("sample_id"), "sample")
    out["study_id"] = norm(row.get("study_id"))
    out["species"] = norm(row.get("species"))
    out["individual_id"] = norm(row.get("individual_id"))
    out["replicate_id"] = norm(row.get("replicate_id") or row.get("biological_replicate"))
    out["biological_replicate"] = norm(row.get("biological_replicate") or row.get("replicate_id"))
    out["omics_type"] = omics_type
    out["assay"] = "rna" if omics_type == "rnaseq" else "atac"
    out["tissue"] = norm(row.get("tissue"))
    out["condition"] = norm(row.get("condition"))
    out["timepoint"] = norm(row.get("timepoint"))
    out["reference_id"] = reference["reference_id"]
    out["reference_key"] = reference.get("reference_key", filesystem_key(reference["reference_id"], "reference"))
    out["read_layout"] = layout
    out["library_strategy"] = norm(row.get("library_strategy"))
    out["library_protocol"] = norm(row.get("library_protocol"))
    out["platform"] = norm(row.get("platform"))
    out["strandedness"] = strandedness
    out["batch"] = norm(row.get("batch"))
    out["fastq_1"] = fastq_1
    out["fastq_2"] = fastq_2
    return out


def validate_paths(rows: list[dict[str, str]], issues: list[dict[str, str]]) -> None:
    for row in rows:
        sample_id = row["sample_id"]
        for field in ["fastq_1", "fastq_2"]:
            value = row.get(field, "")
            if value and not path_exists(value):
                add_issue(issues, "ERROR", "real_mode_inputs", field, "", sample_id, f"FASTQ file does not exist: {value}")
        if row["omics_type"] == "rnaseq":
            for field in ["fasta", "annotation_file"]:
                value = row.get(field, "")
                if not value:
                    add_issue(issues, "ERROR", "reference_manifest", field, "", sample_id, f"RNA real mode requires reference field: {field}")
                elif not path_exists(value):
                    add_issue(issues, "ERROR", "reference_manifest", field, "", sample_id, f"Reference path does not exist: {value}")
        if row["omics_type"] == "atacseq":
            value = row.get("fasta", "")
            if not value:
                add_issue(issues, "ERROR", "reference_manifest", "fasta", "", sample_id, "ATAC real mode requires reference FASTA")
            elif not path_exists(value):
                add_issue(issues, "ERROR", "reference_manifest", "fasta", "", sample_id, f"Reference path does not exist: {value}")


def write_tsv(path: str, fields: list[str], rows: list[dict[str, str]]) -> None:
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, delimiter="\t", extrasaction="ignore", quoting=csv.QUOTE_NONE, escapechar="\\", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference_manifest", required=True)
    parser.add_argument("--real_mode_metadata", default="")
    parser.add_argument("--omics_samplesheet", default="")
    parser.add_argument("--omics_types", default="rnaseq,atacseq")
    parser.add_argument("--reference_cache_dir", default="results/reference_cache")
    parser.add_argument("--launch_dir", default=os.getcwd())
    parser.add_argument("--metadata_base_dir", default="")
    parser.add_argument("--reference_base_dir", default="")
    parser.add_argument("--real_require_paired_atac", default="false")
    parser.add_argument("--output_dir", default="results/omics/input")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    issues: list[dict[str, str]] = []
    requested = parse_requested_types(args.omics_types, issues)
    cache_dir = resolve_config_path(args.reference_cache_dir, args.launch_dir)
    reference_base_dir = resolve_config_path(args.reference_base_dir, args.launch_dir) if args.reference_base_dir else ""
    metadata_base_dir = resolve_config_path(args.metadata_base_dir, args.launch_dir) if args.metadata_base_dir else ""
    references = build_reference_index(args.reference_manifest, cache_dir, reference_base_dir, issues)
    require_paired_atac = parse_bool(args.real_require_paired_atac)

    selected: list[dict[str, str]] = []
    if not any(issue["severity"] == "ERROR" for issue in issues):
        metadata_path = args.real_mode_metadata or args.omics_samplesheet
        source = "real_mode_metadata" if args.real_mode_metadata else "omics_samplesheet"
        fields, rows = read_table(metadata_path, source, issues)
        base_dir = metadata_base_dir or (os.path.dirname(os.path.abspath(metadata_path)) if metadata_path else os.getcwd())
        if source == "omics_samplesheet":
            add_issue(issues, "WARNING", source, "", "", "", "Using legacy omics_samplesheet as Stage 25 real-mode metadata fallback")
        for row_number, row in enumerate(rows, start=2):
            if source == "real_mode_metadata":
                out = stage23_row(row, row_number, references, base_dir, requested, require_paired_atac, issues)
            else:
                out = legacy_row(row, row_number, references, base_dir, requested, require_paired_atac, issues)
            if out is not None:
                selected.append(out)

    counts = Counter(row["sample_id"] for row in selected if row.get("sample_id"))
    for sample_id, count in sorted(counts.items()):
        if count > 1:
            add_issue(issues, "ERROR", "real_mode_inputs", "sample_id", "", sample_id, f"Duplicate selected sample_id: {sample_id}")
    sample_key_to_ids: dict[str, set[str]] = defaultdict(set)
    for row in selected:
        if row.get("sample_key") and row.get("sample_id"):
            sample_key_to_ids[row["sample_key"]].add(row["sample_id"])
    for sample_key, sample_ids in sorted(sample_key_to_ids.items()):
        if len(sample_ids) > 1:
            add_issue(
                issues,
                "ERROR",
                "real_mode_inputs",
                "sample_id",
                "",
                "",
                f"sample_id values collide after filesystem-safe normalization ({sample_key}): {', '.join(sorted(sample_ids))}",
            )
    for omics_type in requested:
        if not any(row["omics_type"] == omics_type for row in selected):
            add_issue(issues, "WARNING", "real_mode_inputs", "omics_type", "", "", f"No rows matched requested omics_type: {omics_type}")
    if requested and not selected:
        add_issue(issues, "ERROR", "real_mode_inputs", "omics_type", "", "", "No real-mode samples matched requested omics_types")
    validate_paths(selected, issues)

    outdir = args.output_dir
    reference_rows = []
    seen_refs = set()
    for row in selected:
        ref_id = row["reference_id"]
        if ref_id in seen_refs:
            continue
        seen_refs.add(ref_id)
        reference_rows.append({field: row.get(field, "") for field in REFERENCE_FIELDS})
    write_tsv(os.path.join(outdir, "omics_manifest_prepared.tsv"), PREPARED_FIELDS, selected)
    write_tsv(os.path.join(outdir, "rnaseq_manifest.tsv"), PREPARED_FIELDS, [row for row in selected if row["omics_type"] == "rnaseq"])
    write_tsv(os.path.join(outdir, "atacseq_manifest.tsv"), PREPARED_FIELDS, [row for row in selected if row["omics_type"] == "atacseq"])
    write_tsv(os.path.join(outdir, "reference_assets.tsv"), REFERENCE_FIELDS, reference_rows)
    write_tsv(os.path.join(outdir, "omics_input_warnings.tsv"), ISSUE_FIELDS, issues)

    severity_counts = Counter(issue["severity"] for issue in issues)
    print(
        "CAME real-mode omics input preparation summary: "
        f"ERROR={severity_counts.get('ERROR', 0)} WARNING={severity_counts.get('WARNING', 0)} selected_samples={len(selected)}"
    )
    for issue in issues:
        if issue["severity"] == "ERROR":
            print(f"ERROR\t{issue['source']}\t{issue['field']}\t{issue['sample_id']}\t{issue['message']}", file=sys.stderr)
    return 1 if severity_counts.get("ERROR", 0) else 0


if __name__ == "__main__":
    raise SystemExit(main())
