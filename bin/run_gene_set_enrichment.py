#!/usr/bin/env python3
"""Run offline gene set overrepresentation tests for CAME candidates."""

import argparse
import csv
import math
import os
import sys
from collections import defaultdict


MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}
CANDIDATE_SETS = [
    "genes",
    "regulatory_element_linked_genes",
    "gra_linked_genes",
    "all_candidates_linked_genes",
]
ENRICHMENT_FIELDS = [
    "candidate_set",
    "gene_set_id",
    "gene_set_name",
    "gene_set_source",
    "n_candidate_genes",
    "n_background_genes",
    "n_overlap",
    "overlap_gene_ids",
    "odds_ratio",
    "p_value",
    "padj",
    "status",
]
WARNING_FIELDS = ["severity", "source", "candidate_set", "gene_set_id", "message"]


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
        raise RuntimeError(f"Missing required table: {path}")
    delimiter = infer_delimiter(path)
    with open(path, newline="") as handle:
        reader = csv.DictReader(handle, delimiter=delimiter)
        raw_fields = reader.fieldnames or []
        fields = [norm(field) for field in raw_fields]
        rows = []
        for row in reader:
            rows.append({field: norm(row.get(raw_field)) for raw_field, field in zip(raw_fields, fields)})
    return fields, rows


def write_tsv(path, fields, rows):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, delimiter="\t", extrasaction="ignore", quoting=csv.QUOTE_NONE, escapechar="\\", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def require_fields(fields, required, source):
    missing = [field for field in required if field not in fields]
    if missing:
        raise RuntimeError(f"{source} missing required column(s): {', '.join(missing)}")


def warn(warnings, severity, source, candidate_set, gene_set_id, message):
    warnings.append(
        {
            "severity": severity,
            "source": source,
            "candidate_set": candidate_set,
            "gene_set_id": gene_set_id,
            "message": message,
        }
    )


def fmt(value):
    if value is None:
        return "NA"
    if isinstance(value, str):
        return value
    if math.isinf(value):
        return "Inf"
    return f"{value:.12g}"


def hypergeom_sf(overlap, background_size, gene_set_size, candidate_size):
    if overlap <= 0:
        return 1.0
    upper = min(gene_set_size, candidate_size)
    denom = math.comb(background_size, candidate_size)
    if denom == 0:
        return 1.0
    total = 0.0
    for k in range(overlap, upper + 1):
        if gene_set_size >= k and background_size - gene_set_size >= candidate_size - k:
            total += math.comb(gene_set_size, k) * math.comb(background_size - gene_set_size, candidate_size - k) / denom
    return min(max(total, 0.0), 1.0)


def odds_ratio(a, b, c, d):
    denom = b * c
    num = a * d
    if denom == 0:
        return float("inf") if num > 0 else 0.0
    return num / denom


def bh_adjust(rows):
    by_set = defaultdict(list)
    for idx, row in enumerate(rows):
        try:
            p_value = float(row["p_value"])
        except ValueError:
            continue
        if row["status"] == "OK":
            by_set[row["candidate_set"]].append((idx, p_value))
    for items in by_set.values():
        ordered = sorted(items, key=lambda item: item[1], reverse=True)
        m = len(ordered)
        running = 1.0
        adjusted = {}
        for rank_from_end, (idx, p_value) in enumerate(ordered, start=1):
            rank = m - rank_from_end + 1
            running = min(running, p_value * m / rank)
            adjusted[idx] = min(max(running, 0.0), 1.0)
        for idx, value in adjusted.items():
            rows[idx]["padj"] = fmt(value)


def load_candidate_sets(path, background, warnings):
    fields, rows = read_table(path)
    require_fields(fields, ["candidate_set", "gene_orthogroup_id"], "candidate_gene_sets")
    sets = {name: set() for name in CANDIDATE_SETS}
    for row in rows:
        candidate_set = norm(row.get("candidate_set"))
        gene_id = norm(row.get("gene_orthogroup_id"))
        if candidate_set not in sets or not gene_id:
            continue
        if gene_id in background:
            sets[candidate_set].add(gene_id)
        else:
            warn(warnings, "WARNING", "candidate_gene_sets", candidate_set, "", f"Candidate gene outside background skipped: {gene_id}")
    return sets


def load_gene_sets(path, background, warnings):
    fields, rows = read_table(path)
    require_fields(fields, ["gene_set_id", "gene_set_name", "gene_orthogroup_id"], "gene_sets")
    grouped = defaultdict(lambda: {"name": "", "source": "", "genes": set()})
    for row in rows:
        gene_set_id = norm(row.get("gene_set_id"))
        gene_id = norm(row.get("gene_orthogroup_id"))
        if not gene_set_id or not gene_id:
            continue
        grouped[gene_set_id]["name"] = grouped[gene_set_id]["name"] or norm(row.get("gene_set_name"))
        grouped[gene_set_id]["source"] = grouped[gene_set_id]["source"] or norm(row.get("gene_set_source"))
        if gene_id in background:
            grouped[gene_set_id]["genes"].add(gene_id)
    valid = {}
    for gene_set_id, item in grouped.items():
        if item["genes"]:
            valid[gene_set_id] = item
        else:
            warn(warnings, "WARNING", "gene_sets", "", gene_set_id, "Gene set has no genes in background and was skipped")
    return valid


def enrich(args):
    warnings = []
    bg_fields, bg_rows = read_table(args.enrichment_background)
    require_fields(bg_fields, ["gene_orthogroup_id"], "enrichment_background")
    background = {norm(row.get("gene_orthogroup_id")) for row in bg_rows if norm(row.get("gene_orthogroup_id"))}
    candidate_sets = load_candidate_sets(args.candidate_gene_sets, background, warnings)
    gene_sets = load_gene_sets(args.gene_sets, background, warnings)

    results = []
    background_size = len(background)
    for candidate_set in CANDIDATE_SETS:
        candidate_genes = candidate_sets.get(candidate_set, set())
        if not candidate_genes:
            warn(warnings, "WARNING", "candidate_gene_sets", candidate_set, "", "Candidate set is empty after background filtering")
        for gene_set_id, gene_set in sorted(gene_sets.items()):
            genes = gene_set["genes"]
            overlap = sorted(candidate_genes & genes)
            a = len(overlap)
            b = len(candidate_genes) - a
            c = len(genes) - a
            d = background_size - a - b - c
            status = "OK"
            p_value = 1.0
            if background_size == 0:
                status = "empty_background"
            elif not candidate_genes:
                status = "empty_candidate_set"
            else:
                p_value = hypergeom_sf(a, background_size, len(genes), len(candidate_genes))
            results.append(
                {
                    "candidate_set": candidate_set,
                    "gene_set_id": gene_set_id,
                    "gene_set_name": gene_set["name"],
                    "gene_set_source": gene_set["source"],
                    "n_candidate_genes": str(len(candidate_genes)),
                    "n_background_genes": str(background_size),
                    "n_overlap": str(a),
                    "overlap_gene_ids": ",".join(overlap),
                    "odds_ratio": fmt(odds_ratio(a, b, c, d)),
                    "p_value": fmt(p_value),
                    "padj": "NA",
                    "status": status,
                }
            )
    bh_adjust(results)

    os.makedirs(args.output_dir, exist_ok=True)
    write_tsv(os.path.join(args.output_dir, "gene_set_enrichment.tsv"), ENRICHMENT_FIELDS, results)
    write_tsv(os.path.join(args.output_dir, "enrichment_warnings.tsv"), WARNING_FIELDS, warnings)
    print(f"CAME gene set enrichment summary: results={len(results)} warnings={len(warnings)}")
    return 0


def parse_args():
    parser = argparse.ArgumentParser(description="Run CAME offline gene set enrichment.")
    parser.add_argument("--candidate_gene_sets", default="results/interpretation/input/candidate_gene_sets.tsv")
    parser.add_argument("--enrichment_background", default="results/interpretation/input/enrichment_background.tsv")
    parser.add_argument("--gene_sets", default="assets/example_samplesheets/gene_sets.tsv")
    parser.add_argument("--output_dir", default="results/interpretation/enrichment")
    return parser.parse_args()


def main():
    try:
        return enrich(parse_args())
    except Exception as exc:
        print(f"ERROR\trun_gene_set_enrichment\t{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
