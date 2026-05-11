#!/usr/bin/env python3
"""Build CAME-ready feature matrices from imported CEEG tables.

This script is a read-only view builder. It does not modify CAME analysis logic
or downstream candidate scores. All CEEG semantic values (unknown_absent,
evidence_status, provenance, biological_system) are preserved verbatim.

Outputs
-------
ceeg_regulatory_projection_features.tsv
    One row per regulatory_element node. Projection edge, metrics joined in.
ceeg_system_features.tsv
    One row per system identifier. Counts and score stats aggregated.
ceeg_evidence_features.tsv
    One row per evidence record. Node context and metrics joined in.

Invariants
----------
- unknown_absent=unknown is preserved verbatim; never mapped to absent.
- Empty ceeg_score for unknown_unmappable nodes is kept as ""; never replaced with 0.
- No column is written that implies functional conservation for projected_direct nodes.
- biological_system and provenance are copied verbatim, never normalised.
- biological_system nodes are excluded from the RE feature matrix.

Usage
-----
  python3 bin/build_came_ceeg_feature_matrices.py \\
    --import-dir results/ceeg_import_test \\
    --outdir results/ceeg_features

Exit codes: 0 = success, 1 = I/O or format error.
"""

import argparse
import csv
import os
import sys
from collections import Counter, defaultdict


# ── norm: strip-only; preserve controlled vocabulary tokens ──────────────────

def norm(value):
    """Strip whitespace only. Never map 'none', 'unknown', 'absent' to ''."""
    return str(value).strip() if value is not None else ""


def lower_norm(value):
    return norm(value).lower()


# ── I/O ──────────────────────────────────────────────────────────────────────

def read_tsv(path):
    if not os.path.exists(path):
        print(f"ERROR: required input not found: {path}", file=sys.stderr)
        sys.exit(1)
    with open(path, newline="") as fh:
        reader = csv.DictReader(fh, delimiter="\t")
        fields = list(reader.fieldnames or [])
        if not fields:
            print(f"ERROR: {path} has no header row", file=sys.stderr)
            sys.exit(1)
        empty_headers = [idx + 1 for idx, field in enumerate(fields) if norm(field) == ""]
        if empty_headers:
            print(
                f"ERROR: {path} has empty column header(s) at position(s): "
                f"{', '.join(str(i) for i in empty_headers)}",
                file=sys.stderr,
            )
            sys.exit(1)
        duplicate_headers = sorted(
            header for header, count in Counter(norm(field) for field in fields).items()
            if count > 1
        )
        if duplicate_headers:
            print(
                f"ERROR: {path} has duplicate column header(s): {', '.join(duplicate_headers)}",
                file=sys.stderr,
            )
            sys.exit(1)
        rows = []
        for idx, row in enumerate(reader, start=2):
            if None in row:
                print(f"ERROR: {path} malformed TSV row {idx} has more fields than the header", file=sys.stderr)
                sys.exit(1)
            if any(row.get(field) is None for field in fields):
                print(f"ERROR: {path} malformed TSV row {idx} has fewer fields than the header", file=sys.stderr)
                sys.exit(1)
            rows.append(row)
        return fields, rows


def require_columns(fields, table_name, required):
    fields = set(fields)
    missing = [col for col in required if col not in fields]
    if missing:
        print(
            f"ERROR: {table_name} missing required column(s): {', '.join(missing)}",
            file=sys.stderr,
        )
        sys.exit(1)


def require_unique_values(rows, table_name, column):
    seen = {}
    for idx, row in enumerate(rows, start=2):
        value = norm(row.get(column))
        if not value:
            print(
                f"ERROR: {table_name} row {idx} has empty required value for {column}",
                file=sys.stderr,
            )
            sys.exit(1)
        if value in seen:
            print(
                f"ERROR: duplicate {column} '{value}' in {table_name} "
                f"(rows {seen[value]} and {idx})",
                file=sys.stderr,
            )
            sys.exit(1)
        seen[value] = idx


def write_tsv(path, fields, rows):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    tmp = path + ".tmp"
    try:
        with open(tmp, "w", newline="") as fh:
            w = csv.DictWriter(fh, fieldnames=fields, delimiter="\t",
                               lineterminator="\n", extrasaction="ignore")
            w.writeheader()
            for row in rows:
                w.writerow(row)
        os.replace(tmp, path)
    except:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


# ── matrix builders ───────────────────────────────────────────────────────────

RE_FIELDS = [
    "node_id", "evidence_id", "biological_system", "system_id", "species_id", "data_mode",
    "evidence_status", "projection_type", "mapping_state",
    "projection_edge_id", "projection_source_node_id", "projection_mode", "projection_weight",
    "ceeg_score", "ceeg_rank", "n_supporting_species",
]

SYS_FIELDS = [
    "system_id", "re_count",
    "observed_count", "projected_direct_count", "projected_indirect_count",
    "unknown_unmappable_count",
    "data_modes",
    "evidence_count", "unknown_evidence_count", "absent_evidence_count",
    "mean_ceeg_score", "max_ceeg_score", "min_ceeg_score",
    "n_supporting_species_max",
    "component_node_ids", "evidence_ids", "component_ceeg_scores",
]

EV_FIELDS = [
    "evidence_id", "node_id", "edge_id", "evidence_type",
    "data_mode", "unknown_absent", "provenance",
    "biological_system", "system_id", "species_id",
    "evidence_status", "mapping_state",
    "ceeg_score", "n_supporting_species",
]


def system_id_for_node(node, system_ids_by_bio=None):
    """Preserve explicit system_id when present; otherwise use biological_system."""
    explicit = norm(node.get("system_id"))
    if explicit:
        return explicit
    bio = norm(node.get("biological_system"))
    if system_ids_by_bio and bio and system_ids_by_bio.get(bio):
        return system_ids_by_bio[bio]
    return bio


def build_matrices(import_dir, outdir):
    node_fields, node_rows         = read_tsv(os.path.join(import_dir, "ceeg_imported_nodes.tsv"))
    edge_fields, edge_rows         = read_tsv(os.path.join(import_dir, "ceeg_imported_edges.tsv"))
    evidence_fields, evidence_rows = read_tsv(os.path.join(import_dir, "ceeg_imported_evidence.tsv"))
    metrics_fields, metrics_rows   = read_tsv(os.path.join(import_dir, "ceeg_imported_metrics.tsv"))
    require_columns(
        node_fields,
        "ceeg_imported_nodes.tsv",
        ["node_id", "node_type", "biological_system", "data_mode", "evidence_status", "projection_type", "mapping_state"],
    )
    require_columns(
        edge_fields,
        "ceeg_imported_edges.tsv",
        ["edge_id", "source_node_id", "target_node_id", "edge_type", "projection_mode"],
    )
    require_columns(
        evidence_fields,
        "ceeg_imported_evidence.tsv",
        ["evidence_id", "node_id", "edge_id", "evidence_type", "data_mode", "unknown_absent", "provenance"],
    )
    require_columns(
        metrics_fields,
        "ceeg_imported_metrics.tsv",
        ["node_id", "biological_system", "data_mode", "ceeg_score", "ceeg_rank", "n_supporting_species"],
    )
    require_unique_values(node_rows, "ceeg_imported_nodes.tsv", "node_id")
    require_unique_values(edge_rows, "ceeg_imported_edges.tsv", "edge_id")
    require_unique_values(evidence_rows, "ceeg_imported_evidence.tsv", "evidence_id")
    require_unique_values(metrics_rows, "ceeg_imported_metrics.tsv", "node_id")

    # ── lookups ───────────────────────────────────────────────────────────────

    # metrics keyed by node_id
    metrics_by_node = {norm(r.get("node_id")): r for r in metrics_rows if norm(r.get("node_id"))}

    # projection edges keyed by target_node_id
    # a valid bundle has at most one incoming projection edge per RE
    edge_by_target = {
        norm(r.get("target_node_id")): r
        for r in edge_rows
        if lower_norm(r.get("edge_type")) == "regulatory_projection" and norm(r.get("target_node_id"))
    }

    # Guard: duplicate target_node_id in edges would silently use the last row,
    # producing wrong projection_weight/projection_mode with no warning.
    _seen: set = set()
    for _r in edge_rows:
        if lower_norm(_r.get("edge_type")) != "regulatory_projection":
            continue
        _t = norm(_r.get("target_node_id"))
        if _t:
            if _t in _seen:
                print(
                    f"ERROR: duplicate target_node_id '{_t}' in imported edges — "
                    "re-run validate_ceeg_model_bundle.py to diagnose",
                    file=sys.stderr,
                )
                sys.exit(1)
            _seen.add(_t)

    # Guard: duplicate node_id in metrics would silently use the last row,
    # producing wrong ceeg_score/rank/n_supporting_species.
    _seen = set()
    for _r in metrics_rows:
        _nid = norm(_r.get("node_id"))
        if _nid:
            if _nid in _seen:
                print(
                    f"ERROR: duplicate node_id '{_nid}' in imported metrics — "
                    "re-run validate_ceeg_model_bundle.py to diagnose",
                    file=sys.stderr,
                )
                sys.exit(1)
            _seen.add(_nid)

    # nodes split by type
    re_nodes  = [r for r in node_rows if lower_norm(r.get("node_type")) == "regulatory_element"]
    sys_nodes = [r for r in node_rows if lower_norm(r.get("node_type")) == "biological_system"]
    system_ids_by_bio = {}
    for n in sys_nodes:
        bio = norm(n.get("biological_system"))
        sid = norm(n.get("system_id"))
        if not bio or not sid:
            continue
        if bio in system_ids_by_bio and system_ids_by_bio[bio] != sid:
            print(
                f"ERROR: biological_system '{bio}' maps to multiple system_id values "
                f"('{system_ids_by_bio[bio]}' and '{sid}') — "
                "re-run validate_ceeg_model_bundle.py to diagnose",
                file=sys.stderr,
            )
            sys.exit(1)
        system_ids_by_bio[bio] = sid

    # quick RE lookup for evidence joins
    re_by_id = {norm(n.get("node_id")): n for n in re_nodes}

    # evidence_ids keyed by node_id — preserves multiple evidence IDs per node (comma-joined)
    evidence_ids_by_node: dict = defaultdict(list)
    for _r in evidence_rows:
        _nid = norm(_r.get("node_id"))
        _eid = norm(_r.get("evidence_id"))
        if _nid and _eid:
            evidence_ids_by_node[_nid].append(_eid)

    # ── 1. ceeg_regulatory_projection_features.tsv ────────────────────────────

    re_feat_rows = []
    for node in re_nodes:
        nid = norm(node.get("node_id"))
        m   = metrics_by_node.get(nid, {})
        e   = edge_by_target.get(nid, {})
        es  = norm(node.get("evidence_status"))
        if lower_norm(es) in ("projected_direct", "projected_indirect") and not e:
            print(
                f"WARNING: node '{nid}' has evidence_status='{es}' "
                "but no projection edge found — projection_edge_id/mode/weight will be empty",
                file=sys.stderr,
            )
        re_feat_rows.append({
            "node_id":              nid,
            # comma-separated when multiple evidence rows share this node_id
            "evidence_id":          ",".join(evidence_ids_by_node.get(nid, [])),
            "biological_system":    norm(node.get("biological_system")),
            "system_id":            system_id_for_node(node, system_ids_by_bio),
            # source column is "species"; fall back to "species_id" for bundle variants
            "species_id":           norm(node.get("species") or node.get("species_id") or ""),
            "data_mode":            norm(node.get("data_mode")),
            "evidence_status":      norm(node.get("evidence_status")),
            "projection_type":      norm(node.get("projection_type")),
            "mapping_state":        norm(node.get("mapping_state")),
            "projection_edge_id":   norm(e.get("edge_id", "")),
            "projection_source_node_id": norm(e.get("source_node_id", "")),
            "projection_mode":      norm(e.get("projection_mode", "")),
            "projection_weight":    norm(e.get("weight", "")),
            # ceeg_score is "" for unknown_unmappable nodes — preserve, never replace with 0
            "ceeg_score":           norm(m.get("ceeg_score", "")),
            "ceeg_rank":            norm(m.get("ceeg_rank", "")),
            "n_supporting_species": norm(m.get("n_supporting_species", "")),
        })

    # ── 2. ceeg_system_features.tsv ──────────────────────────────────────────

    re_by_system = defaultdict(list)
    for node in re_nodes:
        re_by_system[system_id_for_node(node, system_ids_by_bio)].append(node)

    ev_by_system = defaultdict(list)
    for row in evidence_rows:
        nid  = norm(row.get("node_id"))
        node = re_by_id.get(nid)
        if node:
            ev_by_system[system_id_for_node(node, system_ids_by_bio)].append(row)
        elif nid:
            print(
                f"WARNING: evidence '{norm(row.get('evidence_id'))}' references "
                f"node '{nid}' which is not a regulatory_element — "
                "excluded from system aggregates",
                file=sys.stderr,
            )

    all_system_ids = set(system_id_for_node(n, system_ids_by_bio) for n in sys_nodes)
    all_system_ids |= set(re_by_system.keys())

    sys_feat_rows = []
    for sys_id in sorted(all_system_ids):
        re_in_sys = re_by_system.get(sys_id, [])
        ev_in_sys = ev_by_system.get(sys_id, [])

        scores = []
        n_sup_vals = []
        for n in re_in_sys:
            nid = norm(n.get("node_id"))
            m   = metrics_by_node.get(nid, {})
            s   = norm(m.get("ceeg_score", ""))
            ns  = norm(m.get("n_supporting_species", ""))
            if s:
                try:
                    scores.append(float(s))
                except ValueError:
                    print(
                        f"ERROR: non-numeric ceeg_score '{s}' for node '{nid}' — "
                        "re-run validate_ceeg_model_bundle.py to diagnose",
                        file=sys.stderr,
                    )
                    sys.exit(1)
            if ns:
                try:
                    n_sup_vals.append(int(ns))
                except ValueError:
                    print(
                        f"ERROR: non-numeric n_supporting_species '{ns}' for node '{nid}' — "
                        "re-run validate_ceeg_model_bundle.py to diagnose",
                        file=sys.stderr,
                    )
                    sys.exit(1)

        data_modes = sorted({norm(n.get("data_mode")) for n in re_in_sys if norm(n.get("data_mode"))})

        sys_feat_rows.append({
            "system_id":                sys_id,
            "re_count":                 str(len(re_in_sys)),
            "observed_count":           str(sum(1 for n in re_in_sys if lower_norm(n.get("evidence_status")) == "observed")),
            "projected_direct_count":   str(sum(1 for n in re_in_sys if lower_norm(n.get("evidence_status")) == "projected_direct")),
            "projected_indirect_count": str(sum(1 for n in re_in_sys if lower_norm(n.get("evidence_status")) == "projected_indirect")),
            "unknown_unmappable_count": str(sum(1 for n in re_in_sys if lower_norm(n.get("mapping_state")) == "unknown_unmappable")),
            "data_modes":               ",".join(data_modes),
            "evidence_count":           str(len(ev_in_sys)),
            "unknown_evidence_count":   str(sum(1 for e in ev_in_sys if lower_norm(e.get("unknown_absent")) == "unknown")),
            "absent_evidence_count":    str(sum(1 for e in ev_in_sys if lower_norm(e.get("unknown_absent")) == "absent")),
            "mean_ceeg_score":          f"{sum(scores)/len(scores):.4f}" if scores else "",
            "max_ceeg_score":           f"{max(scores):.4f}" if scores else "",
            "min_ceeg_score":           f"{min(scores):.4f}" if scores else "",
            "n_supporting_species_max": str(max(n_sup_vals)) if n_sup_vals else "",
            "component_node_ids":       ",".join(norm(n.get("node_id")) for n in re_in_sys if norm(n.get("node_id"))),
            "evidence_ids":             ",".join(norm(e.get("evidence_id")) for e in ev_in_sys if norm(e.get("evidence_id"))),
            "component_ceeg_scores":    ",".join(
                norm(metrics_by_node.get(norm(n.get("node_id")), {}).get("ceeg_score", ""))
                for n in re_in_sys
            ),
        })

    # ── 3. ceeg_evidence_features.tsv ────────────────────────────────────────

    node_by_id = {norm(n.get("node_id")): n for n in node_rows}

    ev_feat_rows = []
    for ev in evidence_rows:
        nid  = norm(ev.get("node_id"))
        node = node_by_id.get(nid, {})
        if nid and not node:
            print(
                f"WARNING: evidence '{norm(ev.get('evidence_id'))}' references "
                f"node '{nid}' not found in imported nodes — "
                "node-derived fields will be empty",
                file=sys.stderr,
            )
        m    = metrics_by_node.get(nid, {})
        if lower_norm(node.get("node_type")) == "biological_system":
            print(
                f"WARNING: evidence '{norm(ev.get('evidence_id'))}' references "
                f"biological_system node '{nid}' — included in evidence features "
                "but excluded from system evidence_count aggregates",
                file=sys.stderr,
            )
        ev_feat_rows.append({
            "evidence_id":          norm(ev.get("evidence_id")),
            "node_id":              nid,
            "edge_id":              norm(ev.get("edge_id")),
            "evidence_type":        norm(ev.get("evidence_type")),
            "data_mode":            norm(ev.get("data_mode")),
            "unknown_absent":       norm(ev.get("unknown_absent")),       # verbatim
            "provenance":           norm(ev.get("provenance")),            # verbatim
            "biological_system":    norm(node.get("biological_system")),  # verbatim
            "system_id":            system_id_for_node(node, system_ids_by_bio),
            "species_id":           norm(node.get("species") or node.get("species_id") or ""),
            "evidence_status":      norm(node.get("evidence_status")),
            "mapping_state":        norm(node.get("mapping_state")),
            "ceeg_score":           norm(m.get("ceeg_score", "")),        # "" for unmappable
            "n_supporting_species": norm(m.get("n_supporting_species", "")),
        })

    write_tsv(os.path.join(outdir, "ceeg_regulatory_projection_features.tsv"),
              RE_FIELDS, re_feat_rows)
    write_tsv(os.path.join(outdir, "ceeg_system_features.tsv"),
              SYS_FIELDS, sys_feat_rows)
    write_tsv(os.path.join(outdir, "ceeg_evidence_features.tsv"),
              EV_FIELDS, ev_feat_rows)

    print(f"ceeg_regulatory_projection_features.tsv  {len(re_feat_rows)} rows")
    print(f"ceeg_system_features.tsv                 {len(sys_feat_rows)} rows")
    print(f"ceeg_evidence_features.tsv               {len(ev_feat_rows)} rows")


def parse_args():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--import-dir", required=True,
                   help="Directory containing ceeg_imported_*.tsv files")
    p.add_argument("--outdir", required=True,
                   help="Directory for output feature matrix files")
    return p.parse_args()


if __name__ == "__main__":
    args = parse_args()
    build_matrices(args.import_dir, args.outdir)
