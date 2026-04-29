#!/usr/bin/env python3
"""Validate CAME Stage 23 real-mode sample metadata."""

import argparse
import csv
import os
import sys
from collections import Counter, defaultdict


REQUIRED_COLUMNS = [
    "sample_id",
    "study_id",
    "species",
    "individual_id",
    "biological_replicate",
    "assay",
    "tissue",
    "condition",
    "platform",
    "library_protocol",
    "read_layout",
    "fastq_1",
    "reference_id",
]

ASSAY_ENUM = {"rna", "atac", "wgs", "wes", "chip_tf", "chip_histone", "other"}
READ_LAYOUT_ENUM = {"single", "paired"}
RNA_STRANDEDNESS_ENUM = {"forward", "reverse", "unstranded", "unknown"}
CHIP_ASSAYS = {"chip_tf", "chip_histone"}
MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}
KNOWN_PLATFORM_TOKENS = {
    "illumina",
    "novaseq",
    "nextseq",
    "hiseq",
    "miseq",
    "element",
    "bgi",
    "mgiseq",
    "pacbio",
    "sequel",
    "nanopore",
    "promethion",
    "gridion",
    "minion",
}


def norm(value):
    text = str(value if value is not None else "").strip()
    return "" if text.lower() in MISSING_VALUES else text


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
    return "\t" if sample.count("\t") > sample.count(",") else ","


def read_table(path, source, records):
    if not path:
        add(records, "ERROR", source, "", "", "File path was not provided")
        return [], []
    if not os.path.exists(path):
        add(records, "ERROR", source, "", "", f"File does not exist: {path}")
        return [], []
    try:
        delimiter = infer_delimiter(path)
        with open(path, newline="") as handle:
            reader = csv.DictReader(handle, delimiter=delimiter)
            raw_fields = reader.fieldnames or []
            fields = [norm(field) for field in raw_fields]
            rows = []
            for row_number, row in enumerate(reader, start=2):
                if None in row:
                    add(records, "ERROR", source, "", row_number, "Row has more fields than the header")
                cleaned = {}
                for raw_field, field in zip(raw_fields, fields):
                    cleaned[field] = norm(row.get(raw_field))
                rows.append(cleaned)
    except Exception as exc:
        add(records, "ERROR", source, "", "", f"Could not read table: {exc}")
        return [], []
    if not fields:
        add(records, "ERROR", source, "", "", "Table has no header")
    if len(fields) != len(set(fields)):
        add(records, "ERROR", source, "", "", "Table has duplicate column names")
    return fields, rows


def check_required_columns(fields, records):
    present = set(fields)
    for column in REQUIRED_COLUMNS:
        if column not in present:
            add(records, "ERROR", "real_mode_metadata", column, "", "Missing required column")


def check_nonempty(rows, records):
    if not rows:
        add(records, "ERROR", "real_mode_metadata", "", "", "No metadata rows found")


def check_required_values(fields, rows, records):
    present_required = [column for column in REQUIRED_COLUMNS if column in fields]
    for row_number, row in enumerate(rows, start=2):
        for column in present_required:
            if not norm(row.get(column)):
                add(records, "ERROR", "real_mode_metadata", column, row_number, "Missing required value")


def check_duplicates(rows, records):
    counts = Counter(norm(row.get("sample_id")) for row in rows if norm(row.get("sample_id")))
    for sample_id, count in sorted(counts.items()):
        if count > 1:
            add(records, "ERROR", "real_mode_metadata", "sample_id", "", f"Duplicate sample_id: {sample_id}")


def check_assay_and_layout(fields, rows, records):
    has_fastq_2 = "fastq_2" in fields
    has_strandedness = "strandedness" in fields
    has_antibody = "antibody" in fields
    has_target_bed = "target_bed" in fields
    for row_number, row in enumerate(rows, start=2):
        assay = lower_norm(row.get("assay"))
        layout = lower_norm(row.get("read_layout"))
        sample_id = norm(row.get("sample_id")) or f"row {row_number}"
        if assay and assay not in ASSAY_ENUM:
            add(records, "ERROR", "real_mode_metadata", "assay", row_number, f"Unknown assay for {sample_id}: {assay}")
        if layout and layout not in READ_LAYOUT_ENUM:
            add(records, "ERROR", "real_mode_metadata", "read_layout", row_number, f"Invalid read_layout for {sample_id}: {layout}")
        fastq_2 = norm(row.get("fastq_2")) if has_fastq_2 else ""
        if layout == "paired" and not fastq_2:
            add(records, "ERROR", "real_mode_metadata", "fastq_2", row_number, "Paired-end sample requires fastq_2")
        if layout == "single" and fastq_2:
            add(records, "ERROR", "real_mode_metadata", "fastq_2", row_number, "Single-end sample must not provide fastq_2")
        if assay == "rna":
            strandedness = lower_norm(row.get("strandedness")) if has_strandedness else ""
            if not strandedness:
                add(records, "ERROR", "real_mode_metadata", "strandedness", row_number, "RNA sample requires strandedness")
            elif strandedness not in RNA_STRANDEDNESS_ENUM:
                add(records, "ERROR", "real_mode_metadata", "strandedness", row_number, f"Invalid RNA strandedness: {strandedness}")
        if assay in CHIP_ASSAYS and not (norm(row.get("antibody")) if has_antibody else ""):
            add(records, "ERROR", "real_mode_metadata", "antibody", row_number, "ChIP sample requires antibody")
        if assay == "wes" and not (norm(row.get("target_bed")) if has_target_bed else ""):
            add(records, "ERROR", "real_mode_metadata", "target_bed", row_number, "WES sample requires target_bed")


def read_reference_manifest(path, records):
    if not path:
        return {}
    fields, rows = read_table(path, "reference_manifest", records)
    present = set(fields)
    for column in ["reference_id", "species"]:
        if column not in present:
            add(records, "ERROR", "reference_manifest", column, "", "Missing required column for metadata/reference validation")
    references = {}
    for row_number, row in enumerate(rows, start=2):
        reference_id = norm(row.get("reference_id"))
        if not reference_id:
            continue
        if reference_id in references:
            add(records, "ERROR", "reference_manifest", "reference_id", row_number, f"Duplicate reference_id: {reference_id}")
        references[reference_id] = {
            "species": norm(row.get("species")),
            "species_name": norm(row.get("species_name")),
            "seqname_style": lower_norm(row.get("seqname_style")),
        }
    return references


def check_references(rows, references, records):
    if not references:
        return
    seqname_styles = set()
    for row_number, row in enumerate(rows, start=2):
        reference_id = norm(row.get("reference_id"))
        if not reference_id:
            continue
        reference = references.get(reference_id)
        if reference is None:
            add(records, "ERROR", "real_mode_metadata", "reference_id", row_number, f"Unknown reference_id: {reference_id}")
            continue
        species = norm(row.get("species"))
        if species and reference.get("species") and species != reference.get("species"):
            add(records, "ERROR", "real_mode_metadata", "reference_id", row_number, "reference_id species does not match metadata species")
        if reference.get("seqname_style"):
            seqname_styles.add(reference["seqname_style"])
    if len(seqname_styles) > 1:
        add(records, "WARNING", "real_mode_metadata", "reference_id", "", "Metadata references use mixed seqname styles: " + ", ".join(sorted(seqname_styles)))


def warn_replicates(rows, records):
    groups = defaultdict(set)
    for row in rows:
        key = (
            norm(row.get("study_id")),
            norm(row.get("species")),
            lower_norm(row.get("assay")),
            norm(row.get("tissue")),
            norm(row.get("condition")),
        )
        replicate = norm(row.get("biological_replicate"))
        if all(key) and replicate:
            groups[key].add(replicate)
    for key, replicates in sorted(groups.items()):
        if len(replicates) < 2:
            study_id, species, assay, tissue, condition = key
            add(records, "WARNING", "real_mode_metadata", "biological_replicate", "", f"Low replicate count for {study_id}/{species}/{assay}/{tissue}/{condition}: {len(replicates)}")


def warn_recommended_fields(fields, rows, records):
    if "batch" not in fields:
        add(records, "WARNING", "real_mode_metadata", "batch", "", "Recommended batch column is absent")
    else:
        for row_number, row in enumerate(rows, start=2):
            if not norm(row.get("batch")):
                add(records, "WARNING", "real_mode_metadata", "batch", row_number, "Recommended batch value is absent")
    if "read_length" not in fields:
        add(records, "WARNING", "real_mode_metadata", "read_length", "", "Recommended read_length column is absent")
    else:
        for row_number, row in enumerate(rows, start=2):
            value = norm(row.get("read_length"))
            if not value:
                add(records, "WARNING", "real_mode_metadata", "read_length", row_number, "Recommended read_length value is absent")
            else:
                try:
                    float(value)
                except ValueError:
                    add(records, "WARNING", "real_mode_metadata", "read_length", row_number, f"read_length should be numeric, found: {value}")
    for row_number, row in enumerate(rows, start=2):
        assay = lower_norm(row.get("assay"))
        layout = lower_norm(row.get("read_layout"))
        if assay == "atac" and layout == "single":
            add(records, "WARNING", "real_mode_metadata", "read_layout", row_number, "ATAC single-end libraries are allowed but paired-end is preferred")
        platform = lower_norm(row.get("platform"))
        if platform and not any(token in platform for token in KNOWN_PLATFORM_TOKENS):
            add(records, "WARNING", "real_mode_metadata", "platform", row_number, f"Unknown sequencing platform: {row.get('platform')}")


def warn_species_names(rows, references, records):
    labels_by_normalized = defaultdict(set)
    for row in rows:
        species = norm(row.get("species"))
        if not species:
            continue
        normalized = species.lower().replace(" ", "_")
        labels_by_normalized[normalized].add(species)
        if " " in species:
            add(records, "WARNING", "real_mode_metadata", "species", "", f"Species should use underscore-stable identifiers: {species}")
    for normalized, labels in sorted(labels_by_normalized.items()):
        if len(labels) > 1:
            add(records, "WARNING", "real_mode_metadata", "species", "", f"Species naming variants collapse to {normalized}: {', '.join(sorted(labels))}")
    if references:
        names_by_species = defaultdict(set)
        for reference in references.values():
            species = reference.get("species")
            species_name = reference.get("species_name")
            if species and species_name:
                names_by_species[species].add(species_name)
        for species, names in sorted(names_by_species.items()):
            expected = species.replace("_", " ")
            if expected not in names:
                add(records, "WARNING", "reference_manifest", "species_name", "", f"species_name for {species} does not match underscore-expanded species label")


def warn_longitudinal(mode, fields, rows, records):
    if mode not in {"auto", "true", "false"}:
        add(records, "ERROR", "parameters", "longitudinal", "", f"Unsupported longitudinal mode: {mode}")
        return
    time_fields = [field for field in ["timepoint", "collection_time", "age", "day"] if field in fields]
    if mode == "true" and not time_fields:
        add(records, "WARNING", "real_mode_metadata", "timepoint", "", "Longitudinal validation was requested but no time-like column is present")
    if mode in {"auto", "true"} and time_fields:
        for row_number, row in enumerate(rows, start=2):
            if not any(norm(row.get(field)) for field in time_fields):
                add(records, "WARNING", "real_mode_metadata", ",".join(time_fields), row_number, "Longitudinal time metadata is incomplete")


def write_report(path, records):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    fields = ["severity", "source", "field", "row", "message"]
    with open(path, "w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, delimiter="\t", extrasaction="ignore", quoting=csv.QUOTE_NONE, escapechar="\\", lineterminator="\n")
        writer.writeheader()
        writer.writerows(records)


def print_summary(records):
    counts = Counter(row["severity"] for row in records)
    print("CAME real-mode metadata validation summary")
    print(f"ERROR: {counts.get('ERROR', 0)}")
    print(f"WARNING: {counts.get('WARNING', 0)}")
    print(f"INFO: {counts.get('INFO', 0)}")
    for severity in ["ERROR", "WARNING"]:
        shown = 0
        for row in records:
            if row["severity"] != severity:
                continue
            loc = f"{row['source']}:{row['row']}" if row["row"] else row["source"]
            print(f"{severity}\t{loc}\t{row['field']}\t{row['message']}")
            shown += 1
            if shown == 20:
                remaining = counts[severity] - shown
                if remaining > 0:
                    print(f"{severity}\t...\t...\t{remaining} more")
                break


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--metadata", required=True)
    parser.add_argument("--reference_manifest", default="")
    parser.add_argument("--report", required=True)
    parser.add_argument("--longitudinal", choices=["auto", "true", "false"], default="auto")
    return parser.parse_args()


def main():
    args = parse_args()
    records = []
    fields, rows = read_table(args.metadata, "real_mode_metadata", records)
    check_required_columns(fields, records)
    check_nonempty(rows, records)
    check_required_values(fields, rows, records)
    check_duplicates(rows, records)
    check_assay_and_layout(fields, rows, records)
    references = read_reference_manifest(args.reference_manifest, records) if args.reference_manifest else {}
    check_references(rows, references, records)
    warn_replicates(rows, records)
    warn_recommended_fields(fields, rows, records)
    warn_species_names(rows, references, records)
    warn_longitudinal(args.longitudinal, fields, rows, records)
    add(records, "INFO", "real_mode_metadata", "", "", f"Validated {len(rows)} metadata row(s)")
    write_report(args.report, records)
    print_summary(records)
    return 1 if any(row["severity"] == "ERROR" for row in records) else 0


if __name__ == "__main__":
    sys.exit(main())
