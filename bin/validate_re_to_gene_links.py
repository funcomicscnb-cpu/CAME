#!/usr/bin/env python3
"""Validate CAME regulatory-element-to-gene link tables."""

import argparse
import csv
import os
import sys
from collections import defaultdict


MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}
REQUIRED_FIELDS = ["species", "re_feature_id", "gene_feature_id", "link_type"]
OPTIONAL_FIELDS = [
    "re_orthogroup_id",
    "gene_orthogroup_id",
    "distance_to_tss",
    "contact_score",
    "link_confidence",
    "source",
    "notes",
]
SUPPORTED_LINK_TYPES = {"promoter", "proximal", "distal_contact", "nearest_gene", "curated"}
REPORT_FIELDS = [
    "severity",
    "record_type",
    "row",
    "field",
    "species",
    "re_feature_id",
    "gene_feature_id",
    "link_type",
    "re_orthogroup_id",
    "gene_orthogroup_id",
    "resolved_re_orthogroup_ids",
    "resolved_gene_orthogroup_ids",
    "status",
    "message",
]


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


def report(records, severity, record_type, row, field, link, status, message, re_ids=None, gene_ids=None):
    records.append(
        {
            "severity": severity,
            "record_type": record_type,
            "row": str(row or ""),
            "field": field,
            "species": link.get("species", ""),
            "re_feature_id": link.get("re_feature_id", ""),
            "gene_feature_id": link.get("gene_feature_id", ""),
            "link_type": link.get("link_type", ""),
            "re_orthogroup_id": link.get("re_orthogroup_id", ""),
            "gene_orthogroup_id": link.get("gene_orthogroup_id", ""),
            "resolved_re_orthogroup_ids": ",".join(sorted(re_ids or [])),
            "resolved_gene_orthogroup_ids": ",".join(sorted(gene_ids or [])),
            "status": status,
            "message": message,
        }
    )


def load_orthogroups(path):
    if not path:
        return set()
    if not os.path.exists(path):
        raise RuntimeError(f"Missing orthogroup count table: {path}")
    fields, rows = read_table(path)
    if "orthogroup_id" not in fields:
        raise RuntimeError(f"{path} missing required column: orthogroup_id")
    return {norm(row.get("orthogroup_id")) for row in rows if norm(row.get("orthogroup_id"))}


def load_feature_map(path):
    by_type_key = defaultdict(lambda: defaultdict(set))
    if not path:
        return by_type_key
    if not os.path.exists(path):
        raise RuntimeError(f"Missing feature_to_orthogroup_map table: {path}")
    fields, rows = read_table(path)
    missing = [field for field in ["feature_type", "species", "feature_id", "orthogroup_id"] if field not in fields]
    if missing:
        raise RuntimeError(f"{path} missing required column(s): {', '.join(missing)}")
    for row in rows:
        feature_type = norm(row.get("feature_type"))
        species = norm(row.get("species"))
        feature_id = norm(row.get("feature_id"))
        orthogroup_id = norm(row.get("orthogroup_id"))
        if feature_type and species and feature_id and orthogroup_id:
            by_type_key[feature_type][(species, feature_id)].add(orthogroup_id)
    return by_type_key


def resolve_orthogroup(link, feature_kind, known_orthogroups, feature_map):
    if feature_kind == "gene":
        supplied = norm(link.get("gene_orthogroup_id"))
        feature_id = norm(link.get("gene_feature_id"))
        map_type = "gene"
    else:
        supplied = norm(link.get("re_orthogroup_id"))
        feature_id = norm(link.get("re_feature_id"))
        map_type = "regulatory_element"
    if supplied:
        return {supplied}, supplied in known_orthogroups if known_orthogroups else True, "supplied_orthogroup_id"
    species = norm(link.get("species"))
    resolved = set(feature_map.get(map_type, {}).get((species, feature_id), set()))
    return resolved, bool(resolved), "feature_to_orthogroup_map"


def validate(args):
    fields, links = read_table(args.re_to_gene_links)
    records = []
    missing_columns = [field for field in REQUIRED_FIELDS if field not in fields]
    for field in missing_columns:
        report(records, "ERROR", "schema", "", field, {}, "missing_required_column", "Missing required column")
    if missing_columns:
        write_tsv(args.output, REPORT_FIELDS, records)
        return 1

    gene_orthogroups = load_orthogroups(args.gene_orthogroup_counts)
    re_orthogroups = load_orthogroups(args.re_orthogroup_counts)
    feature_map = load_feature_map(args.feature_to_orthogroup_map)

    seen = set()
    for idx, row in enumerate(links, start=2):
        link = {field: norm(row.get(field)) for field in REQUIRED_FIELDS + OPTIONAL_FIELDS}
        empty_required = [field for field in REQUIRED_FIELDS if not link.get(field)]
        if empty_required:
            report(
                records,
                "ERROR",
                "link",
                idx,
                ",".join(empty_required),
                link,
                "empty_required_field",
                f"Empty required value(s): {', '.join(empty_required)}",
            )
            continue

        duplicate_key = tuple(link.get(field, "") for field in REQUIRED_FIELDS + ["re_orthogroup_id", "gene_orthogroup_id"])
        if duplicate_key in seen:
            report(records, "WARNING", "link", idx, "link", link, "duplicate_link", "Duplicated RE-to-gene link retained")
        seen.add(duplicate_key)

        if link["link_type"] not in SUPPORTED_LINK_TYPES:
            report(records, "WARNING", "link", idx, "link_type", link, "unsupported_link_type", "Unsupported link_type retained")

        re_ids, re_ok, re_source = resolve_orthogroup(link, "re", re_orthogroups, feature_map)
        gene_ids, gene_ok, gene_source = resolve_orthogroup(link, "gene", gene_orthogroups, feature_map)
        messages = []
        status = "resolved"
        severity = "INFO"
        if not re_ids:
            messages.append("missing RE orthogroup resolution")
            status = "unresolved"
            severity = "WARNING"
        elif not re_ok:
            messages.append("RE orthogroup absent from Stage 7 RE orthogroup counts")
            status = "unresolved"
            severity = "WARNING"
        if not gene_ids:
            messages.append("missing gene orthogroup resolution")
            status = "unresolved"
            severity = "WARNING"
        elif not gene_ok:
            messages.append("gene orthogroup absent from Stage 7 gene orthogroup counts")
            status = "unresolved"
            severity = "WARNING"
        if len(re_ids) > 1 or len(gene_ids) > 1:
            status = "ambiguous" if status == "resolved" else status
            severity = "WARNING"
            messages.append("multiple orthogroup resolutions")
        if not messages:
            messages.append(f"resolved via RE={re_source}; gene={gene_source}")
        report(records, severity, "link", idx, "orthogroup_resolution", link, status, "; ".join(messages), re_ids, gene_ids)

    write_tsv(args.output, REPORT_FIELDS, records)
    errors = sum(1 for row in records if row["severity"] == "ERROR")
    warnings = sum(1 for row in records if row["severity"] == "WARNING")
    resolved = sum(1 for row in records if row["record_type"] == "link" and row["status"] in {"resolved", "ambiguous"})
    print(f"CAME GRA link validation summary: links={len(links)} resolved={resolved} ERROR={errors} WARNING={warnings}")
    return 1 if errors else 0


def parse_args():
    parser = argparse.ArgumentParser(description="Validate CAME RE-to-gene links for GRA construction.")
    parser.add_argument("--re_to_gene_links", required=True)
    parser.add_argument("--gene_orthogroup_counts", default="")
    parser.add_argument("--re_orthogroup_counts", default="")
    parser.add_argument("--feature_to_orthogroup_map", default="")
    parser.add_argument("--output", default="results/gra/validation/re_to_gene_link_validation_report.tsv")
    return parser.parse_args()


def main():
    try:
        return validate(parse_args())
    except Exception as exc:
        print(f"ERROR\tvalidate_re_to_gene_links\t{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
