#!/usr/bin/env python3
"""Create deterministic synthetic count matrices for CAME Stage 5 tests."""

import argparse
import csv
import hashlib
import os
import sys


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


def features_for(omics_type):
    if omics_type == "rnaseq":
        return [
            {"feature_id": f"gene_{idx:04d}", "feature_type": "gene", "annotation_id": f"synthetic_gene_{idx:04d}"}
            for idx in range(1, 7)
        ]
    if omics_type == "atacseq":
        features = []
        for idx in range(1, 7):
            start = 1000 + (idx - 1) * 500
            features.append(
                {
                    "feature_id": f"re_{idx:04d}",
                    "feature_type": "regulatory_element",
                    "chrom": f"chr{1 + ((idx - 1) % 3)}",
                    "start": str(start),
                    "end": str(start + 250),
                }
            )
        return features
    raise RuntimeError(f"Unsupported omics_type: {omics_type}")


def stable_count(seed, omics_type, sample_id, feature_id):
    payload = f"{seed}|{omics_type}|{sample_id}|{feature_id}".encode()
    digest = hashlib.sha256(payload).hexdigest()
    return 20 + (int(digest[:8], 16) % 500)


def sample_rows(manifest_rows, omics_type):
    rows = [row for row in manifest_rows if norm(row.get("omics_type")) == omics_type]
    seen = set()
    ordered = []
    for row in rows:
        sample_id = norm(row.get("sample_id"))
        if not sample_id:
            raise RuntimeError("Prepared manifest contains a row without sample_id")
        if sample_id in seen:
            raise RuntimeError(f"Prepared manifest contains duplicate sample_id: {sample_id}")
        seen.add(sample_id)
        ordered.append(row)
    return ordered


def write_counts(manifest, omics_type, output, summary, seed):
    _, rows = read_table(manifest)
    samples = sample_rows(rows, omics_type)
    sample_ids = [row["sample_id"] for row in samples]
    features = features_for(omics_type)
    base_fields = ["feature_id", "feature_type", "annotation_id"] if omics_type == "rnaseq" else ["feature_id", "feature_type", "chrom", "start", "end"]
    matrix_rows = []
    totals = {sample_id: 0 for sample_id in sample_ids}
    for feature in features:
        out = dict(feature)
        for sample_id in sample_ids:
            count = stable_count(seed, omics_type, sample_id, feature["feature_id"])
            out[sample_id] = str(count)
            totals[sample_id] += count
        matrix_rows.append(out)
    write_tsv(output, base_fields + sample_ids, matrix_rows)

    if summary:
        summary_rows = []
        for row in samples:
            sample_id = row["sample_id"]
            summary_rows.append(
                {
                    "sample_id": sample_id,
                    "species": norm(row.get("species")),
                    "omics_type": omics_type,
                    "condition": norm(row.get("condition")),
                    "timepoint": norm(row.get("timepoint")),
                    "reference_id": norm(row.get("reference_id")),
                    "status": "OK",
                    "n_features": str(len(features)),
                    "total_counts": str(totals[sample_id]),
                    "output_files": output,
                    "warnings": "",
                }
            )
        write_tsv(
            summary,
            [
                "sample_id",
                "species",
                "omics_type",
                "condition",
                "timepoint",
                "reference_id",
                "status",
                "n_features",
                "total_counts",
                "output_files",
                "warnings",
            ],
            summary_rows,
        )
    print(f"CAME synthetic {omics_type} counts summary: samples={len(sample_ids)} features={len(features)}")


def parse_args():
    parser = argparse.ArgumentParser(description="Create deterministic synthetic CAME count matrices.")
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--omics_type", required=True, choices=["rnaseq", "atacseq"])
    parser.add_argument("--output", required=True)
    parser.add_argument("--summary", default="")
    parser.add_argument("--seed", default="1729")
    return parser.parse_args()


def main():
    args = parse_args()
    try:
        write_counts(args.manifest, args.omics_type, args.output, args.summary, args.seed)
    except Exception as exc:
        print(f"ERROR\tmake_synthetic_counts\t{exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
