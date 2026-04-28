#!/usr/bin/env python3
"""Validate CAME Stage 7 orthology mapping tables."""

import argparse
import csv
import os
import sys
from collections import Counter, defaultdict, deque


MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}
REQUIRED_COLUMNS = ["species", "feature_id", "orthogroup_id"]
GENE_OPTIONAL_COLUMNS = [
    "gene_symbol",
    "human_anchor_id",
    "transcript_id",
    "orthology_type",
    "orthology_confidence",
    "source",
    "notes",
]
RE_OPTIONAL_COLUMNS = [
    "chrom",
    "start",
    "end",
    "human_anchor_region",
    "re_type",
    "orthology_type",
    "orthology_confidence",
    "source",
    "notes",
]
COUNT_METADATA_FIELDS = {
    "gene": ["feature_id", "feature_type", "annotation_id"],
    "regulatory_element": ["feature_id", "feature_type", "chrom", "start", "end"],
}
OMICS_TO_FEATURE_TYPE = {"rnaseq": "gene", "atacseq": "regulatory_element"}
REPORT_FIELDS = ["severity", "source", "field", "row", "message"]


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


def report(records, severity, source, field, message, row=""):
    records.append({"severity": severity, "source": source, "field": field, "row": str(row), "message": message})


def table_source(feature_type):
    return "orthologous_genes" if feature_type == "gene" else "orthologous_res"


def load_orthology(path, feature_type, records):
    source = table_source(feature_type)
    if not path or not os.path.exists(path):
        report(records, "ERROR", source, "path", f"File does not exist: {path}")
        return [], []
    try:
        fields, rows = read_table(path)
    except Exception as exc:
        report(records, "ERROR", source, "path", f"Could not read orthology table: {exc}")
        return [], []

    for column in REQUIRED_COLUMNS:
        if column not in fields:
            report(records, "ERROR", source, column, "Missing required column")
    if any(column not in fields for column in REQUIRED_COLUMNS):
        return fields, rows

    optional_columns = GENE_OPTIONAL_COLUMNS if feature_type == "gene" else RE_OPTIONAL_COLUMNS
    present_optional = [column for column in optional_columns if column in fields]
    if not present_optional:
        report(records, "WARNING", source, "optional_metadata", "No optional orthology metadata columns were provided")

    for idx, row in enumerate(rows, start=2):
        missing = [column for column in REQUIRED_COLUMNS if not norm(row.get(column))]
        if missing:
            report(records, "ERROR", source, ",".join(missing), f"Empty required value(s): {', '.join(missing)}", idx)

    valid_rows = [
        row | {"feature_type": feature_type}
        for row in rows
        if all(norm(row.get(column)) for column in REQUIRED_COLUMNS)
    ]
    summarize_mapping_shape(valid_rows, feature_type, records)
    report(records, "INFO", source, "n_rows", f"Read {len(rows)} row(s), {len(valid_rows)} row(s) with complete required values")
    return fields, valid_rows


def summarize_mapping_shape(rows, feature_type, records):
    source = table_source(feature_type)
    by_species_feature = defaultdict(list)
    by_orthogroup = defaultdict(set)
    feature_nodes = set()
    orthogroup_nodes = set()
    graph = defaultdict(set)
    for row in rows:
        feature_key = (row["species"], row["feature_id"])
        orthogroup = row["orthogroup_id"]
        by_species_feature[feature_key].append(orthogroup)
        by_orthogroup[orthogroup].add(feature_key)
        feature_node = ("feature", feature_key)
        orthogroup_node = ("orthogroup", orthogroup)
        feature_nodes.add(feature_node)
        orthogroup_nodes.add(orthogroup_node)
        graph[feature_node].add(orthogroup_node)
        graph[orthogroup_node].add(feature_node)

    duplicate_pairs = {
        key: values
        for key, values in by_species_feature.items()
        if len(values) != len(set(values)) or len(values) > 1
    }
    for (species, feature_id), orthogroups in sorted(duplicate_pairs.items()):
        unique_orthogroups = sorted(set(orthogroups))
        if len(unique_orthogroups) > 1:
            report(
                records,
                "WARNING",
                source,
                "species,feature_id",
                f"One-to-many mapping for {species}:{feature_id} -> {', '.join(unique_orthogroups)}",
            )
        else:
            report(records, "WARNING", source, "species,feature_id", f"Duplicate mapping row for {species}:{feature_id}")

    many_to_one = {orthogroup: features for orthogroup, features in by_orthogroup.items() if len(features) > 1}
    report(records, "INFO", source, "many_to_one", f"Orthogroups with multiple source features: {len(many_to_one)}")

    many_to_many_components = 0
    visited = set()
    for node in list(feature_nodes | orthogroup_nodes):
        if node in visited:
            continue
        queue = deque([node])
        visited.add(node)
        component = []
        while queue:
            current = queue.popleft()
            component.append(current)
            for neighbor in graph[current]:
                if neighbor not in visited:
                    visited.add(neighbor)
                    queue.append(neighbor)
        n_features = sum(1 for item in component if item[0] == "feature")
        n_orthogroups = sum(1 for item in component if item[0] == "orthogroup")
        if n_features > 1 and n_orthogroups > 1:
            many_to_many_components += 1
    if many_to_many_components:
        report(records, "WARNING", source, "many_to_many", f"Detected {many_to_many_components} many-to-many connected mapping component(s)")


def sample_species_by_omics(omics_samplesheet, records):
    result = defaultdict(dict)
    if not omics_samplesheet:
        return result
    if not os.path.exists(omics_samplesheet):
        report(records, "ERROR", "omics_samplesheet", "path", f"File does not exist: {omics_samplesheet}")
        return result
    try:
        fields, rows = read_table(omics_samplesheet)
    except Exception as exc:
        report(records, "ERROR", "omics_samplesheet", "path", f"Could not read omics samplesheet: {exc}")
        return result
    missing = [column for column in ["sample_id", "species", "omics_type"] if column not in fields]
    for column in missing:
        report(records, "ERROR", "omics_samplesheet", column, "Missing required column for orthology overlap checks")
    if missing:
        return result
    for row in rows:
        sample_id = norm(row.get("sample_id"))
        species = norm(row.get("species"))
        omics_type = norm(row.get("omics_type")).lower()
        if sample_id and species and omics_type:
            result[omics_type][sample_id] = species
    return result


def count_matrix_features(path, feature_type, records, source):
    if not path:
        return [], []
    if not os.path.exists(path):
        report(records, "ERROR", source, "path", f"File does not exist: {path}")
        return [], []
    try:
        fields, rows = read_table(path)
    except Exception as exc:
        report(records, "ERROR", source, "path", f"Could not read count matrix: {exc}")
        return [], []
    required = COUNT_METADATA_FIELDS[feature_type]
    missing = [column for column in required if column not in fields]
    for column in missing:
        report(records, "ERROR", source, column, "Count matrix missing required feature column")
    if missing:
        return fields, []
    return fields, [row["feature_id"] for row in rows if norm(row.get("feature_id"))]


def overlap_count_matrix(path, feature_type, omics_type, mapping_rows, sample_species, records):
    source = f"{omics_type}_counts"
    fields, feature_ids = count_matrix_features(path, feature_type, records, source)
    if not fields or not feature_ids:
        return
    metadata = set(COUNT_METADATA_FIELDS[feature_type])
    sample_columns = [field for field in fields if field not in metadata]
    mapping_keys = {(row["species"], row["feature_id"]) for row in mapping_rows}
    samples = sample_species.get(omics_type, {})
    unknown_samples = [sample for sample in sample_columns if sample not in samples]
    if unknown_samples:
        report(records, "WARNING", source, "sample_id", f"Sample column(s) absent from omics_samplesheet: {', '.join(unknown_samples)}")

    species_values = sorted({samples[sample] for sample in sample_columns if sample in samples})
    for species in species_values:
        input_keys = {(species, feature_id) for feature_id in feature_ids}
        mapped = input_keys & mapping_keys
        report(records, "INFO", source, "feature_overlap", f"{species}: mapped {len(mapped)} of {len(input_keys)} input feature(s)")
        if not mapped and input_keys:
            report(records, "WARNING", source, "feature_overlap", f"No {feature_type} count features overlap orthology mappings for species {species}")


def overlap_differential(path, feature_type, mapping_rows, records, source):
    if not path:
        return
    if not os.path.exists(path):
        report(records, "ERROR", source, "path", f"File does not exist: {path}")
        return
    try:
        fields, rows = read_table(path)
    except Exception as exc:
        report(records, "ERROR", source, "path", f"Could not read differential table: {exc}")
        return
    missing = [column for column in ["species", "feature_id"] if column not in fields]
    for column in missing:
        report(records, "ERROR", source, column, "Differential table missing required overlap column")
    if missing:
        return
    mapping_keys = {(row["species"], row["feature_id"]) for row in mapping_rows}
    by_species = defaultdict(set)
    for row in rows:
        species = norm(row.get("species"))
        feature_id = norm(row.get("feature_id"))
        if species and feature_id:
            by_species[species].add(feature_id)
    for species, features in sorted(by_species.items()):
        mapped = {(species, feature_id) for feature_id in features} & mapping_keys
        report(records, "INFO", source, "feature_overlap", f"{species}: mapped {len(mapped)} of {len(features)} differential feature(s)")
        if not mapped and features:
            report(records, "WARNING", source, "feature_overlap", f"No {feature_type} differential features overlap orthology mappings for species {species}")


def validate(args):
    records = []
    _, gene_rows = load_orthology(args.orthologous_genes, "gene", records)
    _, re_rows = load_orthology(args.orthologous_res, "regulatory_element", records)
    sample_species = sample_species_by_omics(args.omics_samplesheet, records)
    overlap_count_matrix(args.rnaseq_counts, "gene", "rnaseq", gene_rows, sample_species, records)
    overlap_count_matrix(args.atacseq_counts, "regulatory_element", "atacseq", re_rows, sample_species, records)
    overlap_differential(args.differential_expression, "gene", gene_rows, records, "differential_expression")
    overlap_differential(args.differential_accessibility, "regulatory_element", re_rows, records, "differential_accessibility")

    counts = Counter(row["severity"] for row in records)
    write_tsv(args.output, REPORT_FIELDS, records)
    print(
        "CAME orthology validation summary: "
        f"ERROR={counts.get('ERROR', 0)} WARNING={counts.get('WARNING', 0)} INFO={counts.get('INFO', 0)}"
    )
    return 1 if counts.get("ERROR", 0) else 0


def parse_args():
    parser = argparse.ArgumentParser(description="Validate CAME Stage 7 orthology mapping tables.")
    parser.add_argument("--orthologous_genes", required=True)
    parser.add_argument("--orthologous_res", required=True)
    parser.add_argument("--omics_samplesheet", default="")
    parser.add_argument("--rnaseq_counts", default="")
    parser.add_argument("--atacseq_counts", default="")
    parser.add_argument("--differential_expression", default="")
    parser.add_argument("--differential_accessibility", default="")
    parser.add_argument("--output", default="results/orthology/validation/orthology_validation_report.tsv")
    return parser.parse_args()


def main():
    try:
        return validate(parse_args())
    except Exception as exc:
        print(f"ERROR\tvalidate_orthology_tables\t{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
