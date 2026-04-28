#!/usr/bin/env python3
"""Create deterministic stub RE-to-gene links for CAME Stage 20."""

import argparse
import csv
import os
import sys


MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}
LINK_FIELDS = [
    "species",
    "re_feature_id",
    "gene_feature_id",
    "link_type",
    "re_orthogroup_id",
    "gene_orthogroup_id",
    "distance_to_tss",
    "contact_score",
    "link_confidence",
    "source",
    "notes",
]
WARNING_FIELDS = ["severity", "inference_id", "re_feature_id", "gene_feature_id", "message"]


def norm(value):
    text = str(value if value is not None else "").strip()
    return "" if text.lower() in MISSING_VALUES else text


def parse_bool(value):
    return str(value).strip().lower() in {"1", "true", "t", "yes", "y"}


def read_table(path):
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


def link(species, re_id, gene_id, link_type, re_og, gene_og, distance, contact, confidence, notes):
    return {
        "species": species,
        "re_feature_id": re_id,
        "gene_feature_id": gene_id,
        "link_type": link_type,
        "re_orthogroup_id": re_og,
        "gene_orthogroup_id": gene_og,
        "distance_to_tss": distance,
        "contact_score": contact,
        "link_confidence": confidence,
        "source": "synthetic_re_to_gene_inference",
        "notes": notes,
    }


def create_outputs(args):
    if not parse_bool(args.re_to_gene_inference_stub):
        raise SystemExit("re_to_gene_inference real mode must not emit synthetic RE-to-gene links")
    manifest = read_table(args.prepared_manifest)
    if not manifest:
        raise SystemExit("No RE-to-gene inference records found in prepared manifest")
    species = next((row.get("species") for row in manifest if norm(row.get("species"))), "orthogroup")
    inference_id = next((row.get("inference_id") for row in manifest if norm(row.get("inference_id"))), "stub_contract")

    links = [
        link(species, "mmus_re_0001", "gene_0001", "promoter", "OG_RE_0001", "OG_GENE_0001", "40", "", "0.96", "promoter-overlap scaffold example"),
        link(species, "mmus_re_0002", "gene_0001", "proximal", "OG_RE_0002", "OG_GENE_0001", "180", "", "0.82", "one gene linked to multiple REs"),
        link(species, "mmus_re_0003", "gene_0002", "distal_contact", "OG_RE_0003", "OG_GENE_0002", "140", "0.74", "0.78", "distal contact scaffold example"),
        link(species, "mmus_re_0003", "gene_0003", "distal_contact", "OG_RE_0003", "OG_GENE_0003", "160", "0.68", "0.72", "one RE linked to multiple genes"),
        link(species, "mmus_re_0004", "gene_0004", "nearest_gene", "OG_RE_0004", "OG_GENE_0003", "10", "", "0.60", "nearest-gene scaffold example"),
        link(species, "mmus_re_0004", "gene_0005", "nearest_gene", "OG_RE_0004", "OG_GENE_0004", "400", "", "0.55", "ambiguous nearest-gene example retained as an additional row"),
    ]
    warnings = [
        {
            "severity": "WARNING",
            "inference_id": inference_id,
            "re_feature_id": "mmus_re_0003",
            "gene_feature_id": "gene_0002,gene_0003",
            "message": "Synthetic RE linked to multiple genes; ambiguity is represented by multiple rows",
        },
        {
            "severity": "WARNING",
            "inference_id": inference_id,
            "re_feature_id": "mmus_re_0004",
            "gene_feature_id": "gene_0004,gene_0005",
            "message": "Synthetic nearest-gene ambiguity retained for downstream validation",
        },
    ]

    write_tsv(os.path.join(args.output_dir, "re_to_gene_links.tsv"), LINK_FIELDS, links)
    write_tsv(os.path.join(args.output_dir, "re_to_gene_inference_warnings.tsv"), WARNING_FIELDS, warnings)
    print(f"CAME synthetic RE-to-gene links: links={len(links)} warnings={len(warnings)}")
    return 0


def parse_args():
    parser = argparse.ArgumentParser(description="Create synthetic CAME RE-to-gene links.")
    parser.add_argument("--prepared_manifest", required=True)
    parser.add_argument("--re_to_gene_inference_stub", default="true")
    parser.add_argument("--output_dir", default="results/re_to_gene_inference")
    return parser.parse_args()


def main():
    try:
        return create_outputs(parse_args())
    except Exception as exc:
        print(f"ERROR\tmake_synthetic_re_to_gene_links\t{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
