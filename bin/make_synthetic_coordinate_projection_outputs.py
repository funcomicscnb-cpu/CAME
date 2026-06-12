#!/usr/bin/env python3
"""Create deterministic stub coordinate projection and regulatory orthology outputs."""

import argparse
import csv
import os
import sys


MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}
PROJECTED_FIELDS = [
    "projection_id",
    "source_species",
    "target_species",
    "source_feature_id",
    "projected_feature_id",
    "source_chrom",
    "source_start",
    "source_end",
    "target_chrom",
    "target_start",
    "target_end",
    "strand",
    "region_type",
    "alignment_id",
    "method",
    "projection_status",
    "overlap_fraction",
    "mapping_class",
    "notes",
]
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
WARNING_FIELDS = ["severity", "projection_id", "source_feature_id", "target_species", "message"]
# Header-only placeholders so the summary manifest can list these real-mode
# artifacts uniformly across stub and real runs. Must match the real engine.
REGION_SUMMARY_FIELDS = [
    "projection_id", "source_species", "target_species", "source_feature_id", "region_type",
    "source_chrom", "source_start", "source_end", "source_window_len", "source_element_union_len",
    "source_callable_fraction", "raw_fragment_count", "retained_fragment_count", "competing_target_contigs",
    "selected_target_contig", "selected_piece_count", "selected_span_len", "selected_block_union_len",
    "block_density", "mean_fragment_len", "piece_redundancy", "species_mask_support_fraction",
    "mask_components_overlapped", "backlift_fragment_count", "window_recovered_bp", "window_recovered_fraction",
    "element_recovered_bp", "element_recovered_fraction", "core_recovered", "forward_status",
    "roundtrip_qc", "structural_class", "high_confidence_primary",
]
BLOCK_FIELDS = [
    "projection_id", "source_species", "target_species", "source_feature_id", "block_index",
    "target_chrom", "target_start", "target_end", "length",
]


def norm(value):
    text = str(value if value is not None else "").strip()
    return "" if text.lower() in MISSING_VALUES else text


def read_manifest(path):
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


def as_int(value):
    return int(norm(value))


def target_coords(row, index):
    start = as_int(row["source_start"])
    end = as_int(row["source_end"])
    width = end - start
    target_start = start + 1000 + (index * 17)
    return str(target_start), str(target_start + width)


def add_orthology(rows, seen, species, feature_id, orthogroup_id, chrom, start, end, region_type, orthology_type, confidence, notes):
    key = (species, feature_id, orthogroup_id)
    if key in seen:
        return
    seen.add(key)
    rows.append(
        {
            "species": species,
            "feature_id": feature_id,
            "orthogroup_id": orthogroup_id,
            "chrom": chrom,
            "start": start,
            "end": end,
            "human_anchor_region": "",
            "re_type": region_type,
            "orthology_type": orthology_type,
            "orthology_confidence": confidence,
            "source": "synthetic_coordinate_projection",
            "notes": notes,
        }
    )


def create_outputs(args):
    manifest = sorted(read_manifest(args.prepared_manifest), key=lambda row: (row["projection_id"], row["source_feature_id"], row["target_species"]))
    if not manifest:
        raise SystemExit("No coordinate projection records found in prepared manifest")

    projected = []
    orthology = []
    warnings = []
    seen_orthology = set()
    many_to_one_group = "OG_RE_COORD_MANY_001"
    many_to_one_target = None

    for index, row in enumerate(manifest):
        class_index = index % 6
        source_species = row["source_species"]
        target_species = row["target_species"]
        source_feature = row["source_feature_id"]
        region_type = row.get("region_type") or "regulatory_region"
        strand = row.get("source_strand") or "."

        if class_index == 0:
            projected.append(
                {
                    "projection_id": row["projection_id"],
                    "source_species": source_species,
                    "target_species": target_species,
                    "source_feature_id": source_feature,
                    "projected_feature_id": "",
                    "source_chrom": row["source_chrom"],
                    "source_start": row["source_start"],
                    "source_end": row["source_end"],
                    "target_chrom": "",
                    "target_start": "",
                    "target_end": "",
                    "strand": strand,
                    "region_type": region_type,
                    "alignment_id": row["alignment_id"],
                    "method": row["method"],
                    "projection_status": "FAILED",
                    "overlap_fraction": "0.00",
                    "mapping_class": "failed_projection",
                    "notes": "Deterministic failed projection stub",
                }
            )
            warnings.append(
                {
                    "severity": "WARNING",
                    "projection_id": row["projection_id"],
                    "source_feature_id": source_feature,
                    "target_species": target_species,
                    "message": "Deterministic stub failed projection",
                }
            )
            continue

        target_start, target_end = target_coords(row, index)
        target_chrom = f"{row['source_chrom']}_{target_species}"
        projected_feature = f"{target_species}.{source_feature}.projected_{index + 1}"
        if class_index in {2, 3}:
            mapping_class = "many_to_one"
            orthogroup_id = many_to_one_group
            confidence = "medium"
            if many_to_one_target is None:
                many_to_one_target = f"{target_species}.shared_projected_re"
            projected_feature = many_to_one_target
        elif class_index == 4:
            mapping_class = "ambiguous"
            orthogroup_id = f"OG_RE_COORD_AMBIG_{index + 1:03d}"
            confidence = "low"
        else:
            mapping_class = "one_to_one"
            orthogroup_id = f"OG_RE_COORD_{index + 1:04d}"
            confidence = "high"

        projected.append(
            {
                "projection_id": row["projection_id"],
                "source_species": source_species,
                "target_species": target_species,
                "source_feature_id": source_feature,
                "projected_feature_id": projected_feature,
                "source_chrom": row["source_chrom"],
                "source_start": row["source_start"],
                "source_end": row["source_end"],
                "target_chrom": target_chrom,
                "target_start": target_start,
                "target_end": target_end,
                "strand": strand,
                "region_type": region_type,
                "alignment_id": row["alignment_id"],
                "method": row["method"],
                "projection_status": "OK",
                "overlap_fraction": "0.85" if mapping_class != "ambiguous" else "0.52",
                "mapping_class": mapping_class,
                "notes": "Deterministic coordinate projection stub",
            }
        )
        add_orthology(
            orthology,
            seen_orthology,
            source_species,
            source_feature,
            orthogroup_id,
            row["source_chrom"],
            row["source_start"],
            row["source_end"],
            region_type,
            "one_to_many" if mapping_class == "ambiguous" else mapping_class,
            confidence,
            f"{mapping_class} source feature",
        )
        add_orthology(
            orthology,
            seen_orthology,
            target_species,
            projected_feature,
            orthogroup_id,
            target_chrom,
            target_start,
            target_end,
            region_type,
            "one_to_many" if mapping_class == "ambiguous" else mapping_class,
            confidence,
            f"{mapping_class} projected feature",
        )
        if mapping_class == "ambiguous":
            alternate_orthogroup = f"OG_RE_COORD_AMBIG_ALT_{index + 1:03d}"
            alternate_feature = f"{projected_feature}.alt"
            alternate_start = str(int(target_start) + 25)
            alternate_end = str(int(target_end) + 25)
            add_orthology(
                orthology,
                seen_orthology,
                source_species,
                source_feature,
                alternate_orthogroup,
                row["source_chrom"],
                row["source_start"],
                row["source_end"],
                region_type,
                "one_to_many",
                "low",
                "ambiguous alternate source mapping",
            )
            add_orthology(
                orthology,
                seen_orthology,
                target_species,
                alternate_feature,
                alternate_orthogroup,
                target_chrom,
                alternate_start,
                alternate_end,
                region_type,
                "one_to_many",
                "low",
                "ambiguous alternate projected feature",
            )
            warnings.append(
                {
                    "severity": "WARNING",
                    "projection_id": row["projection_id"],
                    "source_feature_id": source_feature,
                    "target_species": target_species,
                    "message": "Deterministic ambiguous projection with multiple orthogroups",
                }
            )

    write_tsv(os.path.join(args.output_dir, "projected_regions.tsv"), PROJECTED_FIELDS, projected)
    write_tsv(os.path.join(args.output_dir, "inferred_orthologous_res.tsv"), ORTHOLOGOUS_RES_FIELDS, orthology)
    write_tsv(os.path.join(args.output_dir, "projection_warnings.tsv"), WARNING_FIELDS, warnings)
    write_tsv(os.path.join(args.output_dir, "region_orthology_summary.tsv"), REGION_SUMMARY_FIELDS, [])
    write_tsv(os.path.join(args.output_dir, "orthologous_region_blocks.tsv"), BLOCK_FIELDS, [])
    print(f"CAME synthetic coordinate projection outputs: projected_records={len(projected)} orthology_rows={len(orthology)} warnings={len(warnings)}")
    return 0


def parse_args():
    parser = argparse.ArgumentParser(description="Create synthetic CAME coordinate projection outputs.")
    parser.add_argument("--prepared_manifest", required=True)
    parser.add_argument("--output_dir", default="results/coordinate_projection")
    return parser.parse_args()


def main():
    try:
        return create_outputs(parse_args())
    except Exception as exc:
        print(f"ERROR\tmake_synthetic_coordinate_projection_outputs\t{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
