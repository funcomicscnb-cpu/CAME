#!/usr/bin/env python3
"""Validate CAME Stage 1 metadata inputs."""

import argparse
import csv
import json
import os
import sys
from collections import Counter, defaultdict
from pathlib import Path

try:
    import yaml
except ImportError:
    yaml = None

try:
    import jsonschema
except ImportError:
    jsonschema = None

sys.path.insert(0, os.path.dirname(__file__))
try:
    from phenotype_utils import normalize_species_label
except ImportError:
    def normalize_species_label(value):
        return "_".join(norm(value).split())


KNOWN_OMICS_TYPES = {"rnaseq", "atacseq"}
PAIRED_LAYOUTS = {"paired", "paired-end", "pe"}
SINGLE_LAYOUTS = {"single", "single-end", "se"}
STRICT_PROMOTIONS = {
    "METADATA_UNKNOWN_OMICS_TYPE",
    "METADATA_OMICS_PHENOTYPE_JOIN_MISSING",
    "METADATA_MISSING_BATCH_COLUMN",
    "METADATA_UNRECOGNIZED_READ_LAYOUT",
    "METADATA_SPECIES_REFERENCE_MISSING",
}

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

PHYLO_REQUIRED_COLUMNS = {
    "phenotype_samplesheet": ["sample_id", "species", "condition", "timepoint", "measurement", "value"],
    "species_traits": ["species", "phylogeny_label", "trait_value"],
    "phylogeny_manifest": ["phylogeny_id", "phylogeny_file"],
}

OPTIONAL_USEFUL = {
    "phenotype_samplesheet": ["batch"],
    "omics_samplesheet": ["batch", "read_layout"],
    "species_traits": ["trait_unit", "trait_source", "trait_confidence"],
    "reference_manifest": ["annotation_version", "source"],
    "phylogeny_manifest": ["source", "branch_length_type"],
}

SCHEMA_FILES = {
    "phenotype_samplesheet": "phenotype_samplesheet.schema.json",
    "omics_samplesheet": "omics_samplesheet.schema.json",
    "species_traits": "species_traits.schema.json",
    "reference_manifest": "reference_manifest_legacy.schema.json",
    "phylogeny_manifest": "phylogeny_manifest.schema.json",
}


def norm(value):
    return str(value or "").strip()


def lower_norm(value):
    return norm(value).lower()


def report_text(value):
    return " ".join(norm(value).split())


def add(records, severity, source, field, row, message, rule_id="", suggestion=""):
    records.append(
        {
            "severity": severity,
            "rule_id": rule_id or "",
            "source": source,
            "field": field or "",
            "row": str(row or ""),
            "message": report_text(message),
            "suggestion": report_text(suggestion),
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


def required_columns_for(table_name, mode):
    if mode == "phylo" and table_name in PHYLO_REQUIRED_COLUMNS:
        return PHYLO_REQUIRED_COLUMNS[table_name]
    return REQUIRED_COLUMNS[table_name]


def check_required_columns(table_name, fields, records, mode="full"):
    present = set(fields)
    for column in required_columns_for(table_name, mode):
        if column not in present:
            add(records, "ERROR", table_name, column, "", "Missing required column")
    if mode == "phylo":
        return
    for column in OPTIONAL_USEFUL.get(table_name, []):
        if column not in present:
            rule_id = "METADATA_MISSING_BATCH_COLUMN" if column == "batch" else ""
            add(records, "WARNING", table_name, column, "", "Optional useful column is absent", rule_id=rule_id)


def check_required_values(table_name, rows, records, mode="full"):
    required = [c for c in required_columns_for(table_name, mode) if rows and c in rows[0]]
    for idx, row in enumerate(rows, start=2):
        for column in required:
            if norm(row.get(column)) == "":
                add(records, "ERROR", table_name, column, idx, "Missing required value")


def check_duplicates(rows, table_name, column, records, rule_id="", suggestion=""):
    values = [norm(row.get(column)) for row in rows if norm(row.get(column))]
    counts = Counter(values)
    for value, count in counts.items():
        if count > 1:
            add(records, "ERROR", table_name, column, "", f"Duplicate {column}: {value}", rule_id=rule_id, suggestion=suggestion)


def check_phylogeny_id_conflicts(rows, records):
    files_by_id = defaultdict(set)
    for row in rows:
        phylogeny_id = norm(row.get("phylogeny_id"))
        phylogeny_file = norm(row.get("phylogeny_file"))
        if phylogeny_id and phylogeny_file:
            files_by_id[phylogeny_id].add(phylogeny_file)
    for phylogeny_id, files in sorted(files_by_id.items()):
        if len(files) > 1:
            add(
                records,
                "ERROR",
                "phylogeny_manifest",
                "phylogeny_id",
                "",
                f"Duplicate phylogeny_id maps to multiple files: {phylogeny_id}",
                rule_id="METADATA_DUPLICATE_PHYLOGENY_ID",
                suggestion="Use unique phylogeny_id values for different phylogeny files.",
            )


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
        add(
            records,
            "WARNING",
            "reference_manifest",
            "species",
            "",
            f"Species from species_traits has no reference_manifest row: {species}",
            rule_id="METADATA_SPECIES_REFERENCE_MISSING",
            suggestion="Add a matching reference_manifest row or remove the unused species trait row.",
        )
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


def check_phylo_mode_consistency(tables, records):
    trait_species = species_set(tables["species_traits"])
    for idx, row in enumerate(tables["phenotype_samplesheet"], start=2):
        species = norm(row.get("species"))
        if species and species not in trait_species:
            add(records, "ERROR", "phenotype_samplesheet", "species", idx, f"Species not found in species_traits: {species}")
    for idx, row in enumerate(tables["phylogeny_manifest"], start=2):
        species = norm(row.get("species"))
        if species and species not in trait_species:
            add(records, "ERROR", "phylogeny_manifest", "species", idx, f"Species not found in species_traits: {species}")


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
            add(
                records,
                "WARNING",
                "omics_samplesheet",
                "omics_type",
                idx,
                f"Unknown omics_type allowed for extension: {omics_type}",
                rule_id="METADATA_UNKNOWN_OMICS_TYPE",
                suggestion="Confirm the omics_type is intentional or correct the spelling.",
            )
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
            add(
                records,
                "WARNING",
                "omics_samplesheet",
                "read_layout",
                idx,
                f"Unrecognized read_layout: {layout}",
                rule_id="METADATA_UNRECOGNIZED_READ_LAYOUT",
                suggestion="Use paired-end, paired, pe, single-end, single, or se.",
            )


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
            add(
                records,
                "WARNING",
                "omics_samplesheet",
                "species/condition/timepoint",
                idx,
                "No matching phenotype metadata row for omics sample",
                rule_id="METADATA_OMICS_PHENOTYPE_JOIN_MISSING",
                suggestion="Add phenotype metadata for this species/condition/timepoint or correct the omics row.",
            )


def check_phylogeny_labels(species_traits, phylogeny_rows, records):
    labels_by_species = defaultdict(set)
    for row in species_traits:
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


def default_schema_dir():
    return Path(__file__).resolve().parents[1] / "assets" / "schema"


def schema_dir_path(value):
    return Path(value).resolve() if value else default_schema_dir()


def load_schema(schema_dir, filename, records, source):
    path = schema_dir / filename
    if jsonschema is None:
        add(records, "WARNING", source, "", "", "jsonschema is unavailable; schema validation was skipped", rule_id="METADATA_SCHEMA_VALIDATION_UNAVAILABLE", suggestion="Install jsonschema to enable schema validation.")
        return None
    if not path.is_file():
        add(records, "WARNING", source, "", "", f"Schema file not found: {path}", rule_id="METADATA_SCHEMA_VALIDATION_UNAVAILABLE", suggestion="Provide --schema_dir pointing to assets/schema.")
        return None
    try:
        with path.open() as handle:
            return json.load(handle)
    except Exception as exc:
        add(records, "WARNING", source, "", "", f"Could not read schema file {path}: {exc}", rule_id="METADATA_SCHEMA_VALIDATION_UNAVAILABLE", suggestion="Check that the schema file is valid JSON.")
        return None


def schema_error_field(error):
    return ".".join(str(part) for part in error.path)


def validate_schema_instance(instance, schema, records, source, row="", severity="ERROR", rule_id="METADATA_SCHEMA_VIOLATION", suggestion="Check the schema for required fields and expected types."):
    if schema is None or jsonschema is None:
        return
    validator = jsonschema.Draft202012Validator(schema)
    for error in sorted(validator.iter_errors(instance), key=lambda item: [str(p) for p in item.path]):
        add(records, severity, source, schema_error_field(error), row, error.message, rule_id=rule_id, suggestion=suggestion)


def validate_table_schemas(table_fields, tables, schema_dir, records):
    if jsonschema is None:
        add(records, "WARNING", "validation", "", "", "jsonschema is unavailable; table schema validation was skipped", rule_id="METADATA_SCHEMA_VALIDATION_UNAVAILABLE", suggestion="Install jsonschema to enable schema validation.")
        return
    if not schema_dir.is_dir():
        add(records, "WARNING", "validation", "", "", f"Schema directory not found: {schema_dir}", rule_id="METADATA_SCHEMA_VALIDATION_UNAVAILABLE", suggestion="Provide --schema_dir pointing to assets/schema.")
        return
    for table_name, rows in tables.items():
        schema = load_schema(schema_dir, SCHEMA_FILES[table_name], records, table_name)
        if not schema:
            continue
        fields = table_fields.get(table_name, [])
        for idx, row in enumerate(rows, start=2):
            instance = {field: row.get(field) for field in fields}
            validate_schema_instance(
                instance,
                schema,
                records,
                table_name,
                row=idx,
                severity="WARNING",
                rule_id="METADATA_TABLE_SCHEMA_WARNING",
                suggestion="Review this row against the metadata schema; extra columns remain allowed.",
            )


def check_study_design(path, records, schema_dir):
    if not path:
        add(records, "ERROR", "study_design", "", "", "File path was not provided")
        return
    if not os.path.exists(path):
        add(records, "ERROR", "study_design", "", "", f"File does not exist: {path}")
        return
    if yaml is None:
        add(records, "WARNING", "study_design", "", "", "PyYAML is unavailable; falling back to top-level key scan", rule_id="METADATA_STUDY_DESIGN_SCHEMA_UNAVAILABLE", suggestion="Install PyYAML to enable YAML parsing.")
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
        return
    try:
        with open(path) as handle:
            data = yaml.safe_load(handle)
    except Exception as exc:
        add(records, "ERROR", "study_design", "", "", f"Could not parse YAML: {exc}", rule_id="METADATA_STUDY_DESIGN_PARSE_ERROR", suggestion="Fix YAML syntax in study_design.yaml.")
        return
    if not isinstance(data, dict):
        add(records, "ERROR", "study_design", "", "", "Study design must be a YAML mapping", rule_id="METADATA_STUDY_DESIGN_SCHEMA_VIOLATION", suggestion="Use a mapping with study, metadata, and contrasts sections.")
        return
    if jsonschema is None or not schema_dir.is_dir():
        return
    schema = load_schema(schema_dir, "study_design.schema.json", records, "study_design")
    validate_schema_instance(
        data,
        schema,
        records,
        "study_design",
        severity="ERROR",
        rule_id="METADATA_STUDY_DESIGN_SCHEMA_VIOLATION",
        suggestion="Check study_design.schema.json for required sections and types.",
    )


def check_phenotype_duplicate_observations(rows, records):
    grouped = defaultdict(list)
    key_fields = ["species", "individual_id", "replicate_id", "condition", "timepoint", "assay", "measurement"]
    for idx, row in enumerate(rows, start=2):
        key = tuple(norm(row.get(field)) for field in key_fields)
        if any(key):
            grouped[key].append((idx, norm(row.get("value"))))
    for _, entries in grouped.items():
        if len(entries) <= 1:
            continue
        values = sorted({value for _, value in entries if value})
        row_list = ", ".join(str(idx) for idx, _ in entries)
        message = "Duplicate phenotype observation key at rows: " + row_list
        if len(values) > 1:
            message += "; conflicting values: " + ", ".join(values)
        add(records, "WARNING", "phenotype_samplesheet", ",".join(["sample_id"] + key_fields), "", message, rule_id="METADATA_DUPLICATE_PHENOTYPE_OBSERVATION", suggestion="Confirm repeated observations are intentional or make observation identifiers unique.")


def check_species_label_variants(tables, records):
    labels = defaultdict(set)
    for rows in tables.values():
        for row in rows:
            species = norm(row.get("species"))
            if species:
                labels[normalize_species_label(species).lower()].add(species)
    for normalized, variants in sorted(labels.items()):
        if len(variants) > 1:
            add(records, "WARNING", "metadata", "species", "", f"Species labels collapse to {normalized}: {', '.join(sorted(variants))}", rule_id="METADATA_SPECIES_LABEL_VARIANT", suggestion="Use one underscore-stable species label consistently across metadata files.")


def check_conflicting_trait_values(rows, records):
    grouped = defaultdict(set)
    for row in rows:
        species = norm(row.get("species"))
        external_trait = norm(row.get("external_trait"))
        covariate = norm(row.get("covariate"))
        value = norm(row.get("trait_value"))
        if not species or (not external_trait and not covariate) or not value:
            continue
        grouped[(species, external_trait, covariate)].add(value)
    for (species, external_trait, covariate), values in sorted(grouped.items()):
        if len(values) > 1:
            key = "/".join(part for part in [species, external_trait, covariate] if part)
            add(records, "WARNING", "species_traits", "trait_value", "", f"Conflicting trait values for {key}: {', '.join(sorted(values))}", rule_id="METADATA_CONFLICTING_TRAIT_VALUE", suggestion="Split repeated traits with clearer covariate names or reconcile conflicting values.")


def promote_warnings(records, strict, rule_ids):
    if not strict:
        return
    for row in records:
        if row.get("rule_id") in rule_ids and row.get("severity") == "WARNING":
            row["severity"] = "ERROR"


def write_report(path, records):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    fields = ["severity", "rule_id", "source", "field", "row", "message", "suggestion"]
    with open(path, "w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, delimiter="\t", extrasaction="ignore", quoting=csv.QUOTE_NONE, escapechar="\\", lineterminator="\n")
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


def severity_summary(records):
    counts = Counter(row["severity"] for row in records)
    return {severity: counts.get(severity, 0) for severity in ["ERROR", "WARNING", "INFO"]}


def parse_args():
    parser = argparse.ArgumentParser(description="Validate CAME Stage 1 metadata.")
    parser.add_argument("--mode", choices=["full", "phylo"], default="full")
    parser.add_argument("--phenotype_samplesheet", required=True)
    parser.add_argument("--omics_samplesheet", default="")
    parser.add_argument("--species_traits", required=True)
    parser.add_argument("--reference_manifest", default="")
    parser.add_argument("--phylogeny_manifest", required=True)
    parser.add_argument("--study_design", default="")
    parser.add_argument("--report", default="results/validation/metadata_validation_report.tsv")
    parser.add_argument("--json_summary", default="")
    parser.add_argument("--schema_dir", default="")
    parser.add_argument("--validation_strict", action="store_true", default=False)
    return parser.parse_args()


def main():
    args = parse_args()
    records = []
    paths = {
        "phenotype_samplesheet": args.phenotype_samplesheet,
        "species_traits": args.species_traits,
        "phylogeny_manifest": args.phylogeny_manifest,
    }
    if args.mode == "full":
        paths["omics_samplesheet"] = args.omics_samplesheet
        paths["reference_manifest"] = args.reference_manifest

    tables = {}
    table_fields = {}
    for table_name, path in paths.items():
        fields, rows = read_table(path, table_name, records)
        table_fields[table_name] = fields
        tables[table_name] = rows
        check_required_columns(table_name, fields, records, mode=args.mode)
        check_required_values(table_name, rows, records, mode=args.mode)

    check_duplicates(tables["phenotype_samplesheet"], "phenotype_samplesheet", "sample_id", records)
    check_numeric(tables["phenotype_samplesheet"], "phenotype_samplesheet", "value", records)
    check_condition_timepoint(tables["phenotype_samplesheet"], "phenotype_samplesheet", records)
    check_phylogeny_labels(tables["species_traits"], tables["phylogeny_manifest"], records)
    check_species_label_variants(tables, records)
    check_conflicting_trait_values(tables["species_traits"], records)

    schema_dir = schema_dir_path(args.schema_dir)
    validate_table_schemas(table_fields, tables, schema_dir, records)

    if args.mode == "phylo":
        check_phylo_mode_consistency(tables, records)
    else:
        check_duplicates(tables["omics_samplesheet"], "omics_samplesheet", "sample_id", records)
        check_duplicates(tables["reference_manifest"], "reference_manifest", "reference_id", records, rule_id="METADATA_DUPLICATE_REFERENCE_ID")
        check_phylogeny_id_conflicts(tables["phylogeny_manifest"], records)
        check_phenotype_duplicate_observations(tables["phenotype_samplesheet"], records)
        check_condition_timepoint(tables["omics_samplesheet"], "omics_samplesheet", records)
        check_species_consistency(tables, records)
        check_references(tables["omics_samplesheet"], tables["reference_manifest"], records)
        check_omics_rows(tables["omics_samplesheet"], records)
        check_omics_metadata_join(tables["omics_samplesheet"], tables["phenotype_samplesheet"], records)
        check_study_design(args.study_design, records, schema_dir)

    add(records, "INFO", "validation", "", "", f"Validated {sum(len(v) for v in tables.values())} metadata rows")
    promote_warnings(records, args.validation_strict, STRICT_PROMOTIONS)

    write_report(args.report, records)
    if args.json_summary:
        with open(args.json_summary, "w") as handle:
            json.dump(severity_summary(records), handle, indent=2, sort_keys=True)
    print_summary(records)
    return 1 if any(row["severity"] == "ERROR" for row in records) else 0


if __name__ == "__main__":
    sys.exit(main())
