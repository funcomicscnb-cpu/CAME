#!/usr/bin/env python3
"""Compute pairwise CAME species contrasts for phenotype and molecular responses."""

import argparse
import csv
import math
import os
import sys
from collections import Counter, defaultdict
from itertools import combinations


MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}
PAIRWISE_FIELDS = [
    "species_a",
    "species_b",
    "contrast_name",
    "baseline_label",
    "response_label",
    "phenotype_response_id",
    "phenotype_response_metric",
    "feature_layer",
    "feature_id",
    "feature_response_metric",
    "delta_phenotype_response",
    "delta_feature_response",
    "direction_match",
    "status",
]
SUMMARY_FIELDS = ["metric", "value"]


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


def read_table(path, required=True):
    if not path or not os.path.exists(path):
        if required:
            raise RuntimeError(f"Missing required table: {path}")
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


def write_tsv(path, fields, rows):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, delimiter="\t", extrasaction="ignore", quoting=csv.QUOTE_NONE, escapechar="\\", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def parse_float(value):
    text = norm(value)
    if not text:
        return None
    try:
        value = float(text)
    except ValueError:
        return None
    if math.isnan(value) or math.isinf(value):
        return None
    return value


def fmt(value):
    if value is None:
        return "NA"
    return f"{value:.12g}"


def require_fields(fields, required, source):
    missing = [field for field in required if field not in fields]
    if missing:
        raise RuntimeError(f"{source} missing required column(s): {', '.join(missing)}")


def selected_phenotypes(rows, scope):
    if scope == "index":
        return [row for row in rows if row.get("phenotype_response_type") == "phenotype_index"]
    if scope == "all":
        return rows
    raise RuntimeError(f"Unsupported phenotype_response_scope: {scope}")


def pair_list(species, species_pairs_path):
    species = sorted(set(species))
    if species_pairs_path and os.path.exists(species_pairs_path):
        fields, rows = read_table(species_pairs_path)
        require_fields(fields, ["species_a", "species_b"], "species_pairs")
        pairs = []
        for row in rows:
            left = norm(row.get("species_a"))
            right = norm(row.get("species_b"))
            if left and right:
                pairs.append((left, right))
        return pairs
    return list(combinations(species, 2))


def direction(delta_pheno, delta_feature):
    if delta_pheno is None or delta_feature is None or delta_pheno == 0 or delta_feature == 0:
        return "zero_or_missing"
    return "same" if (delta_pheno > 0 and delta_feature > 0) or (delta_pheno < 0 and delta_feature < 0) else "opposite"


def key_fields(row):
    return (
        norm(row.get("contrast_name")),
        norm(row.get("baseline_label")),
        norm(row.get("response_label")),
    )


def run_pairwise(args):
    phenotype_fields, phenotype_rows = read_table(args.phenotype_response_table)
    molecular_fields, molecular_rows = read_table(args.molecular_response_long)
    require_fields(phenotype_fields, ["species", "contrast_name", "baseline_label", "response_label", "phenotype_response_id", "phenotype_response_metric", "phenotype_response_value"], "phenotype_response_table")
    require_fields(molecular_fields, ["species", "contrast_name", "baseline_label", "response_label", "feature_layer", "feature_id", "feature_response_metric", "feature_response_value"], "molecular_response_long")

    phenotype_rows = selected_phenotypes(phenotype_rows, args.phenotype_response_scope)
    phenotype_index = defaultdict(dict)
    molecular_index = defaultdict(dict)
    species_values = set()
    for row in phenotype_rows:
        species = norm(row.get("species"))
        if not species:
            continue
        species_values.add(species)
        key = key_fields(row) + (norm(row.get("phenotype_response_id")), norm(row.get("phenotype_response_metric")))
        phenotype_index[key][species] = parse_float(row.get("phenotype_response_value"))
    for row in molecular_rows:
        species = norm(row.get("species"))
        feature_id = norm(row.get("feature_id"))
        if not species or not feature_id:
            continue
        species_values.add(species)
        key = key_fields(row) + (norm(row.get("feature_layer")), feature_id, norm(row.get("feature_response_metric")))
        molecular_index[key][species] = parse_float(row.get("feature_response_value"))

    pairs = pair_list(species_values, args.species_pairs)
    output = []
    for pkey, pvalues in sorted(phenotype_index.items()):
        contrast_name, baseline_label, response_label, phenotype_id, phenotype_metric = pkey
        for mkey, mvalues in sorted(molecular_index.items()):
            if mkey[:3] != pkey[:3]:
                continue
            feature_layer, feature_id, feature_metric = mkey[3:]
            for species_a, species_b in pairs:
                if species_a not in pvalues or species_b not in pvalues or species_a not in mvalues or species_b not in mvalues:
                    continue
                delta_pheno = None if pvalues[species_a] is None or pvalues[species_b] is None else pvalues[species_b] - pvalues[species_a]
                delta_feature = None if mvalues[species_a] is None or mvalues[species_b] is None else mvalues[species_b] - mvalues[species_a]
                match = direction(delta_pheno, delta_feature)
                status = "OK" if match != "zero_or_missing" else "WARNING"
                output.append(
                    {
                        "species_a": species_a,
                        "species_b": species_b,
                        "contrast_name": contrast_name,
                        "baseline_label": baseline_label,
                        "response_label": response_label,
                        "phenotype_response_id": phenotype_id,
                        "phenotype_response_metric": phenotype_metric,
                        "feature_layer": feature_layer,
                        "feature_id": feature_id,
                        "feature_response_metric": feature_metric,
                        "delta_phenotype_response": fmt(delta_pheno),
                        "delta_feature_response": fmt(delta_feature),
                        "direction_match": match,
                        "status": status,
                    }
                )

    counts = Counter(row["direction_match"] for row in output)
    summary = [
        {"metric": "n_pairwise_contrasts", "value": str(len(output))},
        {"metric": "n_direction_same", "value": str(counts.get("same", 0))},
        {"metric": "n_direction_opposite", "value": str(counts.get("opposite", 0))},
        {"metric": "n_direction_zero_or_missing", "value": str(counts.get("zero_or_missing", 0))},
    ]
    os.makedirs(args.output_dir, exist_ok=True)
    write_tsv(os.path.join(args.output_dir, "pairwise_species_molecular_contrasts.tsv"), PAIRWISE_FIELDS, output)
    write_tsv(os.path.join(args.output_dir, "pairwise_species_contrast_summary.tsv"), SUMMARY_FIELDS, summary)
    print(f"CAME pairwise species contrast summary: pairs={len(output)}")
    return 0


def parse_args():
    parser = argparse.ArgumentParser(description="Run CAME Stage 9 pairwise species contrasts.")
    parser.add_argument("--phenotype_response_table", default="results/integration/input/phenotype_response_table.tsv")
    parser.add_argument("--molecular_response_long", default="results/integration/input/molecular_response_long.tsv")
    parser.add_argument("--species_pairs", default="")
    parser.add_argument("--phenotype_response_scope", default="index", choices=["index", "all"])
    parser.add_argument("--output_dir", default="results/integration/pairwise")
    return parser.parse_args()


def main():
    try:
        return run_pairwise(parse_args())
    except Exception as exc:
        print(f"ERROR\trun_pairwise_species_contrasts\t{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
