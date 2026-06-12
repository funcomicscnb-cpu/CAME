#!/usr/bin/env python3
"""Define orthologous regions from forward/reverse liftOver fragments with QC.

This implements the region-projection and round-trip quality-control core of the
reciprocal-best orthology approach. Given a starting set of regions (one or more
source species) and the lifted fragments produced upstream by halLiftover/liftOver
plus reciprocal-best callable masks, this script:

1. filters forward-projected fragments permissively by the query-side callable
   mask (any-overlap retention);
2. when a region produces fragments on more than one target contig, selects a
   single best contig by, in order: presence of a fragment overlapping a lifted
   constituent element, total lifted element bp, total retained region length,
   then fewer fragmented pieces;
3. builds span and block representations of the selected locus;
4. measures round-trip recovery of the original region window and the original
   constituent-element union after back-projection;
5. assigns a forward-mapping status label, a round-trip QC label, and
   block-based structural metrics for downstream classification.

External lift-over execution is orchestrated by Nextflow. This script performs
deterministic interval arithmetic only and is unit-testable without genomics
binaries. It does not infer biological absence: a region excluded here is "not
recovered as conservative callable orthology space", not "homology absent".
"""

import argparse
import os
import sys
from collections import defaultdict

from orthology_intervals import (
    IntervalIndex,
    count_data_lines,
    intersect_ranges,
    merge_intervals,
    overlap_length,
    overlaps_any,
    parse_bed,
    write_tsv,
)


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

BLOCK_FIELDS = [
    "projection_id",
    "source_species",
    "target_species",
    "source_feature_id",
    "block_index",
    "target_chrom",
    "target_start",
    "target_end",
    "length",
]

SUMMARY_FIELDS = [
    "projection_id",
    "source_species",
    "target_species",
    "source_feature_id",
    "region_type",
    "source_chrom",
    "source_start",
    "source_end",
    "source_window_len",
    "source_element_union_len",
    "source_callable_fraction",
    "raw_fragment_count",
    "retained_fragment_count",
    "competing_target_contigs",
    "selected_target_contig",
    "selected_piece_count",
    "selected_span_len",
    "selected_block_union_len",
    "block_density",
    "mean_fragment_len",
    "piece_redundancy",
    "species_mask_support_fraction",
    "mask_components_overlapped",
    "backlift_fragment_count",
    "window_recovered_bp",
    "window_recovered_fraction",
    "element_recovered_bp",
    "element_recovered_fraction",
    "core_recovered",
    "forward_status",
    "roundtrip_qc",
    "structural_class",
    "high_confidence_primary",
]

WARNING_FIELDS = ["severity", "projection_id", "source_feature_id", "target_species", "message"]

MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}


def norm(value):
    text = str(value if value is not None else "").strip()
    return "" if text.lower() in MISSING_VALUES else text


def read_manifest(path):
    import csv

    with open(path, newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        return [{key: norm(value) for key, value in row.items()} for row in reader]


def split_name(name):
    """Parse a BED name into (projection_id, feature_id, origin_contig).

    Orchestration writes fragment names as ``projection_id::feature_id`` so that
    the same feature projected under different projection records stays distinct.
    Back-lifted fragments additionally carry their origin target contig as a
    ``@@contig`` suffix so round-trip recovery can be restricted to the selected
    contig. A bare name (no separator) is treated as feature_id with empty
    projection_id and matched on feature_id alone.
    """
    contig = ""
    if "@@" in name:
        name, contig = name.rsplit("@@", 1)
    if "::" in name:
        projection_id, feature_id = name.split("::", 1)
        return norm(projection_id), norm(feature_id), norm(contig)
    return "", norm(name), norm(contig)


def index_fragments_by_key(intervals):
    """Group BED intervals by (projection_id, feature_id) and by feature_id.

    Each interval is annotated with its parsed ``origin_contig`` (from a
    ``@@contig`` name suffix) for downstream contig-restricted recovery.
    """
    by_key = defaultdict(list)
    by_feature = defaultdict(list)
    for interval in intervals:
        projection_id, feature_id, origin_contig = split_name(interval["name"])
        if not feature_id:
            continue
        interval["origin_contig"] = origin_contig
        by_key[(projection_id, feature_id)].append(interval)
        by_feature[feature_id].append(interval)
    return by_key, by_feature


def lookup(by_key, by_feature, projection_id, feature_id):
    if (projection_id, feature_id) in by_key:
        return by_key[(projection_id, feature_id)]
    if ("", feature_id) in by_key:
        return by_key[("", feature_id)]
    return by_feature.get(feature_id, [])


def round4(value):
    return f"{value:.4f}"


def to_intervals(ranges_by_chrom):
    return [
        {"chrom": chrom, "start": start, "end": end}
        for chrom, ranges in ranges_by_chrom.items()
        for start, end in ranges
    ]


def evaluate_region(row, ctx):
    projection_id = norm(row.get("projection_id"))
    feature_id = norm(row.get("source_feature_id"))
    source_species = norm(row.get("source_species"))
    target_species = norm(row.get("target_species"))
    region_type = norm(row.get("region_type")) or "regulatory_region"
    source_chrom = norm(row.get("source_chrom"))
    source_start = int(row.get("source_start"))
    source_end = int(row.get("source_end"))
    window_len = source_end - source_start
    window = [{"chrom": source_chrom, "start": source_start, "end": source_end}]

    forward = lookup(ctx["forward_by_key"], ctx["forward_by_feature"], projection_id, feature_id)
    elements_fwd = lookup(ctx["element_by_key"], ctx["element_by_feature"], projection_id, feature_id)
    backlift = lookup(ctx["backlift_by_key"], ctx["backlift_by_feature"], projection_id, feature_id)
    element_union = lookup(ctx["union_by_key"], ctx["union_by_feature"], projection_id, feature_id)

    summary = {field: "" for field in SUMMARY_FIELDS}
    summary.update(
        {
            "projection_id": projection_id,
            "source_species": source_species,
            "target_species": target_species,
            "source_feature_id": feature_id,
            "region_type": region_type,
            "source_chrom": source_chrom,
            "source_start": str(source_start),
            "source_end": str(source_end),
            "source_window_len": str(window_len),
        }
    )
    warnings = []

    # Source-side callable fraction.
    if ctx["source_mask"] is not None:
        callable_bp = overlap_length(window, ctx["source_mask"])
        source_callable_fraction = callable_bp / window_len if window_len else 0.0
        summary["source_callable_fraction"] = round4(source_callable_fraction)
    else:
        source_callable_fraction = None

    element_union_len = sum(iv["end"] - iv["start"] for iv in element_union)
    summary["source_element_union_len"] = str(element_union_len) if element_union else ""

    raw_count = len(forward)
    summary["raw_fragment_count"] = str(raw_count)

    # Permissive query-side callable-mask filtering at the fragment level.
    if ctx["species_mask_index"] is not None:
        retained = [
            frag for frag in forward
            if ctx["species_mask_index"].overlaps(frag["chrom"], frag["start"], frag["end"])
        ]
    else:
        retained = list(forward)
    summary["retained_fragment_count"] = str(len(retained))

    def fail(status):
        summary["competing_target_contigs"] = "0"
        summary["selected_piece_count"] = "0"
        summary["forward_status"] = status
        summary["roundtrip_qc"] = "NO_LOCUS"
        summary["structural_class"] = "missing"
        summary["high_confidence_primary"] = "false"
        projected_row = {
            "projection_id": projection_id,
            "source_species": source_species,
            "target_species": target_species,
            "source_feature_id": feature_id,
            "projected_feature_id": "",
            "source_chrom": source_chrom,
            "source_start": str(source_start),
            "source_end": str(source_end),
            "target_chrom": "",
            "target_start": "",
            "target_end": "",
            "strand": norm(row.get("source_strand")) or ".",
            "region_type": region_type,
            "alignment_id": norm(row.get("alignment_id")),
            "method": norm(row.get("method")),
            "projection_status": "FAILED",
            "overlap_fraction": "0.0000",
            "mapping_class": "failed_projection",
            "notes": status,
        }
        return summary, projected_row, [], warnings

    if source_callable_fraction is not None and source_callable_fraction == 0.0:
        warnings.append((projection_id, feature_id, target_species, "Region not within source-side reciprocal-best callable mask"))
        return fail("NOT_CALLABLE_IN_SOURCE")
    if raw_count == 0:
        warnings.append((projection_id, feature_id, target_species, "No forward lift-over mapping produced"))
        return fail("NO_FORWARD_MAPPING")
    if not retained:
        warnings.append((projection_id, feature_id, target_species, "Forward fragments failed query-side callable-mask filter"))
        return fail("RAW_ONLY_FAILED_MASK")

    # Group retained fragments by target contig and score each.
    by_contig = defaultdict(list)
    for frag in retained:
        by_contig[frag["chrom"]].append(frag)
    elements_by_contig = defaultdict(list)
    for frag in elements_fwd:
        elements_by_contig[frag["chrom"]].append(frag)

    contig_scores = {}
    for contig, frags in by_contig.items():
        contig_elements = elements_by_contig.get(contig, [])
        has_element_overlap = any(overlaps_any(frag, contig_elements) for frag in frags) if contig_elements else False
        element_bp = sum(end - start for ranges in merge_intervals(contig_elements).values() for start, end in ranges)
        retained_len = sum(end - start for ranges in merge_intervals(frags).values() for start, end in ranges)
        contig_scores[contig] = (1 if has_element_overlap else 0, element_bp, retained_len, -len(frags))

    competing = len(by_contig)
    summary["competing_target_contigs"] = str(competing)
    selected_contig = max(contig_scores, key=lambda contig: (contig_scores[contig], contig))
    selected = by_contig[selected_contig]
    summary["selected_target_contig"] = selected_contig
    summary["selected_piece_count"] = str(len(selected))

    span_start = min(frag["start"] for frag in selected)
    span_end = max(frag["end"] for frag in selected)
    span_len = span_end - span_start
    summary["selected_span_len"] = str(span_len)

    # Projected strand from the lifted fragments (lift tools flip strand on
    # reverse chains). Only meaningful when the source strand was known; report
    # "." when the source strand was unknown or the fragments disagree.
    source_strand = norm(row.get("source_strand"))
    fragment_strands = {frag.get("strand") for frag in selected if frag.get("strand") in {"+", "-"}}
    if source_strand not in {"+", "-"}:
        projected_strand = "."
    elif len(fragment_strands) == 1:
        projected_strand = next(iter(fragment_strands))
    else:
        projected_strand = "."

    blocks_by_chrom = merge_intervals(selected)
    blocks = to_intervals(blocks_by_chrom)
    block_union_len = sum(end - start for ranges in blocks_by_chrom.values() for start, end in ranges)
    summary["selected_block_union_len"] = str(block_union_len)
    block_density = block_union_len / span_len if span_len else 0.0
    summary["block_density"] = round4(block_density)
    mean_fragment_len = sum(frag["end"] - frag["start"] for frag in selected) / len(selected)
    summary["mean_fragment_len"] = round4(mean_fragment_len)
    raw_piece_bp = sum(frag["end"] - frag["start"] for frag in selected)
    redundancy = (raw_piece_bp - block_union_len) / raw_piece_bp if raw_piece_bp else 0.0
    summary["piece_redundancy"] = round4(redundancy)

    # Mask support and component counts are computed against only the selected
    # contig's mask ranges (via the index), avoiding a whole-genome scan per
    # region. Blocks all lie on the selected contig.
    if ctx["species_mask_index"] is not None:
        mask_ranges = ctx["species_mask_index"].chrom_ranges(selected_contig)
        block_ranges = [(block["start"], block["end"]) for block in blocks]
        mask_overlap_bp = sum(end - start for start, end in intersect_ranges(block_ranges, mask_ranges))
        mask_support = mask_overlap_bp / block_union_len if block_union_len else 0.0
        summary["species_mask_support_fraction"] = round4(mask_support)
        n_components = sum(
            1 for comp_start, comp_end in mask_ranges
            if any(b_start < comp_end and comp_start < b_end for b_start, b_end in block_ranges)
        )
        summary["mask_components_overlapped"] = str(n_components)
    else:
        n_components = None

    # Round-trip recovery uses only back-lifted fragments from the selected
    # contig. Fragments carry their origin target contig as a ``@@contig`` name
    # suffix; when no fragment is tagged (e.g. legacy inputs), all are used.
    tagged = [frag for frag in backlift if frag.get("origin_contig")]
    if tagged:
        selected_backlift = [frag for frag in tagged if frag["origin_contig"] == selected_contig]
    else:
        selected_backlift = list(backlift)
    summary["backlift_fragment_count"] = str(len(selected_backlift))

    window_recovered_bp = overlap_length(selected_backlift, window)
    window_recovered_frac = window_recovered_bp / window_len if window_len else 0.0
    summary["window_recovered_bp"] = str(window_recovered_bp)
    summary["window_recovered_fraction"] = round4(window_recovered_frac)

    if element_union:
        element_recovered_bp = overlap_length(selected_backlift, element_union)
        element_recovered_frac = element_recovered_bp / element_union_len if element_union_len else 0.0
        summary["element_recovered_bp"] = str(element_recovered_bp)
        summary["element_recovered_fraction"] = round4(element_recovered_frac)
        core_recovered = (
            element_recovered_bp >= ctx["min_element_bp"]
            or element_recovered_frac >= ctx["min_element_frac"]
        )
        summary["core_recovered"] = "true" if core_recovered else "false"
    else:
        core_recovered = None
        summary["core_recovered"] = "na"

    # Forward-mapping status label.
    selected_has_element = contig_scores[selected_contig][0] == 1
    if competing > 1:
        forward_status = "MULTICONTIG_RESOLVED"
    elif selected_has_element:
        forward_status = "RETAINED_WITH_ELEMENT"
    else:
        forward_status = "RETAINED_CALLABLE"
    summary["forward_status"] = forward_status

    # Round-trip QC label. High confidence requires recovering the constituent
    # active core, per the reciprocal-best method; when this region has no
    # matching element-union rows (core_recovered is None) the locus is labelled
    # WINDOW_ONLY_NO_CORE (window recovered, but active-core recovery could not be
    # evaluated) and is never primary.
    if len(selected_backlift) == 0:
        roundtrip_qc = "NO_BACKLIFT"
    elif core_recovered is False:
        roundtrip_qc = "CORE_NOT_RECOVERED"
    elif window_recovered_frac < ctx["min_window_frac"]:
        roundtrip_qc = "LOW_RECOVERY"
    elif core_recovered is None:
        roundtrip_qc = "WINDOW_ONLY_NO_CORE"
    else:
        roundtrip_qc = "HIGH_CONFIDENCE"
    summary["roundtrip_qc"] = roundtrip_qc

    # Block-based structural classification.
    n_pieces = len(selected)
    components_for_class = n_components if n_components is not None else 0
    if block_union_len == 0:
        structural_class = "missing"
    elif (
        block_density < ctx["hyperfrag_density"]
        or n_pieces > ctx["hyperfrag_pieces"]
        or components_for_class > ctx["hyperfrag_components"]
    ):
        structural_class = "hyperfragmented"
    elif block_density >= ctx["compact_density"] and components_for_class <= 1:
        structural_class = "compact"
    else:
        structural_class = "fragmented"
    summary["structural_class"] = structural_class

    high_confidence = roundtrip_qc == "HIGH_CONFIDENCE" and structural_class not in {"hyperfragmented", "missing"}
    summary["high_confidence_primary"] = "true" if high_confidence else "false"

    mapping_class = "ambiguous" if competing > 1 else "one_to_one"
    projected_feature = f"{target_species}.{feature_id}.recip_best"
    projected_row = {
        "projection_id": projection_id,
        "source_species": source_species,
        "target_species": target_species,
        "source_feature_id": feature_id,
        "projected_feature_id": projected_feature,
        "source_chrom": source_chrom,
        "source_start": str(source_start),
        "source_end": str(source_end),
        "target_chrom": selected_contig,
        "target_start": str(span_start),
        "target_end": str(span_end),
        "strand": projected_strand,
        "region_type": region_type,
        "alignment_id": norm(row.get("alignment_id")),
        "method": norm(row.get("method")),
        "projection_status": "OK",
        "overlap_fraction": round4(window_recovered_frac),
        "mapping_class": mapping_class,
        "notes": f"{forward_status}|{roundtrip_qc}|{structural_class}",
    }

    block_rows = []
    for block_index, (start, end) in enumerate(blocks_by_chrom.get(selected_contig, []), start=1):
        block_rows.append(
            {
                "projection_id": projection_id,
                "source_species": source_species,
                "target_species": target_species,
                "source_feature_id": feature_id,
                "block_index": str(block_index),
                "target_chrom": selected_contig,
                "target_start": str(start),
                "target_end": str(end),
                "length": str(end - start),
            }
        )

    if competing > 1:
        warnings.append(
            (projection_id, feature_id, target_species, f"Multiple target contigs competed ({competing}); selected {selected_contig}")
        )
    return summary, projected_row, block_rows, warnings


def require_file(path, label):
    """A path that was supplied but is absent is an input error, never evidence.

    Treating a missing callable mask as an empty mask would silently turn a bad
    path into a biological-looking "nothing callable" result, so we fail loudly.
    """
    if path and not os.path.exists(path):
        raise SystemExit(f"ERROR\tproject_orthologous_regions\t{label} does not exist: {path}")


def require_parseable(path, intervals, label):
    """Every data row of a safety-critical BED input must parse.

    Masks and the element union drive callable/core semantics, so a single
    malformed row (a typo, a stray column) must fail rather than be silently
    dropped — a dropped row would quietly change callable/recovery results. A
    legitimately empty file (no data rows) is allowed.
    """
    if not path:
        return
    data_lines = count_data_lines(path)
    if len(intervals) < data_lines:
        raise SystemExit(
            f"ERROR\tproject_orthologous_regions\t{label} has {data_lines - len(intervals)} "
            f"malformed/unparseable BED row(s) of {data_lines}: {path}"
        )


def build_context(args):
    for path, label in (
        (args.forward_fragments, "forward-fragments"),
        (args.backlift_fragments, "backlift-fragments"),
        (args.element_fragments, "element-fragments"),
        (args.source_element_union, "source-element-union"),
        (args.species_callable_mask, "species-callable-mask"),
        (args.source_callable_mask, "source-callable-mask"),
    ):
        require_file(path, label)

    forward_by_key, forward_by_feature = index_fragments_by_key(parse_bed(args.forward_fragments, name_required=True))
    element_by_key, element_by_feature = (
        index_fragments_by_key(parse_bed(args.element_fragments, name_required=True))
        if args.element_fragments
        else (defaultdict(list), defaultdict(list))
    )
    backlift_by_key, backlift_by_feature = index_fragments_by_key(parse_bed(args.backlift_fragments, name_required=True))
    union_intervals = parse_bed(args.source_element_union, name_required=True) if args.source_element_union else []
    union_by_key, union_by_feature = index_fragments_by_key(union_intervals)
    species_mask = parse_bed(args.species_callable_mask) if args.species_callable_mask else None
    source_mask = parse_bed(args.source_callable_mask) if args.source_callable_mask else None
    # Masks and the element union drive callable/retention/core status, so a
    # malformed one must error rather than parse as empty (which would convert an
    # input-artifact error into QC semantics like NOT_CALLABLE/WINDOW_ONLY_NO_CORE).
    # Lift-output fragment files may legitimately be empty (no mapping), so they
    # are not subject to this check.
    require_parseable(args.species_callable_mask, species_mask, "species-callable-mask")
    require_parseable(args.source_callable_mask, source_mask, "source-callable-mask")
    require_parseable(args.source_element_union, union_intervals, "source-element-union")
    species_mask_index = IntervalIndex(species_mask) if species_mask is not None else None
    return {
        "forward_by_key": forward_by_key,
        "forward_by_feature": forward_by_feature,
        "element_by_key": element_by_key,
        "element_by_feature": element_by_feature,
        "backlift_by_key": backlift_by_key,
        "backlift_by_feature": backlift_by_feature,
        "union_by_key": union_by_key,
        "union_by_feature": union_by_feature,
        "species_mask": species_mask,
        "species_mask_index": species_mask_index,
        "source_mask": source_mask,
        "min_element_bp": args.min_element_recovery_bp,
        "min_element_frac": args.min_element_recovery_frac,
        "min_window_frac": args.min_window_recovery_frac,
        "compact_density": args.compact_density,
        "hyperfrag_density": args.hyperfragmented_density,
        "hyperfrag_pieces": args.hyperfragmented_pieces,
        "hyperfrag_components": args.hyperfragmented_components,
    }


def parse_args():
    parser = argparse.ArgumentParser(description="Define orthologous regions with reciprocal-best round-trip QC.")
    parser.add_argument("--prepared-manifest", required=True)
    parser.add_argument("--forward-fragments", required=True, help="Forward-lifted region fragments in target coords (BED, name=projection_id::feature_id).")
    parser.add_argument("--backlift-fragments", required=True, help="Back-lifted region fragments in source coords (BED).")
    parser.add_argument("--element-fragments", default=None, help="Forward-lifted constituent element fragments (BED).")
    parser.add_argument("--source-element-union", default=None, help="Original constituent element union in source coords (BED).")
    parser.add_argument("--species-callable-mask", default=None, help="Query-side reciprocal-best callable mask (BED, target coords).")
    parser.add_argument("--source-callable-mask", default=None, help="Source-side reciprocal-best callable mask (BED, source coords).")
    parser.add_argument("--min-element-recovery-bp", type=int, default=50)
    parser.add_argument("--min-element-recovery-frac", type=float, default=0.5)
    parser.add_argument("--min-window-recovery-frac", type=float, default=0.5)
    parser.add_argument("--compact-density", type=float, default=0.8)
    parser.add_argument("--hyperfragmented-density", type=float, default=0.5)
    parser.add_argument("--hyperfragmented-pieces", type=int, default=8)
    parser.add_argument("--hyperfragmented-components", type=int, default=3)
    parser.add_argument("--output-dir", required=True)
    return parser.parse_args()


def main():
    args = parse_args()
    manifest = read_manifest(args.prepared_manifest)
    if not manifest:
        print("ERROR\tproject_orthologous_regions\tNo coordinate projection records in prepared manifest", file=sys.stderr)
        return 1

    ctx = build_context(args)

    summaries = []
    projected_rows = []
    block_rows = []
    warning_rows = []
    seen = set()
    for row in manifest:
        key = (norm(row.get("projection_id")), norm(row.get("source_feature_id")), norm(row.get("target_species")))
        if not key[1] or key in seen:
            continue
        seen.add(key)
        summary, projected, blocks, warnings = evaluate_region(row, ctx)
        summaries.append(summary)
        projected_rows.append(projected)
        block_rows.extend(blocks)
        for projection_id, feature_id, target_species, message in warnings:
            warning_rows.append(
                {
                    "severity": "WARNING",
                    "projection_id": projection_id,
                    "source_feature_id": feature_id,
                    "target_species": target_species,
                    "message": message,
                }
            )

    summaries.sort(key=lambda item: (item["projection_id"], item["source_feature_id"], item["target_species"]))
    projected_rows.sort(key=lambda item: (item["projection_id"], item["source_feature_id"], item["target_species"]))
    block_rows.sort(key=lambda item: (item["projection_id"], item["source_feature_id"], int(item["block_index"])))

    os.makedirs(args.output_dir, exist_ok=True)
    write_tsv(os.path.join(args.output_dir, "projected_regions.tsv"), PROJECTED_FIELDS, projected_rows)
    write_tsv(os.path.join(args.output_dir, "orthologous_region_blocks.tsv"), BLOCK_FIELDS, block_rows)
    write_tsv(os.path.join(args.output_dir, "region_orthology_summary.tsv"), SUMMARY_FIELDS, summaries)
    write_tsv(os.path.join(args.output_dir, "projection_warnings.tsv"), WARNING_FIELDS, warning_rows)

    high_conf = sum(1 for item in summaries if item["high_confidence_primary"] == "true")
    print(
        "CAME orthologous-region projection: "
        f"regions={len(summaries)} high_confidence_primary={high_conf} "
        f"blocks={len(block_rows)} warnings={len(warning_rows)}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
