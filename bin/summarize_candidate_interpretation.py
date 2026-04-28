#!/usr/bin/env python3
"""Summarize CAME functional interpretation outputs."""

import argparse
import csv
import os
import sys
from collections import Counter, defaultdict


MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}
GENE_FIELDS = [
    "rank",
    "candidate_id",
    "total_score",
    "gene_symbol",
    "description",
    "annotation_status",
    "top_enriched_gene_sets",
    "support_summary",
]
RE_FIELDS = [
    "rank",
    "candidate_id",
    "total_score",
    "linked_gene_orthogroup_id",
    "linked_gene_symbols",
    "n_exported_regions",
    "support_summary",
    "interpretation_status",
]
GRA_FIELDS = [
    "rank",
    "candidate_id",
    "total_score",
    "linked_gene_orthogroup_id",
    "linked_gene_symbols",
    "linked_re_orthogroup_id",
    "n_exported_regions",
    "support_summary",
    "interpretation_status",
]
SUMMARY_FIELDS = ["metric", "value", "source"]
MANIFEST_FIELDS = ["output_name", "path", "status", "n_rows"]


def norm(value):
    text = str(value if value is not None else "").strip()
    return "" if text.lower() in MISSING_VALUES else text


def split_values(value):
    return [norm(item) for item in str(value or "").replace(";", ",").split(",") if norm(item)]


def infer_delimiter(path):
    ext = os.path.splitext(path)[1].lower()
    if ext == ".tsv" or ext == ".bed":
        return "\t"
    if ext == ".csv":
        return ","
    with open(path, newline="") as handle:
        sample = handle.read(min(65536, os.path.getsize(path)))
    return "\t" if sample.count("\t") > sample.count(",") else ","


def read_table(path, required=False):
    if not path or not os.path.exists(path):
        if required:
            raise RuntimeError(f"Missing required table: {path}")
        return [], []
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


def metric(rows, name, value, source):
    rows.append({"metric": name, "value": str(value), "source": source})


def manifest_row(name, path):
    _, rows = read_table(path, required=False)
    if path and os.path.exists(path):
        return {"output_name": name, "path": path, "status": "present", "n_rows": str(len(rows))}
    return {"output_name": name, "path": path or "", "status": "missing", "n_rows": "0"}


def load_annotations(path):
    _, rows = read_table(path, required=True)
    return {norm(row.get("gene_orthogroup_id")): row for row in rows if norm(row.get("gene_orthogroup_id"))}


def enriched_terms(rows):
    by_set = defaultdict(list)
    for row in rows:
        if norm(row.get("status")) != "OK":
            continue
        if norm(row.get("n_overlap")) in {"", "0"}:
            continue
        by_set[norm(row.get("candidate_set"))].append(row)
    result = {}
    for candidate_set, items in by_set.items():
        ordered = sorted(
            items,
            key=lambda row: (
                float(norm(row.get("padj")) or "1") if norm(row.get("padj")) != "NA" else 1.0,
                float(norm(row.get("p_value")) or "1"),
                row.get("gene_set_id", ""),
            ),
        )
        result[candidate_set] = ";".join(
            f"{row.get('gene_set_name') or row.get('gene_set_id')}({row.get('padj')})" for row in ordered[:3]
        )
    return result


def symbols_for(gene_ids, annotations):
    symbols = []
    for gene_id in gene_ids:
        symbol = norm(annotations.get(gene_id, {}).get("gene_symbol"))
        symbols.append(symbol or gene_id)
    return ",".join(symbols)


def summarize(args):
    annotations = load_annotations(args.gene_annotations)
    _, gene_rows = read_table(args.candidate_genes_ranked, required=True)
    _, re_rows = read_table(args.candidate_res_ranked, required=True)
    _, gra_rows = read_table(args.candidate_gras_ranked, required=True)
    _, candidate_gene_sets = read_table(args.candidate_gene_sets, required=True)
    _, enrichment_rows = read_table(args.gene_set_enrichment, required=True)
    _, candidate_bed = read_table(args.candidate_res_bed, required=False)
    _, gra_bed = read_table(args.gra_linked_candidate_res_bed, required=False)
    _, input_warnings = read_table(args.enrichment_input_warnings, required=False)
    _, enrichment_warnings = read_table(args.enrichment_warnings, required=False)
    _, bed_warnings = read_table(args.regulatory_region_export_warnings, required=False)

    terms = enriched_terms(enrichment_rows)
    genes_summary = []
    for row in gene_rows:
        gene_id = norm(row.get("candidate_id"))
        annotation = annotations.get(gene_id, {})
        genes_summary.append(
            {
                "rank": norm(row.get("rank")),
                "candidate_id": gene_id,
                "total_score": norm(row.get("total_score")),
                "gene_symbol": norm(annotation.get("gene_symbol")),
                "description": norm(annotation.get("description")),
                "annotation_status": "annotated" if annotation else "missing_annotation",
                "top_enriched_gene_sets": terms.get("genes", ""),
                "support_summary": norm(row.get("support_summary")),
            }
        )

    bed_count_by_candidate = Counter(norm(row.get("candidate_id")) for row in candidate_bed)
    re_summary = []
    for row in re_rows:
        re_id = norm(row.get("candidate_id"))
        gene_ids = split_values(row.get("linked_gene_orthogroup_id"))
        re_summary.append(
            {
                "rank": norm(row.get("rank")),
                "candidate_id": re_id,
                "total_score": norm(row.get("total_score")),
                "linked_gene_orthogroup_id": ",".join(gene_ids),
                "linked_gene_symbols": symbols_for(gene_ids, annotations),
                "n_exported_regions": str(bed_count_by_candidate.get(re_id, 0)),
                "support_summary": norm(row.get("support_summary")),
                "interpretation_status": "interpreted" if gene_ids else "missing_linked_gene",
            }
        )

    gra_bed_count_by_candidate = Counter(norm(row.get("candidate_id")) for row in gra_bed)
    gra_summary = []
    for row in gra_rows:
        gra_id = norm(row.get("candidate_id"))
        gene_ids = split_values(row.get("linked_gene_orthogroup_id"))
        gra_summary.append(
            {
                "rank": norm(row.get("rank")),
                "candidate_id": gra_id,
                "total_score": norm(row.get("total_score")),
                "linked_gene_orthogroup_id": ",".join(gene_ids),
                "linked_gene_symbols": symbols_for(gene_ids, annotations),
                "linked_re_orthogroup_id": norm(row.get("linked_re_orthogroup_id")),
                "n_exported_regions": str(gra_bed_count_by_candidate.get(gra_id, 0)),
                "support_summary": norm(row.get("support_summary")),
                "interpretation_status": "interpreted" if gene_ids else "missing_linked_gene",
            }
        )

    summary = []
    metric(summary, "n_candidate_gene_interpretations", len(genes_summary), args.candidate_genes_ranked)
    metric(summary, "n_candidate_re_interpretations", len(re_summary), args.candidate_res_ranked)
    metric(summary, "n_candidate_gra_interpretations", len(gra_summary), args.candidate_gras_ranked)
    metric(summary, "n_candidate_gene_set_rows", len(candidate_gene_sets), args.candidate_gene_sets)
    metric(summary, "n_enrichment_results", len(enrichment_rows), args.gene_set_enrichment)
    metric(summary, "n_candidate_re_bed_rows", len(candidate_bed), args.candidate_res_bed)
    metric(summary, "n_gra_linked_re_bed_rows", len(gra_bed), args.gra_linked_candidate_res_bed)
    metric(summary, "n_input_warnings", len(input_warnings), args.enrichment_input_warnings)
    metric(summary, "n_enrichment_warnings", len(enrichment_warnings), args.enrichment_warnings)
    metric(summary, "n_regulatory_region_warnings", len(bed_warnings), args.regulatory_region_export_warnings)
    missing_annotations = sum(1 for row in genes_summary if row["annotation_status"] == "missing_annotation")
    metric(summary, "n_missing_gene_annotations", missing_annotations, args.gene_annotations)

    os.makedirs(args.output_dir, exist_ok=True)
    gene_summary_path = os.path.join(args.output_dir, "candidate_gene_interpretation.tsv")
    re_summary_path = os.path.join(args.output_dir, "candidate_re_interpretation.tsv")
    gra_summary_path = os.path.join(args.output_dir, "candidate_gra_interpretation.tsv")
    summary_path = os.path.join(args.output_dir, "functional_interpretation_summary.tsv")
    manifest_path = os.path.join(args.output_dir, "functional_interpretation_outputs_manifest.tsv")
    write_tsv(gene_summary_path, GENE_FIELDS, genes_summary)
    write_tsv(re_summary_path, RE_FIELDS, re_summary)
    write_tsv(gra_summary_path, GRA_FIELDS, gra_summary)
    write_tsv(summary_path, SUMMARY_FIELDS, summary)
    manifest = [
        manifest_row("candidate_gene_sets", args.candidate_gene_sets),
        manifest_row("enrichment_background", args.enrichment_background),
        manifest_row("enrichment_input_warnings", args.enrichment_input_warnings),
        manifest_row("gene_set_enrichment", args.gene_set_enrichment),
        manifest_row("enrichment_warnings", args.enrichment_warnings),
        manifest_row("candidate_res_bed", args.candidate_res_bed),
        manifest_row("gra_linked_candidate_res_bed", args.gra_linked_candidate_res_bed),
        manifest_row("regulatory_region_export_warnings", args.regulatory_region_export_warnings),
        manifest_row("candidate_gene_interpretation", gene_summary_path),
        manifest_row("candidate_re_interpretation", re_summary_path),
        manifest_row("candidate_gra_interpretation", gra_summary_path),
        manifest_row("functional_interpretation_summary", summary_path),
    ]
    write_tsv(os.path.join(args.output_dir, "functional_interpretation_outputs_manifest.tsv"), MANIFEST_FIELDS, manifest)
    print(
        "CAME functional interpretation summary: "
        f"genes={len(genes_summary)} res={len(re_summary)} gras={len(gra_summary)}"
    )
    return 0


def parse_args():
    parser = argparse.ArgumentParser(description="Summarize CAME Stage 11 functional interpretation.")
    parser.add_argument("--candidate_genes_ranked", default="results/candidates/ranked/candidate_genes_ranked.tsv")
    parser.add_argument("--candidate_res_ranked", default="results/candidates/ranked/candidate_res_ranked.tsv")
    parser.add_argument("--candidate_gras_ranked", default="results/candidates/ranked/candidate_gras_ranked.tsv")
    parser.add_argument("--gene_annotations", default="assets/example_samplesheets/gene_annotations.tsv")
    parser.add_argument("--candidate_gene_sets", default="results/interpretation/input/candidate_gene_sets.tsv")
    parser.add_argument("--enrichment_background", default="results/interpretation/input/enrichment_background.tsv")
    parser.add_argument("--enrichment_input_warnings", default="results/interpretation/input/enrichment_input_warnings.tsv")
    parser.add_argument("--gene_set_enrichment", default="results/interpretation/enrichment/gene_set_enrichment.tsv")
    parser.add_argument("--enrichment_warnings", default="results/interpretation/enrichment/enrichment_warnings.tsv")
    parser.add_argument("--candidate_res_bed", default="results/interpretation/regulatory_regions/candidate_res.bed")
    parser.add_argument("--gra_linked_candidate_res_bed", default="results/interpretation/regulatory_regions/gra_linked_candidate_res.bed")
    parser.add_argument("--regulatory_region_export_warnings", default="results/interpretation/regulatory_regions/regulatory_region_export_warnings.tsv")
    parser.add_argument("--output_dir", default="results/interpretation/summary")
    return parser.parse_args()


def main():
    try:
        return summarize(parse_args())
    except Exception as exc:
        print(f"ERROR\tsummarize_candidate_interpretation\t{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
