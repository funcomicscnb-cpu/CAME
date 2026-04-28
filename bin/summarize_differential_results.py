#!/usr/bin/env python3
"""Summarize CAME Stage 6 differential omics outputs."""

import argparse
import csv
import os
import sys


MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}
SUMMARY_FIELDS = ["omics_type", "contrast_name", "species", "status", "n_features", "n_tested", "n_filtered", "n_significant", "method", "warnings"]
MANIFEST_FIELDS = ["omics_type", "output_type", "path", "exists", "status"]


def norm(value):
    text = str(value if value is not None else "").strip()
    return "" if text.lower() in MISSING_VALUES else text


def read_tsv(path):
    if not path or not os.path.exists(path):
        return []
    with open(path, newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        return [{field: norm(row.get(field)) for field in (reader.fieldnames or [])} for row in reader]


def write_tsv(path, fields, rows):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, delimiter="\t", extrasaction="ignore", quoting=csv.QUOTE_NONE, escapechar="\\", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def summarize(args):
    outputs = {
        "rnaseq": {
            "results": args.rnaseq_results,
            "normalized_counts": args.rnaseq_normalized,
            "warnings": args.rnaseq_warnings,
            "summary": args.rnaseq_summary,
        },
        "atacseq": {
            "results": args.atacseq_results,
            "normalized_counts": args.atacseq_normalized,
            "warnings": args.atacseq_warnings,
            "summary": args.atacseq_summary,
        },
        "input": {
            "manifest": args.input_manifest,
            "warnings": args.input_warnings,
        },
    }
    summary_rows = []
    manifest_rows = []
    for omics_type in ["rnaseq", "atacseq"]:
        summary_rows.extend(read_tsv(outputs[omics_type]["summary"]))
        for output_type, path in outputs[omics_type].items():
            manifest_rows.append(
                {
                    "omics_type": omics_type,
                    "output_type": output_type,
                    "path": path,
                    "exists": "true" if path and os.path.exists(path) else "false",
                    "status": "OK" if path and os.path.exists(path) else "ERROR",
                }
            )
    for output_type, path in outputs["input"].items():
        manifest_rows.append(
            {
                "omics_type": "input",
                "output_type": output_type,
                "path": path,
                "exists": "true" if path and os.path.exists(path) else "false",
                "status": "OK" if path and os.path.exists(path) else "ERROR",
            }
        )
    write_tsv(os.path.join(args.output_dir, "differential_omics_summary.tsv"), SUMMARY_FIELDS, summary_rows)
    write_tsv(os.path.join(args.output_dir, "differential_outputs_manifest.tsv"), MANIFEST_FIELDS, manifest_rows)
    errors = sum(1 for row in manifest_rows if row["status"] == "ERROR")
    print(f"CAME differential output summary: ERROR={errors} contrasts={len(summary_rows)}")
    return 1 if errors else 0


def parse_args():
    parser = argparse.ArgumentParser(description="Summarize CAME Stage 6 differential omics outputs.")
    parser.add_argument("--input_manifest", required=True)
    parser.add_argument("--input_warnings", required=True)
    parser.add_argument("--rnaseq_results", required=True)
    parser.add_argument("--rnaseq_normalized", required=True)
    parser.add_argument("--rnaseq_warnings", required=True)
    parser.add_argument("--rnaseq_summary", required=True)
    parser.add_argument("--atacseq_results", required=True)
    parser.add_argument("--atacseq_normalized", required=True)
    parser.add_argument("--atacseq_warnings", required=True)
    parser.add_argument("--atacseq_summary", required=True)
    parser.add_argument("--output_dir", default="results/differential_omics/summary")
    return parser.parse_args()


def main():
    try:
        return summarize(parse_args())
    except Exception as exc:
        print(f"ERROR\tsummarize_differential_results\t{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
