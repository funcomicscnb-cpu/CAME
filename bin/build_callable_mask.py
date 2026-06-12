#!/usr/bin/env python3
"""Build a conservative callable-orthology mask from reciprocal-best level-1 fills.

Following the reciprocal-best orthology approach, a callable mask in reference
(e.g. hg38) coordinates is defined as the intersection of two top-level
(level-1) reciprocal-best net masks:

1. the reference-side level-1 fills, already in reference coordinates;
2. the query-side level-1 fills, projected back into reference coordinates via
   the reciprocal-best chain (this projection is performed upstream by UCSC
   liftOver and supplied here as a BED file).

Before intersection, fragments shorter than ``--min-fragment`` bp are discarded
and each side is merged. Retained bases therefore correspond to reference
intervals supported as top-level reciprocal-best syntenic space from both the
reference and query perspectives. Exclusion does not imply absence of homology;
it is a conservative callable definition only.

This script performs deterministic interval arithmetic; the upstream netSyntenic,
level-1 fill extraction, and liftOver projection are orchestrated by Nextflow.
"""

import argparse
import os
import sys

from orthology_intervals import (
    count_data_lines,
    filter_min_length,
    intersect_intervals,
    merge_intervals,
    parse_bed,
    total_length,
    write_bed,
)


def parse_args():
    parser = argparse.ArgumentParser(description="Build a reciprocal-best callable-orthology mask.")
    parser.add_argument(
        "--reference-fills",
        required=True,
        help="Reference-side level-1 reciprocal-best net fills, in reference coordinates (BED).",
    )
    parser.add_argument(
        "--query-fills-projected",
        required=True,
        help="Query-side level-1 fills projected to reference coordinates (BED).",
    )
    parser.add_argument("--min-fragment", type=int, default=50, help="Discard fills shorter than this many bp.")
    parser.add_argument("--out", required=True, help="Output callable-mask BED path (merged intersection).")
    return parser.parse_args()


def main():
    args = parse_args()
    parsed = {}
    for label, path in (("reference-fills", args.reference_fills), ("query-fills-projected", args.query_fills_projected)):
        if not os.path.exists(path):
            print(f"ERROR\tbuild_callable_mask\t{label} does not exist: {path}", file=sys.stderr)
            return 1
        intervals = parse_bed(path)
        # Every data row of a callable-fill input must parse; a single malformed
        # row must fail rather than be silently dropped (which would quietly
        # change the callable mask that downstream recovery depends on).
        data_lines = count_data_lines(path)
        if len(intervals) < data_lines:
            print(
                f"ERROR\tbuild_callable_mask\t{label} has {data_lines - len(intervals)} "
                f"malformed/unparseable BED row(s) of {data_lines}: {path}",
                file=sys.stderr,
            )
            return 1
        parsed[label] = intervals
    reference = filter_min_length(parsed["reference-fills"], args.min_fragment)
    query = filter_min_length(parsed["query-fills-projected"], args.min_fragment)

    reference_merged = merge_intervals(reference)
    query_merged = merge_intervals(query)
    reference_intervals = [
        {"chrom": chrom, "start": start, "end": end}
        for chrom, ranges in reference_merged.items()
        for start, end in ranges
    ]
    query_intervals = [
        {"chrom": chrom, "start": start, "end": end}
        for chrom, ranges in query_merged.items()
        for start, end in ranges
    ]

    callable_mask = intersect_intervals(reference_intervals, query_intervals)
    write_bed(args.out, callable_mask)

    mask_bp = sum(end - start for ranges in callable_mask.values() for start, end in ranges)
    print(
        "CAME callable-orthology mask: "
        f"reference_bp={total_length(reference)} query_bp={total_length(query)} "
        f"callable_bp={mask_bp} min_fragment={args.min_fragment}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
