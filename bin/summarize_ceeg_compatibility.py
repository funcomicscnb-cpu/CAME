#!/usr/bin/env python3
"""Summarize CAME CEEG compatibility imported tables.

Usage:
  python3 bin/summarize_ceeg_compatibility.py \\
    --import-dir results/ceeg_import_test \\
    --outdir results/ceeg_import_test

Outputs:
  ceeg_compatibility_summary.tsv   -- metric/value/source table
  ceeg_compatibility_report.md     -- concise human-readable report
"""

import argparse
import csv
import os
import sys
from collections import Counter


SUMMARY_FIELDS = ["metric", "value", "source"]

IMPORTED_FILES = {
    "nodes":    "ceeg_imported_nodes.tsv",
    "edges":    "ceeg_imported_edges.tsv",
    "evidence": "ceeg_imported_evidence.tsv",
    "metrics":  "ceeg_imported_metrics.tsv",
}

# ── helpers ────────────────────────────────────────────────────────────────────

def norm(value):
    return str(value if value is not None else "").strip()


def read_table(path):
    if not path or not os.path.exists(path):
        return [], []
    with open(path, newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        raw_fields = list(reader.fieldnames or [])
        fields = [norm(f) for f in raw_fields]
        rows = []
        for row in reader:
            rows.append({norm(k): norm(v) for k, v in row.items() if k is not None})
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


def m(rows, name, value, source):
    rows.append({"metric": name, "value": str(value), "source": source})

# ── computation ────────────────────────────────────────────────────────────────

def compute_metrics(import_dir, validation_report_path):
    _, node_rows   = read_table(os.path.join(import_dir, IMPORTED_FILES["nodes"]))
    _, edge_rows   = read_table(os.path.join(import_dir, IMPORTED_FILES["edges"]))
    _, ev_rows     = read_table(os.path.join(import_dir, IMPORTED_FILES["evidence"]))
    _, metric_rows = read_table(os.path.join(import_dir, IMPORTED_FILES["metrics"]))

    # ── node-level counts ─────────────────────────────────────────────────────
    re_nodes = [r for r in node_rows if norm(r.get("node_type")).lower() == "regulatory_element"]
    bs_nodes = [r for r in node_rows if norm(r.get("node_type")).lower() == "biological_system"]

    systems = {norm(r.get("biological_system")) for r in node_rows if norm(r.get("biological_system"))}

    evidence_status_counts = Counter(
        norm(r.get("evidence_status")).lower() for r in re_nodes
    )
    mapping_state_counts = Counter(
        norm(r.get("mapping_state")).lower() for r in re_nodes
    )

    # ── edge-level counts ─────────────────────────────────────────────────────
    proj_edges = [r for r in edge_rows if norm(r.get("edge_type")).lower() == "regulatory_projection"]

    # ── evidence-level counts ─────────────────────────────────────────────────
    unknown_absent_counts = Counter(
        norm(r.get("unknown_absent")).lower() for r in ev_rows
    )
    ev_data_mode_counts = Counter(
        norm(r.get("data_mode")).lower() for r in ev_rows if norm(r.get("data_mode"))
    )

    # ── score statistics (skip empty ceeg_score for unmappable nodes) ─────────
    scores = []
    for r in metric_rows:
        s = norm(r.get("ceeg_score"))
        if s:
            try:
                scores.append(float(s))
            except ValueError:
                pass
    n_species_vals = []
    for r in metric_rows:
        ns = norm(r.get("n_supporting_species"))
        if ns:
            try:
                n_species_vals.append(int(ns))
            except ValueError:
                pass

    # ── optional validation report ────────────────────────────────────────────
    validation_error_count = None
    if validation_report_path and os.path.exists(validation_report_path):
        _, val_rows = read_table(validation_report_path)
        validation_error_count = sum(
            1 for r in val_rows if norm(r.get("severity")).upper() == "ERROR"
        )

    # ── build summary rows ────────────────────────────────────────────────────
    summary = []
    m(summary, "ceeg_node_count",               len(node_rows),      "nodes")
    m(summary, "ceeg_edge_count",               len(edge_rows),       "edges")
    m(summary, "ceeg_evidence_count",           len(ev_rows),         "evidence")
    m(summary, "ceeg_regulatory_element_count", len(re_nodes),        "nodes")
    m(summary, "ceeg_projection_edge_count",    len(proj_edges),      "edges")
    m(summary, "ceeg_system_count",             len(systems),         "nodes")
    m(summary, "ceeg_unknown_count",            unknown_absent_counts.get("unknown", 0), "evidence")
    m(summary, "ceeg_absent_count",             unknown_absent_counts.get("absent",  0), "evidence")
    m(summary, "ceeg_observed_count",           evidence_status_counts.get("observed",           0), "nodes")
    m(summary, "ceeg_projected_direct_count",   evidence_status_counts.get("projected_direct",   0), "nodes")
    m(summary, "ceeg_projected_indirect_count", evidence_status_counts.get("projected_indirect",  0), "nodes")
    m(summary, "ceeg_unknown_unmappable_count", mapping_state_counts.get("unknown_unmappable",   0), "nodes")

    # one row per observed data_mode value, plus compact aggregate
    for dm in sorted(ev_data_mode_counts):
        m(summary, f"ceeg_data_mode_{dm}", ev_data_mode_counts[dm], "evidence")
    aggregate = " ".join(f"{dm}:{ev_data_mode_counts[dm]}" for dm in sorted(ev_data_mode_counts))
    m(summary, "ceeg_data_mode_counts", aggregate or "none", "evidence")

    m(summary, "ceeg_mean_score",               f"{sum(scores)/len(scores):.4f}" if scores else "", "metrics")
    m(summary, "ceeg_max_score",                f"{max(scores):.4f}" if scores else "",             "metrics")
    m(summary, "ceeg_min_score",                f"{min(scores):.4f}" if scores else "",             "metrics")
    m(summary, "ceeg_max_n_supporting_species", max(n_species_vals) if n_species_vals else "",      "metrics")

    if validation_error_count is not None:
        m(summary, "ceeg_validation_error_count", validation_error_count, "validation_report")
    else:
        m(summary, "ceeg_validation_error_count", "N/A", "validation_report")

    # ceeg_status vocabulary: OK | ERROR | UNKNOWN | SKIPPED
    # SKIPPED is emitted by the Nextflow stub module (not this script).
    if validation_error_count is None:
        status = "UNKNOWN"
    elif validation_error_count == 0:
        status = "OK"
    else:
        status = "ERROR"
    m(summary, "ceeg_status", status, "summary")

    context = {
        "node_rows": node_rows,
        "re_nodes": re_nodes,
        "bs_nodes": bs_nodes,
        "edge_rows": edge_rows,
        "proj_edges": proj_edges,
        "ev_rows": ev_rows,
        "systems": systems,
        "evidence_status_counts": evidence_status_counts,
        "mapping_state_counts": mapping_state_counts,
        "unknown_absent_counts": unknown_absent_counts,
        "ev_data_mode_counts": ev_data_mode_counts,
        "validation_error_count": validation_error_count,
        "status": status,
        "scores": scores,
    }
    return summary, context

# ── markdown report ────────────────────────────────────────────────────────────

def _md_table(headers, rows_of_values):
    lines = []
    lines.append("| " + " | ".join(headers) + " |")
    lines.append("| " + " | ".join("---" for _ in headers) + " |")
    for row in rows_of_values:
        lines.append("| " + " | ".join(str(v) for v in row) + " |")
    return "\n".join(lines)


def build_markdown(ctx, import_dir):
    c = ctx
    lines = []

    lines.append("# CEEG Compatibility Summary")
    lines.append("")

    # ── record counts ─────────────────────────────────────────────────────────
    lines.append("## Record Counts")
    lines.append("")
    lines.append(_md_table(
        ["Metric", "Count"],
        [
            ["Total nodes",                len(c["node_rows"])],
            ["Regulatory element nodes",   len(c["re_nodes"])],
            ["Biological system nodes",    len(c["bs_nodes"])],
            ["Edges",                      len(c["edge_rows"])],
            ["Regulatory projection edges",len(c["proj_edges"])],
            ["Evidence records",           len(c["ev_rows"])],
            ["Biological systems",         len(c["systems"])],
        ],
    ))
    lines.append("")

    # ── evidence state ────────────────────────────────────────────────────────
    lines.append("## Evidence State")
    lines.append("")
    ua = c["unknown_absent_counts"]
    lines.append(_md_table(
        ["State", "Count", "Interpretation"],
        [
            ["absent",  ua.get("absent",  0), "Bundle entry exists; feature was observed or projected. Not a biological absence."],
            ["unknown", ua.get("unknown", 0), "Node is unmappable; state is not determined"],
        ],
    ))
    lines.append("")
    lines.append(
        "`unknown` and `absent` are distinct states. "
        "In CEEG, `absent` means a bundle entry is present with a determined state — "
        "it does NOT indicate biological absence of the feature. "
        "`unknown` reflects an alignment gap or technical failure; "
        "it must not be treated as `absent`."
    )
    lines.append("")

    # ── data mode ─────────────────────────────────────────────────────────────
    lines.append("## Data Mode (evidence records)")
    lines.append("")
    dm = c["ev_data_mode_counts"]
    dm_table_rows = [[mode, dm[mode]] for mode in sorted(dm)] if dm else [["—", 0]]
    lines.append(_md_table(["Data mode", "Count"], dm_table_rows))
    lines.append("")

    # ── projection evidence ───────────────────────────────────────────────────
    lines.append("## Projection Evidence (regulatory element nodes)")
    lines.append("")
    es = c["evidence_status_counts"]
    ms = c["mapping_state_counts"]
    lines.append("**Evidence status (`evidence_status` field):**")
    lines.append("")
    lines.append(_md_table(
        ["Evidence status", "Count", "Note"],
        [
            ["observed",           es.get("observed",            0), "Directly assayed in reference panel"],
            ["projected_direct",   es.get("projected_direct",    0), "Positional projection by direct alignment only"],
            ["projected_indirect", es.get("projected_indirect",  0), "Indirect projection (e.g. synteny blocks)"],
        ],
    ))
    lines.append("")
    lines.append(
        "`projected_direct` represents positional projection by sequence alignment. "
        "Functional conservation is not implied."
    )
    lines.append("")
    lines.append("**Mapping state (`mapping_state` field):**")
    lines.append("")
    lines.append(_md_table(
        ["Mapping state", "Count", "Note"],
        [
            ["mappable",           ms.get("mappable",           0), "Projection or observation succeeded"],
            ["unknown_unmappable", ms.get("unknown_unmappable", 0), "Alignment failure; projection not attempted"],
        ],
    ))
    lines.append("")

    # ── validation ────────────────────────────────────────────────────────────
    lines.append("## Validation")
    lines.append("")
    vc = c["validation_error_count"]
    if vc is None:
        lines.append(
            "Validation report not found. "
            "Run `python3 bin/validate_ceeg_model_bundle.py` before importing."
        )
    else:
        if vc == 0:
            lines.append("Validation passed: 0 errors.")
        else:
            lines.append(
                f"Validation errors: {vc}. "
                "Imported data may contain invalid entries. "
                "Re-run `python3 bin/validate_ceeg_model_bundle.py` to review errors before use."
            )
    lines.append("")
    lines.append(f"Import directory: `{import_dir}`")
    lines.append("")

    return "\n".join(lines)

# ── argument parsing ───────────────────────────────────────────────────────────

def parse_args():
    parser = argparse.ArgumentParser(
        description="Summarize CAME CEEG compatibility imported tables.",
        epilog=(
            "Example:\n"
            "  python3 bin/summarize_ceeg_compatibility.py \\\n"
            "    --import-dir results/ceeg_import_test \\\n"
            "    --outdir results/ceeg_import_test"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--import-dir", required=True, dest="import_dir",
        metavar="DIR",
        help="Directory containing ceeg_imported_*.tsv files.",
    )
    parser.add_argument(
        "--outdir", required=True,
        metavar="DIR",
        help="Directory to write summary outputs.",
    )
    parser.add_argument(
        "--validation-report", default="", dest="validation_report",
        metavar="FILE",
        help="Optional path to ceeg_bundle_validation_report.tsv (from validate_ceeg_model_bundle.py).",
    )
    return parser.parse_args()

# ── main ───────────────────────────────────────────────────────────────────────

def main():
    args = parse_args()

    for table_key, filename in IMPORTED_FILES.items():
        path = os.path.join(args.import_dir, filename)
        if not os.path.exists(path):
            print(
                f"ERROR: Required imported file not found: {path}\n"
                "Run import_ceeg_model_bundle.py first.",
                file=sys.stderr,
            )
            return 1

    summary_rows, ctx = compute_metrics(args.import_dir, args.validation_report or None)

    summary_path = os.path.join(args.outdir, "ceeg_compatibility_summary.tsv")
    report_path  = os.path.join(args.outdir, "ceeg_compatibility_report.md")

    write_tsv(summary_path, SUMMARY_FIELDS, summary_rows)

    markdown = build_markdown(ctx, args.import_dir)
    os.makedirs(args.outdir, exist_ok=True)
    with open(report_path, "w") as handle:
        handle.write(markdown)

    re_count  = ctx["re_nodes"]
    unk       = ctx["unknown_absent_counts"].get("unknown", 0)
    absent    = ctx["unknown_absent_counts"].get("absent", 0)
    print(
        f"CEEG compatibility summary: "
        f"nodes={len(ctx['node_rows'])} re_nodes={len(re_count)} "
        f"edges={len(ctx['edge_rows'])} evidence={len(ctx['ev_rows'])} "
        f"unknown={unk} absent={absent} status={ctx['status']}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
