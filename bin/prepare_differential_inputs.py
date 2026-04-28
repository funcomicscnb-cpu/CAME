#!/usr/bin/env python3
"""Prepare Stage 6 differential omics inputs for CAME."""

import argparse
import csv
import os
import sys
from collections import Counter, defaultdict

from phenotype_utils import load_profile, profile_contrasts


SUPPORTED_OMICS_TYPES = {"rnaseq", "atacseq"}
OMICS_TYPE_ALIASES = {
    "rna-seq": "rnaseq",
    "rna_seq": "rnaseq",
    "rna seq": "rnaseq",
    "atac-seq": "atacseq",
    "atac_seq": "atacseq",
    "atac seq": "atacseq",
}
MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}
REQUIRED_OMICS_COLUMNS = [
    "sample_id",
    "species",
    "individual_id",
    "replicate_id",
    "omics_type",
    "condition",
    "timepoint",
]
SAMPLE_FIELDS = [
    "sample_id",
    "species",
    "individual_id",
    "replicate_id",
    "omics_type",
    "condition",
    "timepoint",
    "batch",
    "reference_id",
]
CONTRAST_FIELDS = [
    "contrast_id",
    "omics_type",
    "contrast_name",
    "contrast_type",
    "species",
    "baseline_condition",
    "baseline_timepoint",
    "response_condition",
    "response_timepoint",
    "baseline_label",
    "response_label",
    "baseline_sample_ids",
    "response_sample_ids",
    "n_baseline",
    "n_response",
]
ISSUE_FIELDS = ["severity", "source", "field", "omics_type", "species", "contrast_name", "message"]
MANIFEST_FIELDS = ["omics_type", "counts_path", "sample_annotation", "contrasts", "n_samples", "n_contrasts", "status"]
COUNT_METADATA_FIELDS = {
    "rnaseq": ["feature_id", "feature_type", "annotation_id"],
    "atacseq": ["feature_id", "feature_type", "chrom", "start", "end"],
}


def norm(value):
    text = str(value if value is not None else "").strip()
    return "" if text.lower() in MISSING_VALUES else text


def normalize_omics_type(value):
    text = norm(value).lower()
    return OMICS_TYPE_ALIASES.get(text, text)


def infer_delimiter(path):
    ext = os.path.splitext(path)[1].lower()
    if ext == ".tsv":
        return "\t"
    if ext == ".csv":
        return ","
    with open(path, newline="") as handle:
        sample = handle.read(min(65536, os.path.getsize(path)))
    return "\t" if sample.count("\t") > sample.count(",") else ","


def read_table(path):
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


def write_tsv(path, fields, rows):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, delimiter="\t", extrasaction="ignore", quoting=csv.QUOTE_NONE, escapechar="\\", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def issue(issues, severity, source, field, message, omics_type="", species="", contrast_name=""):
    issues.append(
        {
            "severity": severity,
            "source": source,
            "field": field,
            "omics_type": omics_type,
            "species": species,
            "contrast_name": contrast_name,
            "message": message,
        }
    )


def parse_requested_types(raw, issues):
    requested = []
    for item in str(raw or "").split(","):
        omics_type = normalize_omics_type(item)
        if not omics_type:
            continue
        if omics_type not in SUPPORTED_OMICS_TYPES:
            issue(issues, "ERROR", "params", "omics_types", f"Unsupported requested omics_type: {item}")
            continue
        if omics_type not in requested:
            requested.append(omics_type)
    if not requested:
        issue(issues, "ERROR", "params", "omics_types", "No supported omics_types were requested")
    return requested


def count_header(path, omics_type, issues):
    if not path:
        return []
    if not os.path.exists(path):
        issue(issues, "ERROR", "count_matrix", "path", f"Missing count matrix: {path}", omics_type=omics_type)
        return []
    delimiter = infer_delimiter(path)
    with open(path, newline="") as handle:
        reader = csv.reader(handle, delimiter=delimiter)
        try:
            fields = [norm(value) for value in next(reader)]
        except StopIteration:
            issue(issues, "ERROR", "count_matrix", "header", f"Count matrix is empty: {path}", omics_type=omics_type)
            return []
    required = COUNT_METADATA_FIELDS[omics_type]
    missing = [field for field in required if field not in fields]
    if missing:
        issue(
            issues,
            "ERROR",
            "count_matrix",
            "header",
            f"{omics_type} count matrix is missing required feature column(s): {', '.join(missing)}",
            omics_type=omics_type,
        )
        return []
    return [field for field in fields if field not in required]


def require_columns(fields, issues):
    for field in REQUIRED_OMICS_COLUMNS:
        if field not in fields:
            issue(issues, "ERROR", "omics_samplesheet", field, "Missing required column")


def selected_samples(fields, rows, requested, issues):
    require_columns(fields, issues)
    if any(row["severity"] == "ERROR" for row in issues):
        return []
    selected = []
    seen = set()
    for idx, row in enumerate(rows, start=2):
        sample_id = norm(row.get("sample_id"))
        omics_type = normalize_omics_type(row.get("omics_type"))
        if omics_type not in requested:
            continue
        row_issues = []
        for field in REQUIRED_OMICS_COLUMNS:
            if not norm(row.get(field)):
                row_issues.append(field)
        if row_issues:
            issue(
                issues,
                "ERROR",
                "omics_samplesheet",
                ",".join(row_issues),
                f"Row {idx} is missing required value(s): {', '.join(row_issues)}",
                omics_type=omics_type,
            )
            continue
        if sample_id in seen:
            issue(issues, "ERROR", "omics_samplesheet", "sample_id", f"Duplicate sample_id: {sample_id}", omics_type=omics_type)
            continue
        seen.add(sample_id)
        selected.append({field: norm(row.get(field)) for field in SAMPLE_FIELDS} | {"omics_type": omics_type})
    counts = Counter(row["omics_type"] for row in selected)
    for omics_type in requested:
        if counts.get(omics_type, 0) == 0:
            issue(issues, "ERROR", "omics_samplesheet", "omics_type", f"No metadata rows matched requested omics_type: {omics_type}", omics_type=omics_type)
    return selected


def validate_sample_agreement(selected, requested, count_paths, issues):
    sample_ids_by_type = defaultdict(list)
    for row in selected:
        sample_ids_by_type[row["omics_type"]].append(row["sample_id"])
    for omics_type in requested:
        matrix_samples = count_header(count_paths.get(omics_type, ""), omics_type, issues)
        metadata_samples = sample_ids_by_type.get(omics_type, [])
        missing_from_counts = sorted(set(metadata_samples) - set(matrix_samples))
        missing_from_metadata = sorted(set(matrix_samples) - set(metadata_samples))
        if missing_from_counts:
            issue(
                issues,
                "ERROR",
                "count_matrix",
                "sample_id",
                f"Metadata sample(s) absent from {omics_type} count matrix: {', '.join(missing_from_counts)}",
                omics_type=omics_type,
            )
        if missing_from_metadata:
            issue(
                issues,
                "ERROR",
                "omics_samplesheet",
                "sample_id",
                f"{omics_type} count matrix sample(s) absent from metadata: {', '.join(missing_from_metadata)}",
                omics_type=omics_type,
            )


def text(value):
    return str(value if value is not None else "").strip()


def contrast_type(raw_type):
    ctype = text(raw_type)
    return "condition_contrast" if ctype == "treated_vs_control" else ctype


def contrast_label(contrast, *names):
    for name in names:
        value = text(contrast.get(name))
        if value:
            return value
    return ""


def cli_contrast(args, issues):
    values = [args.baseline_condition, args.response_condition, args.baseline_timepoint, args.response_timepoint]
    supplied = [value for value in values if norm(value)]
    if supplied and len(supplied) != 4:
        issue(
            issues,
            "ERROR",
            "params",
            "contrast",
            "CLI contrast override requires all four params: baseline_condition, response_condition, baseline_timepoint, response_timepoint",
        )
        return []
    if len(supplied) == 4:
        bc = norm(args.baseline_condition)
        rc = norm(args.response_condition)
        bt = norm(args.baseline_timepoint)
        rt = norm(args.response_timepoint)
        if bc == rc and bt == rt:
            issue(
                issues,
                "WARNING",
                "params",
                "contrast",
                f"CLI contrast baseline and response are identical (condition='{bc}', timepoint='{bt}'). "
                "Differential results will be trivially empty.",
            )
        return [
            {
                "name": "cli_baseline_vs_response",
                "type": "baseline_vs_response",
                "baseline_condition": bc,
                "response_condition": rc,
                "baseline_timepoint": bt,
                "response_timepoint": rt,
            }
        ]
    return None


def load_contrasts(args, issues):
    override = cli_contrast(args, issues)
    if override is not None:
        return override
    if not norm(args.study_profile):
        issue(issues, "ERROR", "params", "study_profile", "Provide --study_profile or a complete CLI contrast override")
        return []
    try:
        return profile_contrasts(load_profile(args.study_profile))
    except Exception as exc:
        issue(issues, "ERROR", "study_profile", "phenotype_index.contrasts", str(exc))
        return []


def label(condition, timepoint):
    return f"{condition}|{timepoint}" if condition and timepoint else condition or timepoint


def required_label(contrast, contrast_name, issues, field, omics_type):
    value = text(contrast.get(field))
    if not value:
        issue(issues, "WARNING", "study_profile", field, f"Contrast {contrast_name} is missing required field: {field}", omics_type=omics_type, contrast_name=contrast_name)
    return value


def validate_available(value, available, label_type, contrast_name, omics_type, issues):
    if value and value not in available:
        issue(
            issues,
            "WARNING",
            "contrast",
            label_type,
            f"Contrast {contrast_name} references missing {label_type}: {value}",
            omics_type=omics_type,
            contrast_name=contrast_name,
        )
        return False
    return True


def exact_pair(contrast, name, ctype, conditions, timepoints, omics_type, issues):
    if ctype == "baseline_vs_response":
        bc = required_label(contrast, name, issues, "baseline_condition", omics_type)
        rc = required_label(contrast, name, issues, "response_condition", omics_type)
        bt = required_label(contrast, name, issues, "baseline_timepoint", omics_type)
        rt = required_label(contrast, name, issues, "response_timepoint", omics_type)
    elif ctype == "condition_contrast":
        bc = contrast_label(contrast, "baseline_condition", "control_condition")
        rc = contrast_label(contrast, "response_condition", "treated_condition")
        bt = text(contrast.get("baseline_timepoint"))
        rt = text(contrast.get("response_timepoint"))
        if not bc:
            required_label(contrast, name, issues, "control_condition", omics_type)
        if not rc:
            required_label(contrast, name, issues, "treated_condition", omics_type)
        if bool(bt) != bool(rt):
            issue(issues, "WARNING", "contrast", "timepoint", f"Contrast {name} must provide both baseline_timepoint and response_timepoint", omics_type=omics_type, contrast_name=name)
    elif ctype == "timepoint_contrast":
        bt = contrast_label(contrast, "from_timepoint", "baseline_timepoint")
        rt = contrast_label(contrast, "to_timepoint", "response_timepoint")
        bc = text(contrast.get("baseline_condition"))
        rc = text(contrast.get("response_condition"))
        if not bt:
            required_label(contrast, name, issues, "from_timepoint", omics_type)
        if not rt:
            required_label(contrast, name, issues, "to_timepoint", omics_type)
        if bool(bc) != bool(rc):
            issue(issues, "WARNING", "contrast", "condition", f"Contrast {name} must provide both baseline_condition and response_condition", omics_type=omics_type, contrast_name=name)
    else:
        issue(issues, "WARNING", "contrast", "type", f"Unsupported contrast type: {ctype}", omics_type=omics_type, contrast_name=name)
        return None

    valid = True
    for condition in [bc, rc]:
        valid = validate_available(condition, conditions, "condition", name, omics_type, issues) and valid
    for timepoint in [bt, rt]:
        valid = validate_available(timepoint, timepoints, "timepoint", name, omics_type, issues) and valid
    if not valid or not (bc or bt) or not (rc or rt):
        return None
    return (bc, bt), (rc, rt)


def pairs_for_species(contrast, species, assay_rows, observed, conditions, timepoints, omics_type, issues):
    name = text(contrast.get("name")) or "unnamed_contrast"
    ctype = contrast_type(contrast.get("type"))
    if ctype == "condition_contrast" and not text(contrast.get("baseline_timepoint")) and not text(contrast.get("response_timepoint")):
        bc = contrast_label(contrast, "baseline_condition", "control_condition")
        rc = contrast_label(contrast, "response_condition", "treated_condition")
        if not bc or not rc:
            return []
        if not (validate_available(bc, conditions, "condition", name, omics_type, issues) and validate_available(rc, conditions, "condition", name, omics_type, issues)):
            return []
        shared = sorted(
            timepoint
            for timepoint in timepoints
            if (species, bc, timepoint) in observed and (species, rc, timepoint) in observed
        )
        return [((bc, timepoint), (rc, timepoint)) for timepoint in shared]
    if ctype == "timepoint_contrast" and not text(contrast.get("baseline_condition")) and not text(contrast.get("response_condition")):
        bt = contrast_label(contrast, "from_timepoint", "baseline_timepoint")
        rt = contrast_label(contrast, "to_timepoint", "response_timepoint")
        if not bt or not rt:
            return []
        if not (validate_available(bt, timepoints, "timepoint", name, omics_type, issues) and validate_available(rt, timepoints, "timepoint", name, omics_type, issues)):
            return []
        species_conditions = sorted({row["condition"] for row in assay_rows if row["species"] == species})
        shared = [
            condition
            for condition in species_conditions
            if (species, condition, bt) in observed and (species, condition, rt) in observed
        ]
        return [((condition, bt), (condition, rt)) for condition in shared]
    pair = exact_pair(contrast, name, ctype, conditions, timepoints, omics_type, issues)
    return [pair] if pair else []


def build_contrasts(selected, requested, contrasts, issues):
    rows = []
    grouped = defaultdict(list)
    for row in selected:
        grouped[row["omics_type"]].append(row)
    for omics_type in requested:
        assay_rows = grouped.get(omics_type, [])
        conditions = {row["condition"] for row in assay_rows if row["condition"]}
        timepoints = {row["timepoint"] for row in assay_rows if row["timepoint"]}
        species_values = sorted({row["species"] for row in assay_rows if row["species"]})
        observed = {(row["species"], row["condition"], row["timepoint"]) for row in assay_rows}
        assay_contrasts = []
        for contrast in contrasts:
            name = text(contrast.get("name")) or "unnamed_contrast"
            ctype = contrast_type(contrast.get("type"))
            for species in species_values:
                pairs = pairs_for_species(contrast, species, assay_rows, observed, conditions, timepoints, omics_type, issues)
                if not pairs:
                    issue(
                        issues,
                        "WARNING",
                        "contrast",
                        "species",
                        f"No executable {name} pair for species {species}",
                        omics_type=omics_type,
                        species=species,
                        contrast_name=name,
                    )
                    continue
                for baseline_key, response_key in pairs:
                    base_rows = [
                        row
                        for row in assay_rows
                        if row["species"] == species and row["condition"] == baseline_key[0] and row["timepoint"] == baseline_key[1]
                    ]
                    resp_rows = [
                        row
                        for row in assay_rows
                        if row["species"] == species and row["condition"] == response_key[0] and row["timepoint"] == response_key[1]
                    ]
                    if not base_rows or not resp_rows:
                        issue(
                            issues,
                            "WARNING",
                            "contrast",
                            "group",
                            f"Skipping {name} for {species}; baseline or response group is absent",
                            omics_type=omics_type,
                            species=species,
                            contrast_name=name,
                        )
                        continue
                    baseline_label = label(*baseline_key)
                    response_label = label(*response_key)
                    contrast_id = f"{omics_type}|{species}|{name}|{baseline_label}_vs_{response_label}"
                    assay_contrasts.append(
                        {
                            "contrast_id": contrast_id,
                            "omics_type": omics_type,
                            "contrast_name": name,
                            "contrast_type": ctype,
                            "species": species,
                            "baseline_condition": baseline_key[0],
                            "baseline_timepoint": baseline_key[1],
                            "response_condition": response_key[0],
                            "response_timepoint": response_key[1],
                            "baseline_label": baseline_label,
                            "response_label": response_label,
                            "baseline_sample_ids": ",".join(row["sample_id"] for row in base_rows),
                            "response_sample_ids": ",".join(row["sample_id"] for row in resp_rows),
                            "n_baseline": str(len(base_rows)),
                            "n_response": str(len(resp_rows)),
                        }
                    )
        rows.extend(assay_contrasts)
        if not assay_contrasts:
            issue(
                issues,
                "ERROR",
                "contrast",
                "executable",
                f"No executable contrast remains for requested assay: {omics_type}",
                omics_type=omics_type,
            )
    return rows


def prepare(args):
    issues = []
    requested = parse_requested_types(args.omics_types, issues)
    fields, omics_rows = read_table(args.omics_samplesheet)
    selected = selected_samples(fields, omics_rows, requested, issues)
    count_paths = {"rnaseq": norm(args.rnaseq_counts), "atacseq": norm(args.atacseq_counts)}
    validate_sample_agreement(selected, requested, count_paths, issues)
    contrasts = load_contrasts(args, issues)
    contrast_rows = []
    if not any(row["severity"] == "ERROR" for row in issues):
        contrast_rows = build_contrasts(selected, requested, contrasts, issues)

    os.makedirs(args.output_dir, exist_ok=True)
    write_tsv(os.path.join(args.output_dir, "differential_samples.tsv"), SAMPLE_FIELDS, selected)
    write_tsv(os.path.join(args.output_dir, "differential_contrasts.tsv"), CONTRAST_FIELDS, contrast_rows)
    for omics_type in ["rnaseq", "atacseq"]:
        assay_samples = [row for row in selected if row["omics_type"] == omics_type]
        assay_contrasts = [row for row in contrast_rows if row["omics_type"] == omics_type]
        write_tsv(os.path.join(args.output_dir, f"{omics_type}_sample_annotation.tsv"), SAMPLE_FIELDS, assay_samples)
        write_tsv(os.path.join(args.output_dir, f"{omics_type}_contrasts.tsv"), CONTRAST_FIELDS, assay_contrasts)
    manifest_rows = []
    for omics_type in ["rnaseq", "atacseq"]:
        requested_assay = omics_type in requested
        n_samples = sum(1 for row in selected if row["omics_type"] == omics_type)
        n_contrasts = sum(1 for row in contrast_rows if row["omics_type"] == omics_type)
        manifest_rows.append(
            {
                "omics_type": omics_type,
                "counts_path": count_paths.get(omics_type, ""),
                "sample_annotation": os.path.join(args.output_dir, f"{omics_type}_sample_annotation.tsv"),
                "contrasts": os.path.join(args.output_dir, f"{omics_type}_contrasts.tsv"),
                "n_samples": str(n_samples),
                "n_contrasts": str(n_contrasts),
                "status": "REQUESTED" if requested_assay else "SKIPPED",
            }
        )
    write_tsv(os.path.join(args.output_dir, "differential_input_manifest.tsv"), MANIFEST_FIELDS, manifest_rows)
    write_tsv(os.path.join(args.output_dir, "differential_input_warnings.tsv"), ISSUE_FIELDS, issues)
    counts = Counter(row["severity"] for row in issues)
    print(
        "CAME differential input preparation summary: "
        f"ERROR={counts.get('ERROR', 0)} WARNING={counts.get('WARNING', 0)} contrasts={len(contrast_rows)}"
    )
    for row in issues:
        if row["severity"] == "ERROR":
            print(f"ERROR\t{row['source']}\t{row['field']}\t{row['omics_type']}\t{row['message']}", file=sys.stderr)
    return 1 if counts.get("ERROR", 0) else 0


def parse_args():
    parser = argparse.ArgumentParser(description="Prepare CAME Stage 6 differential omics inputs.")
    parser.add_argument("--omics_samplesheet", required=True)
    parser.add_argument("--study_profile", default="")
    parser.add_argument("--omics_types", default="rnaseq,atacseq")
    parser.add_argument("--rnaseq_counts", default="")
    parser.add_argument("--atacseq_counts", default="")
    parser.add_argument("--baseline_condition", default="")
    parser.add_argument("--response_condition", default="")
    parser.add_argument("--baseline_timepoint", default="")
    parser.add_argument("--response_timepoint", default="")
    parser.add_argument("--output_dir", default="results/differential_omics/input")
    return parser.parse_args()


def main():
    try:
        return prepare(parse_args())
    except Exception as exc:
        print(f"ERROR\tprepare_differential_inputs\t{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
