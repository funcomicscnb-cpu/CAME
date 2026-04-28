#!/usr/bin/env python3
"""Summarize CAME reference preparation inputs and output contracts."""

import argparse
import csv
import os
import sys


MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}
SUMMARY_FIELDS = ["metric", "value"]
MANIFEST_FIELDS = ["reference_id", "species", "output_type", "path", "exists", "mode", "status", "description"]


def norm(value):
    text = str(value if value is not None else "").strip()
    return "" if text.lower() in MISSING_VALUES else text


def read_table(path, delimiter="\t"):
    if not path or not os.path.exists(path):
        return []
    with open(path, newline="") as handle:
        reader = csv.DictReader(handle, delimiter=delimiter)
        return [{key: norm(value) for key, value in row.items()} for row in reader]


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


def parse_bool(value):
    return str(value).strip().lower() in {"1", "true", "t", "yes", "y"}


def resolve_output_path(outputs_root, value):
    path = norm(value)
    if not path or os.path.isabs(path):
        return path
    return os.path.normpath(os.path.join(outputs_root, path))


def summarize(args):
    prepared = read_table(args.prepared_manifest)
    warnings = read_table(args.warnings)
    outputs = read_table(args.outputs_table)
    mode = "stub" if parse_bool(args.reference_stub) else "real"
    outputs_root = os.path.abspath(args.outputs_root)

    manifest_rows = []
    missing_outputs = 0
    for row in outputs:
        path = norm(row.get("path"))
        resolved = resolve_output_path(outputs_root, path)
        exists = bool(resolved and os.path.exists(resolved) and os.path.getsize(resolved) > 0)
        if not exists:
            missing_outputs += 1
        manifest_rows.append(
            {
                "reference_id": norm(row.get("reference_id")),
                "species": norm(row.get("species")),
                "output_type": norm(row.get("output_type")),
                "path": path,
                "exists": "true" if exists else "false",
                "mode": norm(row.get("mode")) or mode,
                "status": "OK" if exists else "ERROR",
                "description": norm(row.get("description")),
            }
        )

    wgs_samples = {norm(row.get("sample_id")) for row in prepared if norm(row.get("sample_id"))}
    references = {norm(row.get("reference_id")) for row in prepared if norm(row.get("reference_id"))}
    species = {norm(row.get("species")) for row in prepared if norm(row.get("species"))}
    warning_count = sum(1 for row in warnings if norm(row.get("severity")) == "WARNING")
    error_count = sum(1 for row in warnings if norm(row.get("severity")) == "ERROR")
    status = "OK" if missing_outputs == 0 and error_count == 0 else "ERROR"

    summary_rows = [
        {"metric": "mode", "value": mode},
        {"metric": "wgs_samples", "value": str(len(wgs_samples))},
        {"metric": "references", "value": str(len(references))},
        {"metric": "species", "value": str(len(species))},
        {"metric": "outputs_expected", "value": str(len(outputs))},
        {"metric": "outputs_generated", "value": str(len(outputs) - missing_outputs)},
        {"metric": "warnings", "value": str(warning_count)},
        {"metric": "errors", "value": str(error_count)},
        {"metric": "status", "value": status},
    ]

    write_tsv(os.path.join(args.output_dir, "reference_prepare_summary.tsv"), SUMMARY_FIELDS, summary_rows)
    write_tsv(os.path.join(args.output_dir, "reference_outputs_manifest.tsv"), MANIFEST_FIELDS, manifest_rows)
    print(
        "CAME reference preparation summary: "
        f"mode={mode} samples={len(wgs_samples)} references={len(references)} outputs={len(outputs) - missing_outputs}/{len(outputs)}"
    )
    return 1 if status == "ERROR" else 0


def parse_args():
    parser = argparse.ArgumentParser(description="Summarize CAME reference preparation outputs.")
    parser.add_argument("--prepared_manifest", required=True)
    parser.add_argument("--warnings", required=True)
    parser.add_argument("--outputs_table", required=True)
    parser.add_argument("--outputs_root", default=".")
    parser.add_argument("--reference_stub", default="true")
    parser.add_argument("--output_dir", default="results/reference/summary")
    return parser.parse_args()


def main():
    try:
        return summarize(parse_args())
    except Exception as exc:
        print(f"ERROR\tsummarize_reference_prepare\t{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
