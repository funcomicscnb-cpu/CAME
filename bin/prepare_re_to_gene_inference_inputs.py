#!/usr/bin/env python3
"""Prepare optional RE-to-gene inference metadata for CAME."""

import argparse
import csv
import os
import sys
from collections import Counter, defaultdict


MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}
ALLOWED_METHODS = {
    "stub",
    "promoter_overlap",
    "nearest_gene",
    "distance_window",
    "chromatin_contact",
    "precomputed",
}
REQUIRED_REGION_COLUMNS = ["species", "feature_id", "chrom", "start", "end"]
REQUIRED_GENE_COLUMNS = ["species", "gene_feature_id", "chrom", "start", "end"]
REQUIRED_CONTACT_COLUMNS = [
    "species",
    "region_a_chrom",
    "region_a_start",
    "region_a_end",
    "region_b_chrom",
    "region_b_start",
    "region_b_end",
    "contact_score",
]
REQUIRED_CONFIG_COLUMNS = ["inference_id", "species", "method"]
NUMERIC_CONFIG_FIELDS = [
    "max_distance",
    "promoter_upstream",
    "promoter_downstream",
    "min_contact_score",
]
MANIFEST_FIELDS = [
    "inference_id",
    "species",
    "method",
    "input_re_count",
    "input_gene_count",
    "input_contact_count",
    "max_distance",
    "promoter_upstream",
    "promoter_downstream",
    "min_contact_score",
    "regulatory_regions",
    "gene_coordinates",
    "chromatin_contacts",
    "notes",
]
ISSUE_FIELDS = ["severity", "source", "field", "row", "feature_id", "message"]


def norm(value):
    text = str(value if value is not None else "").strip()
    return "" if text.lower() in MISSING_VALUES else text


def lower_norm(value):
    return norm(value).lower()


def parse_bool(value):
    return str(value).strip().lower() in {"1", "true", "t", "yes", "y"}


def infer_delimiter(path):
    ext = os.path.splitext(path)[1].lower()
    if ext == ".tsv":
        return "\t"
    if ext == ".csv":
        return ","
    with open(path, newline="") as handle:
        sample = handle.read(min(65536, os.path.getsize(path)))
    return "\t" if sample.count("\t") > sample.count(",") else ","


def add_issue(issues, severity, source, field, row, feature_id, message):
    issues.append(
        {
            "severity": severity,
            "source": source,
            "field": field or "",
            "row": str(row or ""),
            "feature_id": feature_id or "",
            "message": message,
        }
    )


def read_table(path, label, issues, optional=False):
    path = norm(path)
    if not path:
        if not optional:
            add_issue(issues, "ERROR", label, "", "", "", "File path was not provided")
        return [], []
    if not os.path.exists(path):
        add_issue(issues, "ERROR", label, "", "", "", f"File does not exist: {path}")
        return [], []
    try:
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
    except Exception as exc:
        add_issue(issues, "ERROR", label, "", "", "", f"Could not read table: {exc}")
        return [], []
    if not fields:
        add_issue(issues, "ERROR", label, "", "", "", "Table has no header")
    if len(fields) != len(set(fields)):
        add_issue(issues, "ERROR", label, "", "", "", "Table has duplicate column names")
    return fields, rows


def require_columns(fields, required, label, issues):
    missing = []
    present = set(fields)
    for column in required:
        if column not in present:
            missing.append(column)
            add_issue(issues, "ERROR", label, column, "", "", "Missing required column")
    return missing


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


def parse_int(value):
    text = norm(value)
    if not text:
        return None
    if any(char in text for char in ".eE"):
        return None
    try:
        return int(text)
    except ValueError:
        return None


def parse_float(value):
    text = norm(value)
    if not text:
        return None
    try:
        return float(text)
    except ValueError:
        return None


def check_required_values(row, columns, label, row_number, issues, feature_id=""):
    for column in columns:
        if norm(row.get(column)) == "":
            add_issue(issues, "ERROR", label, column, row_number, feature_id, "Missing required value")


def validate_interval(issues, label, row_number, feature_id, start_value, end_value, start_field, end_field):
    start = parse_int(start_value)
    end = parse_int(end_value)
    if start is None:
        add_issue(issues, "ERROR", label, start_field, row_number, feature_id, f"{start_field} must be an integer")
    if end is None:
        add_issue(issues, "ERROR", label, end_field, row_number, feature_id, f"{end_field} must be an integer")
    if start is not None and start < 0:
        add_issue(issues, "ERROR", label, start_field, row_number, feature_id, f"{start_field} must be >= 0")
    if start is not None and end is not None and start >= end:
        add_issue(issues, "ERROR", label, f"{start_field},{end_field}", row_number, feature_id, "start must be less than end")
    return start, end


def validate_regions(rows, issues):
    valid = []
    seen = Counter()
    for row_number, row in enumerate(rows, start=2):
        feature_id = norm(row.get("feature_id"))
        check_required_values(row, REQUIRED_REGION_COLUMNS, "regulatory_regions", row_number, issues, feature_id)
        start, end = validate_interval(issues, "regulatory_regions", row_number, feature_id, row.get("start"), row.get("end"), "start", "end")
        species = norm(row.get("species"))
        if species and feature_id:
            seen[(species, feature_id)] += 1
        if all(norm(row.get(column)) for column in REQUIRED_REGION_COLUMNS) and start is not None and end is not None and start >= 0 and start < end:
            item = dict(row)
            item["start"] = str(start)
            item["end"] = str(end)
            valid.append(item)
    for (species, feature_id), count in seen.items():
        if count > 1:
            add_issue(issues, "ERROR", "regulatory_regions", "species,feature_id", "", feature_id, f"Duplicate regulatory region for species {species}: {feature_id}")
    return valid


def validate_genes(rows, issues):
    valid = []
    seen = Counter()
    for row_number, row in enumerate(rows, start=2):
        gene_id = norm(row.get("gene_feature_id"))
        check_required_values(row, REQUIRED_GENE_COLUMNS, "gene_coordinates", row_number, issues, gene_id)
        start, end = validate_interval(issues, "gene_coordinates", row_number, gene_id, row.get("start"), row.get("end"), "start", "end")
        tss = norm(row.get("tss"))
        if tss and parse_int(tss) is None:
            add_issue(issues, "ERROR", "gene_coordinates", "tss", row_number, gene_id, "tss must be an integer when supplied")
        species = norm(row.get("species"))
        if species and gene_id:
            seen[(species, gene_id)] += 1
        if all(norm(row.get(column)) for column in REQUIRED_GENE_COLUMNS) and start is not None and end is not None and start >= 0 and start < end:
            item = dict(row)
            item["start"] = str(start)
            item["end"] = str(end)
            valid.append(item)
    for (species, gene_id), count in seen.items():
        if count > 1:
            add_issue(issues, "ERROR", "gene_coordinates", "species,gene_feature_id", "", gene_id, f"Duplicate gene feature for species {species}: {gene_id}")
    return valid


def validate_contacts(rows, issues):
    valid = []
    for row_number, row in enumerate(rows, start=2):
        check_required_values(row, REQUIRED_CONTACT_COLUMNS, "chromatin_contacts", row_number, issues)
        a_start, a_end = validate_interval(
            issues,
            "chromatin_contacts",
            row_number,
            "",
            row.get("region_a_start"),
            row.get("region_a_end"),
            "region_a_start",
            "region_a_end",
        )
        b_start, b_end = validate_interval(
            issues,
            "chromatin_contacts",
            row_number,
            "",
            row.get("region_b_start"),
            row.get("region_b_end"),
            "region_b_start",
            "region_b_end",
        )
        score = parse_float(row.get("contact_score"))
        if score is None:
            add_issue(issues, "ERROR", "chromatin_contacts", "contact_score", row_number, "", "contact_score must be numeric")
        if (
            all(norm(row.get(column)) for column in REQUIRED_CONTACT_COLUMNS)
            and a_start is not None
            and a_end is not None
            and b_start is not None
            and b_end is not None
            and a_start >= 0
            and b_start >= 0
            and a_start < a_end
            and b_start < b_end
            and score is not None
        ):
            item = dict(row)
            item["region_a_start"] = str(a_start)
            item["region_a_end"] = str(a_end)
            item["region_b_start"] = str(b_start)
            item["region_b_end"] = str(b_end)
            item["contact_score"] = format(score, ".12g")
            valid.append(item)
    return valid


def rows_by_species(rows):
    grouped = defaultdict(list)
    for row in rows:
        species = norm(row.get("species"))
        if species:
            grouped[species].append(row)
    return grouped


def validate_configs(rows, regions_by_species, genes_by_species, contacts_by_species, stub_mode, contacts_path, issues):
    valid = []
    inference_ids = Counter()
    for row_number, row in enumerate(rows, start=2):
        inference_id = norm(row.get("inference_id"))
        check_required_values(row, REQUIRED_CONFIG_COLUMNS, "re_to_gene_inference_config", row_number, issues, inference_id)
        if inference_id:
            inference_ids[inference_id] += 1
        species = norm(row.get("species"))
        method = lower_norm(row.get("method"))
        if method and method not in ALLOWED_METHODS:
            add_issue(issues, "ERROR", "re_to_gene_inference_config", "method", row_number, inference_id, f"Unsupported method: {row.get('method')}")
        for field in NUMERIC_CONFIG_FIELDS:
            value = norm(row.get(field))
            if value and parse_float(value) is None:
                add_issue(issues, "ERROR", "re_to_gene_inference_config", field, row_number, inference_id, f"{field} must be numeric when supplied")
        for field in ["max_distance", "promoter_upstream", "promoter_downstream"]:
            value = norm(row.get(field))
            parsed = parse_float(value)
            if value and parsed is not None and parsed < 0:
                add_issue(issues, "ERROR", "re_to_gene_inference_config", field, row_number, inference_id, f"{field} must be >= 0")
        min_contact = norm(row.get("min_contact_score"))
        parsed_min_contact = parse_float(min_contact)
        if min_contact and parsed_min_contact is not None and parsed_min_contact < 0:
            add_issue(issues, "ERROR", "re_to_gene_inference_config", "min_contact_score", row_number, inference_id, "min_contact_score must be >= 0")
        if species and species not in regions_by_species:
            add_issue(issues, "ERROR", "re_to_gene_inference_config", "species", row_number, inference_id, f"species has no regulatory regions: {species}")
        if species and species not in genes_by_species:
            add_issue(issues, "ERROR", "re_to_gene_inference_config", "species", row_number, inference_id, f"species has no gene coordinates: {species}")
        if method == "stub" and not stub_mode:
            add_issue(issues, "ERROR", "re_to_gene_inference_config", "method", row_number, inference_id, "method=stub is not valid when --re_to_gene_inference_stub false")
        if method == "chromatin_contact":
            if not contacts_path:
                severity = "ERROR" if not stub_mode else "WARNING"
                add_issue(issues, severity, "re_to_gene_inference_config", "method", row_number, inference_id, "chromatin_contact requires --chromatin_contacts for real inference")
            elif species and species not in contacts_by_species:
                severity = "ERROR" if not stub_mode else "WARNING"
                add_issue(issues, severity, "re_to_gene_inference_config", "species", row_number, inference_id, f"species has no chromatin contacts: {species}")
        if method == "precomputed" and not stub_mode:
            add_issue(issues, "ERROR", "re_to_gene_inference_config", "method", row_number, inference_id, "precomputed real mode requires a future precomputed map input; no map asset is defined in Stage 20")
        if method in {"promoter_overlap", "nearest_gene", "distance_window", "chromatin_contact"} and not stub_mode:
            add_issue(issues, "WARNING", "re_to_gene_inference_config", "method", row_number, inference_id, f"method={method} is scaffold-only in Stage 20 real mode")
        if species and method in ALLOWED_METHODS and species in regions_by_species and species in genes_by_species:
            valid.append(row)
    for inference_id, count in inference_ids.items():
        if count > 1:
            add_issue(issues, "ERROR", "re_to_gene_inference_config", "inference_id", "", inference_id, f"Duplicate inference_id: {inference_id}")
    return valid


def build_manifest(config_rows, regions_by_species, genes_by_species, contacts_by_species, args):
    manifest = []
    for config in config_rows:
        species = norm(config.get("species"))
        manifest.append(
            {
                "inference_id": norm(config.get("inference_id")),
                "species": species,
                "method": lower_norm(config.get("method")),
                "input_re_count": str(len(regions_by_species.get(species, []))),
                "input_gene_count": str(len(genes_by_species.get(species, []))),
                "input_contact_count": str(len(contacts_by_species.get(species, []))),
                "max_distance": norm(config.get("max_distance")),
                "promoter_upstream": norm(config.get("promoter_upstream")),
                "promoter_downstream": norm(config.get("promoter_downstream")),
                "min_contact_score": norm(config.get("min_contact_score")),
                "regulatory_regions": os.path.abspath(args.regulatory_regions),
                "gene_coordinates": os.path.abspath(args.gene_coordinates),
                "chromatin_contacts": os.path.abspath(args.chromatin_contacts) if norm(args.chromatin_contacts) else "",
                "notes": norm(config.get("notes")),
            }
        )
    return manifest


def parse_args():
    parser = argparse.ArgumentParser(description="Prepare CAME RE-to-gene inference scaffold inputs.")
    parser.add_argument("--regulatory_regions", required=True)
    parser.add_argument("--gene_coordinates", required=True)
    parser.add_argument("--chromatin_contacts", default="")
    parser.add_argument("--re_to_gene_inference_config", required=True)
    parser.add_argument("--re_to_gene_inference_stub", default="true")
    parser.add_argument("--output_dir", default="results/re_to_gene_inference/input")
    return parser.parse_args()


def main():
    args = parse_args()
    issues = []
    stub_mode = parse_bool(args.re_to_gene_inference_stub)
    contacts_path = norm(args.chromatin_contacts)

    region_fields, raw_regions = read_table(args.regulatory_regions, "regulatory_regions", issues)
    gene_fields, raw_genes = read_table(args.gene_coordinates, "gene_coordinates", issues)
    contact_fields, raw_contacts = read_table(args.chromatin_contacts, "chromatin_contacts", issues, optional=True)
    config_fields, raw_configs = read_table(args.re_to_gene_inference_config, "re_to_gene_inference_config", issues)

    region_missing = require_columns(region_fields, REQUIRED_REGION_COLUMNS, "regulatory_regions", issues)
    gene_missing = require_columns(gene_fields, REQUIRED_GENE_COLUMNS, "gene_coordinates", issues)
    contact_missing = []
    if contact_fields or raw_contacts:
        contact_missing = require_columns(contact_fields, REQUIRED_CONTACT_COLUMNS, "chromatin_contacts", issues)
    config_missing = require_columns(config_fields, REQUIRED_CONFIG_COLUMNS, "re_to_gene_inference_config", issues)

    valid_regions = validate_regions(raw_regions, issues) if not region_missing else []
    valid_genes = validate_genes(raw_genes, issues) if not gene_missing else []
    valid_contacts = validate_contacts(raw_contacts, issues) if contact_fields and not contact_missing else []
    regions_by_species = rows_by_species(valid_regions)
    genes_by_species = rows_by_species(valid_genes)
    contacts_by_species = rows_by_species(valid_contacts)
    valid_configs = validate_configs(raw_configs, regions_by_species, genes_by_species, contacts_by_species, stub_mode, contacts_path, issues) if not config_missing else []

    manifest = []
    if not any(issue["severity"] == "ERROR" for issue in issues):
        manifest = build_manifest(valid_configs, regions_by_species, genes_by_species, contacts_by_species, args)
        if not manifest:
            add_issue(issues, "ERROR", "re_to_gene_inference_config", "inference_id", "", "", "No RE-to-gene inference records were prepared")

    os.makedirs(args.output_dir, exist_ok=True)
    write_tsv(os.path.join(args.output_dir, "re_to_gene_inference_manifest.tsv"), MANIFEST_FIELDS, manifest)
    write_tsv(os.path.join(args.output_dir, "re_to_gene_inference_warnings.tsv"), ISSUE_FIELDS, issues)

    counts = Counter(issue["severity"] for issue in issues)
    print(
        "CAME RE-to-gene inference input preparation summary: "
        f"ERROR={counts.get('ERROR', 0)} WARNING={counts.get('WARNING', 0)} prepared_records={len(manifest)}"
    )
    for issue in issues:
        if issue["severity"] == "ERROR":
            print(f"ERROR\t{issue['source']}\t{issue['field']}\t{issue['feature_id']}\t{issue['message']}", file=sys.stderr)
    return 1 if counts.get("ERROR", 0) else 0


if __name__ == "__main__":
    sys.exit(main())
