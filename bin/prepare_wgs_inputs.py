#!/usr/bin/env python3
"""Prepare Stage 27 WGS small-variant inputs."""

from __future__ import annotations

import argparse
import csv
import os
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path


MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}
PAIRED_LAYOUTS = {"paired", "paired-end", "paired_end", "pe"}
SINGLE_LAYOUTS = {"single", "single-end", "single_end", "se"}
WGS_REQUIRED_FIELDS = [
    "sample_id",
    "study_id",
    "species",
    "individual_id",
    "biological_replicate",
    "assay",
    "read_layout",
    "fastq_1",
    "reference_id",
    "platform",
    "library_protocol",
]
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
    "library_id",
    "run_id",
    "lane",
    "platform",
    "batch",
    "fastq_1",
    "fastq_2",
    "fasta",
    "genome_fasta",
    "fai",
    "dict",
    "bwa_index_prefix",
    "known_sites_vcf",
    "repeatmask_bed",
    "mappability_bed",
    "mitochondrial_name",
    "annotation_file",
    "annotation_format",
    "wgs_mode",
    "wgs_variant_mode",
    "wgs_filtering_mode",
    "bqsr_policy",
]
REFERENCE_FIELDS = [
    "reference_id",
    "reference_key",
    "species",
    "fasta",
    "fai",
    "dict",
    "bwa_index_prefix",
    "known_sites_vcf",
    "repeatmask_bed",
    "mappability_bed",
]
ISSUE_FIELDS = ["severity", "source", "field", "row", "sample_id", "message"]
KNOWN_SITES_WARNING = "WARNING: known_sites_vcf absent; BQSR skipped and hard-filtering/no-BQSR fallback used."


def norm(value: object) -> str:
    text = str(value if value is not None else "").strip()
    return "" if text.lower() in MISSING_VALUES else text


def lower_norm(value: object) -> str:
    return norm(value).lower()


def parse_bool(value: object) -> bool:
    return str(value).strip().lower() in {"1", "true", "t", "yes", "y"}


def filesystem_key(value: object, prefix: str) -> str:
    text = norm(value)
    key = re.sub(r"[^A-Za-z0-9._-]+", "_", text).strip("._-")
    key = re.sub(r"_+", "_", key)
    return key or prefix


def add_issue(issues: list[dict[str, str]], severity: str, source: str, field: str, row: int | str, sample_id: str, message: str) -> None:
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
    if not text or os.path.isabs(text):
        return text
    return os.path.normpath(os.path.join(launch_dir, text))


def normalize_layout(value: object) -> str:
    text = lower_norm(value)
    if text in PAIRED_LAYOUTS:
        return "paired_end"
    if text in SINGLE_LAYOUTS:
        return "single_end"
    return text


def path_exists(path: str) -> bool:
    return bool(path) and os.path.exists(path)


def bwa_mem2_index_exists(prefix: str) -> bool:
    if not prefix:
        return False
    suffix_sets = [
        [".amb", ".ann", ".pac", ".0123", ".bwt.2bit.64"],
        [".amb", ".ann", ".bwt", ".pac", ".sa"],
    ]
    return any(all(os.path.exists(prefix + suffix) for suffix in suffixes) for suffixes in suffix_sets)


def choose(row: dict[str, str], *fields: str) -> str:
    for field in fields:
        value = norm(row.get(field))
        if value:
            return value
    return ""


def build_reference_index(reference_path: str, cache_dir: str, reference_base_dir: str, issues: list[dict[str, str]]) -> dict[str, dict[str, str]]:
    fields, rows = read_table(reference_path, "reference_manifest", issues)
    present = set(fields)
    for column in ["reference_id", "species"]:
        if column not in present:
            add_issue(issues, "ERROR", "reference_manifest", column, "", "", "Missing required column")
    base_dir = reference_base_dir or os.path.dirname(os.path.abspath(reference_path))
    references: dict[str, dict[str, str]] = {}
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
        fasta = resolve_path(choose(row, "fasta", "genome_fasta"), base_dir)
        fai = resolve_path(row.get("fai"), base_dir)
        sequence_dict = resolve_path(choose(row, "dict", "sequence_dict"), base_dir)
        raw_bwa = resolve_path(choose(row, "bwa_index_prefix", "bwa_index"), base_dir)
        cache_prefix = os.path.join(cache_dir, reference_key, "bwa_mem2", "genome")
        bwa_prefix = raw_bwa if bwa_mem2_index_exists(raw_bwa) else cache_prefix
        references[reference_id] = {
            "reference_id": reference_id,
            "reference_key": reference_key,
            "species": norm(row.get("species")),
            "fasta": fasta,
            "genome_fasta": fasta,
            "fai": fai,
            "dict": sequence_dict,
            "bwa_index_prefix": bwa_prefix,
            "known_sites_vcf": resolve_path(choose(row, "known_sites_vcf", "known_sites"), base_dir),
            "repeatmask_bed": resolve_path(choose(row, "repeatmask_bed", "repeatmasker_bed"), base_dir),
            "mappability_bed": resolve_path(row.get("mappability_bed"), base_dir),
            "mitochondrial_name": norm(row.get("mitochondrial_name")),
            "annotation_file": resolve_path(choose(row, "annotation_file", "gtf"), base_dir),
            "annotation_format": lower_norm(row.get("annotation_format")),
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
    return references


def require_columns(fields: list[str], issues: list[dict[str, str]]) -> None:
    present = set(fields)
    for field in WGS_REQUIRED_FIELDS:
        if field not in present:
            add_issue(issues, "ERROR", "wgs_samplesheet", field, "", "", "Missing required column")


def require_value(row: dict[str, str], field: str, row_number: int, sample_id: str, issues: list[dict[str, str]]) -> None:
    if not norm(row.get(field)):
        add_issue(issues, "ERROR", "wgs_samplesheet", field, row_number, sample_id, "Missing required value")


def validate_reference_paths(row: dict[str, str], sample_id: str, issues: list[dict[str, str]]) -> None:
    for field in ["fasta", "fai", "dict"]:
        value = row.get(field, "")
        if not value:
            add_issue(issues, "ERROR", "reference_manifest", field, "", sample_id, f"WGS real mode requires reference field: {field}")
        elif not path_exists(value):
            add_issue(issues, "ERROR", "reference_manifest", field, "", sample_id, f"Reference path does not exist: {value}")
    if not row.get("bwa_index_prefix") and not row.get("fasta"):
        add_issue(issues, "ERROR", "reference_manifest", "bwa_index_prefix", "", sample_id, "WGS real mode requires BWA-MEM2 index prefix or buildable FASTA")


def validate_known_sites(
    row: dict[str, str],
    row_number: int,
    sample_id: str,
    require_known_sites: bool,
    allow_no_bqsr: bool,
    real_mode: bool,
    issues: list[dict[str, str]],
) -> None:
    known_sites = norm(row.get("known_sites_vcf"))
    if known_sites:
        if real_mode and not path_exists(known_sites):
            add_issue(issues, "ERROR", "reference_manifest", "known_sites_vcf", row_number, sample_id, f"known_sites_vcf path does not exist: {known_sites}")
        return
    if require_known_sites:
        add_issue(issues, "ERROR", "reference_manifest", "known_sites_vcf", row_number, sample_id, "known_sites_vcf is required by --require_known_sites true")
    else:
        add_issue(issues, "WARNING", "reference_manifest", "known_sites_vcf", row_number, sample_id, KNOWN_SITES_WARNING)
    if real_mode and not allow_no_bqsr:
        add_issue(issues, "ERROR", "parameters", "allow_no_bqsr", "", sample_id, "Stage 27 does not implement BQSR; set --allow_no_bqsr true to use the no-BQSR baseline")


def prepared_row(
    row: dict[str, str],
    reference: dict[str, str],
    layout: str,
    fastq_1: str,
    fastq_2: str,
    wgs_mode: str,
    variant_mode: str,
    filtering_mode: str,
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
    out["omics_type"] = "wgs"
    out["assay"] = "wgs"
    out["tissue"] = norm(row.get("tissue"))
    out["condition"] = norm(row.get("condition"))
    out["timepoint"] = norm(row.get("timepoint"))
    out["reference_id"] = reference["reference_id"]
    out["reference_key"] = reference.get("reference_key", filesystem_key(reference["reference_id"], "reference"))
    out["read_layout"] = layout
    out["library_strategy"] = norm(row.get("library_strategy"))
    out["library_protocol"] = norm(row.get("library_protocol"))
    out["library_id"] = norm(row.get("library_id"))
    out["run_id"] = norm(row.get("run_id"))
    out["lane"] = norm(row.get("lane"))
    out["platform"] = norm(row.get("platform"))
    out["batch"] = norm(row.get("batch"))
    out["fastq_1"] = fastq_1
    out["fastq_2"] = fastq_2
    out["wgs_mode"] = wgs_mode
    out["wgs_variant_mode"] = variant_mode
    out["wgs_filtering_mode"] = filtering_mode
    out["bqsr_policy"] = "no_bqsr_stage27"
    return out


def prepare_rows(args: argparse.Namespace, references: dict[str, dict[str, str]], fields: list[str], rows: list[dict[str, str]], issues: list[dict[str, str]]) -> list[dict[str, str]]:
    require_columns(fields, issues)
    if any(issue["severity"] == "ERROR" for issue in issues):
        return []
    base_dir = args.metadata_base_dir or os.path.dirname(os.path.abspath(args.wgs_samplesheet))
    real_mode = args.wgs_mode == "real"
    selected: list[dict[str, str]] = []
    for row_number, row in enumerate(rows, start=2):
        sample_id = norm(row.get("sample_id"))
        assay = lower_norm(row.get("assay"))
        if assay == "wes":
            add_issue(issues, "ERROR", "wgs_samplesheet", "assay", row_number, sample_id, "WES production support is not implemented in Stage 27")
            continue
        if assay and assay != "wgs":
            continue
        for field in WGS_REQUIRED_FIELDS:
            require_value(row, field, row_number, sample_id, issues)
        layout = normalize_layout(row.get("read_layout"))
        if layout not in {"paired_end", "single_end"}:
            add_issue(issues, "ERROR", "wgs_samplesheet", "read_layout", row_number, sample_id, f"Unsupported read_layout for WGS: {row.get('read_layout')}")
        fastq_1 = resolve_path(row.get("fastq_1"), base_dir)
        fastq_2 = resolve_path(row.get("fastq_2"), base_dir)
        if layout == "paired_end" and not fastq_2:
            add_issue(issues, "ERROR", "wgs_samplesheet", "fastq_2", row_number, sample_id, "Paired-end WGS sample requires fastq_2")
        if layout == "single_end" and fastq_2:
            add_issue(issues, "ERROR", "wgs_samplesheet", "fastq_2", row_number, sample_id, "Single-end WGS sample must not provide fastq_2")
        reference_id = norm(row.get("reference_id"))
        reference = references.get(reference_id)
        if not reference:
            add_issue(issues, "ERROR", "wgs_samplesheet", "reference_id", row_number, sample_id, f"Unknown reference_id: {reference_id}")
            continue
        if norm(row.get("species")) != reference.get("species"):
            add_issue(issues, "ERROR", "wgs_samplesheet", "reference_id", row_number, sample_id, "reference_id species does not match WGS sample species")
        out = prepared_row(row, reference, layout, fastq_1, fastq_2, args.wgs_mode, args.wgs_variant_mode, args.wgs_filtering_mode)
        validate_known_sites(out, row_number, sample_id, args.require_known_sites, args.allow_no_bqsr, real_mode, issues)
        if real_mode:
            for field in ["fastq_1", "fastq_2"]:
                value = out.get(field, "")
                if value and not path_exists(value):
                    add_issue(issues, "ERROR", "wgs_samplesheet", field, row_number, sample_id, f"FASTQ file does not exist: {value}")
            validate_reference_paths(out, sample_id, issues)
        selected.append(out)
    counts = Counter(row["sample_id"] for row in selected if row.get("sample_id"))
    for sample_id, count in sorted(counts.items()):
        if count > 1:
            add_issue(issues, "ERROR", "wgs_inputs", "sample_id", "", sample_id, f"Duplicate selected sample_id: {sample_id}")
    sample_key_to_ids: dict[str, set[str]] = defaultdict(set)
    for row in selected:
        sample_key_to_ids[row["sample_key"]].add(row["sample_id"])
    for sample_key, sample_ids in sorted(sample_key_to_ids.items()):
        if len(sample_ids) > 1:
            add_issue(issues, "ERROR", "wgs_inputs", "sample_id", "", "", f"sample_id values collide after filesystem-safe normalization ({sample_key}): {', '.join(sorted(sample_ids))}")
    if not selected:
        add_issue(issues, "ERROR", "wgs_inputs", "assay", "", "", "No WGS samples matched assay=wgs")
    return selected


def write_tsv(path: str, fields: list[str], rows: list[dict[str, str]]) -> None:
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, delimiter="\t", extrasaction="ignore", quoting=csv.QUOTE_NONE, escapechar="\\", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--wgs_samplesheet", required=True)
    parser.add_argument("--reference_manifest", required=True)
    parser.add_argument("--wgs_mode", choices=["stub", "real"], default="stub")
    parser.add_argument("--wgs_variant_mode", choices=["haplotypecaller"], default="haplotypecaller")
    parser.add_argument("--wgs_filtering_mode", choices=["hard_filter", "none"], default="hard_filter")
    parser.add_argument("--require_known_sites", default="false")
    parser.add_argument("--allow_no_bqsr", default="true")
    parser.add_argument("--reference_cache_dir", default="results/reference_cache")
    parser.add_argument("--launch_dir", default=os.getcwd())
    parser.add_argument("--metadata_base_dir", default="")
    parser.add_argument("--reference_base_dir", default="")
    parser.add_argument("--output_dir", default="results/wgs/input")
    args = parser.parse_args(argv)
    args.require_known_sites = parse_bool(args.require_known_sites)
    args.allow_no_bqsr = parse_bool(args.allow_no_bqsr)
    args.reference_cache_dir = resolve_config_path(args.reference_cache_dir, args.launch_dir)
    args.metadata_base_dir = resolve_config_path(args.metadata_base_dir, args.launch_dir) if args.metadata_base_dir else ""
    args.reference_base_dir = resolve_config_path(args.reference_base_dir, args.launch_dir) if args.reference_base_dir else ""
    return args


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    issues: list[dict[str, str]] = []
    references = build_reference_index(args.reference_manifest, args.reference_cache_dir, args.reference_base_dir, issues)
    fields, rows = read_table(args.wgs_samplesheet, "wgs_samplesheet", issues)
    selected = prepare_rows(args, references, fields, rows, issues)
    reference_rows = []
    seen_refs = set()
    for row in selected:
        ref_id = row["reference_id"]
        if ref_id in seen_refs:
            continue
        seen_refs.add(ref_id)
        reference_rows.append({field: row.get(field, "") for field in REFERENCE_FIELDS})
    outdir = args.output_dir
    write_tsv(os.path.join(outdir, "wgs_manifest_prepared.tsv"), PREPARED_FIELDS, selected)
    write_tsv(os.path.join(outdir, "wgs_manifest.tsv"), PREPARED_FIELDS, selected)
    write_tsv(os.path.join(outdir, "wgs_reference_assets.tsv"), REFERENCE_FIELDS, reference_rows)
    write_tsv(os.path.join(outdir, "wgs_input_warnings.tsv"), ISSUE_FIELDS, issues)
    counts = Counter(issue["severity"] for issue in issues)
    print(
        "CAME WGS input preparation summary: "
        f"ERROR={counts.get('ERROR', 0)} WARNING={counts.get('WARNING', 0)} selected_samples={len(selected)}"
    )
    for issue in issues:
        if issue["severity"] == "ERROR":
            print(f"ERROR\t{issue['source']}\t{issue['field']}\t{issue['sample_id']}\t{issue['message']}", file=sys.stderr)
    return 1 if counts.get("ERROR", 0) else 0


if __name__ == "__main__":
    raise SystemExit(main())
