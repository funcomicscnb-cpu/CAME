#!/usr/bin/env python3
"""Import a validated CEEG model bundle into CAME-compatible tabular outputs.

Validation must be run before import:

  python3 bin/validate_ceeg_model_bundle.py <bundle_dir>
  python3 bin/import_ceeg_model_bundle.py --bundle <bundle_dir> --outdir <outdir>

This script is a pass-through importer: all source columns are written verbatim.
No values are recomputed, normalised, or inferred. Two lightweight invariant checks
are performed on critical semantic contracts — these mirror the validator's rules and
are present to catch bundle corruption that may occur after validation:

  - unknown_absent=unknown is never silently coerced to absent
  - evidence_type for projected nodes (direct or indirect) must not imply functional conservation

Neither check alters any value. Violations cause a non-zero exit before any file
is written.

Outputs (written to --outdir):

  ceeg_imported_nodes.tsv
  ceeg_imported_edges.tsv
  ceeg_imported_evidence.tsv
  ceeg_imported_metrics.tsv

Each output carries all original columns plus ceeg_bundle_source (path to the
source file inside the bundle, recorded for downstream provenance).

This script does not modify any existing CAME orthology, GRA, or metadata files.
"""

import argparse
import csv
import os
import sys
from collections import Counter

# ── constants ─────────────────────────────────────────────────────────────────

BUNDLE_FILES = {
    "nodes":    "nodes.tsv",
    "edges":    "edges.tsv",
    "evidence": "evidence.tsv",
    "metrics":  "metrics.tsv",
}

OUTPUT_FILES = {
    "nodes":    "ceeg_imported_nodes.tsv",
    "edges":    "ceeg_imported_edges.tsv",
    "evidence": "ceeg_imported_evidence.tsv",
    "metrics":  "ceeg_imported_metrics.tsv",
}

PROVENANCE_COLUMN = "ceeg_bundle_source"

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

UNIQUE_ID_COLUMNS = {
    "nodes": "node_id",
    "edges": "edge_id",
    "evidence": "evidence_id",
    "metrics": "node_id",
}

OPTIONAL_REQUIRED_VALUES = {
    "edges": {"projection_mode"},
    "evidence": {"provenance"},
    "metrics": {"ceeg_score", "ceeg_rank", "n_supporting_species"},
}

# evidence_type values that imply functional conservation (mirrors validate_ceeg_model_bundle.py)
FUNCTIONAL_CONSERVATION_TYPES = {
    "functional_conservation",
    "functional_homology",
    "conservation_inference",
    "functional_equivalence",
}

# ── helpers ────────────────────────────────────────────────────────────────────

def norm(value):
    """Strip surrounding whitespace only. Do not map 'none', 'unknown', etc. to ''."""
    return str(value).strip() if value is not None else ""


def read_tsv(path, table_key):
    """Read a tab-separated file; return (fields, rows).

    Field names and cell values are preserved exactly. Stripped values are
    used only by semantic invariant checks.
    """
    with open(path, newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        fields = list(reader.fieldnames or [])
        if not fields:
            abort(f"{path}: file has no header row")
        for col in fields:
            if norm(col) == "":
                abort(f"{path}: empty column header")
        normalized_fields = [norm(col) for col in fields]
        normalized_duplicates = sorted(k for k, v in Counter(normalized_fields).items() if v > 1)
        if normalized_duplicates:
            abort(
                f"{path}: duplicate column header(s) after trimming whitespace: "
                f"{', '.join(normalized_duplicates)}"
            )
        duplicates = sorted(k for k, v in Counter(fields).items() if v > 1)
        if duplicates:
            abort(f"{path}: duplicate column header(s): {', '.join(duplicates)}")
        if PROVENANCE_COLUMN in normalized_fields:
            abort(
                f"{path}: input table already contains reserved column "
                f"'{PROVENANCE_COLUMN}'"
            )
        missing = [c for c in REQUIRED_COLUMNS[table_key] if c not in fields]
        if missing:
            abort(f"{path}: missing required column(s): {', '.join(missing)}")
        rows = []
        for idx, row in enumerate(reader, start=2):
            if None in row:
                abort(f"{path}: malformed TSV row {idx} has more fields than the header")
            if any(row.get(field) is None for field in fields):
                abort(f"{path}: malformed TSV row {idx} has fewer fields than the header")
            optional_values = OPTIONAL_REQUIRED_VALUES.get(table_key, set())
            for col in REQUIRED_COLUMNS[table_key]:
                if col in optional_values:
                    continue
                if norm(row.get(col)) == "":
                    abort(f"{path}: empty required value in column '{col}' at row {idx}")
            if (
                table_key == "edges"
                and norm(row.get("edge_type")).lower() == "regulatory_projection"
                and norm(row.get("projection_mode")) == ""
            ):
                abort(f"{path}: regulatory_projection edge missing projection_mode at row {idx}")
            rows.append(row)
        if table_key in ("nodes", "evidence", "metrics") and not rows:
            abort(f"{path}: required table has no data rows")
        id_col = UNIQUE_ID_COLUMNS.get(table_key)
        if id_col:
            seen_ids = {}
            for idx, row in enumerate(rows, start=2):
                value = norm(row.get(id_col))
                if not value:
                    continue
                if value in seen_ids:
                    abort(
                        f"{path}: duplicate {id_col} '{value}' at row {idx} "
                        f"(first seen at row {seen_ids[value]})"
                    )
                seen_ids[value] = idx
    return fields, rows


def write_tsv(path, fields, rows):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    tmp = path + ".tmp"
    try:
        with open(tmp, "w", newline="") as handle:
            writer = csv.DictWriter(
                handle, fieldnames=fields, delimiter="\t",
                extrasaction="ignore", lineterminator="\n",
            )
            writer.writeheader()
            writer.writerows(rows)
        os.replace(tmp, path)
    except:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def abort(message):
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(1)

# ── invariant checks ───────────────────────────────────────────────────────────

def check_invariants(node_rows, edge_rows, evidence_rows, metrics_rows):
    """Lightweight checks on critical semantic contracts.

    These mirror the validator's rules. They exist to catch bundle corruption
    that may occur after validation has been run. Violations abort the import
    before any output file is written.
    """
    errors = []

    # Build node_id → mapping_state and node_id → evidence_status index from nodes
    node_mapping_state = {
        norm(r.get("node_id")): norm(r.get("mapping_state")).lower()
        for r in node_rows
        if norm(r.get("node_id"))
    }
    node_evidence_status = {
        norm(r.get("node_id")): norm(r.get("evidence_status")).lower()
        for r in node_rows
        if norm(r.get("node_id"))
    }
    edge_ids = {
        norm(r.get("edge_id"))
        for r in edge_rows
        if norm(r.get("edge_id"))
    }
    seen_projection_targets = {}
    for idx, row in enumerate(edge_rows, start=2):
        edge_id = norm(row.get("edge_id"))
        source_node_id = norm(row.get("source_node_id"))
        target_node_id = norm(row.get("target_node_id"))
        edge_type = norm(row.get("edge_type")).lower()
        for field, value in (("source_node_id", source_node_id), ("target_node_id", target_node_id)):
            if value and value not in node_mapping_state:
                errors.append(
                    f"edge row {idx}: {field} '{value}' not found in nodes — "
                    "bundle may have been corrupted after validation"
                )
        if source_node_id and target_node_id and source_node_id == target_node_id:
            errors.append(
                f"edge row {idx}: edge_id '{edge_id}' has the same source and target node "
                f"'{source_node_id}'"
            )
        if edge_type == "regulatory_projection" and target_node_id:
            if target_node_id in seen_projection_targets:
                errors.append(
                    f"edge row {idx}: multiple regulatory_projection edges target "
                    f"'{target_node_id}'"
                )
            else:
                seen_projection_targets[target_node_id] = idx

    for idx, row in enumerate(metrics_rows, start=2):
        node_id = norm(row.get("node_id"))
        if node_id and node_id not in node_mapping_state:
            errors.append(
                f"metrics row {idx}: node_id '{node_id}' not found in nodes — "
                "bundle may have been corrupted after validation"
            )

    for idx, row in enumerate(evidence_rows, start=2):
        node_id = norm(row.get("node_id"))
        edge_id = norm(row.get("edge_id"))
        unknown_absent = norm(row.get("unknown_absent")).lower()
        evidence_type = norm(row.get("evidence_type")).lower()

        # Guard: all further contracts require the node to exist in the node index.
        if node_id and node_id not in node_mapping_state:
            errors.append(
                f"evidence row {idx}: node_id '{node_id}' not found in nodes — "
                "bundle may have been corrupted after validation"
            )
            continue
        if edge_id and edge_id not in edge_ids:
            errors.append(
                f"evidence row {idx}: edge_id '{edge_id}' not found in edges — "
                "bundle may have been corrupted after validation"
            )

        # Contract: unknown_unmappable nodes must carry unknown_absent=unknown, not absent.
        ms = node_mapping_state.get(node_id, "")
        if ms == "unknown_unmappable" and unknown_absent == "absent":
            errors.append(
                f"evidence row {idx}: node '{node_id}' has mapping_state=unknown_unmappable "
                "but unknown_absent=absent — unknown must not be represented as absent"
            )

        # Contract: a successfully mapped node must have a determined state (absent, not unknown).
        if ms == "mappable" and unknown_absent == "unknown":
            errors.append(
                f"evidence row {idx}: node '{node_id}' has mapping_state=mappable "
                "but unknown_absent=unknown — a successfully mapped node must not have unknown state"
            )

        # Contract: projected nodes (direct or indirect) must not carry functional-conservation evidence.
        es = node_evidence_status.get(node_id, "")
        if es in ("projected_direct", "projected_indirect") and evidence_type in FUNCTIONAL_CONSERVATION_TYPES:
            errors.append(
                f"evidence row {idx}: node '{node_id}' has evidence_status='{es}' "
                f"but evidence_type='{evidence_type}' implies functional conservation — "
                "positional projection carries no functional conservation claim"
            )

    return errors

# ── import logic ───────────────────────────────────────────────────────────────

def import_table(bundle_dir, table_key, outdir, _preloaded=None):
    """Read one bundle table, add provenance column, write to outdir.

    Returns (output_path, n_rows, original_fields).
    """
    src_filename = BUNDLE_FILES[table_key]
    src_path = os.path.join(bundle_dir, src_filename)
    dst_path = os.path.join(outdir, OUTPUT_FILES[table_key])

    if _preloaded is not None:
        fields, rows = _preloaded
    else:
        fields, rows = read_tsv(src_path, table_key)

    out_fields = list(fields)
    out_fields.append(PROVENANCE_COLUMN)

    for row in rows:
        row[PROVENANCE_COLUMN] = src_path

    write_tsv(dst_path, out_fields, rows)
    return dst_path, len(rows), fields


def print_summary(results, bundle_dir, outdir):
    total = sum(n for _, n, _ in results.values())
    print("CEEG bundle import summary")
    print(f"Bundle : {bundle_dir}")
    print(f"Outdir : {outdir}")
    print(f"Tables : {len(results)}")
    print(f"Rows   : {total}")
    for table_key, (dst_path, n_rows, original_fields) in results.items():
        print(f"  {table_key:10s}  {n_rows:4d} rows  {len(original_fields)} source columns  → {dst_path}")

# ── argument parsing ───────────────────────────────────────────────────────────

def parse_args():
    parser = argparse.ArgumentParser(
        description="Import a validated CEEG model bundle into CAME-compatible tabular outputs.",
        epilog=(
            "Run validation first:\n"
            "  python3 bin/validate_ceeg_model_bundle.py <bundle_dir>\n"
            "Then import:\n"
            "  python3 bin/import_ceeg_model_bundle.py "
            "--bundle assets/example_samplesheets/ceeg_model_bundle --outdir results/ceeg_import_test"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--bundle", required=True,
        metavar="DIR",
        help="Path to the validated CEEG model bundle directory.",
    )
    parser.add_argument(
        "--outdir", required=True,
        metavar="DIR",
        help="Directory to write ceeg_imported_*.tsv output files.",
    )
    return parser.parse_args()

# ── main ───────────────────────────────────────────────────────────────────────

def main():
    args = parse_args()
    bundle_dir = os.path.abspath(args.bundle.rstrip("/"))
    outdir = args.outdir

    if not os.path.isdir(bundle_dir):
        abort(f"Bundle directory does not exist: {bundle_dir}")

    for table_key, filename in BUNDLE_FILES.items():
        path = os.path.join(bundle_dir, filename)
        if not os.path.exists(path):
            abort(
                f"Required bundle file not found: {path}\n"
                "Run python3 bin/validate_ceeg_model_bundle.py before importing."
            )

    # Load all tables upfront — invariant check and import operate on the same in-memory data,
    # eliminating a TOCTOU window where files could change between the two reads.
    preloaded = {}
    for table_key, filename in BUNDLE_FILES.items():
        preloaded[table_key] = read_tsv(os.path.join(bundle_dir, filename), table_key)

    node_rows = preloaded["nodes"][1]
    edge_rows = preloaded["edges"][1]
    evidence_rows = preloaded["evidence"][1]
    if not edge_rows and any(
        norm(r.get("evidence_status")).lower() in ("projected_direct", "projected_indirect")
        for r in node_rows
    ):
        abort(
            "edges.tsv has no data rows while projected nodes are present — "
            "re-run validate_ceeg_model_bundle.py to diagnose."
        )

    metrics_rows = preloaded["metrics"][1]

    errors = check_invariants(node_rows, edge_rows, evidence_rows, metrics_rows)
    if errors:
        print(
            "ERROR: Bundle failed semantic invariant checks. "
            "Re-run validate_ceeg_model_bundle.py to diagnose.",
            file=sys.stderr,
        )
        for msg in errors:
            print(f"  {msg}", file=sys.stderr)
        return 1

    results = {}
    for table_key in BUNDLE_FILES:
        dst_path, n_rows, original_fields = import_table(
            bundle_dir, table_key, outdir, _preloaded=preloaded[table_key]
        )
        results[table_key] = (dst_path, n_rows, original_fields)

    print_summary(results, bundle_dir, outdir)
    return 0


if __name__ == "__main__":
    sys.exit(main())
