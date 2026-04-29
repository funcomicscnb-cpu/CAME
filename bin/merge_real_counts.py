#!/usr/bin/env python3
"""Merge per-sample real-mode RNA or ATAC count outputs."""

from __future__ import annotations

import argparse
import csv
from collections import OrderedDict
from pathlib import Path


def read_manifest(path: Path, omics_type: str) -> list[dict[str, str]]:
    with path.open(newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        return [row for row in reader if row.get("omics_type") == omics_type]


def write_tsv(path: Path, fields: list[str], rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, delimiter="\t", extrasaction="ignore", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def sample_key(row: dict[str, str]) -> str:
    return row.get("sample_key") or row.get("sample_id") or ""


def merge_rna(args: argparse.Namespace) -> None:
    rows = read_manifest(Path(args.manifest), "rnaseq")
    samples = [row["sample_id"] for row in rows]
    features: OrderedDict[str, dict[str, str]] = OrderedDict()
    count_dir = Path(args.input_dir)
    for row in rows:
        sid = row["sample_id"]
        skey = sample_key(row)
        path = count_dir / f"{skey}.featureCounts.txt"
        if not path.exists():
            raise SystemExit(f"Missing featureCounts output: {path}")
        with path.open() as handle:
            reader = csv.reader((line for line in handle if not line.startswith("#")), delimiter="\t")
            try:
                header = next(reader)
            except StopIteration:
                raise SystemExit(f"Empty featureCounts output: {path}")
            count_col = len(header) - 1
            for record in reader:
                if not record:
                    continue
                feature_id = record[0]
                features.setdefault(feature_id, {"feature_id": feature_id, "feature_type": "gene", "annotation_id": "featureCounts"})
                features[feature_id][sid] = record[count_col]
    fields = ["feature_id", "feature_type", "annotation_id"] + samples
    write_tsv(Path(args.output), fields, list(features.values()))


def merge_atac(args: argparse.Namespace) -> None:
    rows = read_manifest(Path(args.manifest), "atacseq")
    samples = [row["sample_id"] for row in rows]
    features: OrderedDict[str, dict[str, str]] = OrderedDict()
    with Path(args.consensus_peaks).open() as handle:
        for idx, line in enumerate((line for line in handle if line.strip()), start=1):
            chrom, start, end = line.rstrip("\n").split("\t")[:3]
            feature_id = f"re_{idx:06d}"
            features[feature_id] = {
                "feature_id": feature_id,
                "feature_type": "regulatory_element",
                "chrom": chrom,
                "start": start,
                "end": end,
            }
    count_dir = Path(args.input_dir)
    for row in rows:
        sid = row["sample_id"]
        skey = sample_key(row)
        path = count_dir / f"{skey}.bedtools_counts.tsv"
        if not path.exists():
            raise SystemExit(f"Missing bedtools count output: {path}")
        with path.open() as handle:
            for feature_id, line in zip(features, handle):
                features[feature_id][sid] = line.rstrip("\n").split("\t")[-1]
    fields = ["feature_id", "feature_type", "chrom", "start", "end"] + samples
    output = Path(args.output)
    write_tsv(output, fields, list(features.values()))
    if args.re_counts_output:
        write_tsv(Path(args.re_counts_output), fields, list(features.values()))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assay", required=True, choices=["rnaseq", "atacseq"])
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--input_dir", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--consensus_peaks", default="")
    parser.add_argument("--re_counts_output", default="")
    args = parser.parse_args(argv)

    if args.assay == "rnaseq":
        merge_rna(args)
    else:
        if not args.consensus_peaks:
            raise SystemExit("--consensus_peaks is required for ATAC count merging")
        merge_atac(args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
