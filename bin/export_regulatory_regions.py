#!/usr/bin/env python3
"""Export candidate regulatory regions as GREAT-ready BED-like tables."""

import argparse
import csv
import os
import sys
from collections import defaultdict


MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}
BED_FIELDS = [
    "chrom",
    "start",
    "end",
    "name",
    "score",
    "strand",
    "candidate_type",
    "candidate_id",
    "linked_gene_orthogroup_id",
    "support_summary",
    "species",
    "source_feature_id",
]
WARNING_FIELDS = ["severity", "source", "candidate_type", "candidate_id", "re_orthogroup_id", "message"]


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


def warn(warnings, severity, source, candidate_type, candidate_id, re_id, message):
    warnings.append(
        {
            "severity": severity,
            "source": source,
            "candidate_type": candidate_type,
            "candidate_id": candidate_id,
            "re_orthogroup_id": re_id,
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


def selected_rows(rows, top_n, min_score):
    filtered = []
    for row in rows:
        score = parse_float(row.get("total_score"))
        if min_score is not None and (score is None or score < min_score):
            continue
        filtered.append(row)
    ordered = sorted(
        filtered,
        key=lambda row: (
            parse_float(row.get("rank")) if parse_float(row.get("rank")) is not None else 10**12,
            -(parse_float(row.get("total_score")) or 0.0),
            row.get("candidate_id", ""),
        ),
    )
    if top_n and top_n > 0:
        ordered = ordered[:top_n]
    return ordered


def parse_coord(row):
    chrom = norm(row.get("chrom"))
    start_text = norm(row.get("start"))
    end_text = norm(row.get("end"))
    if not chrom or not start_text or not end_text:
        return None
    try:
        start = int(float(start_text))
        end = int(float(end_text))
    except ValueError:
        return None
    if end <= start:
        return None
    return chrom, str(start), str(end)


def load_coordinates(path):
    fields, rows = read_table(path)
    require_fields(fields, ["feature_type", "species", "feature_id", "orthogroup_id", "chrom", "start", "end"], "feature_to_orthogroup_map")
    by_re = defaultdict(list)
    for row in rows:
        if norm(row.get("feature_type")) != "regulatory_element":
            continue
        re_id = norm(row.get("orthogroup_id"))
        if re_id:
            by_re[re_id].append(row)
    return by_re


def load_gra_membership(path):
    fields, rows = read_table(path, required=False)
    gra_to_res = defaultdict(set)
    re_to_genes = defaultdict(set)
    if not fields:
        return gra_to_res, re_to_genes
    require_fields(fields, ["gra_id", "gene_orthogroup_id", "re_orthogroup_id"], "gra_re_membership")
    for row in rows:
        gra_id = norm(row.get("gra_id"))
        gene_id = norm(row.get("gene_orthogroup_id"))
        re_id = norm(row.get("re_orthogroup_id"))
        if gra_id and re_id:
            gra_to_res[gra_id].add(re_id)
        if re_id and gene_id:
            re_to_genes[re_id].add(gene_id)
    return gra_to_res, re_to_genes


def load_ranked(path, source):
    fields, rows = read_table(path)
    require_fields(fields, ["rank", "candidate_id", "candidate_type", "total_score", "support_summary"], source)
    return rows


def bed_rows_for_re(candidate_row, re_id, candidate_type, linked_gene_ids, coordinate_rows, warnings):
    rows = []
    candidate_id = norm(candidate_row.get("candidate_id"))
    coords = coordinate_rows.get(re_id, [])
    if not coords:
        warn(warnings, "WARNING", "feature_to_orthogroup_map", candidate_type, candidate_id, re_id, "Missing coordinates for regulatory element")
        return rows
    for idx, coord_row in enumerate(coords, start=1):
        coord = parse_coord(coord_row)
        if not coord:
            warn(warnings, "WARNING", "feature_to_orthogroup_map", candidate_type, candidate_id, re_id, "Invalid or missing coordinate values")
            continue
        chrom, start, end = coord
        name = re_id if candidate_type == "regulatory_element" else f"{candidate_id}|{re_id}"
        if len(coords) > 1:
            name = f"{name}|{idx}"
        rows.append(
            {
                "chrom": chrom,
                "start": start,
                "end": end,
                "name": name,
                "score": norm(candidate_row.get("total_score")) or "0",
                "strand": norm(coord_row.get("strand")) or ".",
                "candidate_type": candidate_type,
                "candidate_id": candidate_id,
                "linked_gene_orthogroup_id": ",".join(sorted(linked_gene_ids)),
                "support_summary": norm(candidate_row.get("support_summary")),
                "species": norm(coord_row.get("species")),
                "source_feature_id": norm(coord_row.get("feature_id")),
            }
        )
    if not rows:
        warn(warnings, "WARNING", "feature_to_orthogroup_map", candidate_type, candidate_id, re_id, "No valid coordinate rows exported")
    return rows


def export(args):
    warnings = []
    coordinate_rows = load_coordinates(args.feature_to_orthogroup_map)
    gra_to_res, re_to_genes = load_gra_membership(args.gra_re_membership)
    res_ranked = selected_rows(load_ranked(args.candidate_res, "candidate_res"), args.top_n, args.min_score)
    gras_ranked = selected_rows(load_ranked(args.candidate_gras, "candidate_gras"), args.top_n, args.min_score)

    direct_rows = []
    for row in res_ranked:
        re_id = norm(row.get("candidate_id"))
        linked_genes = set(split_values(row.get("linked_gene_orthogroup_id"))) | re_to_genes.get(re_id, set())
        direct_rows.extend(bed_rows_for_re(row, re_id, "regulatory_element", linked_genes, coordinate_rows, warnings))

    gra_rows = []
    for row in gras_ranked:
        gra_id = norm(row.get("candidate_id"))
        linked_genes = set(split_values(row.get("linked_gene_orthogroup_id")))
        re_ids = set(split_values(row.get("linked_re_orthogroup_id"))) | gra_to_res.get(gra_id, set())
        if not re_ids:
            warn(warnings, "WARNING", "gra_re_membership", "gra", gra_id, "", "Selected GRA has no linked regulatory elements")
        for re_id in sorted(re_ids):
            genes = linked_genes | re_to_genes.get(re_id, set())
            gra_rows.extend(bed_rows_for_re(row, re_id, "gra", genes, coordinate_rows, warnings))

    os.makedirs(args.output_dir, exist_ok=True)
    write_tsv(os.path.join(args.output_dir, "candidate_res.bed"), BED_FIELDS, direct_rows)
    write_tsv(os.path.join(args.output_dir, "gra_linked_candidate_res.bed"), BED_FIELDS, gra_rows)
    write_tsv(os.path.join(args.output_dir, "regulatory_region_export_warnings.tsv"), WARNING_FIELDS, warnings)
    print(
        "CAME regulatory region export summary: "
        f"candidate_res={len(direct_rows)} gra_linked_res={len(gra_rows)} warnings={len(warnings)}"
    )
    return 0


def parse_args():
    parser = argparse.ArgumentParser(description="Export CAME Stage 11 regulatory regions.")
    parser.add_argument("--candidate_res", default="results/candidates/ranked/candidate_res_ranked.tsv")
    parser.add_argument("--candidate_gras", default="results/candidates/ranked/candidate_gras_ranked.tsv")
    parser.add_argument("--feature_to_orthogroup_map", default="results/orthology/feature_to_orthogroup_map.tsv")
    parser.add_argument("--gra_re_membership", default="results/gra/tables/gra_re_membership.tsv")
    parser.add_argument("--top_n", type=int, default=50)
    parser.add_argument("--min_score", type=float, default=None)
    parser.add_argument("--output_dir", default="results/interpretation/regulatory_regions")
    return parser.parse_args()


def main():
    try:
        return export(parse_args())
    except Exception as exc:
        print(f"ERROR\texport_regulatory_regions\t{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
