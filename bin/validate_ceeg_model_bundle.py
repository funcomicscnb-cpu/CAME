#!/usr/bin/env python3
"""Validate an optional CEEG model bundle directory for CAME compatibility.

Checks presence and required columns for nodes.tsv, edges.tsv, evidence.tsv,
and metrics.tsv, then enforces CEEG semantic contracts:

  - unknown_unmappable nodes must have unknown_absent=unknown (not absent)
  - projected_direct nodes must not carry functional-conservation evidence types
  - regulatory_projection edges must have a non-empty projection_mode
  - data_mode values must be bulk | single_cell | hybrid | unknown
  - mappable nodes must have non-empty provenance in evidence records
  - all node cross-references must resolve within nodes.tsv

Usage
-----
  python3 bin/validate_ceeg_model_bundle.py assets/example_samplesheets/ceeg_model_bundle
  python3 bin/validate_ceeg_model_bundle.py --bundle_dir /path/to/bundle --report out.tsv

Exit codes: 0 = valid (zero ERRORs), 1 = invalid (one or more ERRORs), 2 = usage error.
"""

import argparse
import csv
import os
import sys
from collections import Counter

# ── controlled vocabularies ───────────────────────────────────────────────────

VALID_DATA_MODES = {"bulk", "single_cell", "hybrid", "unknown"}
VALID_EVIDENCE_STATUS = {"observed", "projected_direct", "projected_indirect"}
VALID_PROJECTION_TYPES = {"direct", "indirect", "none"}
VALID_UNKNOWN_ABSENT = {"unknown", "absent"}
VALID_MAPPING_STATES = {"mappable", "unknown_unmappable"}
VALID_NODE_TYPES = {"biological_system", "regulatory_element"}

# Required projection_type for each evidence_status value.
EVIDENCE_STATUS_TO_PROJECTION_TYPE = {
    "observed":           "none",
    "projected_direct":   "direct",
    "projected_indirect": "indirect",
}

# evidence_type values that imply functional conservation — forbidden on projected_direct nodes
FUNCTIONAL_CONSERVATION_EVIDENCE_TYPES = {
    "functional_conservation",
    "functional_homology",
    "conservation_inference",
    "functional_equivalence",
}

REQUIRED_COLUMNS = {
    "nodes": [
        "node_id", "node_type", "biological_system",
        "data_mode", "evidence_status", "projection_type", "mapping_state",
    ],
    "edges": [
        "edge_id", "source_node_id", "target_node_id",
        "edge_type", "projection_mode",
    ],
    "evidence": [
        "evidence_id", "node_id", "evidence_type",
        "data_mode", "unknown_absent", "provenance",
    ],
    "metrics": [
        "node_id", "biological_system", "data_mode",
        "ceeg_score", "ceeg_rank", "n_supporting_species",
    ],
}

# ── helpers ────────────────────────────────────────────────────────────────────

def norm(value):
    return str(value).strip() if value is not None else ""


def lower_norm(value):
    return norm(value).lower()


def add(records, severity, source, field, row, message, rule_id="", suggestion=""):
    records.append({
        "severity": severity,
        "rule_id": rule_id or "",
        "source": source,
        "field": field or "",
        "row": str(row or ""),
        "message": " ".join(norm(message).split()),
        "suggestion": " ".join(norm(suggestion).split()),
    })


def read_tsv(path, source, records):
    if not os.path.exists(path):
        add(
            records, "ERROR", source, "", "",
            f"Required file not found: {path}",
            rule_id="CEEG_BUNDLE_MISSING_FILE",
            suggestion=f"Add {os.path.basename(path)} to the bundle directory.",
        )
        return [], []
    try:
        with open(path, newline="") as handle:
            reader = csv.DictReader(handle, delimiter="\t")
            fields = list(reader.fieldnames or [])
            rows = list(reader)
    except Exception as exc:
        add(records, "ERROR", source, "", "", f"Could not read file: {exc}",
            rule_id="CEEG_BUNDLE_UNREADABLE_FILE")
        return [], []
    if not fields:
        add(records, "ERROR", source, "", "", "File has no header row",
            rule_id="CEEG_BUNDLE_EMPTY_FILE")
    else:
        for col in fields:
            if norm(col) == "":
                add(
                    records, "ERROR", source, "", "",
                    "Empty column header",
                    rule_id="CEEG_BUNDLE_EMPTY_COLUMN_HEADER",
                    suggestion=f"Remove the empty column from {source}.tsv.",
                )
        duplicates = sorted(k for k, v in Counter(fields).items() if v > 1)
        for col in duplicates:
            add(
                records, "ERROR", source, col, "",
                f"Duplicate column header: {col}",
                rule_id="CEEG_BUNDLE_DUPLICATE_COLUMN",
                suggestion=f"Remove the duplicate '{col}' column from {source}.tsv.",
            )
    for idx, row in enumerate(rows, start=2):
        if None in row:
            add(
                records, "ERROR", source, "", idx,
                "Malformed TSV row has more fields than the header",
                rule_id="CEEG_BUNDLE_MALFORMED_TSV_ROW",
                suggestion="Ensure every data row has the same number of tab-separated fields as the header.",
            )
        elif any(row.get(field) is None for field in fields):
            add(
                records, "ERROR", source, "", idx,
                "Malformed TSV row has fewer fields than the header",
                rule_id="CEEG_BUNDLE_MALFORMED_TSV_ROW",
                suggestion="Ensure every data row has the same number of tab-separated fields as the header.",
            )
    return fields, rows


def check_required_columns(source, fields, records):
    present = set(fields)
    for col in REQUIRED_COLUMNS.get(source, []):
        if col not in present:
            add(
                records, "ERROR", source, col, "",
                f"Missing required column: {col}",
                rule_id="CEEG_BUNDLE_MISSING_REQUIRED_COLUMN",
                suggestion=f"Add column '{col}' to {source}.tsv.",
            )


# ceeg_score, ceeg_rank, and n_supporting_species may be legitimately empty for
# unknown_unmappable nodes; the column header is required but the cell value is not.
METRICS_OPTIONAL_VALUES = {"ceeg_score", "ceeg_rank", "n_supporting_species"}

# provenance may be empty for unknown_unmappable nodes (alignment failed, no artifact);
# check_evidence emits a WARNING for mappable nodes that are missing provenance.
EVIDENCE_OPTIONAL_VALUES = {"provenance"}

# projection_mode is only required for regulatory_projection edges; other edge types
# may omit it. The column header is required but the cell value is not for non-projection edges.
EDGES_OPTIONAL_VALUES = {"projection_mode"}

# Known edge types. Unknown types emit a WARNING so bundles with custom types are not
# rejected outright — CEEG edge_type vocabulary may be extended in future releases.
VALID_EDGE_TYPES = {"regulatory_projection"}


def check_required_values(source, rows, records, optional_values=None):
    required = REQUIRED_COLUMNS.get(source, [])
    skip = set(optional_values or [])
    for idx, row in enumerate(rows, start=2):
        for col in required:
            if col in skip:
                continue
            if col in row and norm(row[col]) == "":
                add(
                    records, "ERROR", source, col, idx,
                    f"Empty required value in column '{col}'",
                    rule_id="CEEG_BUNDLE_EMPTY_REQUIRED_VALUE",
                )

# ── per-table semantic checks ─────────────────────────────────────────────────

def check_nodes(rows, records):
    seen_ids = {}
    for idx, row in enumerate(rows, start=2):
        node_id = norm(row.get("node_id"))
        if not node_id:
            continue

        if node_id in seen_ids:
            add(
                records, "ERROR", "nodes", "node_id", idx,
                f"Duplicate node_id: {node_id}",
                rule_id="CEEG_BUNDLE_DUPLICATE_NODE_ID",
                suggestion="Each node_id must be unique within nodes.tsv.",
            )
        else:
            seen_ids[node_id] = idx

        dm = lower_norm(row.get("data_mode"))
        if dm and dm not in VALID_DATA_MODES:
            add(
                records, "ERROR", "nodes", "data_mode", idx,
                f"Invalid data_mode '{dm}'; expected one of: {', '.join(sorted(VALID_DATA_MODES))}",
                rule_id="CEEG_BUNDLE_INVALID_DATA_MODE",
                suggestion="Use bulk, single_cell, hybrid, or unknown.",
            )

        nt = lower_norm(row.get("node_type"))
        if nt and nt not in VALID_NODE_TYPES:
            add(
                records, "ERROR", "nodes", "node_type", idx,
                f"Invalid node_type '{nt}'",
                rule_id="CEEG_BUNDLE_INVALID_NODE_TYPE",
                suggestion=f"Use one of: {', '.join(sorted(VALID_NODE_TYPES))}.",
            )

        es = lower_norm(row.get("evidence_status"))
        if es and es not in VALID_EVIDENCE_STATUS:
            add(
                records, "ERROR", "nodes", "evidence_status", idx,
                f"Invalid evidence_status '{es}'",
                rule_id="CEEG_BUNDLE_INVALID_EVIDENCE_STATUS",
                suggestion=f"Use one of: {', '.join(sorted(VALID_EVIDENCE_STATUS))}.",
            )

        pt = lower_norm(row.get("projection_type"))
        if pt and pt not in VALID_PROJECTION_TYPES:
            add(
                records, "ERROR", "nodes", "projection_type", idx,
                f"Invalid projection_type '{pt}'",
                rule_id="CEEG_BUNDLE_INVALID_PROJECTION_TYPE",
                suggestion=f"Use one of: {', '.join(sorted(VALID_PROJECTION_TYPES))}.",
            )

        if es and pt and es in EVIDENCE_STATUS_TO_PROJECTION_TYPE and EVIDENCE_STATUS_TO_PROJECTION_TYPE[es] != pt:
            add(
                records, "ERROR", "nodes", "projection_type", idx,
                (
                    f"Node '{node_id}': evidence_status='{es}' requires "
                    f"projection_type='{EVIDENCE_STATUS_TO_PROJECTION_TYPE[es]}', got '{pt}'"
                ),
                rule_id="CEEG_BUNDLE_INCONSISTENT_PROJECTION_TYPE",
                suggestion=(
                    f"Set projection_type='{EVIDENCE_STATUS_TO_PROJECTION_TYPE[es]}' "
                    f"to match evidence_status='{es}'."
                ),
            )

        ms = lower_norm(row.get("mapping_state"))
        if ms and ms not in VALID_MAPPING_STATES:
            add(
                records, "ERROR", "nodes", "mapping_state", idx,
                f"Invalid mapping_state '{ms}'",
                rule_id="CEEG_BUNDLE_INVALID_MAPPING_STATE",
                suggestion=f"Use one of: {', '.join(sorted(VALID_MAPPING_STATES))}.",
            )

        if not norm(row.get("biological_system")):
            add(
                records, "ERROR", "nodes", "biological_system", idx,
                "biological_system must not be empty",
                rule_id="CEEG_BUNDLE_MISSING_BIOLOGICAL_SYSTEM",
                suggestion="Assign every node to a named biological_system identifier.",
            )

    return seen_ids


def check_edges(rows, node_ids, records):
    seen_edge_ids = {}
    seen_proj_targets = {}
    for idx, row in enumerate(rows, start=2):
        edge_id    = norm(row.get("edge_id"))
        edge_type  = lower_norm(row.get("edge_type"))
        source     = norm(row.get("source_node_id"))
        target     = norm(row.get("target_node_id"))
        projection_mode = norm(row.get("projection_mode"))

        if edge_id:
            if edge_id in seen_edge_ids:
                add(
                    records, "ERROR", "edges", "edge_id", idx,
                    f"Duplicate edge_id: {edge_id}",
                    rule_id="CEEG_BUNDLE_DUPLICATE_EDGE_ID",
                    suggestion="Each edge_id must be unique within edges.tsv.",
                )
            else:
                seen_edge_ids[edge_id] = idx

        if edge_type and edge_type not in VALID_EDGE_TYPES:
            add(
                records, "WARNING", "edges", "edge_type", idx,
                f"Unrecognized edge_type '{edge_type}'",
                rule_id="CEEG_BUNDLE_UNKNOWN_EDGE_TYPE",
                suggestion=(
                    f"Known edge types: {', '.join(sorted(VALID_EDGE_TYPES))}. "
                    "Custom types are permitted but may not be processed by downstream steps."
                ),
            )

        if edge_type == "regulatory_projection" and not projection_mode:
            add(
                records, "ERROR", "edges", "projection_mode", idx,
                "regulatory_projection edge is missing projection_mode",
                rule_id="CEEG_BUNDLE_MISSING_PROJECTION_MODE",
                suggestion=(
                    "Set projection_mode (e.g. direct_alignment, synteny_block) "
                    "for every regulatory_projection edge."
                ),
            )

        if source and target and source == target:
            add(
                records, "ERROR", "edges", "target_node_id", idx,
                f"Edge '{edge_id}' has the same source and target node: '{source}'",
                rule_id="CEEG_BUNDLE_SELF_REFERENCE_EDGE",
                suggestion="Projection edges must connect two different nodes.",
            )

        if target and edge_type == "regulatory_projection":
            if target in seen_proj_targets:
                add(
                    records, "ERROR", "edges", "target_node_id", idx,
                    f"Multiple regulatory_projection edges to target '{target}'",
                    rule_id="CEEG_BUNDLE_DUPLICATE_PROJECTION_TARGET",
                    suggestion="A regulatory element may have at most one incoming projection edge.",
                )
            else:
                seen_proj_targets[target] = idx

        for ref_col in ("source_node_id", "target_node_id"):
            ref = norm(row.get(ref_col))
            if ref and ref not in node_ids:
                add(
                    records, "ERROR", "edges", ref_col, idx,
                    f"Node '{ref}' referenced in {ref_col} does not exist in nodes.tsv",
                    rule_id="CEEG_BUNDLE_UNRESOLVED_NODE_REF",
                    suggestion="Add the missing node to nodes.tsv or correct the edge reference.",
                )


def check_evidence(rows, node_ids, edge_ids, node_mapping_state, node_evidence_status, records):
    seen_evidence_ids = {}
    for idx, row in enumerate(rows, start=2):
        evidence_id = norm(row.get("evidence_id"))
        if evidence_id:
            if evidence_id in seen_evidence_ids:
                add(
                    records, "ERROR", "evidence", "evidence_id", idx,
                    f"Duplicate evidence_id: {evidence_id}",
                    rule_id="CEEG_BUNDLE_DUPLICATE_EVIDENCE_ID",
                    suggestion="Each evidence_id must be unique within evidence.tsv.",
                )
            else:
                seen_evidence_ids[evidence_id] = idx

        ev_edge_id = norm(row.get("edge_id"))
        if ev_edge_id and ev_edge_id not in edge_ids:
            add(
                records, "ERROR", "evidence", "edge_id", idx,
                f"Edge '{ev_edge_id}' referenced in evidence does not exist in edges.tsv",
                rule_id="CEEG_BUNDLE_UNRESOLVED_EDGE_REF",
                suggestion="Add the edge to edges.tsv or remove the edge_id from this evidence record.",
            )

        node_id = norm(row.get("node_id"))
        evidence_type = lower_norm(row.get("evidence_type"))
        ua = lower_norm(row.get("unknown_absent"))
        provenance = norm(row.get("provenance"))

        if ua and ua not in VALID_UNKNOWN_ABSENT:
            add(
                records, "ERROR", "evidence", "unknown_absent", idx,
                f"Invalid unknown_absent value '{ua}'",
                rule_id="CEEG_BUNDLE_INVALID_UNKNOWN_ABSENT",
                suggestion=f"Use one of: {', '.join(sorted(VALID_UNKNOWN_ABSENT))}.",
            )

        # Core contract: unknown_unmappable must not be represented as absent.
        if node_id in node_mapping_state:
            ms = node_mapping_state[node_id]
            if ms == "unknown_unmappable" and ua == "absent":
                add(
                    records, "ERROR", "evidence", "unknown_absent", idx,
                    (
                        f"Node '{node_id}' has mapping_state=unknown_unmappable "
                        "but unknown_absent=absent; unknown state must not be represented as absent"
                    ),
                    rule_id="CEEG_BUNDLE_UNKNOWN_REPRESENTED_AS_ABSENT",
                    suggestion="Set unknown_absent=unknown for unmappable nodes.",
                )

        # Core contract: a successfully mapped node must have a determined state (absent).
        if node_id in node_mapping_state:
            ms = node_mapping_state[node_id]
            if ms == "mappable" and ua == "unknown":
                add(
                    records, "ERROR", "evidence", "unknown_absent", idx,
                    (
                        f"Node '{node_id}' has mapping_state=mappable "
                        "but unknown_absent=unknown; a successfully mapped node must have "
                        "a determined reference panel state (absent)"
                    ),
                    rule_id="CEEG_BUNDLE_MAPPABLE_UNKNOWN_ABSENT",
                    suggestion="Set unknown_absent=absent for mappable nodes.",
                )

        # Core contract: positional projection (direct or indirect) carries no functional conservation claim.
        if node_id in node_evidence_status:
            es = node_evidence_status[node_id]
            if es in ("projected_direct", "projected_indirect") and evidence_type in FUNCTIONAL_CONSERVATION_EVIDENCE_TYPES:
                add(
                    records, "ERROR", "evidence", "evidence_type", idx,
                    (
                        f"Node '{node_id}' has evidence_status='{es}' "
                        f"but evidence_type='{evidence_type}' implies functional conservation; "
                        "positional projection carries no functional conservation claim"
                    ),
                    rule_id="CEEG_BUNDLE_PROJECTED_FUNCTIONAL_CONSERVATION",
                    suggestion=(
                        "Remove functional-conservation evidence types from projected nodes "
                        "or reclassify the node's evidence_status."
                    ),
                )

        # Provenance must be retained for mappable nodes.
        if node_id in node_mapping_state:
            ms = node_mapping_state[node_id]
            if ms == "mappable" and not provenance:
                add(
                    records, "WARNING", "evidence", "provenance", idx,
                    f"Evidence record for mappable node '{node_id}' has no provenance",
                    rule_id="CEEG_BUNDLE_MISSING_PROVENANCE",
                    suggestion=(
                        "Supply a provenance string (e.g. pipeline version, "
                        "source assay, alignment tool)."
                    ),
                )

        dm = lower_norm(row.get("data_mode"))
        if dm and dm not in VALID_DATA_MODES:
            add(
                records, "ERROR", "evidence", "data_mode", idx,
                f"Invalid data_mode '{dm}'",
                rule_id="CEEG_BUNDLE_INVALID_DATA_MODE",
                suggestion=f"Use one of: {', '.join(sorted(VALID_DATA_MODES))}.",
            )

        if node_id and node_id not in node_ids:
            add(
                records, "ERROR", "evidence", "node_id", idx,
                f"Node '{node_id}' referenced in evidence does not exist in nodes.tsv",
                rule_id="CEEG_BUNDLE_UNRESOLVED_NODE_REF",
                suggestion="Add the missing node to nodes.tsv or correct the evidence record.",
            )


def check_metrics(rows, node_ids, node_mapping_state, records):
    seen_metric_nodes = {}
    for idx, row in enumerate(rows, start=2):
        dm = lower_norm(row.get("data_mode"))
        if dm and dm not in VALID_DATA_MODES:
            add(
                records, "ERROR", "metrics", "data_mode", idx,
                f"Invalid data_mode '{dm}'",
                rule_id="CEEG_BUNDLE_INVALID_DATA_MODE",
                suggestion=f"Use one of: {', '.join(sorted(VALID_DATA_MODES))}.",
            )
        node_id = norm(row.get("node_id"))
        if node_id:
            if node_id in seen_metric_nodes:
                add(
                    records, "ERROR", "metrics", "node_id", idx,
                    f"Duplicate node_id in metrics: {node_id}",
                    rule_id="CEEG_BUNDLE_DUPLICATE_METRICS_NODE",
                    suggestion="Each node_id should appear at most once in metrics.tsv.",
                )
            else:
                seen_metric_nodes[node_id] = idx
        if node_id and node_id not in node_ids:
            add(
                records, "ERROR", "metrics", "node_id", idx,
                f"Node '{node_id}' referenced in metrics does not exist in nodes.tsv",
                rule_id="CEEG_BUNDLE_UNRESOLVED_NODE_REF",
                suggestion="Add the missing node to nodes.tsv or correct the metrics record.",
            )
        score_str = norm(row.get("ceeg_score", ""))
        if score_str:
            try:
                float(score_str)
            except ValueError:
                add(
                    records, "ERROR", "metrics", "ceeg_score", idx,
                    f"ceeg_score '{score_str}' is not a valid decimal number",
                    rule_id="CEEG_BUNDLE_INVALID_SCORE_FORMAT",
                    suggestion="Use a decimal number (e.g. 0.75) or leave empty for unmappable nodes.",
                )
        rank_str = norm(row.get("ceeg_rank", ""))
        if rank_str:
            try:
                int(rank_str)
            except ValueError:
                add(
                    records, "ERROR", "metrics", "ceeg_rank", idx,
                    f"ceeg_rank '{rank_str}' is not a valid integer",
                    rule_id="CEEG_BUNDLE_INVALID_RANK_FORMAT",
                    suggestion="Use a positive integer (e.g. 1, 2, 3).",
                )
        ns_str = norm(row.get("n_supporting_species", ""))
        if ns_str:
            try:
                if int(ns_str) < 0:
                    raise ValueError("negative")
            except ValueError:
                add(
                    records, "ERROR", "metrics", "n_supporting_species", idx,
                    f"n_supporting_species '{ns_str}' is not a valid non-negative integer",
                    rule_id="CEEG_BUNDLE_INVALID_SPECIES_COUNT_FORMAT",
                    suggestion="Use a non-negative integer (e.g. 0, 1, 2).",
                )
        # Warn when a mappable node has no score — empty is expected only for unmappable nodes.
        ms = node_mapping_state.get(node_id, "")
        if ms == "mappable" and not score_str:
            add(
                records, "WARNING", "metrics", "ceeg_score", idx,
                f"Mappable node '{node_id}' has no ceeg_score",
                rule_id="CEEG_BUNDLE_MISSING_SCORE",
                suggestion="Provide a ceeg_score for mappable nodes; empty scores are expected only for unknown_unmappable nodes.",
            )

# ── report helpers ─────────────────────────────────────────────────────────────

def write_report(path, records):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    fields = ["severity", "rule_id", "source", "field", "row", "message", "suggestion"]
    tmp = path + ".tmp"
    try:
        with open(tmp, "w", newline="") as handle:
            writer = csv.DictWriter(
                handle, fieldnames=fields, delimiter="\t",
                extrasaction="ignore", lineterminator="\n",
            )
            writer.writeheader()
            writer.writerows(records)
        os.replace(tmp, path)
    except:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def print_summary(records, bundle_dir):
    counts = Counter(row["severity"] for row in records)
    print("CEEG bundle validation summary")
    print(f"Bundle : {bundle_dir}")
    print(f"ERROR  : {counts.get('ERROR', 0)}")
    print(f"WARNING: {counts.get('WARNING', 0)}")
    print(f"INFO   : {counts.get('INFO', 0)}")
    for severity in ("ERROR", "WARNING"):
        shown = 0
        for row in records:
            if row["severity"] != severity:
                continue
            loc = f"{row['source']}:{row['row']}" if row["row"] else row["source"]
            print(f"  {severity}  {loc}  {row['rule_id'] or row['field']}  {row['message']}")
            shown += 1
            if shown == 20:
                remaining = counts[severity] - shown
                if remaining > 0:
                    print(f"  {severity}  ...  ...  {remaining} more")
                break

# ── argument parsing ───────────────────────────────────────────────────────────

def parse_args():
    parser = argparse.ArgumentParser(
        description="Validate a CEEG model bundle directory for CAME compatibility.",
        epilog=(
            "Examples:\n"
            "  python3 bin/validate_ceeg_model_bundle.py "
            "assets/example_samplesheets/ceeg_model_bundle\n"
            "  python3 bin/validate_ceeg_model_bundle.py "
            "--bundle_dir /path/to/bundle --report report.tsv"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "bundle_dir_pos", nargs="?", default=None,
        metavar="bundle_dir",
        help="Path to the CEEG model bundle directory (positional shortcut).",
    )
    parser.add_argument(
        "--bundle_dir", default=None,
        help="Path to the CEEG model bundle directory.",
    )
    parser.add_argument(
        "--report", default="",
        help="Path to write the validation report TSV (optional).",
    )
    return parser.parse_args()

# ── main ───────────────────────────────────────────────────────────────────────

def main():
    args = parse_args()
    bundle_dir = args.bundle_dir or args.bundle_dir_pos
    if not bundle_dir:
        print(
            "ERROR: supply bundle_dir as a positional argument or via --bundle_dir",
            file=sys.stderr,
        )
        return 2
    bundle_dir = bundle_dir.rstrip("/")

    records = []

    if not os.path.isdir(bundle_dir):
        add(
            records, "ERROR", "bundle", "", "",
            f"Bundle directory does not exist: {bundle_dir}",
            rule_id="CEEG_BUNDLE_MISSING_DIRECTORY",
        )
        if args.report:
            write_report(args.report, records)
        print_summary(records, bundle_dir)
        return 1

    # ── load tables ───────────────────────────────────────────────────────────
    node_fields, node_rows = read_tsv(os.path.join(bundle_dir, "nodes.tsv"), "nodes", records)
    edge_fields, edge_rows = read_tsv(os.path.join(bundle_dir, "edges.tsv"), "edges", records)
    ev_fields, ev_rows = read_tsv(os.path.join(bundle_dir, "evidence.tsv"), "evidence", records)
    met_fields, met_rows = read_tsv(os.path.join(bundle_dir, "metrics.tsv"), "metrics", records)

    # ── column + value presence ───────────────────────────────────────────────
    for source, fields, rows in [
        ("nodes", node_fields, node_rows),
        ("edges", edge_fields, edge_rows),
        ("evidence", ev_fields, ev_rows),
        ("metrics", met_fields, met_rows),
    ]:
        check_required_columns(source, fields, records)
        if source == "metrics":
            optional = METRICS_OPTIONAL_VALUES
        elif source == "evidence":
            optional = EVIDENCE_OPTIONAL_VALUES
        elif source == "edges":
            optional = EDGES_OPTIONAL_VALUES
        else:
            optional = None
        check_required_values(source, rows, records, optional_values=optional)

    # ── build cross-reference indexes ─────────────────────────────────────────
    _nodes_ok = bool(node_fields)  # False when nodes.tsv was missing or unreadable
    if node_fields and not node_rows:
        add(
            records, "ERROR", "nodes", "", "",
            "nodes.tsv has a header but no data rows",
            rule_id="CEEG_BUNDLE_EMPTY_NODES_TABLE",
            suggestion="Add at least one node row to nodes.tsv.",
        )
        _nodes_ok = False  # suppress cascade UNRESOLVED_NODE_REF errors
    if edge_fields and not edge_rows and any(
        lower_norm(r.get("evidence_status")) in ("projected_direct", "projected_indirect")
        for r in node_rows
    ):
        add(
            records, "ERROR", "edges", "", "",
            "edges.tsv has a header but no data rows while projected nodes are present",
            rule_id="CEEG_BUNDLE_EMPTY_EDGES_TABLE",
            suggestion="Add projection edge rows or remove projected node statuses.",
        )
    if ev_fields and not ev_rows:
        add(
            records, "ERROR", "evidence", "", "",
            "evidence.tsv has a header but no data rows",
            rule_id="CEEG_BUNDLE_EMPTY_EVIDENCE_TABLE",
            suggestion="Add at least one evidence row to evidence.tsv.",
        )
    if met_fields and not met_rows:
        add(
            records, "ERROR", "metrics", "", "",
            "metrics.tsv has a header but no data rows",
            rule_id="CEEG_BUNDLE_EMPTY_METRICS_TABLE",
            suggestion="Add at least one metrics row to metrics.tsv.",
        )
    node_ids = {
        norm(r.get("node_id")): i
        for i, r in enumerate(node_rows, start=2)
        if norm(r.get("node_id"))
    }
    node_mapping_state = {
        norm(r.get("node_id")): lower_norm(r.get("mapping_state"))
        for r in node_rows if norm(r.get("node_id"))
    }
    node_evidence_status = {
        norm(r.get("node_id")): lower_norm(r.get("evidence_status"))
        for r in node_rows if norm(r.get("node_id"))
    }
    edge_ids = {norm(r.get("edge_id")) for r in edge_rows if norm(r.get("edge_id"))}

    # ── semantic checks ───────────────────────────────────────────────────────
    # Cross-reference checks are skipped when nodes.tsv failed to load or is empty;
    # without a node index every edge/evidence/metrics reference would produce a
    # spurious UNRESOLVED_NODE_REF.
    check_nodes(node_rows, records)
    if _nodes_ok:
        check_edges(edge_rows, node_ids, records)
        check_evidence(ev_rows, node_ids, edge_ids, node_mapping_state, node_evidence_status, records)
        check_metrics(met_rows, node_ids, node_mapping_state, records)
    else:
        add(records, "INFO", "validation", "", "",
            "Cross-reference checks skipped: nodes.tsv could not be loaded.")

    total = len(node_rows) + len(edge_rows) + len(ev_rows) + len(met_rows)
    add(
        records, "INFO", "validation", "", "",
        (
            f"Validated {total} rows across "
            f"nodes ({len(node_rows)}), edges ({len(edge_rows)}), "
            f"evidence ({len(ev_rows)}), metrics ({len(met_rows)})"
        ),
    )

    if args.report:
        write_report(args.report, records)
    print_summary(records, bundle_dir)
    return 1 if any(row["severity"] == "ERROR" for row in records) else 0


if __name__ == "__main__":
    sys.exit(main())
