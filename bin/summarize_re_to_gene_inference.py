#!/usr/bin/env python3
"""Summarize CAME RE-to-gene inference scaffold outputs."""

import argparse
import csv
import os
import sys
from collections import Counter, defaultdict


MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}
SUMMARY_FIELDS = ["metric", "value"]
MANIFEST_FIELDS = ["output_type", "path", "exists", "records", "mode", "status"]


def norm(value):
    text = str(value if value is not None else "").strip()
    return "" if text.lower() in MISSING_VALUES else text


def parse_bool(value):
    return str(value).strip().lower() in {"1", "true", "t", "yes", "y"}


def read_table(path):
    if not path or not os.path.exists(path):
        return []
    with open(path, newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        return [{key: norm(value) for key, value in row.items()} for row in reader]


def write_tsv(path, fields, rows):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=fields,
            delimiter="\t",
            extrasaction="ignore",
            quoting=csv.QUOTE_NONE,
            escapechar="\\",
            lineterminator="\n",
        )
        writer.writeheader()
        writer.writerows(rows)


def as_int(value):
    text = norm(value)
    if not text:
        return 0
    try:
        return int(float(text))
    except ValueError:
        return 0


def output_record(path, output_type, mode):
    rows = read_table(path)
    exists = os.path.exists(path) and os.path.getsize(path) > 0
    return {
        "output_type": output_type,
        "path": path,
        "exists": "true" if exists else "false",
        "records": str(len(rows)),
        "mode": mode,
        "status": "OK" if exists else "ERROR",
    }


def summarize(args):
    mode = "stub" if parse_bool(args.re_to_gene_inference_stub) else "real"
    prepared = read_table(args.prepared_manifest)
    links = read_table(args.re_to_gene_links)
    warnings = read_table(args.inference_warnings)

    input_res = max([as_int(row.get("input_re_count")) for row in prepared] or [0])
    input_genes = max([as_int(row.get("input_gene_count")) for row in prepared] or [0])
    input_contacts = max([as_int(row.get("input_contact_count")) for row in prepared] or [0])
    methods = sorted({norm(row.get("method")) for row in prepared if norm(row.get("method"))})
    linked_res = {norm(row.get("re_feature_id")) for row in links if norm(row.get("re_feature_id"))}

    genes_by_re = defaultdict(set)
    res_by_gene = defaultdict(set)
    for row in links:
        re_id = norm(row.get("re_feature_id"))
        gene_id = norm(row.get("gene_feature_id"))
        if re_id and gene_id:
            genes_by_re[re_id].add(gene_id)
            res_by_gene[gene_id].add(re_id)
    ambiguous_res = {re_id for re_id, genes in genes_by_re.items() if len(genes) > 1}
    genes_with_multiple_res = {gene_id for gene_id, res in res_by_gene.items() if len(res) > 1}
    unresolved_res = max(input_res - len(linked_res), 0)
    link_type_counts = Counter(norm(row.get("link_type")) for row in links if norm(row.get("link_type")))

    manifest_rows = [
        output_record(args.re_to_gene_links, "re_to_gene_links", mode),
        output_record(args.inference_warnings, "re_to_gene_inference_warnings", mode),
    ]
    errors = sum(1 for row in manifest_rows if row["status"] == "ERROR")

    summary_rows = [
        {"metric": "mode", "value": mode},
        {"metric": "configured_methods", "value": ",".join(methods)},
        {"metric": "input_res", "value": str(input_res)},
        {"metric": "input_genes", "value": str(input_genes)},
        {"metric": "input_contacts", "value": str(input_contacts)},
        {"metric": "links_produced", "value": str(len(links))},
        {"metric": "ambiguous_links", "value": str(len(ambiguous_res))},
        {"metric": "genes_linked_to_multiple_res", "value": str(len(genes_with_multiple_res))},
        {"metric": "unresolved_res", "value": str(unresolved_res)},
        {"metric": "warnings", "value": str(len(warnings))},
    ]
    for link_type in sorted(link_type_counts):
        summary_rows.append({"metric": f"links_{link_type}", "value": str(link_type_counts[link_type])})
    summary_rows.append({"metric": "status", "value": "OK" if errors == 0 else "ERROR"})

    write_tsv(os.path.join(args.output_dir, "re_to_gene_inference_summary.tsv"), SUMMARY_FIELDS, summary_rows)
    write_tsv(os.path.join(args.output_dir, "re_to_gene_inference_outputs_manifest.tsv"), MANIFEST_FIELDS, manifest_rows)
    print(
        "CAME RE-to-gene inference summary: "
        f"mode={mode} input_res={input_res} input_genes={input_genes} links={len(links)}"
    )
    return 1 if errors else 0


def parse_args():
    parser = argparse.ArgumentParser(description="Summarize CAME RE-to-gene inference outputs.")
    parser.add_argument("--prepared_manifest", required=True)
    parser.add_argument("--re_to_gene_links", required=True)
    parser.add_argument("--inference_warnings", required=True)
    parser.add_argument("--re_to_gene_inference_stub", default="true")
    parser.add_argument("--output_dir", default="results/re_to_gene_inference/summary")
    return parser.parse_args()


def main():
    try:
        return summarize(parse_args())
    except Exception as exc:
        print(f"ERROR\tsummarize_re_to_gene_inference\t{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
