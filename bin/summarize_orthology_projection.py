#!/usr/bin/env python3
"""Summarize CAME Stage 7 orthology projection outputs."""

import argparse
import csv
import os
import sys
from collections import defaultdict


MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}
COUNT_METADATA_FIELDS = {
    "gene": ["feature_id", "feature_type", "annotation_id"],
    "regulatory_element": ["feature_id", "feature_type", "chrom", "start", "end"],
}
SUMMARY_FIELDS = [
    "source_table",
    "feature_type",
    "species",
    "n_input_features",
    "n_mapped",
    "n_unmapped",
    "n_ambiguous",
    "n_orthogroups",
    "coverage_fraction",
]
MANIFEST_FIELDS = ["output_type", "path", "exists", "status"]


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
    if not path or not os.path.exists(path):
        return [], []
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


def sample_species_by_omics(omics_samplesheet):
    _, rows = read_table(omics_samplesheet)
    result = defaultdict(dict)
    for row in rows:
        sample_id = norm(row.get("sample_id"))
        species = norm(row.get("species"))
        omics_type = norm(row.get("omics_type")).lower()
        if sample_id and species and omics_type:
            result[omics_type][sample_id] = species
    return result


def feature_map_index(feature_map):
    _, rows = read_table(feature_map)
    mapped = defaultdict(lambda: defaultdict(set))
    ambiguous = defaultdict(lambda: defaultdict(set))
    orthogroups = defaultdict(lambda: defaultdict(lambda: defaultdict(set)))
    for row in rows:
        feature_type = norm(row.get("feature_type"))
        species = norm(row.get("species"))
        feature_id = norm(row.get("feature_id"))
        orthogroup_id = norm(row.get("orthogroup_id"))
        if not feature_type or not species or not feature_id or not orthogroup_id:
            continue
        mapped[feature_type][species].add(feature_id)
        orthogroups[feature_type][species][feature_id].add(orthogroup_id)
        if norm(row.get("is_ambiguous")).lower() == "true":
            ambiguous[feature_type][species].add(feature_id)
    return mapped, ambiguous, orthogroups


def count_input_features(path, feature_type, omics_type, sample_species):
    fields, rows = read_table(path)
    if not rows:
        return {}
    sample_columns = [field for field in fields if field not in set(COUNT_METADATA_FIELDS[feature_type])]
    species_values = sorted({sample_species.get(omics_type, {}).get(sample, "") for sample in sample_columns})
    species_values = [species for species in species_values if species]
    feature_ids = {norm(row.get("feature_id")) for row in rows if norm(row.get("feature_id"))}
    return {species: set(feature_ids) for species in species_values}


def differential_input_features(path):
    _, rows = read_table(path)
    result = defaultdict(set)
    for row in rows:
        species = norm(row.get("species"))
        feature_id = norm(row.get("feature_id"))
        if species and feature_id:
            result[species].add(feature_id)
    return result


def summary_rows_for_source(source_table, feature_type, input_by_species, mapped, ambiguous, orthogroups):
    rows = []
    for species in sorted(input_by_species):
        input_features = input_by_species[species]
        mapped_features = input_features & mapped.get(feature_type, {}).get(species, set())
        ambiguous_features = input_features & ambiguous.get(feature_type, {}).get(species, set())
        mapped_orthogroups = set()
        for feature_id in mapped_features:
            for orthogroup in orthogroups.get(feature_type, {}).get(species, {}).get(feature_id, set()):
                mapped_orthogroups.add(orthogroup)
        n_input = len(input_features)
        n_mapped = len(mapped_features)
        coverage = (n_mapped / n_input) if n_input else 0.0
        rows.append(
            {
                "source_table": source_table,
                "feature_type": feature_type,
                "species": species,
                "n_input_features": str(n_input),
                "n_mapped": str(n_mapped),
                "n_unmapped": str(n_input - n_mapped),
                "n_ambiguous": str(len(ambiguous_features)),
                "n_orthogroups": str(len(mapped_orthogroups)),
                "coverage_fraction": format(coverage, ".6g"),
            }
        )
    return rows


def manifest_rows(paths):
    rows = []
    for output_type, path in paths:
        rows.append(
            {
                "output_type": output_type,
                "path": path,
                "exists": "true" if path and os.path.exists(path) else "false",
                "status": "OK" if path and os.path.exists(path) else "ERROR",
            }
        )
    return rows


def summarize(args):
    sample_species = sample_species_by_omics(args.omics_samplesheet)
    mapped, ambiguous, orthogroups = feature_map_index(args.feature_map)

    summary_rows = []
    summary_rows.extend(
        summary_rows_for_source(
            "rnaseq_counts",
            "gene",
            count_input_features(args.rnaseq_counts, "gene", "rnaseq", sample_species),
            mapped,
            ambiguous,
            orthogroups,
        )
    )
    summary_rows.extend(
        summary_rows_for_source(
            "atacseq_counts",
            "regulatory_element",
            count_input_features(args.atacseq_counts, "regulatory_element", "atacseq", sample_species),
            mapped,
            ambiguous,
            orthogroups,
        )
    )
    summary_rows.extend(
        summary_rows_for_source(
            "differential_expression",
            "gene",
            differential_input_features(args.differential_expression),
            mapped,
            ambiguous,
            orthogroups,
        )
    )
    summary_rows.extend(
        summary_rows_for_source(
            "differential_accessibility",
            "regulatory_element",
            differential_input_features(args.differential_accessibility),
            mapped,
            ambiguous,
            orthogroups,
        )
    )

    outputs = [
        ("feature_to_orthogroup_map", args.feature_map),
        ("gene_orthogroup_counts", args.gene_orthogroup_counts),
        ("re_orthogroup_counts", args.re_orthogroup_counts),
        ("differential_expression_orthogroups", args.differential_expression_orthogroups),
        ("differential_accessibility_orthogroups", args.differential_accessibility_orthogroups),
        ("orthology_projection_warnings", args.warnings),
    ]
    manifest = manifest_rows(outputs)
    os.makedirs(args.output_dir, exist_ok=True)
    write_tsv(os.path.join(args.output_dir, "orthology_projection_summary.tsv"), SUMMARY_FIELDS, summary_rows)
    write_tsv(os.path.join(args.output_dir, "orthology_outputs_manifest.tsv"), MANIFEST_FIELDS, manifest)
    errors = sum(1 for row in manifest if row["status"] == "ERROR")
    print(f"CAME orthology summary: ERROR={errors} rows={len(summary_rows)}")
    return 1 if errors else 0


def parse_args():
    parser = argparse.ArgumentParser(description="Summarize CAME Stage 7 orthology projection outputs.")
    parser.add_argument("--omics_samplesheet", required=True)
    parser.add_argument("--rnaseq_counts", default="")
    parser.add_argument("--atacseq_counts", default="")
    parser.add_argument("--differential_expression", default="")
    parser.add_argument("--differential_accessibility", default="")
    parser.add_argument("--feature_map", required=True)
    parser.add_argument("--gene_orthogroup_counts", required=True)
    parser.add_argument("--re_orthogroup_counts", required=True)
    parser.add_argument("--differential_expression_orthogroups", required=True)
    parser.add_argument("--differential_accessibility_orthogroups", required=True)
    parser.add_argument("--warnings", required=True)
    parser.add_argument("--output_dir", default="results/orthology/summary")
    return parser.parse_args()


def main():
    try:
        return summarize(parse_args())
    except Exception as exc:
        print(f"ERROR\tsummarize_orthology_projection\t{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
