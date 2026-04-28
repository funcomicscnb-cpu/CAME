#!/usr/bin/env python3
"""Prepare contrast-ready stub omics inputs for CAME all-run orchestration."""

import argparse
import csv
import os
import sys

from phenotype_utils import load_profile, profile_contrasts


MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}
SUPPORTED_OMICS_TYPES = {"rnaseq", "atacseq"}
OMICS_TYPE_ALIASES = {
    "rna-seq": "rnaseq",
    "rna_seq": "rnaseq",
    "rna seq": "rnaseq",
    "atac-seq": "atacseq",
    "atac_seq": "atacseq",
    "atac seq": "atacseq",
}
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


def read_rows(path):
    delimiter = infer_delimiter(path)
    with open(path, newline="") as handle:
        reader = csv.DictReader(handle, delimiter=delimiter)
        fields = [norm(field) for field in reader.fieldnames or []]
        rows = []
        for row in reader:
            rows.append({field: norm(row.get(field)) for field in fields})
    if not fields:
        raise RuntimeError(f"Input table has no header: {path}")
    return fields, rows


def write_table(path, fields, rows, delimiter):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    tsv = delimiter == "\t"
    with open(path, "w", newline="") as handle:
        writer = csv.DictWriter(
            handle, fieldnames=fields, delimiter=delimiter, extrasaction="ignore",
            quoting=csv.QUOTE_NONE if tsv else csv.QUOTE_MINIMAL,
            escapechar="\\" if tsv else None,
            lineterminator="\n",
        )
        writer.writeheader()
        writer.writerows(rows)


def contrast_value(contrast, *names):
    for name in names:
        value = norm(contrast.get(name))
        if value:
            return value
    return ""


def choose_contrast(study_profile, omics_rows):
    contrasts = profile_contrasts(load_profile(study_profile))
    source_conditions = sorted({norm(row.get("condition")) for row in omics_rows if norm(row.get("condition"))})
    source_timepoints = sorted({norm(row.get("timepoint")) for row in omics_rows if norm(row.get("timepoint"))})
    fallback_condition = source_conditions[0] if source_conditions else "stub_condition"
    fallback_timepoint = source_timepoints[0] if source_timepoints else "stub_timepoint"

    for contrast in contrasts:
        ctype = contrast_value(contrast, "type")
        if ctype == "treated_vs_control":
            ctype = "condition_contrast"
        name = contrast_value(contrast, "name") or "unnamed_contrast"
        if ctype == "baseline_vs_response":
            baseline_condition = contrast_value(contrast, "baseline_condition")
            response_condition = contrast_value(contrast, "response_condition")
            baseline_timepoint = contrast_value(contrast, "baseline_timepoint")
            response_timepoint = contrast_value(contrast, "response_timepoint")
        elif ctype == "condition_contrast":
            baseline_condition = contrast_value(contrast, "baseline_condition", "control_condition")
            response_condition = contrast_value(contrast, "response_condition", "treated_condition")
            baseline_timepoint = contrast_value(contrast, "baseline_timepoint") or fallback_timepoint
            response_timepoint = contrast_value(contrast, "response_timepoint") or fallback_timepoint
        elif ctype == "timepoint_contrast":
            baseline_condition = contrast_value(contrast, "baseline_condition") or fallback_condition
            response_condition = contrast_value(contrast, "response_condition") or fallback_condition
            baseline_timepoint = contrast_value(contrast, "from_timepoint", "baseline_timepoint")
            response_timepoint = contrast_value(contrast, "to_timepoint", "response_timepoint")
        else:
            continue
        if all([baseline_condition, response_condition, baseline_timepoint, response_timepoint]):
            return {
                "name": name,
                "type": ctype,
                "baseline_condition": baseline_condition,
                "response_condition": response_condition,
                "baseline_timepoint": baseline_timepoint,
                "response_timepoint": response_timepoint,
            }
    raise RuntimeError("No supported contrast with resolvable baseline/response labels was found in study_profile")


def contrast_label(contrast, side):
    return f"{contrast[side + '_condition']}|{contrast[side + '_timepoint']}"


def sample_id_for(sample_id, side):
    return f"{sample_id}_{side}"


def duplicate_omics_rows(fields, rows, contrast):
    required = ["sample_id", "omics_type", "condition", "timepoint"]
    missing = [field for field in required if field not in fields]
    if missing:
        raise RuntimeError(f"Omics samplesheet is missing required column(s): {', '.join(missing)}")

    expanded = []
    sample_map = {omics_type: [] for omics_type in SUPPORTED_OMICS_TYPES}
    for row in rows:
        omics_type = normalize_omics_type(row.get("omics_type"))
        if omics_type not in SUPPORTED_OMICS_TYPES:
            continue
        sample_id = norm(row.get("sample_id"))
        if not sample_id:
            continue
        for side in ["baseline", "response"]:
            copied = dict(row)
            copied["sample_id"] = sample_id_for(sample_id, side)
            copied["omics_type"] = omics_type
            copied["condition"] = contrast[f"{side}_condition"]
            copied["timepoint"] = contrast[f"{side}_timepoint"]
            expanded.append(copied)
            sample_map[omics_type].append(
                {
                    "source_sample_id": sample_id,
                    "stub_sample_id": copied["sample_id"],
                    "side": side,
                    "species": norm(row.get("species")),
                }
            )
    return expanded, sample_map


def duplicate_counts(counts_path, omics_type, sample_map, output_path):
    fields, rows = read_rows(counts_path)
    metadata_fields = COUNT_METADATA_FIELDS[omics_type]
    missing = [field for field in metadata_fields if field not in fields]
    if missing:
        raise RuntimeError(f"{omics_type} count matrix is missing column(s): {', '.join(missing)}")

    source_samples = [field for field in fields if field not in metadata_fields]
    source_lookup = {entry["source_sample_id"]: [] for entry in sample_map}
    for entry in sample_map:
        source_lookup.setdefault(entry["source_sample_id"], []).append(entry)

    output_sample_fields = []
    for sample_id in source_samples:
        for entry in source_lookup.get(sample_id, []):
            output_sample_fields.append(entry["stub_sample_id"])
    if not output_sample_fields:
        raise RuntimeError(f"No {omics_type} count columns matched the omics samplesheet")

    output_rows = []
    for row in rows:
        out = {field: row.get(field, "") for field in metadata_fields}
        for sample_id in source_samples:
            for entry in source_lookup.get(sample_id, []):
                out[entry["stub_sample_id"]] = row.get(sample_id, "")
        output_rows.append(out)
    write_table(output_path, metadata_fields + output_sample_fields, output_rows, "\t")
    return len(output_rows), len(output_sample_fields)


def prepare(args):
    fields, omics_rows = read_rows(args.omics_samplesheet)
    contrast = choose_contrast(args.study_profile, omics_rows)
    expanded_rows, sample_map = duplicate_omics_rows(fields, omics_rows, contrast)

    os.makedirs(args.output_dir, exist_ok=True)
    samplesheet_out = os.path.join(args.output_dir, "omics_samplesheet_contrast_stub.csv")
    write_table(samplesheet_out, fields, expanded_rows, ",")

    summary_rows = [
        {
            "record_type": "contrast",
            "key": "name",
            "value": contrast["name"],
            "status": "COMPLETE",
            "message": "Profile contrast used for all-run stub omics labels",
        },
        {
            "record_type": "contrast",
            "key": "baseline_label",
            "value": contrast_label(contrast, "baseline"),
            "status": "COMPLETE",
            "message": "",
        },
        {
            "record_type": "contrast",
            "key": "response_label",
            "value": contrast_label(contrast, "response"),
            "status": "COMPLETE",
            "message": "",
        },
    ]
    for omics_type, counts_path in [("rnaseq", args.rnaseq_counts), ("atacseq", args.atacseq_counts)]:
        output_path = os.path.join(args.output_dir, f"{omics_type}_counts_contrast_stub.tsv")
        n_features, n_samples = duplicate_counts(counts_path, omics_type, sample_map[omics_type], output_path)
        summary_rows.append(
            {
                "record_type": "counts",
                "key": omics_type,
                "value": output_path,
                "status": "COMPLETE",
                "message": f"features={n_features}; samples={n_samples}",
            }
        )
    summary_rows.append(
        {
            "record_type": "samplesheet",
            "key": "expanded_samples",
            "value": str(len(expanded_rows)),
            "status": "COMPLETE",
            "message": "Stub-mode all-run duplicates synthetic omics samples into baseline and response labels",
        }
    )
    write_table(
        os.path.join(args.output_dir, "omics_contrast_stub_summary.tsv"),
        ["record_type", "key", "value", "status", "message"],
        summary_rows,
        "\t",
    )
    print(
        "CAME all-run stub omics contrast summary: "
        f"contrast={contrast['name']} expanded_samples={len(expanded_rows)}"
    )


def parse_args():
    parser = argparse.ArgumentParser(description="Prepare CAME all-run contrast-ready stub omics inputs.")
    parser.add_argument("--omics_samplesheet", required=True)
    parser.add_argument("--study_profile", required=True)
    parser.add_argument("--rnaseq_counts", required=True)
    parser.add_argument("--atacseq_counts", required=True)
    parser.add_argument("--output_dir", default="input")
    return parser.parse_args()


def main():
    try:
        prepare(parse_args())
    except Exception as exc:
        print(f"ERROR\tprepare_all_stub_omics_contrasts\t{exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
