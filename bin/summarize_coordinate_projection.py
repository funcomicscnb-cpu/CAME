#!/usr/bin/env python3
"""Summarize CAME coordinate projection scaffold outputs."""

import argparse
import csv
import os
import sys


MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}
SUMMARY_FIELDS = ["metric", "value"]
MANIFEST_FIELDS = ["output_type", "path", "exists", "records", "mode", "status"]


def norm(value):
    text = str(value if value is not None else "").strip()
    return "" if text.lower() in MISSING_VALUES else text


def parse_bool(value):
    return str(value).strip().lower() in {"1", "true", "t", "yes", "y"}


def read_table(path):
    if not path or not os.path.exists(path):
        return []
    with open(path, newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
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


def output_record(path, output_type, mode):
    rows = read_table(path)
    exists = os.path.exists(path) and os.path.getsize(path) > 0
    return {
        "output_type": output_type,
        "path": path,
        "exists": "true" if exists else "false",
        "records": str(len(rows)),
        "mode": mode,
        "status": "OK" if exists else "ERROR",
    }


def summarize(args):
    mode = "stub" if parse_bool(args.coordinate_projection_stub) else "real"
    prepared = read_table(args.prepared_manifest)
    projected = read_table(args.projected_regions)
    orthology = read_table(args.inferred_orthologous_res)
    warnings = read_table(args.projection_warnings)

    input_regions = {(row.get("source_species"), row.get("source_feature_id")) for row in prepared if norm(row.get("source_feature_id"))}
    projected_ok = [row for row in projected if norm(row.get("projection_status")) == "OK"]
    failed = [row for row in projected if norm(row.get("projection_status")) == "FAILED"]
    orthogroups = {norm(row.get("orthogroup_id")) for row in orthology if norm(row.get("orthogroup_id"))}
    ambiguous_features = {
        (row.get("species"), row.get("feature_id"))
        for row in orthology
        if norm(row.get("orthology_type")) in {"one_to_many", "many_to_many"} or "ambiguous" in norm(row.get("notes")).lower()
    }

    manifest_rows = [
        output_record(args.projected_regions, "projected_regions", mode),
        output_record(args.inferred_orthologous_res, "inferred_orthologous_res", mode),
        output_record(args.projection_warnings, "projection_warnings", mode),
    ]
    errors = sum(1 for row in manifest_rows if row["status"] == "ERROR")
    summary_rows = [
        {"metric": "mode", "value": mode},
        {"metric": "input_regions", "value": str(len(input_regions))},
        {"metric": "projection_records", "value": str(len(projected))},
        {"metric": "projected_regions", "value": str(len(projected_ok))},
        {"metric": "inferred_orthogroups", "value": str(len(orthogroups))},
        {"metric": "ambiguous_mappings", "value": str(len(ambiguous_features))},
        {"metric": "failed_projections", "value": str(len(failed))},
        {"metric": "warnings", "value": str(len(warnings))},
        {"metric": "status", "value": "OK" if errors == 0 else "ERROR"},
    ]
    write_tsv(os.path.join(args.output_dir, "coordinate_projection_summary.tsv"), SUMMARY_FIELDS, summary_rows)
    write_tsv(os.path.join(args.output_dir, "coordinate_projection_outputs_manifest.tsv"), MANIFEST_FIELDS, manifest_rows)
    print(
        "CAME coordinate projection summary: "
        f"mode={mode} input_regions={len(input_regions)} projected_regions={len(projected_ok)} orthogroups={len(orthogroups)}"
    )
    return 1 if errors else 0


def parse_args():
    parser = argparse.ArgumentParser(description="Summarize CAME coordinate projection outputs.")
    parser.add_argument("--prepared_manifest", required=True)
    parser.add_argument("--projected_regions", required=True)
    parser.add_argument("--inferred_orthologous_res", required=True)
    parser.add_argument("--projection_warnings", required=True)
    parser.add_argument("--coordinate_projection_stub", default="true")
    parser.add_argument("--output_dir", default="results/coordinate_projection/summary")
    return parser.parse_args()


def main():
    try:
        return summarize(parse_args())
    except Exception as exc:
        print(f"ERROR\tsummarize_coordinate_projection\t{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
