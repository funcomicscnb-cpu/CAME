#!/usr/bin/env python3
"""Cluster CAME molecular responses by cross-species response pattern."""

import argparse
import csv
import math
import os
import re
import sys
from collections import Counter, defaultdict


MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}
LAYERS = ["expression", "accessibility", "gra_activity"]
CLUSTER_FIELDS = [
    "feature_layer",
    "feature_id",
    "contrast_name",
    "cluster_id",
    "cluster_label",
    "species_pattern",
    "n_species",
    "mean_response",
    "response_direction",
]
SUMMARY_FIELDS = ["feature_layer", "contrast_name", "cluster_label", "n_features"]


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
    if not path or not os.path.exists(path):
        raise RuntimeError(f"Missing required molecular response table: {path}")
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


def sign(value):
    if value is None:
        return "NA"
    if value > 0:
        return "+"
    if value < 0:
        return "-"
    return "0"


def sanitize(value):
    return re.sub(r"[^A-Za-z0-9_.-]+", "_", value).strip("_") or "cluster"


def response_label(values):
    numeric = [value for value in values if value is not None]
    if len(numeric) < 2:
        return "insufficient_data"
    positives = sum(1 for value in numeric if value > 0)
    negatives = sum(1 for value in numeric if value < 0)
    zeros = sum(1 for value in numeric if value == 0)
    if positives == len(numeric):
        return "shared_up"
    if negatives == len(numeric):
        return "shared_down"
    if positives + negatives == 1 and zeros >= 1:
        return "species_specific"
    if positives and not negatives:
        return "lineage_or_subset_specific"
    if negatives and not positives:
        return "lineage_or_subset_specific"
    if positives and negatives:
        return "mixed"
    return "insufficient_data"


def direction(values):
    numeric = [value for value in values if value is not None]
    positives = sum(1 for value in numeric if value > 0)
    negatives = sum(1 for value in numeric if value < 0)
    if positives and not negatives:
        return "up"
    if negatives and not positives:
        return "down"
    if positives and negatives:
        return "mixed"
    return "none"


def sign_cluster_id(pattern, label):
    return f"sign_{label}_{sanitize(pattern)}"


def hclust_ids(grouped):
    try:
        from scipy.cluster.hierarchy import fcluster, linkage
        from scipy.spatial.distance import pdist
    except Exception:
        print("WARNING\tcluster_molecular_responses\tSciPy unavailable; falling back to sign-pattern clustering", file=sys.stderr)
        return {}

    ids = {}
    for (layer, contrast), items in grouped.items():
        species = sorted({species for _, species_values in items for species in species_values})
        if len(items) < 2 or not species:
            for feature_id, _ in items:
                ids[(layer, contrast, feature_id)] = "hclust_1"
            continue
        matrix = []
        valid_features = []
        for feature_id, species_values in items:
            matrix.append([species_values.get(item) if species_values.get(item) is not None else 0.0 for item in species])
            valid_features.append(feature_id)
        try:
            distances = pdist(matrix, metric="euclidean")
            if len(distances) == 0:
                labels = [1] * len(valid_features)
            else:
                labels = fcluster(linkage(distances, method="average"), t=1.0, criterion="distance")
        except Exception as exc:
            print(f"WARNING\tcluster_molecular_responses\tHierarchical clustering failed for {layer}/{contrast}; using one cluster: {exc}", file=sys.stderr)
            labels = [1] * len(valid_features)
        for feature_id, label in zip(valid_features, labels):
            ids[(layer, contrast, feature_id)] = f"hclust_{int(label)}"
    return ids


def cluster(args):
    fields, rows = read_table(args.molecular_response_long)
    missing = [field for field in ["species", "contrast_name", "feature_layer", "feature_id", "feature_response_value"] if field not in fields]
    if missing:
        raise RuntimeError(f"molecular response table missing required column(s): {', '.join(missing)}")

    values = defaultdict(dict)
    for row in rows:
        layer = norm(row.get("feature_layer"))
        contrast = norm(row.get("contrast_name"))
        feature_id = norm(row.get("feature_id"))
        species = norm(row.get("species"))
        value = parse_float(row.get("feature_response_value"))
        if not layer or not contrast or not feature_id or not species:
            continue
        values[(layer, contrast, feature_id)][species] = value

    grouped_for_hclust = defaultdict(list)
    for (layer, contrast, feature_id), species_values in values.items():
        grouped_for_hclust[(layer, contrast)].append((feature_id, species_values))
    hids = hclust_ids(grouped_for_hclust) if args.method in {"hierarchical", "hclust"} else {}

    output_by_layer = {layer: [] for layer in LAYERS}
    summary_counts = Counter()
    for (layer, contrast, feature_id), species_values in sorted(values.items()):
        ordered_species = sorted(species_values)
        numeric = [species_values[item] for item in ordered_species if species_values[item] is not None]
        pattern = ";".join(f"{species}:{sign(species_values[species])}" for species in ordered_species)
        label = response_label([species_values[item] for item in ordered_species])
        cluster_id = hids.get((layer, contrast, feature_id)) or sign_cluster_id(pattern, label)
        row = {
            "feature_layer": layer,
            "feature_id": feature_id,
            "contrast_name": contrast,
            "cluster_id": cluster_id,
            "cluster_label": label,
            "species_pattern": pattern,
            "n_species": str(len(numeric)),
            "mean_response": fmt(sum(numeric) / len(numeric) if numeric else None),
            "response_direction": direction(numeric),
        }
        output_by_layer.setdefault(layer, []).append(row)
        summary_counts[(layer, contrast, label)] += 1

    os.makedirs(args.output_dir, exist_ok=True)
    for layer in LAYERS:
        write_tsv(os.path.join(args.output_dir, f"response_clusters_{layer}.tsv"), CLUSTER_FIELDS, output_by_layer.get(layer, []))
    summary = [
        {
            "feature_layer": layer,
            "contrast_name": contrast,
            "cluster_label": label,
            "n_features": str(count),
        }
        for (layer, contrast, label), count in sorted(summary_counts.items())
    ]
    write_tsv(os.path.join(args.output_dir, "response_cluster_summary.tsv"), SUMMARY_FIELDS, summary)
    print(f"CAME molecular response clustering summary: features={sum(len(rows) for rows in output_by_layer.values())} method={args.method}")
    return 0


def parse_args():
    parser = argparse.ArgumentParser(description="Cluster CAME molecular response patterns.")
    parser.add_argument("--molecular_response_long", default="results/integration/input/molecular_response_long.tsv")
    parser.add_argument("--method", default="sign", choices=["sign", "hierarchical", "hclust"])
    parser.add_argument("--output_dir", default="results/integration/clustering")
    return parser.parse_args()


def main():
    try:
        return cluster(parse_args())
    except Exception as exc:
        print(f"ERROR\tcluster_molecular_responses\t{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
