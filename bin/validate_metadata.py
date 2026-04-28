#!/usr/bin/env python3
"""Validate CAME Stage 1 metadata inputs."""

import argparse
import csv
import json
import os
import sys
from collections import Counter, defaultdict


KNOWN_OMICS_TYPES = {"rnaseq", "atacseq"}
PAIRED_LAYOUTS = {"paired", "paired-end", "pe"}
SINGLE_LAYOUTS = {"single", "single-end", "se"}

REQUIRED_COLUMNS = {
    "phenotype_samplesheet": [
        "sample_id",
        "species",
        "individual_id",
        "replicate_id",
        "condition",
        "timepoint",
        "assay",
        "measurement",
        "value",
        "unit",
    ],
    "omics_samplesheet": [
        "sample_id",
        "species",
        "individual_id",
        "replicate_id",
        "omics_type",
        "condition",
        "timepoint",
        "reference_id",
    ],
    "species_traits": ["species", "phylogeny_label", "trait_value"],
    "reference_manifest": ["reference_id", "species", "genome_fasta"],
    "phylogeny_manifest": ["phylogeny_id", "phylogeny_file"],
}

OPTIONAL_USEFUL = {
    "phenotype_samplesheet": ["batch"],
    "omics_samplesheet": ["batch", "read_layout"],
    "species_traits": ["trait_unit", "trait_source", "trait_confidence"],
    "reference_manifest": ["annotation_version", "source"],
    "phylogeny_manifest": ["source", "branch_length_type"],
}


def norm(value):
    return str(value or "").strip()


def lower_norm(value):
    return norm(value).lower()


def add(records, severity, source, field, row, message):
    records.append(
        {
            "severity": severity,
            "source": source,
            "field": field or "",
            "row": str(row or ""),
            "message": message,
        }
    )


def infer_delimiter(path):
    ext = os.path.splitext(path)[1].lower()
    if ext == ".tsv":
        return "\t"
    if ext == ".csv":
        return ","
    with open(path, newline="") as handle:
        sample = handle.read(min(65536, os.path.getsize(path)))
    tabs = sample.count("\t")
    commas = sample.count(",")
    return "\t" if tabs > commas else ","


def read_table(path, table_name, records):
    if not path:
        add(records, "ERROR", table_name, "", "", "File path was not provided")
        return [], []
    if not os.path.exists(path):
        add(records, "ERROR", table_name, "", "", f"File does not exist: {path}")
        return [], []
    try:
        delimiter = infer_delimiter(path)
        with open(path, newline="") as handle:
            reader = csv.DictReader(handle, delimiter=delimiter)
            fields = reader.fieldnames or []
            rows = list(reader)
    except Exception as exc:
        add(records, "ERROR", table_name, "", "", f"Could not read table: {exc}")
        return [], []
    if not fields:
        add(records, "ERROR", table_name, "", "", "Table has no header")
    return fields, rows


def check_required_columns(table_name, fields, records):
    present = set(fields)
    for column in REQUIRED_COLUMNS[table_name]:
        if column not in present:
            add(records, "ERROR", table_name, column, "", "Missing required column")
    for column in OPTIONAL_USEFUL.get(table_name, []):
        if column not in present:
            add(records, "WARNING", table_name, column, "", "Optional useful column is absent")


def check_required_values(table_name, rows, records):
    required = [c for c in REQUIRED_COLUMNS[table_name] if rows and c in rows[0]]
    for idx, row in enumerate(rows, start=2):
        for column in required:
            if norm(row.get(column)) == "":
                add(records, "ERROR", table_name, column, idx, "Missing required value")


def check_duplicates(rows, table_name, column, records):
    values = [norm(row.get(column)) for row in rows if norm(row.get(column))]
    counts = Counter(values)
    for value, count in counts.items():
        if count > 1:
            add(records, "ERROR", table_name, column, "", f"Duplicate {column}: {value}")


def check_numeric(rows, table_name, column, records):
    for idx, row in enumerate(rows, start=2):
        value = norm(row.get(column))
        if value == "":
            continue
        try:
            float(value)
        except ValueError:
            add(records, "ERROR", table_name, column, idx, f"Expected numeric value, found: {value}")


def species_set(rows):
    return {norm(row.get("species")) for row in rows if norm(row.get("species"))}


def check_species_consistency(tables, records):
    trait_species = species_set(tables["species_traits"])
    ref_species = species_set(tables["reference_manifest"])
    phy_species = species_set(tables["phylogeny_manifest"])
    for idx, row in enumerate(tables["reference_manifest"], start=2):
        species = norm(row.get("species"))
        if species and species not in trait_species:
            add(records, "ERROR", "reference_manifest", "species", idx, f"Species not found in species_traits: {species}")
    for species in sorted(trait_species - ref_species):
        add(records, "WARNING", "reference_manifest", "species", "", f"Species from species_traits has no reference_manifest row: {species}")
    for table_name in ["phenotype_samplesheet", "omics_samplesheet"]:
        for idx, row in enumerate(tables[table_name], start=2):
            species = norm(row.get("species"))
            if not species:
                continue
            if species not in trait_species:
                add(records, "ERROR", table_name, "species", idx, f"Species not found in species_traits: {species}")
            if species not in ref_species:
                add(records, "ERROR", table_name, "species", idx, f"Species not found in reference_manifest: {species}")
    for idx, row in enumerate(tables["phylogeny_manifest"], start=2):
        species = norm(row.get("species"))
        if species and species not in trait_species:
            add(records, "ERROR", "phylogeny_manifest", "species", idx, f"Species not found in species_traits: {species}")
    if phy_species:
        missing = sorted((trait_species | ref_species) - phy_species)
        if missing:
            add(records, "WARNING", "phylogeny_manifest", "species", "", "Some species lack optional phylogeny_manifest rows: " + ", ".join(missing))


def check_references(omics_rows, reference_rows, records):
    references = {norm(row.get("reference_id")) for row in reference_rows if norm(row.get("reference_id"))}
    ref_species = {
        norm(row.get("reference_id")): norm(row.get("species"))
        for row in reference_rows
        if norm(row.get("reference_id"))
    }
    for idx, row in enumerate(omics_rows, start=2):
        reference_id = norm(row.get("reference_id"))
        if reference_id and reference_id not in references:
            add(records, "ERROR", "omics_samplesheet", "reference_id", idx, f"Unknown reference_id: {reference_id}")
        elif reference_id and norm(row.get("species")) != ref_species.get(reference_id):
            add(records, "ERROR", "omics_samplesheet", "reference_id", idx, "reference_id species does not match omics sample species")


def check_omics_rows(rows, records):
    for idx, row in enumerate(rows, start=2):
        omics_type = lower_norm(row.get("omics_type"))
        if omics_type and omics_type not in KNOWN_OMICS_TYPES:
            add(records, "WARNING", "omics_samplesheet", "omics_type", idx, f"Unknown omics_type allowed for extension: {omics_type}")
        layout = lower_norm(row.get("read_layout"))
        fastq_1 = norm(row.get("fastq_1"))
        fastq_2 = norm(row.get("fastq_2"))
        if layout in PAIRED_LAYOUTS:
            if not fastq_1 or not fastq_2:
                add(records, "ERROR", "omics_samplesheet", "fastq_1/fastq_2", idx, "Paired-end sample requires fastq_1 and fastq_2")
        elif layout in SINGLE_LAYOUTS:
            if not fastq_1:
                add(records, "ERROR", "omics_samplesheet", "fastq_1", idx, "Single-end sample requires fastq_1")
        elif layout:
            add(records, "WARNING", "omics_samplesheet", "read_layout", idx, f"Unrecognized read_layout: {layout}")


def check_condition_timepoint(rows, table_name, records):
    for idx, row in enumerate(rows, start=2):
        for column in ["condition", "timepoint"]:
            if norm(row.get(column)) == "":
                add(records, "ERROR", table_name, column, idx, f"{column} must be non-empty")


def check_omics_metadata_join(omics_rows, phenotype_rows, records):
    phenotype_keys = {
        (norm(row.get("species")), norm(row.get("condition")), norm(row.get("timepoint")))
        for row in phenotype_rows
        if norm(row.get("species")) and norm(row.get("condition")) and norm(row.get("timepoint"))
    }
    for idx, row in enumerate(omics_rows, start=2):
        key = (norm(row.get("species")), norm(row.get("condition")), norm(row.get("timepoint")))
        if all(key) and key not in phenotype_keys:
            add(records, "WARNING", "omics_samplesheet", "species/condition/timepoint", idx, "No matching phenotype metadata row for omics sample")


def check_phylogeny_labels(species_traits, phylogeny_rows, records):
    labels_by_species = defaultdict(set)
    for idx, row in enumerate(species_traits, start=2):
        species = norm(row.get("species"))
        label = norm(row.get("phylogeny_label"))
        if species and label:
            labels_by_species[species].add(label)
    for species, labels in labels_by_species.items():
        if len(labels) > 1:
            add(records, "ERROR", "species_traits", "phylogeny_label", "", f"Multiple phylogeny labels for species {species}: {', '.join(sorted(labels))}")
    trait_label_by_species = {species: next(iter(labels)) for species, labels in labels_by_species.items() if len(labels) == 1}
    for idx, row in enumerate(phylogeny_rows, start=2):
        species = norm(row.get("species"))
        label = norm(row.get("phylogeny_label"))
        if species and label and trait_label_by_species.get(species) and label != trait_label_by_species[species]:
            add(records, "ERROR", "phylogeny_manifest", "phylogeny_label", idx, f"Phylogeny label for {species} differs from species_traits")


def check_study_design(path, records):
    if not path:
        add(records, "ERROR", "study_design", "", "", "File path was not provided")
        return
    if not os.path.exists(path):
        add(records, "ERROR", "study_design", "", "", f"File does not exist: {path}")
        return
    try:
        with open(path) as handle:
            lines = handle.readlines()
    except Exception as exc:
        add(records, "ERROR", "study_design", "", "", f"Could not read YAML: {exc}")
        return
    top_level = set()
    for raw in lines:
        line = raw.rstrip()
        if not line or line.lstrip().startswith("#"):
            continue
        if not raw.startswith((" ", "\t")) and ":" in line:
            top_level.add(line.split(":", 1)[0].strip())
    for section in ["study", "metadata", "contrasts"]:
        if section not in top_level:
            add(records, "ERROR", "study_design", section, "", "Missing required top-level section")


def write_report(path, records):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    fields = ["severity", "source", "field", "row", "message"]
    with open(path, "w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, delimiter="\t", quoting=csv.QUOTE_NONE, escapechar="\\", lineterminator="\n")
        writer.writeheader()
        writer.writerows(records)


def print_summary(records):
    counts = Counter(row["severity"] for row in records)
    print("CAME metadata validation summary")
    print(f"ERROR: {counts.get('ERROR', 0)}")
    print(f"WARNING: {counts.get('WARNING', 0)}")
    print(f"INFO: {counts.get('INFO', 0)}")
    for severity in ["ERROR", "WARNING"]:
        shown = 0
        for row in records:
            if row["severity"] == severity:
                loc = f"{row['source']}:{row['row']}" if row["row"] else row["source"]
                print(f"{severity}\t{loc}\t{row['field']}\t{row['message']}")
                shown += 1
                if shown == 20:
                    remaining = counts[severity] - shown
                    if remaining > 0:
                        print(f"{severity}\t...\t...\t{remaining} more")
                    break


def parse_args():
    parser = argparse.ArgumentParser(description="Validate CAME Stage 1 metadata.")
    parser.add_argument("--phenotype_samplesheet", required=True)
    parser.add_argument("--omics_samplesheet", required=True)
    parser.add_argument("--species_traits", required=True)
    parser.add_argument("--reference_manifest", required=True)
    parser.add_argument("--phylogeny_manifest", required=True)
    parser.add_argument("--study_design", required=True)
    parser.add_argument("--report", default="results/validation/metadata_validation_report.tsv")
    parser.add_argument("--json_summary", default="")
    return parser.parse_args()


def main():
    args = parse_args()
    records = []
    paths = {
        "phenotype_samplesheet": args.phenotype_samplesheet,
        "omics_samplesheet": args.omics_samplesheet,
        "species_traits": args.species_traits,
        "reference_manifest": args.reference_manifest,
        "phylogeny_manifest": args.phylogeny_manifest,
    }
    tables = {}
    for table_name, path in paths.items():
        fields, rows = read_table(path, table_name, records)
        tables[table_name] = rows
        check_required_columns(table_name, fields, records)
        check_required_values(table_name, rows, records)

    check_duplicates(tables["phenotype_samplesheet"], "phenotype_samplesheet", "sample_id", records)
    check_duplicates(tables["omics_samplesheet"], "omics_samplesheet", "sample_id", records)
    check_numeric(tables["phenotype_samplesheet"], "phenotype_samplesheet", "value", records)
    check_condition_timepoint(tables["phenotype_samplesheet"], "phenotype_samplesheet", records)
    check_condition_timepoint(tables["omics_samplesheet"], "omics_samplesheet", records)
    check_species_consistency(tables, records)
    check_references(tables["omics_samplesheet"], tables["reference_manifest"], records)
    check_omics_rows(tables["omics_samplesheet"], records)
    check_omics_metadata_join(tables["omics_samplesheet"], tables["phenotype_samplesheet"], records)
    check_phylogeny_labels(tables["species_traits"], tables["phylogeny_manifest"], records)
    check_study_design(args.study_design, records)
    add(records, "INFO", "validation", "", "", f"Validated {sum(len(v) for v in tables.values())} metadata rows")

    write_report(args.report, records)
    if args.json_summary:
        with open(args.json_summary, "w") as handle:
            json.dump(Counter(row["severity"] for row in records), handle, indent=2, sort_keys=True)
    print_summary(records)
    return 1 if any(row["severity"] == "ERROR" for row in records) else 0


if __name__ == "__main__":
    sys.exit(main())
