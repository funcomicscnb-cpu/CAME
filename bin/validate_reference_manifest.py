#!/usr/bin/env python3
"""Validate CAME Stage 23 real-mode reference manifests."""

import argparse
import csv
import os
import sys
from collections import Counter, defaultdict


REQUIRED_COLUMNS = [
    "reference_id",
    "species",
    "species_name",
    "assembly_name",
    "assembly_accession",
    "assembly_source",
    "assembly_release",
    "assembly_report",
    "fasta",
    "fai",
    "annotation_file",
    "annotation_format",
    "annotation_source",
    "annotation_release",
    "seqname_style",
    "mitochondrial_name",
]

ENUMS = {
    "annotation_format": {"gtf", "gff3", "bed", "other"},
    "seqname_style": {"ncbi", "ensembl", "ucsc", "custom"},
    "assembly_source": {"NCBI", "Ensembl", "UCSC", "Custom"},
}

ASSAY_ALIASES = {
    "rna": "rna",
    "rnaseq": "rna",
    "rna-seq": "rna",
    "rna_seq": "rna",
    "atac": "atac",
    "atacseq": "atac",
    "atac-seq": "atac",
    "atac_seq": "atac",
    "wgs": "wgs",
    "wes": "wes",
}

SUPPORTED_ASSAYS = {"rna", "atac", "wgs", "wes"}

RECOMMENDED_ASSETS = [
    "transcript_fasta",
    "star_index",
    "bwa_index",
    "bowtie2_index",
    "chrom_sizes",
    "blacklist_bed",
    "repeatmasker_bed",
    "mappability_bed",
]

BUSCO_FIELDS = ["busco_lineage", "busco_complete"]

ASSAY_RECOMMENDED = {
    "rna": ["transcript_fasta", "star_index"],
    "atac": ["bowtie2_index", "chrom_sizes", "blacklist_bed", "mappability_bed"],
    "wgs": ["bwa_index", "fai"],
    "wes": ["bwa_index", "fai"],
}

PATH_FIELDS = set(REQUIRED_COLUMNS) | set(RECOMMENDED_ASSETS) | {
    "genome_fasta",
    "gtf",
    "bwa_index",
    "star_index",
    "bowtie2_index",
    "transcript_fasta",
}
NON_PATH_FIELDS = {
    "reference_id",
    "species",
    "species_name",
    "assembly_name",
    "assembly_accession",
    "assembly_source",
    "assembly_release",
    "annotation_format",
    "annotation_source",
    "annotation_release",
    "seqname_style",
    "mitochondrial_name",
}
PATH_FIELDS -= NON_PATH_FIELDS

MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}


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


def read_table(path, records):
    if not path:
        add(records, "ERROR", "reference_manifest", "", "", "File path was not provided")
        return [], []
    if not os.path.exists(path):
        add(records, "ERROR", "reference_manifest", "", "", f"File does not exist: {path}")
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
                    add(records, "ERROR", "reference_manifest", "", row_number, "Row has more fields than the header")
                cleaned = {}
                for raw_field, field in zip(raw_fields, fields):
                    cleaned[field] = norm(row.get(raw_field))
                rows.append(cleaned)
    except Exception as exc:
        add(records, "ERROR", "reference_manifest", "", "", f"Could not read table: {exc}")
        return [], []
    if not fields:
        add(records, "ERROR", "reference_manifest", "", "", "Table has no header")
    if len(fields) != len(set(fields)):
        add(records, "ERROR", "reference_manifest", "", "", "Table has duplicate column names")
    return fields, rows


def check_required_columns(fields, records):
    present = set(fields)
    for column in REQUIRED_COLUMNS:
        if column not in present:
            add(records, "ERROR", "reference_manifest", column, "", "Missing required column")


def check_nonempty(rows, records):
    if not rows:
        add(records, "ERROR", "reference_manifest", "", "", "No reference rows found")


def check_required_values(rows, fields, records):
    present_required = [column for column in REQUIRED_COLUMNS if column in fields]
    for row_number, row in enumerate(rows, start=2):
        for column in present_required:
            if norm(row.get(column)) == "":
                add(records, "ERROR", "reference_manifest", column, row_number, "Missing required value")


def check_enums(rows, fields, records):
    for row_number, row in enumerate(rows, start=2):
        for field, allowed in ENUMS.items():
            if field not in fields:
                continue
            value = norm(row.get(field))
            if value and value not in allowed:
                add(records, "ERROR", "reference_manifest", field, row_number, f"Invalid value '{value}'. Expected one of: {', '.join(sorted(allowed))}")


def check_duplicate_references(rows, records):
    counts = Counter(norm(row.get("reference_id")) for row in rows if norm(row.get("reference_id")))
    for reference_id, count in sorted(counts.items()):
        if count > 1:
            add(records, "ERROR", "reference_manifest", "reference_id", "", f"Duplicate reference_id: {reference_id}")


def check_species_assemblies(rows, records):
    assemblies = defaultdict(set)
    for row in rows:
        species = norm(row.get("species"))
        if not species:
            continue
        assembly = (norm(row.get("assembly_name")), norm(row.get("assembly_accession")))
        assemblies[species].add(assembly)
    for species, values in sorted(assemblies.items()):
        complete_values = {value for value in values if any(value)}
        if len(complete_values) > 1:
            rendered = ", ".join(f"{name or '?'} ({accession or '?'})" for name, accession in sorted(complete_values))
            add(records, "ERROR", "reference_manifest", "species/assembly", "", f"Species has conflicting assemblies: {species}: {rendered}")


def parse_assays(value, records):
    assays = []
    for raw in str(value or "").split(","):
        item = lower_norm(raw)
        if not item:
            continue
        assay = ASSAY_ALIASES.get(item, item)
        if assay not in SUPPORTED_ASSAYS:
            add(records, "ERROR", "parameters", "assays", "", f"Unsupported assay for reference validation: {item}")
            continue
        if assay not in assays:
            assays.append(assay)
    return assays


def warn_missing_recommended(fields, rows, records):
    present = set(fields)
    for field in RECOMMENDED_ASSETS:
        if field not in present:
            add(records, "WARNING", "reference_manifest", field, "", "Recommended real-mode asset column is absent")
            continue
        for row_number, row in enumerate(rows, start=2):
            if not norm(row.get(field)):
                add(records, "WARNING", "reference_manifest", field, row_number, "Recommended real-mode asset is absent")
    for field in BUSCO_FIELDS:
        if field not in present:
            add(records, "WARNING", "reference_manifest", field, "", "Recommended BUSCO metadata column is absent")
            continue
        for row_number, row in enumerate(rows, start=2):
            if not norm(row.get(field)):
                add(records, "WARNING", "reference_manifest", field, row_number, "Recommended BUSCO metadata is absent")


def warn_assay_assets(assays, fields, rows, records):
    present = set(fields)
    for assay in assays:
        for field in ASSAY_RECOMMENDED.get(assay, []):
            if field not in present:
                add(records, "WARNING", "reference_manifest", field, "", f"{assay} validation declared but assay-relevant reference column is absent")
                continue
            for row_number, row in enumerate(rows, start=2):
                if not norm(row.get(field)):
                    add(records, "WARNING", "reference_manifest", field, row_number, f"{assay} validation declared but assay-relevant reference asset is absent")


def resolve_path(value, base_dir):
    path = norm(value)
    if not path or "://" in path or os.path.isabs(path):
        return path
    return os.path.normpath(os.path.join(base_dir, path))


def path_exists(path, field):
    if not path:
        return True
    if os.path.exists(path):
        return True
    if field in {"bwa_index", "bowtie2_index"}:
        suffixes = [".amb", ".ann", ".bwt", ".pac", ".sa"] if field == "bwa_index" else [".1.bt2", ".1.bt2l"]
        return any(os.path.exists(path + suffix) for suffix in suffixes)
    return False


def check_paths(manifest_path, fields, rows, records):
    base_dir = os.path.dirname(os.path.abspath(manifest_path))
    for row_number, row in enumerate(rows, start=2):
        for field in sorted(PATH_FIELDS & set(fields)):
            value = norm(row.get(field))
            if not value:
                continue
            resolved = resolve_path(value, base_dir)
            if not path_exists(resolved, field):
                add(records, "ERROR", "reference_manifest", field, row_number, f"Path does not exist: {value}")


def write_report(path, records):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    fields = ["severity", "source", "field", "row", "message"]
    with open(path, "w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, delimiter="\t", extrasaction="ignore", quoting=csv.QUOTE_NONE, escapechar="\\", lineterminator="\n")
        writer.writeheader()
        writer.writerows(records)


def print_summary(records):
    counts = Counter(row["severity"] for row in records)
    print("CAME real-mode reference manifest validation summary")
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
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--report", required=True)
    parser.add_argument("--assays", default="")
    parser.add_argument("--check-paths", action="store_true", default=False)
    return parser.parse_args()


def main():
    args = parse_args()
    records = []
    assays = parse_assays(args.assays, records)
    fields, rows = read_table(args.manifest, records)
    check_required_columns(fields, records)
    check_nonempty(rows, records)
    check_required_values(rows, fields, records)
    check_enums(rows, fields, records)
    check_duplicate_references(rows, records)
    check_species_assemblies(rows, records)
    warn_missing_recommended(fields, rows, records)
    warn_assay_assets(assays, fields, rows, records)
    if args.check_paths:
        check_paths(args.manifest, fields, rows, records)
    add(records, "INFO", "reference_manifest", "", "", f"Validated {len(rows)} reference row(s)")
    write_report(args.report, records)
    print_summary(records)
    return 1 if any(row["severity"] == "ERROR" for row in records) else 0


if __name__ == "__main__":
    sys.exit(main())
