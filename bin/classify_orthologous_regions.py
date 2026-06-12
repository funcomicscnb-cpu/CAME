#!/usr/bin/env python3
"""Build the inferred regulatory-orthology table from the region projection summary.

Consumes ``region_orthology_summary.tsv`` produced by
``project_orthologous_regions.py`` and emits ``inferred_orthologous_res.tsv`` in
the same schema as CAME regulatory-orthology inputs. The primary lifted
regulatory set is defined as loci with high-confidence round-trip recovery and a
non-hyperfragmented structure; lower-confidence loci are retained with explicit
confidence labels rather than dropped silently, and never reinterpreted as
biological absence.
"""

import argparse
import csv
import os
import sys

from orthology_intervals import write_tsv


ORTHOLOGOUS_RES_FIELDS = [
    "species",
    "feature_id",
    "orthogroup_id",
    "chrom",
    "start",
    "end",
    "human_anchor_region",
    "re_type",
    "orthology_type",
    "orthology_confidence",
    "source",
    "notes",
]

MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}


def norm(value):
    text = str(value if value is not None else "").strip()
    return "" if text.lower() in MISSING_VALUES else text


def read_summary(path):
    with open(path, newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        return [{key: norm(value) for key, value in row.items()} for row in reader]


def confidence_for(row):
    if row["high_confidence_primary"] == "true":
        return "high"
    if row["roundtrip_qc"] in {"HIGH_CONFIDENCE", "LOW_RECOVERY"}:
        return "medium"
    return "low"


def orthology_type_for(row):
    if norm(row.get("competing_target_contigs")) not in {"", "0", "1"}:
        return "one_to_many"
    return "one_to_one"


def parse_args():
    parser = argparse.ArgumentParser(description="Classify and emit inferred regulatory orthology from projection summary.")
    parser.add_argument("--region-summary", required=True)
    parser.add_argument("--projected-regions", required=True, help="projected_regions.tsv for target coordinates.")
    parser.add_argument("--output-dir", required=True)
    parser.add_argument(
        "--primary-only",
        action="store_true",
        help="Emit only high-confidence, non-hyperfragmented primary loci.",
    )
    return parser.parse_args()


def index_projected(path):
    index = {}
    with open(path, newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        for raw in reader:
            row = {key: norm(value) for key, value in raw.items()}
            index[(row.get("projection_id", ""), row.get("source_feature_id", ""), row.get("target_species", ""))] = row
    return index


def main():
    args = parse_args()
    summary = read_summary(args.region_summary)
    projected = index_projected(args.projected_regions)

    rows = []
    for record in summary:
        if record["structural_class"] == "missing":
            continue
        is_primary = record["high_confidence_primary"] == "true"
        if args.primary_only and not is_primary:
            continue

        projection_id = record["projection_id"]
        feature_id = record["source_feature_id"]
        target_species = record["target_species"]
        source_species = record["source_species"]
        region_type = record["region_type"]
        orthogroup_id = f"OG_RE_RB_{projection_id}_{feature_id}"
        human_anchor = f"{record['source_chrom']}:{record['source_start']}-{record['source_end']}"
        notes = f"{record['forward_status']}|{record['roundtrip_qc']}|{record['structural_class']}"
        otype = orthology_type_for(record)
        confidence = confidence_for(record)

        # Source-side row anchored on the original region.
        rows.append(
            {
                "species": source_species,
                "feature_id": feature_id,
                "orthogroup_id": orthogroup_id,
                "chrom": record["source_chrom"],
                "start": record["source_start"],
                "end": record["source_end"],
                "human_anchor_region": human_anchor,
                "re_type": region_type,
                "orthology_type": otype,
                "orthology_confidence": confidence,
                "source": "reciprocal_best_orthology",
                "notes": f"source region; {notes}",
            }
        )

        target_row = projected.get((projection_id, feature_id, target_species))
        if target_row and target_row.get("projection_status") == "OK" and target_row.get("target_chrom"):
            rows.append(
                {
                    "species": target_species,
                    "feature_id": f"{target_species}.{feature_id}.recip_best",
                    "orthogroup_id": orthogroup_id,
                    "chrom": target_row["target_chrom"],
                    "start": target_row["target_start"],
                    "end": target_row["target_end"],
                    "human_anchor_region": human_anchor,
                    "re_type": region_type,
                    "orthology_type": otype,
                    "orthology_confidence": confidence,
                    "source": "reciprocal_best_orthology",
                    "notes": f"projected span; {notes}",
                }
            )

    os.makedirs(args.output_dir, exist_ok=True)
    write_tsv(os.path.join(args.output_dir, "inferred_orthologous_res.tsv"), ORTHOLOGOUS_RES_FIELDS, rows)
    primary = sum(1 for record in summary if record["high_confidence_primary"] == "true")
    print(
        "CAME regulatory orthology inference: "
        f"summary_regions={len(summary)} primary_loci={primary} emitted_rows={len(rows)} primary_only={args.primary_only}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
