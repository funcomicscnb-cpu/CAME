#!/usr/bin/env python3
"""Define reciprocal-best liftOver chains by chain-identifier intersection.

This implements the identifier-intersection step of the UCSC reciprocal-best
procedure described for orthologous-region definition. Given the chain subsets
retained by the net in each orientation (human-as-target and species-as-target),
reciprocal-best chains are the chains whose identifiers appear in *both*
net-derived subsets. The original raw chain file is then filtered to that
identifier list to produce the reciprocal-best chain set.

CAME owns this as study-side, query-specific coordinate-projection preparation.
It does not build or modify any CEEG model bundle. External UCSC tools
(halSynteny, axtChain, chainNet, chainSwap, netChainSubset) are orchestrated by
Nextflow; this script only performs the deterministic identifier intersection
and filtering, which is testable without those binaries.
"""

import argparse
import os
import sys

from orthology_intervals import (
    chain_body_issue,
    chain_header_stats,
    count_data_lines,
    duplicate_chain_ids,
    extract_chain_ids,
    filter_chain_by_ids,
)


def parse_args():
    parser = argparse.ArgumentParser(description="Define reciprocal-best liftOver chains.")
    parser.add_argument(
        "--target-net-chains",
        required=True,
        help="netChainSubset output from the target-as-reference reciprocal net (chain format).",
    )
    parser.add_argument(
        "--query-net-chains",
        required=True,
        help="netChainSubset output from the query-as-reference reciprocal net (chain format).",
    )
    parser.add_argument(
        "--raw-chains",
        required=True,
        help="Original raw chain file to filter down to reciprocal-best identifiers.",
    )
    parser.add_argument("--out-chains", required=True, help="Reciprocal-best chain output path.")
    parser.add_argument("--out-ids", default=None, help="Optional path to write the reciprocal-best id list.")
    return parser.parse_args()


def main():
    args = parse_args()
    # --- Validate all inputs BEFORE writing any output, so a fatal mismatch never
    # leaves inconsistent out_chains / out_ids artifacts behind. ---
    for label, path in (
        ("target-net-chains", args.target_net_chains),
        ("query-net-chains", args.query_net_chains),
        ("raw-chains", args.raw_chains),
    ):
        if not os.path.exists(path):
            print(f"ERROR\tdefine_reciprocal_best_chains\t{label} does not exist: {path}", file=sys.stderr)
            return 1
        headers, parseable = chain_header_stats(path)
        if headers == 0 and count_data_lines(path) > 0:
            print(f"ERROR\tdefine_reciprocal_best_chains\t{label} has content but no UCSC chain headers (malformed?): {path}", file=sys.stderr)
            return 1
        # Header-looking lines that lack the full 13 fields cannot yield an id and
        # would be silently dropped; treat any such line as malformed.
        if headers > parseable:
            print(f"ERROR\tdefine_reciprocal_best_chains\t{label} has {headers - parseable} malformed chain header(s) of {headers}: {path}", file=sys.stderr)
            return 1
        # Body records (size / size dt dq) must be structurally valid so a filtered
        # block is never copied through with a corrupt body.
        body_issue = chain_body_issue(path)
        if body_issue:
            print(f"ERROR\tdefine_reciprocal_best_chains\t{label} {body_issue}: {path}", file=sys.stderr)
            return 1
        # Chain ids are unique within a file and are the reciprocal-best join key;
        # duplicates are an ambiguity (e.g. concatenated chain files).
        dups = duplicate_chain_ids(path)
        if dups:
            preview = ", ".join(sorted(dups)[:10])
            print(f"ERROR\tdefine_reciprocal_best_chains\t{label} has {len(dups)} duplicate chain id(s): {preview} ({path})", file=sys.stderr)
            return 1

    target_ids = extract_chain_ids(args.target_net_chains)
    query_ids = extract_chain_ids(args.query_net_chains)
    raw_ids = extract_chain_ids(args.raw_chains)
    reciprocal_best_ids = target_ids & query_ids

    # Reciprocal-best IDs come from net subsets of the raw chains, so every one
    # must be present in the raw chain. Compare against the raw chain's unique id
    # SET (not a written-block count, which duplicate raw ids could inflate). A
    # shortfall means mismatched inputs (e.g. a raw chain from a different run).
    missing_ids = reciprocal_best_ids - raw_ids
    if missing_ids:
        preview = ", ".join(sorted(missing_ids)[:10])
        print(
            f"ERROR\tdefine_reciprocal_best_chains\t{len(missing_ids)} of "
            f"{len(reciprocal_best_ids)} reciprocal-best chain id(s) are absent from the raw chain "
            f"({args.raw_chains}); inputs appear mismatched: {preview}",
            file=sys.stderr,
        )
        return 1

    # --- All validation passed; now write outputs (parent dirs created as
    # needed). A write failure is reported cleanly, not as a raw traceback. ---
    try:
        kept = filter_chain_by_ids(args.raw_chains, reciprocal_best_ids, args.out_chains)
        if args.out_ids:
            os.makedirs(os.path.dirname(args.out_ids) or ".", exist_ok=True)
            with open(args.out_ids, "w") as handle:
                for chain_id in sorted(reciprocal_best_ids, key=lambda value: (len(value), value)):
                    handle.write(chain_id + "\n")
    except OSError as exc:
        print(f"ERROR\tdefine_reciprocal_best_chains\tFailed to write outputs: {exc}", file=sys.stderr)
        return 1

    print(
        "CAME reciprocal-best chain definition: "
        f"target_ids={len(target_ids)} query_ids={len(query_ids)} "
        f"reciprocal_best_ids={len(reciprocal_best_ids)} chains_written={kept}"
    )
    if not reciprocal_best_ids:
        print(
            "WARNING\tdefine_reciprocal_best_chains\tNo reciprocal-best chain identifiers were shared between orientations.",
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
