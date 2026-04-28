#!/usr/bin/env python3
"""Aggregate regulatory-element orthogroup accessibility into GRA activity."""

import argparse
import csv
import os
import statistics
import sys
from collections import defaultdict


MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}
COUNT_META_FIELDS = [
    "orthogroup_id",
    "feature_type",
    "mapping_status",
    "n_source_features",
    "n_species",
    "is_ambiguous",
    "ambiguity_reason",
    "species_members",
    "source_feature_ids",
]
MATRIX_FIELDS_PREFIX = ["gra_id", "gene_orthogroup_id", "feature_type"]
LONG_FIELDS = [
    "gra_id",
    "gene_orthogroup_id",
    "sample_id",
    "species",
    "aggregation",
    "value",
    "n_res_contributing",
    "n_res_total",
    "status",
]
CONTRIBUTING_FIELDS = [
    "gra_id",
    "gene_orthogroup_id",
    "sample_id",
    "re_orthogroup_id",
    "value",
    "weight",
    "used",
]
WARNING_FIELDS = ["severity", "gra_id", "gene_orthogroup_id", "re_orthogroup_id", "sample_id", "message"]


def norm(value):
    text = str(value if value is not None else "").strip()
    return "" if text.lower() in MISSING_VALUES else text


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


def warning(rows, severity, gra_id, gene_id, re_id, sample_id, message):
    rows.append(
        {
            "severity": severity,
            "gra_id": gra_id,
            "gene_orthogroup_id": gene_id,
            "re_orthogroup_id": re_id,
            "sample_id": sample_id,
            "message": message,
        }
    )


def parse_float(value):
    text = norm(value)
    if not text:
        return None
    try:
        return float(text)
    except ValueError:
        return None


def format_number(value):
    if value is None:
        return "NA"
    if abs(value - round(value)) < 1e-9:
        return str(int(round(value)))
    return format(value, ".12g")


def sample_species(omics_samplesheet):
    fields, rows = read_table(omics_samplesheet)
    missing = [field for field in ["sample_id", "species"] if field not in fields]
    if missing:
        raise RuntimeError(f"omics_samplesheet missing required column(s): {', '.join(missing)}")
    return {row["sample_id"]: row["species"] for row in rows if row.get("sample_id")}


def re_count_index(path):
    fields, rows = read_table(path)
    if "orthogroup_id" not in fields:
        raise RuntimeError("re_orthogroup_counts missing required column: orthogroup_id")
    sample_columns = [field for field in fields if field not in set(COUNT_META_FIELDS)]
    values = {}
    for row in rows:
        orthogroup_id = norm(row.get("orthogroup_id"))
        if orthogroup_id:
            values[orthogroup_id] = {sample: parse_float(row.get(sample)) for sample in sample_columns}
    return sample_columns, values


def membership_rows(architecture_path, membership_path):
    path = membership_path or architecture_path
    fields, rows = read_table(path)
    missing = [field for field in ["gra_id", "gene_orthogroup_id", "re_orthogroup_id"] if field not in fields]
    if missing:
        raise RuntimeError(f"{path} missing required GRA membership column(s): {', '.join(missing)}")
    return rows


def row_weight(row):
    for field in ["contact_score", "link_confidence"]:
        value = parse_float(row.get(field))
        if value is not None:
            return value
    return None


def aggregate(values, weights, mode):
    if not values:
        return None, "no_signal"
    if mode == "sum":
        return sum(values), "OK"
    if mode == "median":
        return statistics.median(values), "OK"
    if mode == "max":
        return max(values), "OK"
    if mode == "weighted_mean":
        usable = [(value, weight) for value, weight in zip(values, weights) if weight is not None and weight > 0]
        if usable:
            numerator = sum(value * weight for value, weight in usable)
            denominator = sum(weight for _, weight in usable)
            return numerator / denominator, "OK"
        return sum(values) / len(values), "weighted_mean_fallback_to_mean"
    return sum(values) / len(values), "OK"


def aggregate_activity(args):
    if args.aggregation not in {"mean", "sum", "median", "max", "weighted_mean"}:
        raise RuntimeError(f"Unsupported GRA aggregation mode: {args.aggregation}")
    sample_columns, re_counts = re_count_index(args.re_orthogroup_counts)
    species_by_sample = sample_species(args.omics_samplesheet)
    memberships = membership_rows(args.gene_regulatory_architectures, args.gra_re_membership)

    by_gra_re = {}
    warnings = []
    for row in memberships:
        gra_id = norm(row.get("gra_id"))
        gene_id = norm(row.get("gene_orthogroup_id"))
        re_id = norm(row.get("re_orthogroup_id"))
        if not gra_id or not gene_id or not re_id:
            continue
        key = (gra_id, gene_id, re_id)
        if key not in by_gra_re:
            by_gra_re[key] = dict(row)
        elif args.aggregation == "weighted_mean":
            current = row_weight(by_gra_re[key])
            candidate = row_weight(row)
            if current is None and candidate is not None:
                by_gra_re[key] = dict(row)

    gra_members = defaultdict(list)
    for key, row in by_gra_re.items():
        gra_id, gene_id, re_id = key
        if re_id not in re_counts:
            warning(warnings, "WARNING", gra_id, gene_id, re_id, "", "RE orthogroup absent from re_orthogroup_counts")
            continue
        gra_members[(gra_id, gene_id)].append(row)

    matrix_rows = []
    long_rows = []
    contributing_rows = []
    weighted_fallback_warned = set()
    for gra_id, gene_id in sorted(gra_members):
        rows = sorted(gra_members[(gra_id, gene_id)], key=lambda item: item["re_orthogroup_id"])
        out = {"gra_id": gra_id, "gene_orthogroup_id": gene_id, "feature_type": "gene_regulatory_architecture"}
        for sample in sample_columns:
            values = []
            weights = []
            for row in rows:
                re_id = row["re_orthogroup_id"]
                value = re_counts[re_id].get(sample)
                weight = row_weight(row)
                used = value is not None
                contributing_rows.append(
                    {
                        "gra_id": gra_id,
                        "gene_orthogroup_id": gene_id,
                        "sample_id": sample,
                        "re_orthogroup_id": re_id,
                        "value": format_number(value),
                        "weight": format_number(weight) if weight is not None else "",
                        "used": "true" if used else "false",
                    }
                )
                if used:
                    values.append(value)
                    weights.append(weight)
            value, status = aggregate(values, weights, args.aggregation)
            if status == "weighted_mean_fallback_to_mean" and gra_id not in weighted_fallback_warned:
                warning(warnings, "WARNING", gra_id, gene_id, "", "", "weighted_mean requested but no usable weights were available; used mean")
                weighted_fallback_warned.add(gra_id)
            out[sample] = format_number(value)
            long_rows.append(
                {
                    "gra_id": gra_id,
                    "gene_orthogroup_id": gene_id,
                    "sample_id": sample,
                    "species": species_by_sample.get(sample, ""),
                    "aggregation": args.aggregation,
                    "value": format_number(value),
                    "n_res_contributing": str(len(values)),
                    "n_res_total": str(len(rows)),
                    "status": status,
                }
            )
        matrix_rows.append(out)

    os.makedirs(args.output_dir, exist_ok=True)
    write_tsv(os.path.join(args.output_dir, "gra_activity_matrix.tsv"), MATRIX_FIELDS_PREFIX + sample_columns, matrix_rows)
    write_tsv(os.path.join(args.output_dir, "gra_activity_long.tsv"), LONG_FIELDS, long_rows)
    write_tsv(os.path.join(args.output_dir, "gra_activity_contributing_res.tsv"), CONTRIBUTING_FIELDS, contributing_rows)
    write_tsv(os.path.join(args.output_dir, "gra_activity_warnings.tsv"), WARNING_FIELDS, warnings)
    print(
        "CAME GRA activity summary: "
        f"GRAs={len(matrix_rows)} samples={len(sample_columns)} aggregation={args.aggregation} WARNING={len(warnings)}"
    )
    return 0


def parse_args():
    parser = argparse.ArgumentParser(description="Aggregate CAME GRA activity from RE orthogroup counts.")
    parser.add_argument("--re_orthogroup_counts", required=True)
    parser.add_argument("--gene_regulatory_architectures", required=True)
    parser.add_argument("--gra_re_membership", default="")
    parser.add_argument("--omics_samplesheet", required=True)
    parser.add_argument("--aggregation", default="mean")
    parser.add_argument("--output_dir", default="results/gra/activity")
    return parser.parse_args()


def main():
    try:
        return aggregate_activity(parse_args())
    except Exception as exc:
        print(f"ERROR\taggregate_gra_activity\t{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
