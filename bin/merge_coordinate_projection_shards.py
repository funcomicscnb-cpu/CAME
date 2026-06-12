#!/usr/bin/env python3
"""Merge coordinate-projection shard outputs deterministically."""

from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path


def read_tsv(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open(newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        fields = list(reader.fieldnames or [])
        rows = [{field: row.get(field, "") for field in fields} for row in reader]
    return fields, rows


def write_tsv(path: Path, fields: list[str], rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as handle:
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


def merge(paths: list[str], label: str) -> tuple[list[str], list[dict[str, str]]]:
    fields: list[str] | None = None
    merged: list[dict[str, str]] = []
    for text in sorted(paths):
        path = Path(text)
        if not path.exists():
            raise FileNotFoundError(f"{label} shard output does not exist: {path}")
        current_fields, rows = read_tsv(path)
        if fields is None:
            fields = current_fields
        elif current_fields != fields:
            raise ValueError(f"{label} shard header mismatch in {path}")
        merged.extend(rows)
    if fields is None:
        raise ValueError(f"No {label} shard outputs supplied")
    merged.sort(key=lambda row: tuple(row.get(field, "") for field in fields or []))
    return fields, merged


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--projected-regions", "--projected_regions", nargs="+", required=True)
    parser.add_argument("--region-summaries", "--region_summaries", nargs="+", required=True)
    parser.add_argument("--blocks", nargs="+", required=True)
    parser.add_argument("--projection-warnings", "--projection_warnings", nargs="+", required=True)
    parser.add_argument("--output-dir", "--output_dir", required=True)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    try:
        args = parse_args(argv)
        output_dir = Path(args.output_dir)
        for label, paths, name in [
            ("projected_regions", args.projected_regions, "projected_regions.tsv"),
            ("region_orthology_summary", args.region_summaries, "region_orthology_summary.tsv"),
            ("orthologous_region_blocks", args.blocks, "orthologous_region_blocks.tsv"),
            ("projection_warnings", args.projection_warnings, "projection_warnings.tsv"),
        ]:
            fields, rows = merge(paths, label)
            write_tsv(output_dir / name, fields, rows)
        print(
            "CAME coordinate projection shard merge: "
            f"projected={len(args.projected_regions)} summaries={len(args.region_summaries)}"
        )
        return 0
    except Exception as exc:
        print(f"ERROR\tmerge_coordinate_projection_shards\t{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
