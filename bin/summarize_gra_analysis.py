#!/usr/bin/env python3
"""Summarize CAME Stage 8 GRA analysis outputs."""

import argparse
import csv
import os
import statistics
import sys


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


def summarize(args):
    validation_fields, validation_rows = read_table(args.validation_report)
    arch_fields, architecture_rows = read_table(args.gene_regulatory_architectures)
    membership_fields, membership_rows = read_table(args.gra_re_membership)
    diff_fields, diff_rows = read_table(args.differential_gra_activity)
    gene_fields, gene_rows = read_table(args.gene_orthogroup_counts)

    summary = []
    validation_link_rows = [row for row in validation_rows if row.get("record_type") == "link" and row.get("field") == "orthogroup_resolution"]
    resolved_links = [row for row in validation_link_rows if row.get("status") in {"resolved", "ambiguous"}]
    ambiguous_links = [row for row in membership_rows if row.get("is_ambiguous") == "true"]
    metric(summary, "n_re_to_gene_links", len(validation_link_rows), args.validation_report)
    metric(summary, "n_resolved_links", len(resolved_links), args.validation_report)
    metric(summary, "n_gras", len(architecture_rows), args.gene_regulatory_architectures)
    metric(summary, "n_ambiguous_links", len(ambiguous_links), args.gra_re_membership)

    re_counts = []
    for row in architecture_rows:
        try:
            re_counts.append(int(row.get("n_res", "0")))
        except ValueError:
            pass
    if re_counts:
        metric(summary, "min_res_per_gra", min(re_counts), args.gene_regulatory_architectures)
        metric(summary, "median_res_per_gra", statistics.median(re_counts), args.gene_regulatory_architectures)
        metric(summary, "max_res_per_gra", max(re_counts), args.gene_regulatory_architectures)
    else:
        metric(summary, "min_res_per_gra", 0, args.gene_regulatory_architectures)
        metric(summary, "median_res_per_gra", 0, args.gene_regulatory_architectures)
        metric(summary, "max_res_per_gra", 0, args.gene_regulatory_architectures)

    gene_orthogroups = {row.get("orthogroup_id") for row in gene_rows if row.get("orthogroup_id")}
    gra_genes = {row.get("gene_orthogroup_id") for row in architecture_rows if row.get("gene_orthogroup_id")}
    if gene_orthogroups:
        metric(summary, "n_genes_with_no_res", len(gene_orthogroups - gra_genes), args.gene_orthogroup_counts)
    else:
        metric(summary, "n_genes_with_no_res", "NA", args.gene_orthogroup_counts)

    differential_gras = {row.get("gra_id") for row in diff_rows if row.get("gra_id")}
    metric(summary, "n_differential_gra_rows", len(diff_rows), args.differential_gra_activity)
    metric(summary, "n_differential_gras", len(differential_gras), args.differential_gra_activity)

    manifest = [
        manifest_row("re_to_gene_link_validation_report", args.validation_report),
        manifest_row("gene_regulatory_architectures", args.gene_regulatory_architectures),
        manifest_row("gra_re_membership", args.gra_re_membership),
        manifest_row("gra_link_warnings", args.gra_link_warnings),
        manifest_row("gra_activity_matrix", args.gra_activity_matrix),
        manifest_row("gra_activity_long", args.gra_activity_long),
        manifest_row("gra_activity_contributing_res", args.gra_activity_contributing_res),
        manifest_row("gra_activity_warnings", args.gra_activity_warnings),
        manifest_row("differential_gra_activity", args.differential_gra_activity),
        manifest_row("normalized_gra_activity", args.normalized_gra_activity),
        manifest_row("differential_gra_activity_warnings", args.differential_gra_activity_warnings),
    ]
    os.makedirs(args.output_dir, exist_ok=True)
    write_tsv(os.path.join(args.output_dir, "gra_analysis_summary.tsv"), SUMMARY_FIELDS, summary)
    write_tsv(os.path.join(args.output_dir, "gra_outputs_manifest.tsv"), MANIFEST_FIELDS, manifest)
    print(f"CAME GRA summary: GRAs={len(architecture_rows)} resolved_links={len(resolved_links)} differential_rows={len(diff_rows)}")
    return 0


def parse_args():
    parser = argparse.ArgumentParser(description="Summarize CAME GRA analysis outputs.")
    parser.add_argument("--validation_report", required=True)
    parser.add_argument("--gene_orthogroup_counts", default="")
    parser.add_argument("--gene_regulatory_architectures", required=True)
    parser.add_argument("--gra_re_membership", required=True)
    parser.add_argument("--gra_link_warnings", required=True)
    parser.add_argument("--gra_activity_matrix", required=True)
    parser.add_argument("--gra_activity_long", required=True)
    parser.add_argument("--gra_activity_contributing_res", required=True)
    parser.add_argument("--gra_activity_warnings", required=True)
    parser.add_argument("--differential_gra_activity", required=True)
    parser.add_argument("--normalized_gra_activity", required=True)
    parser.add_argument("--differential_gra_activity_warnings", required=True)
    parser.add_argument("--output_dir", default="results/gra/summary")
    return parser.parse_args()


def main():
    try:
        return summarize(parse_args())
    except Exception as exc:
        print(f"ERROR\tsummarize_gra_analysis\t{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
