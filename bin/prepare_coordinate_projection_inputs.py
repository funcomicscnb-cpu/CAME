#!/usr/bin/env python3
"""Prepare optional coordinate projection metadata for CAME."""

import argparse
import csv
import os
import sys
from collections import Counter


MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}
ALLOWED_METHODS = {"stub", "liftover_chain", "maf_projection", "precomputed_map"}
# Reserved substrings used to encode BED fragment names downstream as
# "projection_id::feature_id" with an optional "@@contig" provenance suffix.
# IDs containing them would corrupt name parsing, so they are rejected here.
RESERVED_ID_DELIMITERS = ("::", "@@")


def reserved_delimiter(value):
    return next((delim for delim in RESERVED_ID_DELIMITERS if delim in value), None)
REQUIRED_REGION_COLUMNS = ["species", "feature_id", "chrom", "start", "end"]
REQUIRED_ALIGNMENT_COLUMNS = ["source_species", "target_species", "alignment_id"]
REQUIRED_CONFIG_COLUMNS = ["projection_id", "source_species", "target_species", "method"]
ALIGNMENT_PATH_FIELDS = ["chain_file", "maf_file", "net_file"]
OUTPUT_FIELDS = [
    "projection_id",
    "source_species",
    "target_species",
    "method",
    "alignment_id",
    "alignment_type",
    "chain_file",
    "maf_file",
    "net_file",
    "min_overlap_fraction",
    "reciprocal_required",
    "source_feature_id",
    "source_chrom",
    "source_start",
    "source_end",
    "source_strand",
    "region_type",
    "region_source",
    "alignment_source",
    "config_notes",
    "region_notes",
    "alignment_notes",
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


def read_table(path, label, issues):
    if not path:
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
    present = set(fields)
    for column in required:
        if column not in present:
            add_issue(issues, "ERROR", label, column, "", "", "Missing required column")


def resolve_path(value, base_dir):
    path = norm(value)
    if not path or "://" in path or os.path.isabs(path):
        return path
    return os.path.normpath(os.path.join(base_dir, path))


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


def check_required_values(row, columns, label, row_number, issues, feature_id=""):
    for column in columns:
        if norm(row.get(column)) == "":
            add_issue(issues, "ERROR", label, column, row_number, feature_id, "Missing required value")


def parse_int(value):
    text = norm(value)
    if not text:
        return None
    try:
        if any(char in text for char in ".eE"):
            return None
        return int(text)
    except ValueError:
        return None


def validate_regions(rows, issues):
    valid = []
    seen = Counter()
    for row_number, row in enumerate(rows, start=2):
        feature_id = norm(row.get("feature_id"))
        check_required_values(row, REQUIRED_REGION_COLUMNS, "regulatory_regions", row_number, issues, feature_id)
        bad_delim = reserved_delimiter(feature_id)
        if bad_delim:
            add_issue(issues, "ERROR", "regulatory_regions", "feature_id", row_number, feature_id, f"feature_id must not contain the reserved delimiter '{bad_delim}'")
        start = parse_int(row.get("start"))
        end = parse_int(row.get("end"))
        if start is None:
            add_issue(issues, "ERROR", "regulatory_regions", "start", row_number, feature_id, "start must be an integer")
        if end is None:
            add_issue(issues, "ERROR", "regulatory_regions", "end", row_number, feature_id, "end must be an integer")
        if start is not None and start < 0:
            add_issue(issues, "ERROR", "regulatory_regions", "start", row_number, feature_id, "start must be >= 0 for zero-based half-open intervals")
        if start is not None and end is not None and start >= end:
            add_issue(issues, "ERROR", "regulatory_regions", "start,end", row_number, feature_id, "start must be less than end")
        species = norm(row.get("species"))
        if species and feature_id:
            seen[(species, feature_id)] += 1
        if all(norm(row.get(column)) for column in REQUIRED_REGION_COLUMNS) and start is not None and end is not None and start >= 0 and start < end:
            prepared = dict(row)
            prepared["start"] = str(start)
            prepared["end"] = str(end)
            valid.append(prepared)
    for (species, feature_id), count in seen.items():
        if count > 1:
            add_issue(issues, "ERROR", "regulatory_regions", "species,feature_id", "", feature_id, f"Duplicate region feature for species {species}: {feature_id}")
    return valid


def prepare_alignment_rows(rows, manifest_path):
    base_dir = os.path.dirname(os.path.abspath(manifest_path))
    prepared = []
    for row in rows:
        item = dict(row)
        for field in ALIGNMENT_PATH_FIELDS:
            item[field] = resolve_path(item.get(field), base_dir)
        prepared.append(item)
    return prepared


def alignment_index(rows, issues):
    index = {}
    counts = Counter()
    for row_number, row in enumerate(rows, start=2):
        check_required_values(row, REQUIRED_ALIGNMENT_COLUMNS, "genome_alignment_manifest", row_number, issues)
        key = (norm(row.get("source_species")), norm(row.get("target_species")))
        if all(key):
            counts[key] += 1
            index[key] = row
    for key, count in counts.items():
        if count > 1:
            add_issue(issues, "ERROR", "genome_alignment_manifest", "source_species,target_species", "", "", f"Duplicate alignment pair: {key[0]}->{key[1]}")
    return index


def validate_configs(rows, region_species, alignment_by_pair, coordinate_projection_stub, issues, lift_tool="liftover"):
    valid = []
    projection_ids = Counter()
    # When projection runs through a HAL alignment (halLiftover), per-pair chain
    # and MAF assets are not used, so do not require them; the HAL file itself is
    # validated once by the caller.
    hal_mode = lift_tool == "halliftover"
    for row_number, row in enumerate(rows, start=2):
        projection_id = norm(row.get("projection_id"))
        check_required_values(row, REQUIRED_CONFIG_COLUMNS, "coordinate_projection_config", row_number, issues)
        bad_delim = reserved_delimiter(projection_id)
        if bad_delim:
            add_issue(issues, "ERROR", "coordinate_projection_config", "projection_id", row_number, "", f"projection_id must not contain the reserved delimiter '{bad_delim}'")
        if projection_id:
            projection_ids[projection_id] += 1
        source_species = norm(row.get("source_species"))
        target_species = norm(row.get("target_species"))
        method = lower_norm(row.get("method"))
        if method and method not in ALLOWED_METHODS:
            add_issue(issues, "ERROR", "coordinate_projection_config", "method", row_number, "", f"Unsupported method: {row.get('method')}")
        if source_species and source_species not in region_species:
            add_issue(issues, "ERROR", "coordinate_projection_config", "source_species", row_number, "", f"source_species has no regulatory regions: {source_species}")
        alignment = alignment_by_pair.get((source_species, target_species))
        if source_species and target_species and alignment is None:
            add_issue(issues, "ERROR", "coordinate_projection_config", "source_species,target_species", row_number, "", f"No alignment metadata for species pair: {source_species}->{target_species}")
        if method == "stub" and not coordinate_projection_stub:
            add_issue(issues, "ERROR", "coordinate_projection_config", "method", row_number, "", "method=stub is not valid when --coordinate_projection_stub false")
        if not coordinate_projection_stub and alignment and not hal_mode:
            # The liftOver executor projects through a chain, so it requires a
            # chain_file for chain-based methods and cannot run MAF projection.
            # These checks mirror the orchestration guard so prep and execution
            # agree (no config that passes prep then fails at run time).
            if method in ("liftover_chain", "precomputed_map"):
                require_existing_asset(alignment.get("chain_file"), "chain_file", row_number, issues)
            elif method == "maf_projection":
                add_issue(issues, "ERROR", "coordinate_projection_config", "method", row_number, "", "method=maf_projection requires orthology_lift_tool=halliftover; the liftOver executor needs a chain-based method")
        if source_species and target_species and method in ALLOWED_METHODS and alignment:
            valid.append(row)
    for projection_id, count in projection_ids.items():
        if count > 1:
            add_issue(issues, "ERROR", "coordinate_projection_config", "projection_id", "", "", f"Duplicate projection_id: {projection_id}")
    return valid


def require_existing_asset(path, field, row_number, issues):
    if not norm(path):
        add_issue(issues, "ERROR", "genome_alignment_manifest", field, row_number, "", f"Real mode requires {field} for the selected projection method")
    elif not os.path.exists(path):
        add_issue(issues, "ERROR", "genome_alignment_manifest", field, row_number, "", f"Alignment asset does not exist in real mode: {path}")


def build_manifest(region_rows, config_rows, alignment_by_pair):
    manifest = []
    regions_by_species = {}
    for row in region_rows:
        regions_by_species.setdefault(norm(row.get("species")), []).append(row)
    for config in config_rows:
        source_species = norm(config.get("source_species"))
        target_species = norm(config.get("target_species"))
        alignment = alignment_by_pair[(source_species, target_species)]
        for region in regions_by_species.get(source_species, []):
            manifest.append(
                {
                    "projection_id": norm(config.get("projection_id")),
                    "source_species": source_species,
                    "target_species": target_species,
                    "method": lower_norm(config.get("method")),
                    "alignment_id": norm(alignment.get("alignment_id")),
                    "alignment_type": norm(alignment.get("alignment_type")),
                    "chain_file": norm(alignment.get("chain_file")),
                    "maf_file": norm(alignment.get("maf_file")),
                    "net_file": norm(alignment.get("net_file")),
                    "min_overlap_fraction": norm(config.get("min_overlap_fraction")),
                    "reciprocal_required": lower_norm(config.get("reciprocal_required")),
                    "source_feature_id": norm(region.get("feature_id")),
                    "source_chrom": norm(region.get("chrom")),
                    "source_start": norm(region.get("start")),
                    "source_end": norm(region.get("end")),
                    "source_strand": norm(region.get("strand")),
                    "region_type": norm(region.get("region_type")),
                    "region_source": norm(region.get("source")),
                    "alignment_source": norm(alignment.get("source")),
                    "config_notes": norm(config.get("notes")),
                    "region_notes": norm(region.get("notes")),
                    "alignment_notes": norm(alignment.get("notes")),
                }
            )
    return manifest


def parse_args():
    parser = argparse.ArgumentParser(description="Prepare CAME coordinate projection inputs.")
    parser.add_argument("--regulatory_regions", required=True)
    parser.add_argument("--genome_alignment_manifest", required=True)
    parser.add_argument("--coordinate_projection_config", required=True)
    parser.add_argument("--coordinate_projection_stub", default="true")
    parser.add_argument("--orthology_lift_tool", default="liftover")
    parser.add_argument("--orthology_hal_file", default="")
    parser.add_argument("--output_dir", default="results/coordinate_projection/input")
    return parser.parse_args()


def main():
    args = parse_args()
    issues = []
    coordinate_projection_stub = parse_bool(args.coordinate_projection_stub)

    region_fields, raw_regions = read_table(args.regulatory_regions, "regulatory_regions", issues)
    alignment_fields, raw_alignments = read_table(args.genome_alignment_manifest, "genome_alignment_manifest", issues)
    config_fields, raw_configs = read_table(args.coordinate_projection_config, "coordinate_projection_config", issues)
    require_columns(region_fields, REQUIRED_REGION_COLUMNS, "regulatory_regions", issues)
    require_columns(alignment_fields, REQUIRED_ALIGNMENT_COLUMNS, "genome_alignment_manifest", issues)
    require_columns(config_fields, REQUIRED_CONFIG_COLUMNS, "coordinate_projection_config", issues)

    lift_tool = lower_norm(args.orthology_lift_tool) or "liftover"
    valid_regions = validate_regions(raw_regions, issues)
    alignments = prepare_alignment_rows(raw_alignments, args.genome_alignment_manifest)
    alignment_by_pair = alignment_index(alignments, issues)
    region_species = {norm(row.get("species")) for row in valid_regions if norm(row.get("species"))}
    valid_configs = validate_configs(raw_configs, region_species, alignment_by_pair, coordinate_projection_stub, issues, lift_tool)

    # In HAL real mode the single HAL alignment replaces per-pair chain/MAF assets.
    if not coordinate_projection_stub and lift_tool == "halliftover":
        hal_file = norm(args.orthology_hal_file)
        if not hal_file:
            add_issue(issues, "ERROR", "coordinate_projection_config", "orthology_hal_file", "", "", "orthology_lift_tool=halliftover requires --orthology_hal_file")
        elif not os.path.exists(hal_file):
            add_issue(issues, "ERROR", "coordinate_projection_config", "orthology_hal_file", "", "", f"HAL alignment does not exist: {hal_file}")

    manifest = []
    if not any(issue["severity"] == "ERROR" for issue in issues):
        manifest = build_manifest(valid_regions, valid_configs, alignment_by_pair)
        if not manifest:
            add_issue(issues, "ERROR", "coordinate_projection_config", "projection_id", "", "", "No coordinate projection records were prepared")

    os.makedirs(args.output_dir, exist_ok=True)
    write_tsv(os.path.join(args.output_dir, "coordinate_projection_manifest.tsv"), OUTPUT_FIELDS, manifest)
    write_tsv(os.path.join(args.output_dir, "coordinate_projection_warnings.tsv"), ISSUE_FIELDS, issues)

    counts = Counter(issue["severity"] for issue in issues)
    print(
        "CAME coordinate projection input preparation summary: "
        f"ERROR={counts.get('ERROR', 0)} WARNING={counts.get('WARNING', 0)} prepared_records={len(manifest)}"
    )
    for issue in issues:
        if issue["severity"] == "ERROR":
            print(f"ERROR\t{issue['source']}\t{issue['field']}\t{issue['feature_id']}\t{issue['message']}", file=sys.stderr)
    return 1 if counts.get("ERROR", 0) else 0


if __name__ == "__main__":
    sys.exit(main())
