#!/usr/bin/env python3
"""Summarize and validate Stage 5 bulk omics outputs."""

import argparse
import csv
import os
import sys
from collections import defaultdict


MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}


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


def count_header(path):
    if not path or not os.path.exists(path):
        return []
    delimiter = infer_delimiter(path)
    with open(path, newline="") as handle:
        reader = csv.reader(handle, delimiter=delimiter)
        try:
            return [norm(value) for value in next(reader)]
        except StopIteration:
            return []


def warnings_by_sample(path):
    _, rows = read_table(path)
    grouped = defaultdict(list)
    for row in rows:
        severity = norm(row.get("severity"))
        message = norm(row.get("message"))
        sample_id = norm(row.get("sample_id"))
        if severity in {"WARNING", "ERROR"} and message:
            grouped[sample_id].append(f"{severity}: {message}")
    return grouped


def summarize(args):
    _, prepared = read_table(args.prepared_manifest)
    warnings = warnings_by_sample(args.warnings)
    count_paths = {
        "rnaseq": args.rnaseq_counts,
        "atacseq": args.atacseq_counts,
    }
    summary_paths = {
        "rnaseq": args.rnaseq_summary,
        "atacseq": args.atacseq_summary,
    }
    count_headers = {omics_type: count_header(path) for omics_type, path in count_paths.items()}

    run_rows = []
    manifest_rows = []
    error_count = 0
    for row in prepared:
        sample_id = norm(row.get("sample_id"))
        omics_type = norm(row.get("omics_type"))
        count_path = count_paths.get(omics_type, "")
        summary_path = summary_paths.get(omics_type, "")
        output_files = [path for path in [count_path, summary_path] if path]
        sample_messages = list(warnings.get(sample_id, []))
        status = "OK"
        if not count_path or not os.path.exists(count_path):
            status = "ERROR"
            error_count += 1
            sample_messages.append(f"Missing expected count matrix for {omics_type}")
        elif sample_id not in count_headers.get(omics_type, []):
            status = "ERROR"
            error_count += 1
            sample_messages.append(f"Sample is absent from {omics_type} count matrix: {sample_id}")
        elif sample_messages:
            status = "WARNING"

        run_rows.append(
            {
                "sample_id": sample_id,
                "species": norm(row.get("species")),
                "omics_type": omics_type,
                "condition": norm(row.get("condition")),
                "timepoint": norm(row.get("timepoint")),
                "reference_id": norm(row.get("reference_id")),
                "status": status,
                "output_files": ",".join(output_files),
                "warnings": "; ".join(sample_messages),
            }
        )
        for output_type, path in [("count_matrix", count_path), ("sample_summary", summary_path)]:
            manifest_rows.append(
                {
                    "sample_id": sample_id,
                    "omics_type": omics_type,
                    "output_type": output_type,
                    "path": path,
                    "exists": "true" if path and os.path.exists(path) else "false",
                    "sample_present": "true" if output_type != "count_matrix" or sample_id in count_headers.get(omics_type, []) else "false",
                }
            )

    write_tsv(
        os.path.join(args.output_dir, "omics_run_summary.tsv"),
        ["sample_id", "species", "omics_type", "condition", "timepoint", "reference_id", "status", "output_files", "warnings"],
        run_rows,
    )
    write_tsv(
        os.path.join(args.output_dir, "omics_outputs_manifest.tsv"),
        ["sample_id", "omics_type", "output_type", "path", "exists", "sample_present"],
        manifest_rows,
    )
    print(f"CAME omics output summary: ERROR={error_count} samples={len(run_rows)}")
    return 1 if error_count else 0


def parse_args():
    parser = argparse.ArgumentParser(description="Summarize CAME Stage 5 output files.")
    parser.add_argument("--prepared_manifest", required=True)
    parser.add_argument("--rnaseq_counts", required=True)
    parser.add_argument("--atacseq_counts", required=True)
    parser.add_argument("--rnaseq_summary", required=True)
    parser.add_argument("--atacseq_summary", required=True)
    parser.add_argument("--warnings", default="")
    parser.add_argument("--output_dir", default="results/omics/summary")
    return parser.parse_args()


def main():
    try:
        return summarize(parse_args())
    except Exception as exc:
        print(f"ERROR\tsummarize_omics_outputs\t{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
