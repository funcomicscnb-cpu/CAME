#!/usr/bin/env python3
"""Summarize CAME candidate prioritization outputs."""

import argparse
import csv
import os
import sys
from collections import Counter, defaultdict


MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}
SUMMARY_FIELDS = ["metric", "value", "source"]
MANIFEST_FIELDS = ["output_name", "path", "status", "n_rows"]


def norm(value):
    text = str(value if value is not None else "").strip()
    return "" if text.lower() in MISSING_VALUES else text


def infer_delimiter(path):
    ext = os.path.splitext(path)[1].lower()
    if ext == ".tsv":
        return "\t"
    if ext == ".csv":
        return ","
    with open(path, newline="") as handle:
        sample = handle.read(min(65536, os.path.getsize(path)))
    return "\t" if sample.count("\t") > sample.count(",") else ","


def read_table(path):
    if not path or not os.path.exists(path):
        return [], []
    delimiter = infer_delimiter(path)
    with open(path, newline="") as handle:
        reader = csv.DictReader(handle, delimiter=delimiter)
        raw_fields = reader.fieldnames or []
        fields = [norm(field) for field in raw_fields]
        rows = []
        for row in reader:
            cleaned = {}
            for raw_field, field in zip(raw_fields, fields):
                cleaned[field] = norm(row.get(raw_field))
            rows.append(cleaned)
    return fields, rows


def write_tsv(path, fields, rows):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, delimiter="\t", extrasaction="ignore", quoting=csv.QUOTE_NONE, escapechar="\\", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def metric(rows, name, value, source):
    rows.append({"metric": name, "value": str(value), "source": source})


def manifest_row(name, path):
    _, rows = read_table(path)
    if path and os.path.exists(path):
        return {"output_name": name, "path": path, "status": "present", "n_rows": str(len(rows))}
    return {"output_name": name, "path": path or "", "status": "missing", "n_rows": "0"}


def summarize(args):
    _, evidence_rows = read_table(args.candidate_evidence_long)
    _, evidence_warnings = read_table(args.candidate_evidence_warnings)
    _, scored_rows = read_table(args.candidate_evidence_scored)
    _, all_ranked = read_table(args.candidate_all_ranked)
    _, genes = read_table(args.candidate_genes_ranked)
    _, res = read_table(args.candidate_res_ranked)
    _, gras = read_table(args.candidate_gras_ranked)
    _, scoring_warnings = read_table(args.candidate_scoring_warnings)

    summary = []
    by_type = Counter(norm(row.get("candidate_type")) for row in all_ranked if norm(row.get("candidate_type")))
    for candidate_type in ["gene", "regulatory_element", "gra"]:
        metric(summary, f"n_candidates_{candidate_type}", by_type.get(candidate_type, 0), args.candidate_all_ranked)
    metric(summary, "n_ranked_candidates", len(all_ranked), args.candidate_all_ranked)
    metric(summary, "n_ranked_genes", len(genes), args.candidate_genes_ranked)
    metric(summary, "n_ranked_res", len(res), args.candidate_res_ranked)
    metric(summary, "n_ranked_gras", len(gras), args.candidate_gras_ranked)

    evidence_counts = Counter(norm(row.get("evidence_type")) for row in evidence_rows if norm(row.get("evidence_type")))
    for evidence_type, count in sorted(evidence_counts.items()):
        metric(summary, f"n_evidence_rows_{evidence_type}", count, args.candidate_evidence_long)

    scored_counts = Counter(norm(row.get("evidence_type")) for row in scored_rows if norm(row.get("duplicate_status")) == "counted")
    for evidence_type, count in sorted(scored_counts.items()):
        metric(summary, f"n_scored_rows_{evidence_type}", count, args.candidate_evidence_scored)

    top_by_type = defaultdict(list)
    for row in all_ranked:
        if norm(row.get("rank")) == "1":
            top_by_type[norm(row.get("candidate_type"))].append(norm(row.get("candidate_id")))
    for candidate_type in ["gene", "regulatory_element", "gra"]:
        metric(summary, f"top_candidate_{candidate_type}", ",".join(top_by_type.get(candidate_type, [])), args.candidate_all_ranked)

    warning_sources = Counter(norm(row.get("source_table")) for row in evidence_warnings if norm(row.get("source_table")))
    for source, count in sorted(warning_sources.items()):
        metric(summary, "n_evidence_warnings", count, source)
    scoring_warning_sources = Counter(norm(row.get("source")) for row in scoring_warnings if norm(row.get("source")))
    for source, count in sorted(scoring_warning_sources.items()):
        metric(summary, "n_scoring_warnings", count, source)

    missing_layers = sorted(
        {
            norm(row.get("source_table"))
            for row in evidence_warnings
            if "Missing optional evidence layer" in norm(row.get("message"))
        }
    )
    metric(summary, "missing_evidence_layers", ",".join(missing_layers), args.candidate_evidence_warnings)

    manifest = [
        manifest_row("candidate_evidence_long", args.candidate_evidence_long),
        manifest_row("candidate_evidence_warnings", args.candidate_evidence_warnings),
        manifest_row("candidate_evidence_scored", args.candidate_evidence_scored),
        manifest_row("candidate_genes_ranked", args.candidate_genes_ranked),
        manifest_row("candidate_res_ranked", args.candidate_res_ranked),
        manifest_row("candidate_gras_ranked", args.candidate_gras_ranked),
        manifest_row("candidate_all_ranked", args.candidate_all_ranked),
        manifest_row("candidate_scoring_warnings", args.candidate_scoring_warnings),
    ]
    os.makedirs(args.output_dir, exist_ok=True)
    write_tsv(os.path.join(args.output_dir, "candidate_prioritization_summary.tsv"), SUMMARY_FIELDS, summary)
    write_tsv(os.path.join(args.output_dir, "candidate_outputs_manifest.tsv"), MANIFEST_FIELDS, manifest)
    print(f"CAME candidate prioritization summary: candidates={len(all_ranked)} evidence_rows={len(evidence_rows)}")
    return 0


def parse_args():
    parser = argparse.ArgumentParser(description="Summarize CAME Stage 10 candidate prioritization.")
    parser.add_argument("--candidate_evidence_long", default="results/candidates/evidence/candidate_evidence_long.tsv")
    parser.add_argument("--candidate_evidence_warnings", default="results/candidates/evidence/candidate_evidence_warnings.tsv")
    parser.add_argument("--candidate_evidence_scored", default="results/candidates/evidence/candidate_evidence_scored.tsv")
    parser.add_argument("--candidate_genes_ranked", default="results/candidates/ranked/candidate_genes_ranked.tsv")
    parser.add_argument("--candidate_res_ranked", default="results/candidates/ranked/candidate_res_ranked.tsv")
    parser.add_argument("--candidate_gras_ranked", default="results/candidates/ranked/candidate_gras_ranked.tsv")
    parser.add_argument("--candidate_all_ranked", default="results/candidates/ranked/candidate_all_ranked.tsv")
    parser.add_argument("--candidate_scoring_warnings", default="results/candidates/ranked/candidate_scoring_warnings.tsv")
    parser.add_argument("--output_dir", default="results/candidates/summary")
    return parser.parse_args()


def main():
    try:
        return summarize(parse_args())
    except Exception as exc:
        print(f"ERROR\tsummarize_candidate_prioritization\t{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
