#!/usr/bin/env python3
"""Split a prepared real-mode manifest into per-sample and per-reference TSVs."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path


ASSAY_TO_OMICS = {"rnaseq": "rnaseq", "atacseq": "atacseq", "wgs": "wgs"}


def read_rows(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open(newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        fields = reader.fieldnames or []
        return fields, list(reader)


def write_tsv(path: Path, fields: list[str], rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, delimiter="\t", extrasaction="ignore", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--assay", required=True, choices=sorted(ASSAY_TO_OMICS))
    parser.add_argument("--output_dir", required=True)
    args = parser.parse_args(argv)

    fields, rows = read_rows(Path(args.manifest))
    selected = [row for row in rows if row.get("omics_type") == ASSAY_TO_OMICS[args.assay]]
    outdir = Path(args.output_dir)
    write_tsv(outdir / "manifest" / f"{args.assay}_manifest.tsv", fields, selected)

    sample_keys: set[str] = set()
    reference_rows: dict[str, dict[str, str]] = {}
    for row in selected:
        sample_key = row.get("sample_key") or row.get("sample_id")
        if not sample_key:
            raise SystemExit("Prepared manifest row is missing sample_key and sample_id")
        if sample_key in sample_keys:
            raise SystemExit(f"Duplicate sample_key in prepared manifest: {sample_key}")
        sample_keys.add(sample_key)
        write_tsv(outdir / "samples" / f"{sample_key}.tsv", fields, [row])
        reference_key = row.get("reference_key") or row.get("reference_id")
        if reference_key:
            reference_rows.setdefault(reference_key, row)

    for reference_key, row in sorted(reference_rows.items()):
        write_tsv(outdir / "references" / f"{reference_key}.tsv", fields, [row])

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
