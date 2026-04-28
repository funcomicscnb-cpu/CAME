#!/usr/bin/env python3
"""Summarize CAME phenotype-omics integration outputs."""

import argparse
import csv
import os
import sys
from collections import Counter


MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}
SUMMARY_FIELDS = ["metric", "value", "source"]
MANIFEST_FIELDS = ["output_name", "path", "status", "n_rows"]


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


def metric(rows, name, value, source):
    rows.append({"metric": name, "value": str(value), "source": source})


def count_rows(path):
    _, rows = read_table(path)
    return len(rows)


def manifest_row(name, path):
    if path and os.path.exists(path):
        return {"output_name": name, "path": path, "status": "present", "n_rows": str(count_rows(path))}
    return {"output_name": name, "path": path or "", "status": "missing", "n_rows": "0"}


def summarize_associations(rows):
    counts = Counter()
    for row in rows:
        key = (norm(row.get("model_type")), norm(row.get("status")))
        counts[key] += 1
    return counts


def summarize(args):
    _, phenotype_rows = read_table(args.phenotype_response_table)
    _, molecular_rows = read_table(args.molecular_response_long)
    _, model_rows = read_table(args.model_table)
    _, expression_assoc = read_table(args.phenotype_expression_associations)
    _, accessibility_assoc = read_table(args.phenotype_accessibility_associations)
    _, gra_assoc = read_table(args.phenotype_gra_associations)
    _, assoc_warnings = read_table(args.association_warnings)
    _, cluster_summary = read_table(args.response_cluster_summary)
    _, pairwise_rows = read_table(args.pairwise_species_molecular_contrasts)

    summary = []
    metric(summary, "n_phenotype_responses", len(phenotype_rows), args.phenotype_response_table)
    metric(summary, "n_model_rows", len(model_rows), args.model_table)
    layer_features = {}
    for row in molecular_rows:
        layer = norm(row.get("feature_layer"))
        feature = norm(row.get("feature_id"))
        if layer and feature:
            layer_features.setdefault(layer, set()).add(feature)
    for layer in ["expression", "accessibility", "gra_activity"]:
        metric(summary, f"n_molecular_features_{layer}", len(layer_features.get(layer, set())), args.molecular_response_long)

    assoc_rows = expression_assoc + accessibility_assoc + gra_assoc
    assoc_counts = summarize_associations(assoc_rows)
    metric(summary, "n_successful_lm_associations", assoc_counts.get(("lm", "OK"), 0), "associations")
    metric(summary, "n_successful_pgls_associations", assoc_counts.get(("pgls_brownian", "OK"), 0), "associations")
    metric(summary, "n_skipped_lm_associations", assoc_counts.get(("lm", "SKIPPED"), 0), "associations")
    metric(summary, "n_skipped_pgls_associations", assoc_counts.get(("pgls_brownian", "SKIPPED"), 0), "associations")

    warning_reasons = Counter(norm(row.get("message")) for row in assoc_warnings if norm(row.get("message")))
    for reason, count in sorted(warning_reasons.items()):
        metric(summary, "n_skipped_associations_reason", count, reason)

    cluster_counts = Counter((norm(row.get("feature_layer")), norm(row.get("cluster_label"))) for row in cluster_summary)
    for (layer, label), count in sorted(cluster_counts.items()):
        if layer and label:
            metric(summary, f"n_clusters_{layer}_{label}", count, args.response_cluster_summary)
    metric(summary, "n_pairwise_contrasts", len(pairwise_rows), args.pairwise_species_molecular_contrasts)

    manifest = [
        manifest_row("phenotype_response_table", args.phenotype_response_table),
        manifest_row("molecular_response_long", args.molecular_response_long),
        manifest_row("phenotype_omics_model_table", args.model_table),
        manifest_row("phenotype_omics_input_warnings", args.input_warnings),
        manifest_row("response_clusters_expression", args.response_clusters_expression),
        manifest_row("response_clusters_accessibility", args.response_clusters_accessibility),
        manifest_row("response_clusters_gra_activity", args.response_clusters_gra_activity),
        manifest_row("response_cluster_summary", args.response_cluster_summary),
        manifest_row("phenotype_expression_associations", args.phenotype_expression_associations),
        manifest_row("phenotype_accessibility_associations", args.phenotype_accessibility_associations),
        manifest_row("phenotype_gra_associations", args.phenotype_gra_associations),
        manifest_row("phenotype_omics_association_warnings", args.association_warnings),
        manifest_row("pairwise_species_molecular_contrasts", args.pairwise_species_molecular_contrasts),
        manifest_row("pairwise_species_contrast_summary", args.pairwise_species_contrast_summary),
    ]
    os.makedirs(args.output_dir, exist_ok=True)
    write_tsv(os.path.join(args.output_dir, "phenotype_omics_integration_summary.tsv"), SUMMARY_FIELDS, summary)
    write_tsv(os.path.join(args.output_dir, "phenotype_omics_outputs_manifest.tsv"), MANIFEST_FIELDS, manifest)
    print(f"CAME phenotype-omics integration summary: model_rows={len(model_rows)} associations={len(assoc_rows)} pairwise={len(pairwise_rows)}")
    return 0


def parse_args():
    parser = argparse.ArgumentParser(description="Summarize CAME Stage 9 outputs.")
    parser.add_argument("--phenotype_response_table", required=True)
    parser.add_argument("--molecular_response_long", required=True)
    parser.add_argument("--model_table", required=True)
    parser.add_argument("--input_warnings", required=True)
    parser.add_argument("--response_clusters_expression", required=True)
    parser.add_argument("--response_clusters_accessibility", required=True)
    parser.add_argument("--response_clusters_gra_activity", required=True)
    parser.add_argument("--response_cluster_summary", required=True)
    parser.add_argument("--phenotype_expression_associations", required=True)
    parser.add_argument("--phenotype_accessibility_associations", required=True)
    parser.add_argument("--phenotype_gra_associations", required=True)
    parser.add_argument("--association_warnings", required=True)
    parser.add_argument("--pairwise_species_molecular_contrasts", required=True)
    parser.add_argument("--pairwise_species_contrast_summary", required=True)
    parser.add_argument("--output_dir", default="results/integration/summary")
    return parser.parse_args()


def main():
    try:
        return summarize(parse_args())
    except Exception as exc:
        print(f"ERROR\tsummarize_phenotype_omics_integration\t{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
