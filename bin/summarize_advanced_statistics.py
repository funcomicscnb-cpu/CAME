#!/usr/bin/env python3
"""Summarize optional CAME advanced-statistics scaffold outputs."""

import argparse
import csv
import os
import sys
from collections import Counter


SUMMARY_FIELDS = ["metric", "value", "source"]
MANIFEST_FIELDS = ["output_name", "path", "status", "n_rows"]
MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}


def norm(value):
    text = str(value if value is not None else "").strip()
    return "" if text.lower() in MISSING_VALUES else text


def read_table(path):
    if not path or not os.path.exists(path):
        return [], []
    with open(path, newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        fields = reader.fieldnames or []
        return fields, [dict(row) for row in reader]


def write_tsv(path, fields, rows):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=fields,
            delimiter="\t",
            extrasaction="ignore",
            quoting=csv.QUOTE_NONE,
            escapechar="\\",
            lineterminator="\n",
        )
        writer.writeheader()
        writer.writerows(rows)


def add_metric(rows, metric, value, source):
    rows.append({"metric": metric, "value": str(value), "source": source})


def count_rows(path):
    _, rows = read_table(path)
    return len(rows)


def manifest_row(name, path):
    if path and os.path.exists(path):
        return {"output_name": name, "path": path, "status": "present", "n_rows": str(count_rows(path))}
    return {"output_name": name, "path": path or "", "status": "missing", "n_rows": "0"}


def summarize(args):
    _, manifest_rows = read_table(args.advanced_model_manifest)
    _, input_warnings = read_table(args.advanced_model_warnings)
    _, model_results = read_table(args.model_comparison_results)
    _, model_warnings = read_table(args.model_comparison_warnings)
    _, robustness_results = read_table(args.robustness_check_results)
    _, robustness_warnings = read_table(args.robustness_warnings)

    summary = []
    add_metric(summary, "n_configured_models", len(manifest_rows), args.advanced_model_manifest)
    add_metric(summary, "n_enabled_models", sum(1 for row in manifest_rows if norm(row.get("enabled")) == "true"), args.advanced_model_manifest)
    status_counts = Counter(norm(row.get("status")) for row in manifest_rows)
    for status, count in sorted(status_counts.items()):
        if status:
            add_metric(summary, f"n_models_{status.lower()}", count, args.advanced_model_manifest)

    family_counts = Counter(norm(row.get("model_family")) for row in manifest_rows)
    for family, count in sorted(family_counts.items()):
        if family:
            add_metric(summary, f"n_configured_family_{family}", count, args.advanced_model_manifest)

    model_status = Counter(norm(row.get("status")) for row in model_results)
    add_metric(summary, "n_model_comparison_rows", len(model_results), args.model_comparison_results)
    add_metric(summary, "n_model_comparison_ok", model_status.get("OK", 0), args.model_comparison_results)
    add_metric(summary, "n_model_comparison_warnings", len(model_warnings), args.model_comparison_warnings)

    robust_status = Counter(norm(row.get("status")) for row in robustness_results)
    add_metric(summary, "n_robustness_rows", len(robustness_results), args.robustness_check_results)
    add_metric(summary, "n_robustness_ok", robust_status.get("OK", 0), args.robustness_check_results)
    add_metric(summary, "n_robustness_warning_rows", robust_status.get("WARNING", 0), args.robustness_check_results)
    add_metric(summary, "n_robustness_warnings", len(robustness_warnings), args.robustness_warnings)

    placeholder_count = sum(1 for row in manifest_rows if norm(row.get("model_family")).endswith("_placeholder"))
    add_metric(summary, "n_placeholder_models", placeholder_count, args.advanced_model_manifest)
    add_metric(summary, "n_input_warnings", len(input_warnings), args.advanced_model_warnings)

    output_dir = args.output_dir
    summary_path = os.path.join(output_dir, "advanced_statistics_summary.tsv")
    manifest_path = os.path.join(output_dir, "advanced_statistics_outputs_manifest.tsv")
    write_tsv(summary_path, SUMMARY_FIELDS, summary)

    outputs = [
        manifest_row("advanced_model_manifest", args.advanced_model_manifest),
        manifest_row("advanced_model_warnings", args.advanced_model_warnings),
        manifest_row("model_comparison_results", args.model_comparison_results),
        manifest_row("model_comparison_warnings", args.model_comparison_warnings),
        manifest_row("robustness_check_results", args.robustness_check_results),
        manifest_row("robustness_warnings", args.robustness_warnings),
        manifest_row("advanced_statistics_summary", summary_path),
    ]
    write_tsv(manifest_path, MANIFEST_FIELDS, outputs)
    print(f"CAME advanced statistics summary: models={len(manifest_rows)} model_results={len(model_results)} robustness_rows={len(robustness_results)}")
    return 0


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--advanced_model_manifest", required=True)
    parser.add_argument("--advanced_model_warnings", required=True)
    parser.add_argument("--model_comparison_results", required=True)
    parser.add_argument("--model_comparison_warnings", required=True)
    parser.add_argument("--robustness_check_results", required=True)
    parser.add_argument("--robustness_warnings", required=True)
    parser.add_argument("--output_dir", default="results/advanced_statistics/summary")
    return parser.parse_args()


def main():
    try:
        return summarize(parse_args())
    except Exception as exc:
        print(f"ERROR\tsummarize_advanced_statistics\t{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
