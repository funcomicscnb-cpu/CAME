#!/usr/bin/env python3
"""Project species-specific CAME features to orthology groups."""

import argparse
import csv
import os
import sys
from collections import Counter, defaultdict


MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}
OMICS_ALIASES = {
    "rna-seq": "rnaseq",
    "rna_seq": "rnaseq",
    "rna seq": "rnaseq",
    "atac-seq": "atacseq",
    "atac_seq": "atacseq",
    "atac seq": "atacseq",
}
SUPPORTED_OMICS_TYPES = {"rnaseq", "atacseq"}
COUNT_METADATA_FIELDS = {
    "gene": ["feature_id", "feature_type", "annotation_id"],
    "regulatory_element": ["feature_id", "feature_type", "chrom", "start", "end"],
}
ORTHOLOGY_REQUIRED_FIELDS = ["species", "feature_id", "orthogroup_id"]
FEATURE_MAP_FIELDS = [
    "feature_type",
    "species",
    "feature_id",
    "orthogroup_id",
    "mapping_status",
    "n_mapped_orthogroups",
    "is_ambiguous",
    "ambiguity_reason",
    "gene_symbol",
    "human_anchor_id",
    "transcript_id",
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
ORTHOGROUP_META_FIELDS = [
    "orthogroup_id",
    "feature_type",
    "mapping_status",
    "n_source_features",
    "n_species",
    "is_ambiguous",
    "ambiguity_reason",
    "species_members",
    "source_feature_ids",
]
ORTHOGROUP_DIFF_META_FIELDS = [
    "orthogroup_id",
    "feature_type",
    "species",
    "mapping_status",
    "n_source_features",
    "n_species",
    "is_ambiguous",
    "ambiguity_reason",
    "species_members",
    "source_feature_ids",
]
WARNING_FIELDS = ["severity", "feature_type", "source", "species", "feature_id", "orthogroup_id", "message"]
STANDARD_DIFF_FIELDS = {
    "gene": [
        "omics_type",
        "contrast_name",
        "contrast_type",
        "baseline_label",
        "response_label",
        "n_baseline",
        "n_response",
        "base_mean",
        "baseline_mean",
        "response_mean",
        "log2_fold_change",
        "statistic",
        "p_value",
        "padj",
        "method",
        "status",
        "message",
        "annotation_id",
    ],
    "regulatory_element": [
        "omics_type",
        "contrast_name",
        "contrast_type",
        "baseline_label",
        "response_label",
        "n_baseline",
        "n_response",
        "base_mean",
        "baseline_mean",
        "response_mean",
        "log2_fold_change",
        "statistic",
        "p_value",
        "padj",
        "method",
        "status",
        "message",
        "chrom",
        "start",
        "end",
    ],
}
DIFF_GROUP_FIELDS = ["omics_type", "contrast_name", "contrast_type", "species", "baseline_label", "response_label"]
MEAN_FIELDS = {"base_mean", "baseline_mean", "response_mean", "log2_fold_change", "statistic"}
MIN_FIELDS = {"p_value", "padj"}


def norm(value):
    text = str(value if value is not None else "").strip()
    return "" if text.lower() in MISSING_VALUES else text


def normalize_omics_type(value):
    text = norm(value).lower()
    return OMICS_ALIASES.get(text, text)


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


def warn(warnings, severity, feature_type, source, message, species="", feature_id="", orthogroup_id=""):
    warnings.append(
        {
            "severity": severity,
            "feature_type": feature_type,
            "source": source,
            "species": species,
            "feature_id": feature_id,
            "orthogroup_id": orthogroup_id,
            "message": message,
        }
    )


def parse_requested(raw):
    requested = []
    for item in str(raw or "").split(","):
        omics_type = normalize_omics_type(item)
        if omics_type and omics_type in SUPPORTED_OMICS_TYPES and omics_type not in requested:
            requested.append(omics_type)
    return requested


def parse_float(value):
    text = norm(value)
    if not text:
        return None
    try:
        return float(text)
    except ValueError:
        return None


def format_number(value):
    if value is None:
        return "NA"
    if abs(value - round(value)) < 1e-9:
        return str(int(round(value)))
    return format(value, ".12g")


def table_source(feature_type):
    return "orthologous_genes" if feature_type == "gene" else "orthologous_res"


def load_orthology(path, feature_type, warnings):
    fields, raw_rows = read_table(path)
    missing = [field for field in ORTHOLOGY_REQUIRED_FIELDS if field not in fields]
    if missing:
        raise RuntimeError(f"{table_source(feature_type)} missing required column(s): {', '.join(missing)}")

    exact_seen = set()
    complete = []
    for idx, row in enumerate(raw_rows, start=2):
        missing_values = [field for field in ORTHOLOGY_REQUIRED_FIELDS if not norm(row.get(field))]
        if missing_values:
            raise RuntimeError(f"{table_source(feature_type)} row {idx} has empty required value(s): {', '.join(missing_values)}")
        key = (row["species"], row["feature_id"], row["orthogroup_id"])
        if key in exact_seen:
            warn(
                warnings,
                "WARNING",
                feature_type,
                table_source(feature_type),
                "Duplicate exact mapping row ignored during projection",
                row["species"],
                row["feature_id"],
                row["orthogroup_id"],
            )
            continue
        exact_seen.add(key)
        complete.append({field: norm(row.get(field)) for field in fields} | {"feature_type": feature_type})
    return complete


def build_mapping_index(mapping_rows):
    by_key = defaultdict(list)
    for row in mapping_rows:
        by_key[(row["species"], row["feature_id"])].append(row)
    orthogroups_by_key = {key: sorted({row["orthogroup_id"] for row in rows}) for key, rows in by_key.items()}
    status_by_key = {}
    for key, orthogroups in orthogroups_by_key.items():
        status_by_key[key] = {
            "mapping_status": "ambiguous" if len(orthogroups) > 1 else "mapped",
            "is_ambiguous": "true" if len(orthogroups) > 1 else "false",
            "ambiguity_reason": "one_to_many_orthology_mapping" if len(orthogroups) > 1 else "",
            "n_mapped_orthogroups": str(len(orthogroups)),
        }
    return by_key, status_by_key


def feature_map_rows(mapping_rows, status_by_feature_type):
    rows = []
    for row in sorted(mapping_rows, key=lambda item: (item["feature_type"], item["species"], item["feature_id"], item["orthogroup_id"])):
        key = (row["species"], row["feature_id"])
        status = status_by_feature_type[row["feature_type"]][key]
        out = {field: "" for field in FEATURE_MAP_FIELDS}
        out.update({field: norm(row.get(field)) for field in FEATURE_MAP_FIELDS})
        out.update(status)
        out["feature_type"] = row["feature_type"]
        out["species"] = row["species"]
        out["feature_id"] = row["feature_id"]
        out["orthogroup_id"] = row["orthogroup_id"]
        rows.append(out)
    return rows


def sample_species_by_omics(omics_samplesheet):
    fields, rows = read_table(omics_samplesheet)
    missing = [field for field in ["sample_id", "species", "omics_type"] if field not in fields]
    if missing:
        raise RuntimeError(f"omics_samplesheet missing required column(s) for orthology projection: {', '.join(missing)}")
    result = defaultdict(dict)
    for row in rows:
        sample_id = norm(row.get("sample_id"))
        species = norm(row.get("species"))
        omics_type = normalize_omics_type(row.get("omics_type"))
        if sample_id and species and omics_type:
            result[omics_type][sample_id] = species
    return result


def count_fields(path, feature_type):
    fields, rows = read_table(path)
    missing = [field for field in COUNT_METADATA_FIELDS[feature_type] if field not in fields]
    if missing:
        raise RuntimeError(f"{path} missing required count column(s): {', '.join(missing)}")
    sample_columns = [field for field in fields if field not in set(COUNT_METADATA_FIELDS[feature_type])]
    return fields, rows, sample_columns


def empty_count_output(output_path, sample_columns=None):
    fields = ORTHOGROUP_META_FIELDS + list(sample_columns or [])
    write_tsv(output_path, fields, [])


def add_membership_to_entry(entry, feature_type, species, feature_id, status):
    entry["feature_type"] = feature_type
    entry["source_keys"].add((species, feature_id))
    entry["species"].add(species)
    entry["features"].add(feature_id)
    if status["is_ambiguous"] == "true":
        entry["ambiguity_reasons"].add(status["ambiguity_reason"])


def add_membership(meta, orthogroup_id, feature_type, species, feature_id, status):
    add_membership_to_entry(meta[orthogroup_id], feature_type, species, feature_id, status)


def orthogroup_meta_row(orthogroup_id, entry):
    is_ambiguous = bool(entry["ambiguity_reasons"])
    reasons = sorted(reason for reason in entry["ambiguity_reasons"] if reason)
    return {
        "orthogroup_id": orthogroup_id,
        "feature_type": entry["feature_type"],
        "mapping_status": "ambiguous" if is_ambiguous else "mapped",
        "n_source_features": str(len(entry["source_keys"])),
        "n_species": str(len(entry["species"])),
        "is_ambiguous": "true" if is_ambiguous else "false",
        "ambiguity_reason": ",".join(reasons),
        "species_members": ",".join(sorted(entry["species"])),
        "source_feature_ids": ",".join(sorted(entry["features"])),
    }


def project_count_matrix(path, feature_type, omics_type, mapping_by_key, status_by_key, sample_species, output_path, warnings):
    fields, rows, sample_columns = count_fields(path, feature_type)
    unknown_samples = [sample for sample in sample_columns if sample not in sample_species.get(omics_type, {})]
    if unknown_samples:
        warn(warnings, "WARNING", feature_type, f"{omics_type}_counts", f"Sample column(s) absent from omics_samplesheet: {', '.join(unknown_samples)}")

    values = defaultdict(lambda: {sample: 0.0 for sample in sample_columns})
    observed = defaultdict(lambda: {sample: False for sample in sample_columns})
    meta = defaultdict(lambda: {"feature_type": feature_type, "source_keys": set(), "species": set(), "features": set(), "ambiguity_reasons": set()})
    unmapped_seen = set()
    for row in rows:
        feature_id = norm(row.get("feature_id"))
        for sample in sample_columns:
            species = sample_species.get(omics_type, {}).get(sample, "")
            if not species:
                continue
            key = (species, feature_id)
            mappings = mapping_by_key.get(key, [])
            if not mappings:
                if key not in unmapped_seen:
                    warn(warnings, "WARNING", feature_type, f"{omics_type}_counts", "Feature has no orthology mapping for this sample species", species, feature_id)
                    unmapped_seen.add(key)
                continue
            count = parse_float(row.get(sample))
            if count is None:
                raise RuntimeError(f"{path} contains non-numeric count for feature {feature_id}, sample {sample}")
            for mapping in mappings:
                orthogroup_id = mapping["orthogroup_id"]
                values[orthogroup_id][sample] += count
                observed[orthogroup_id][sample] = True
                add_membership(meta, orthogroup_id, feature_type, species, feature_id, status_by_key[key])

    output_rows = []
    for orthogroup_id in sorted(values):
        out = orthogroup_meta_row(orthogroup_id, meta[orthogroup_id])
        for sample in sample_columns:
            out[sample] = format_number(values[orthogroup_id][sample]) if observed[orthogroup_id][sample] else "NA"
        output_rows.append(out)
    write_tsv(output_path, ORTHOGROUP_META_FIELDS + sample_columns, output_rows)
    return len(rows), len(output_rows)


def empty_diff_fields(feature_type):
    return ORTHOGROUP_DIFF_META_FIELDS + STANDARD_DIFF_FIELDS[feature_type]


def unique_join(values, sep=","):
    unique = sorted({norm(value) for value in values if norm(value)})
    return sep.join(unique)


def aggregate_numeric(rows, field, mode):
    values = [parse_float(row.get(field)) for row in rows]
    values = [value for value in values if value is not None]
    if not values:
        return "NA"
    if mode == "min":
        return format_number(min(values))
    return format_number(sum(values) / len(values))


def aggregate_diff_field(rows, field, group_fields):
    if field in MEAN_FIELDS:
        return aggregate_numeric(rows, field, "mean")
    if field in MIN_FIELDS:
        return aggregate_numeric(rows, field, "min")
    if field in group_fields:
        return norm(rows[0].get(field))
    if field == "message":
        return unique_join([row.get(field) for row in rows], sep="; ")
    return unique_join([row.get(field) for row in rows])


def project_differential_table(path, feature_type, mapping_by_key, status_by_key, output_path, warnings, source_name):
    if not path:
        write_tsv(output_path, empty_diff_fields(feature_type), [])
        warn(warnings, "WARNING", feature_type, source_name, "Differential input absent; wrote empty orthogroup differential output")
        return 0, 0
    if not os.path.exists(path):
        raise RuntimeError(f"Missing differential input: {path}")

    fields, rows = read_table(path)
    missing = [field for field in ["species", "feature_id", "feature_type"] if field not in fields]
    if missing:
        raise RuntimeError(f"{path} missing required differential column(s): {', '.join(missing)}")

    passthrough_fields = [field for field in fields if field not in {"feature_id", "feature_type", "species"}]
    output_fields = ORTHOGROUP_DIFF_META_FIELDS + passthrough_fields
    group_fields = [field for field in DIFF_GROUP_FIELDS if field in fields]
    grouped = defaultdict(list)
    meta = defaultdict(lambda: {"feature_type": feature_type, "source_keys": set(), "species": set(), "features": set(), "ambiguity_reasons": set()})
    unmapped_seen = set()

    for row in rows:
        species = norm(row.get("species"))
        feature_id = norm(row.get("feature_id"))
        key = (species, feature_id)
        mappings = mapping_by_key.get(key, [])
        if not mappings:
            if key not in unmapped_seen:
                warn(warnings, "WARNING", feature_type, source_name, "Differential feature has no orthology mapping", species, feature_id)
                unmapped_seen.add(key)
            continue
        for mapping in mappings:
            orthogroup_id = mapping["orthogroup_id"]
            projected = dict(row)
            projected["orthogroup_id"] = orthogroup_id
            group_key = tuple([orthogroup_id] + [projected.get(field, "") for field in group_fields])
            grouped[group_key].append(projected)
            add_membership_to_entry(meta[group_key], feature_type, species, feature_id, status_by_key[key])

    output_rows = []
    pvalue_summary_warned = False
    for group_key in sorted(grouped):
        group_rows = grouped[group_key]
        entry = meta[group_key]
        out = orthogroup_meta_row(group_rows[0]["orthogroup_id"], entry)
        out["species"] = norm(group_rows[0].get("species"))
        for field in passthrough_fields:
            out[field] = aggregate_diff_field(group_rows, field, group_fields)
        if len(group_rows) > 1 and any(field in passthrough_fields for field in MIN_FIELDS):
            pvalue_summary_warned = True
        output_rows.append(out)

    if pvalue_summary_warned:
        warn(
            warnings,
            "WARNING",
            feature_type,
            source_name,
            "Orthogroup p_value/padj values use the minimum mapped-feature value as a pragmatic summary, not meta-analysis",
        )
    write_tsv(output_path, output_fields, output_rows)
    return len(rows), len(output_rows)


def ensure_requested_inputs(args, requested):
    missing = []
    if "rnaseq" in requested and (not args.rnaseq_counts or not os.path.exists(args.rnaseq_counts)):
        missing.append(f"RNA-seq count matrix not found: {args.rnaseq_counts}")
    if "atacseq" in requested and (not args.atacseq_counts or not os.path.exists(args.atacseq_counts)):
        missing.append(f"ATAC-seq count matrix not found: {args.atacseq_counts}")
    if missing:
        raise RuntimeError("; ".join(missing))


def project(args):
    requested = parse_requested(args.omics_types)
    if not requested:
        raise RuntimeError("No supported omics_types requested")
    ensure_requested_inputs(args, requested)
    os.makedirs(args.output_dir, exist_ok=True)

    warnings = []
    sample_species = sample_species_by_omics(args.omics_samplesheet)
    gene_mappings = load_orthology(args.orthologous_genes, "gene", warnings)
    re_mappings = load_orthology(args.orthologous_res, "regulatory_element", warnings)
    gene_by_key, gene_status = build_mapping_index(gene_mappings)
    re_by_key, re_status = build_mapping_index(re_mappings)
    write_tsv(
        os.path.join(args.output_dir, "feature_to_orthogroup_map.tsv"),
        FEATURE_MAP_FIELDS,
        feature_map_rows(
            gene_mappings + re_mappings,
            {"gene": gene_status, "regulatory_element": re_status},
        ),
    )

    count_stats = {}
    if "rnaseq" in requested:
        count_stats["rnaseq"] = project_count_matrix(
            args.rnaseq_counts,
            "gene",
            "rnaseq",
            gene_by_key,
            gene_status,
            sample_species,
            os.path.join(args.output_dir, "gene_orthogroup_counts.tsv"),
            warnings,
        )
    else:
        empty_count_output(os.path.join(args.output_dir, "gene_orthogroup_counts.tsv"))
    if "atacseq" in requested:
        count_stats["atacseq"] = project_count_matrix(
            args.atacseq_counts,
            "regulatory_element",
            "atacseq",
            re_by_key,
            re_status,
            sample_species,
            os.path.join(args.output_dir, "re_orthogroup_counts.tsv"),
            warnings,
        )
    else:
        empty_count_output(os.path.join(args.output_dir, "re_orthogroup_counts.tsv"))

    diff_stats = {}
    diff_stats["differential_expression"] = project_differential_table(
        args.differential_expression,
        "gene",
        gene_by_key,
        gene_status,
        os.path.join(args.output_dir, "differential_expression_orthogroups.tsv"),
        warnings,
        "differential_expression",
    )
    diff_stats["differential_accessibility"] = project_differential_table(
        args.differential_accessibility,
        "regulatory_element",
        re_by_key,
        re_status,
        os.path.join(args.output_dir, "differential_accessibility_orthogroups.tsv"),
        warnings,
        "differential_accessibility",
    )
    write_tsv(os.path.join(args.output_dir, "orthology_projection_warnings.tsv"), WARNING_FIELDS, warnings)

    warning_counts = Counter(row["severity"] for row in warnings)
    total_count_orthogroups = sum(projected for _, projected in count_stats.values())
    total_diff_orthogroups = sum(projected for _, projected in diff_stats.values())
    print(
        "CAME orthology projection summary: "
        f"count_orthogroups={total_count_orthogroups} differential_orthogroups={total_diff_orthogroups} "
        f"WARNING={warning_counts.get('WARNING', 0)}"
    )
    return 0


def parse_args():
    parser = argparse.ArgumentParser(description="Project CAME molecular features to orthogroups.")
    parser.add_argument("--orthologous_genes", required=True)
    parser.add_argument("--orthologous_res", required=True)
    parser.add_argument("--omics_samplesheet", required=True)
    parser.add_argument("--omics_types", default="rnaseq,atacseq")
    parser.add_argument("--rnaseq_counts", default="")
    parser.add_argument("--atacseq_counts", default="")
    parser.add_argument("--differential_expression", default="")
    parser.add_argument("--differential_accessibility", default="")
    parser.add_argument("--output_dir", default="results/orthology")
    return parser.parse_args()


def main():
    try:
        return project(parse_args())
    except Exception as exc:
        print(f"ERROR\tproject_features_to_orthogroups\t{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
