#!/usr/bin/env python3
"""Prepare candidate-linked gene sets for CAME functional interpretation."""

import argparse
import csv
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
CANDIDATE_SET_FIELDS = [
    "candidate_set",
    "gene_orthogroup_id",
    "source_candidate_type",
    "source_candidate_id",
    "source_rank",
    "source_total_score",
    "link_source",
    "gene_symbol",
    "selection_status",
]
BACKGROUND_FIELDS = ["gene_orthogroup_id", "gene_symbol", "background_source"]
WARNING_FIELDS = ["severity", "source", "candidate_set", "candidate_id", "gene_orthogroup_id", "message"]
OPTIONAL_ANNOTATION_FIELDS = [
    "description",
    "species",
    "source_gene_id",
    "chrom",
    "start",
    "end",
    "strand",
    "biotype",
    "external_id",
    "notes",
]


def norm(value):
    text = str(value if value is not None else "").strip()
    return "" if text.lower() in MISSING_VALUES else text


def split_values(value):
    return [norm(item) for item in str(value or "").replace(";", ",").split(",") if norm(item)]


def infer_delimiter(path):
    ext = os.path.splitext(path)[1].lower()
    if ext == ".tsv":
        return "\t"
    if ext == ".csv":
        return ","
    with open(path, newline="") as handle:
        sample = handle.read(min(65536, os.path.getsize(path)))
    return "\t" if sample.count("\t") > sample.count(",") else ","


def read_table(path, required=True):
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


def require_fields(fields, required, source):
    missing = [field for field in required if field not in fields]
    if missing:
        raise RuntimeError(f"{source} missing required column(s): {', '.join(missing)}")


def warn(warnings, severity, source, candidate_set, candidate_id, gene_id, message):
    warnings.append(
        {
            "severity": severity,
            "source": source,
            "candidate_set": candidate_set,
            "candidate_id": candidate_id,
            "gene_orthogroup_id": gene_id,
            "message": message,
        }
    )


def parse_float(value):
    text = norm(value)
    if not text:
        return None
    try:
        return float(text)
    except ValueError:
        return None


def numeric_rank(row):
    value = parse_float(row.get("rank"))
    if value is None:
        return 10**12
    return value


def numeric_score(row):
    value = parse_float(row.get("total_score"))
    if value is None:
        return float("-inf")
    return value


def selected_rows(rows, top_n, min_score):
    filtered = []
    for row in rows:
        score = numeric_score(row)
        if min_score is not None and (score == float("-inf") or score < min_score):
            continue
        filtered.append(row)
    ordered = sorted(filtered, key=lambda row: (numeric_rank(row), -numeric_score(row), row.get("candidate_id", "")))
    if top_n and top_n > 0:
        ordered = ordered[:top_n]
    return ordered


def load_annotations(path, warnings):
    fields, rows = read_table(path)
    require_fields(fields, ["gene_orthogroup_id", "gene_symbol"], "gene_annotations")
    missing_optional = [field for field in OPTIONAL_ANNOTATION_FIELDS if field not in fields]
    for field in missing_optional:
        warn(warnings, "WARNING", "gene_annotations", "", "", "", f"Missing optional annotation column: {field}")
    annotations = {}
    for row in rows:
        gene_id = norm(row.get("gene_orthogroup_id"))
        if gene_id and gene_id not in annotations:
            annotations[gene_id] = row
    return annotations


def load_gene_set_gene_ids(path):
    fields, rows = read_table(path)
    require_fields(fields, ["gene_set_id", "gene_set_name", "gene_orthogroup_id"], "gene_sets")
    return {norm(row.get("gene_orthogroup_id")) for row in rows if norm(row.get("gene_orthogroup_id"))}


def load_ranked(path, source):
    fields, rows = read_table(path)
    require_fields(fields, ["rank", "candidate_id", "candidate_type", "total_score"], source)
    return rows


def load_links(gra_re_membership, gene_regulatory_architectures):
    re_to_genes = defaultdict(set)
    gra_to_genes = defaultdict(set)
    gra_to_res = defaultdict(set)
    fields, rows = read_table(gra_re_membership, required=False)
    if fields:
        require_fields(fields, ["gra_id", "gene_orthogroup_id", "re_orthogroup_id"], "gra_re_membership")
        for row in rows:
            gra_id = norm(row.get("gra_id"))
            gene_id = norm(row.get("gene_orthogroup_id"))
            re_id = norm(row.get("re_orthogroup_id"))
            if re_id and gene_id:
                re_to_genes[re_id].add(gene_id)
            if gra_id and gene_id:
                gra_to_genes[gra_id].add(gene_id)
            if gra_id and re_id:
                gra_to_res[gra_id].add(re_id)
    fields, rows = read_table(gene_regulatory_architectures, required=False)
    if fields:
        require_fields(fields, ["gra_id", "gene_orthogroup_id"], "gene_regulatory_architectures")
        for row in rows:
            gra_id = norm(row.get("gra_id"))
            gene_id = norm(row.get("gene_orthogroup_id"))
            if gra_id and gene_id:
                gra_to_genes[gra_id].add(gene_id)
    return re_to_genes, gra_to_genes, gra_to_res


def linked_genes(row, candidate_type, re_to_genes, gra_to_genes):
    direct = split_values(row.get("linked_gene_orthogroup_id"))
    if direct:
        return direct, "ranked_table"
    candidate_id = norm(row.get("candidate_id"))
    if candidate_type == "gene":
        return [candidate_id] if candidate_id else [], "direct"
    if candidate_type == "regulatory_element":
        genes = sorted(re_to_genes.get(candidate_id, set()))
        return genes, "gra_re_membership" if genes else ""
    if candidate_type == "gra":
        genes = sorted(gra_to_genes.get(candidate_id, set()))
        return genes, "gra_tables" if genes else ""
    return [], ""


def append_rows(output_rows, warnings, candidate_set, source_type, row, genes, link_source, annotations, background):
    candidate_id = norm(row.get("candidate_id"))
    if not genes:
        warn(warnings, "WARNING", "candidate_links", candidate_set, candidate_id, "", "Selected candidate has no linked gene orthogroup")
        return
    for gene_id in genes:
        annotation = annotations.get(gene_id, {})
        status = "selected"
        if gene_id not in annotations:
            status = "missing_annotation"
            warn(warnings, "WARNING", "gene_annotations", candidate_set, candidate_id, gene_id, "Candidate gene is absent from gene_annotations")
        elif gene_id not in background:
            status = "outside_background"
            warn(warnings, "WARNING", "enrichment_background", candidate_set, candidate_id, gene_id, "Candidate gene is absent from enrichment background")
        output_rows.append(
            {
                "candidate_set": candidate_set,
                "gene_orthogroup_id": gene_id,
                "source_candidate_type": source_type,
                "source_candidate_id": candidate_id,
                "source_rank": norm(row.get("rank")),
                "source_total_score": norm(row.get("total_score")),
                "link_source": link_source,
                "gene_symbol": norm(annotation.get("gene_symbol")),
                "selection_status": status,
            }
        )


def prepare(args):
    warnings = []
    annotations = load_annotations(args.gene_annotations, warnings)
    gene_set_gene_ids = load_gene_set_gene_ids(args.gene_sets)
    background = set(annotations) & gene_set_gene_ids

    background_rows = [
        {
            "gene_orthogroup_id": gene_id,
            "gene_symbol": norm(annotations[gene_id].get("gene_symbol")),
            "background_source": "gene_annotations_and_gene_sets",
        }
        for gene_id in sorted(background)
    ]
    if not background_rows:
        warn(warnings, "WARNING", "enrichment_background", "", "", "", "Background is empty after intersecting gene_annotations with gene_sets")

    re_to_genes, gra_to_genes, _ = load_links(args.gra_re_membership, args.gene_regulatory_architectures)
    genes_ranked = selected_rows(load_ranked(args.candidate_genes, "candidate_genes"), args.top_n, args.min_score)
    res_ranked = selected_rows(load_ranked(args.candidate_res, "candidate_res"), args.top_n, args.min_score)
    gras_ranked = selected_rows(load_ranked(args.candidate_gras, "candidate_gras"), args.top_n, args.min_score)
    all_ranked = selected_rows(load_ranked(args.candidate_all, "candidate_all"), args.top_n, args.min_score)

    output_rows = []
    for row in genes_ranked:
        append_rows(output_rows, warnings, "genes", "gene", row, [norm(row.get("candidate_id"))], "direct", annotations, background)
    for row in res_ranked:
        genes, link_source = linked_genes(row, "regulatory_element", re_to_genes, gra_to_genes)
        append_rows(output_rows, warnings, "regulatory_element_linked_genes", "regulatory_element", row, genes, link_source, annotations, background)
    for row in gras_ranked:
        genes, link_source = linked_genes(row, "gra", re_to_genes, gra_to_genes)
        append_rows(output_rows, warnings, "gra_linked_genes", "gra", row, genes, link_source, annotations, background)
    for row in all_ranked:
        source_type = norm(row.get("candidate_type"))
        genes, link_source = linked_genes(row, source_type, re_to_genes, gra_to_genes)
        append_rows(output_rows, warnings, "all_candidates_linked_genes", source_type, row, genes, link_source, annotations, background)

    for candidate_set in CANDIDATE_SETS:
        if not any(row["candidate_set"] == candidate_set for row in output_rows):
            warn(warnings, "WARNING", "candidate_gene_sets", candidate_set, "", "", "Candidate gene set is empty")

    os.makedirs(args.output_dir, exist_ok=True)
    write_tsv(os.path.join(args.output_dir, "candidate_gene_sets.tsv"), CANDIDATE_SET_FIELDS, output_rows)
    write_tsv(os.path.join(args.output_dir, "enrichment_background.tsv"), BACKGROUND_FIELDS, background_rows)
    write_tsv(os.path.join(args.output_dir, "enrichment_input_warnings.tsv"), WARNING_FIELDS, warnings)
    print(
        "CAME functional interpretation input summary: "
        f"candidate_gene_rows={len(output_rows)} background_genes={len(background_rows)} warnings={len(warnings)}"
    )
    return 0


def parse_args():
    parser = argparse.ArgumentParser(description="Prepare CAME Stage 11 enrichment inputs.")
    parser.add_argument("--candidate_genes", default="results/candidates/ranked/candidate_genes_ranked.tsv")
    parser.add_argument("--candidate_res", default="results/candidates/ranked/candidate_res_ranked.tsv")
    parser.add_argument("--candidate_gras", default="results/candidates/ranked/candidate_gras_ranked.tsv")
    parser.add_argument("--candidate_all", default="results/candidates/ranked/candidate_all_ranked.tsv")
    parser.add_argument("--gene_annotations", default="assets/example_samplesheets/gene_annotations.tsv")
    parser.add_argument("--gene_sets", default="assets/example_samplesheets/gene_sets.tsv")
    parser.add_argument("--gra_re_membership", default="results/gra/tables/gra_re_membership.tsv")
    parser.add_argument("--gene_regulatory_architectures", default="results/gra/tables/gene_regulatory_architectures.tsv")
    parser.add_argument("--top_n", type=int, default=50)
    parser.add_argument("--min_score", type=float, default=None)
    parser.add_argument("--output_dir", default="results/interpretation/input")
    return parser.parse_args()


def main():
    try:
        return prepare(parse_args())
    except Exception as exc:
        print(f"ERROR\tprepare_enrichment_inputs\t{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
