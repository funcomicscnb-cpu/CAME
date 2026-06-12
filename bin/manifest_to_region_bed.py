#!/usr/bin/env python3
"""Convert a prepared coordinate-projection manifest into lift-ready BED inputs.

Emits, for the reciprocal-best orthology orchestration:

- ``regions.bed``: every unique source region in source coordinates, named
  ``projection_id::feature_id`` so downstream fragment files stay keyed;
- ``chains.tsv``: one row per distinct alignment asset group (chain/net files +
  target species + method), each pointing at a per-group BED in ``regions/``.

The per-group BEDs let the orchestration run one lift-over invocation per
alignment asset without re-parsing the manifest in shell. This script does no
biological inference; it only reshapes validated metadata into tool inputs.
"""

import argparse
import csv
import os
import sys
from collections import OrderedDict

MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}


def norm(value):
    text = str(value if value is not None else "").strip()
    return "" if text.lower() in MISSING_VALUES else text


def read_manifest(path):
    with open(path, newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        return [{key: norm(value) for key, value in row.items()} for row in reader]


def main():
    parser = argparse.ArgumentParser(description="Reshape prepared manifest into lift-over BED inputs.")
    parser.add_argument("--prepared-manifest", required=True)
    parser.add_argument("--output-dir", required=True)
    args = parser.parse_args()

    manifest = read_manifest(args.prepared_manifest)
    if not manifest:
        print("ERROR\tmanifest_to_region_bed\tEmpty prepared manifest", file=sys.stderr)
        return 1

    os.makedirs(os.path.join(args.output_dir, "regions"), exist_ok=True)

    all_regions = OrderedDict()
    groups = OrderedDict()
    for row in manifest:
        key = (norm(row.get("projection_id")), norm(row.get("source_feature_id")))
        if not key[1]:
            continue
        name = f"{key[0]}::{key[1]}"
        # BED6 so lift-over tools can flip strand on reverse chains. Unknown
        # source strand is written as "+" for the lift; the projection engine
        # reports "." for features whose source strand was unknown.
        strand = norm(row.get("source_strand"))
        bed_line = (
            norm(row.get("source_chrom")),
            norm(row.get("source_start")),
            norm(row.get("source_end")),
            name,
            "0",
            strand if strand in {"+", "-"} else "+",
        )
        all_regions[name] = bed_line

        group_key = (
            norm(row.get("source_species")),
            norm(row.get("target_species")),
            norm(row.get("method")),
            norm(row.get("chain_file")),
            norm(row.get("net_file")),
        )
        groups.setdefault(group_key, OrderedDict())[name] = bed_line

    with open(os.path.join(args.output_dir, "regions.bed"), "w") as handle:
        for line in all_regions.values():
            handle.write("\t".join(line) + "\n")

    chains_index = []
    for idx, (group_key, regions) in enumerate(groups.items()):
        source_species, target_species, method, chain_file, net_file = group_key
        bed_rel = os.path.join("regions", f"group_{idx}.bed")
        with open(os.path.join(args.output_dir, bed_rel), "w") as handle:
            for line in regions.values():
                handle.write("\t".join(line) + "\n")
        chains_index.append(
            {
                "idx": str(idx),
                "source_species": source_species or ".",
                "target_species": target_species or ".",
                "method": method or ".",
                # Sentinel "." keeps every field non-empty so tab-delimited shell
                # `read` does not collapse adjacent tabs and shift later columns.
                "chain_file": chain_file or ".",
                "bed": bed_rel,
            }
        )

    with open(os.path.join(args.output_dir, "chains.tsv"), "w", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=["idx", "source_species", "target_species", "method", "chain_file", "bed"],
            delimiter="\t",
            lineterminator="\n",
        )
        writer.writeheader()
        writer.writerows(chains_index)

    print(f"CAME manifest-to-bed: regions={len(all_regions)} alignment_groups={len(groups)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
