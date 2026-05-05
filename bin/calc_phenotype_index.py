#!/usr/bin/env python3
"""Calculate profile-defined phenotype indexes from normalized CAME phenotype data."""

import argparse
import os
import sys
from collections import defaultdict

from phenotype_utils import (
    GROUP_KEY,
    REPLICATE_KEY,
    aggregate,
    as_list,
    component_name_for_row,
    evaluate_formula_tree,
    format_value,
    load_profile,
    norm,
    normalize_aggregation,
    parse_float,
    phenotype_index,
    primary_index,
    profile_indexes,
    profile_qc_policy,
    profile_components,
    profile_id,
    read_table,
    replicate_id_for_row,
    stderr,
    validate_formula_tree,
    write_tsv,
    FormulaDivisionByZero,
    FormulaError,
)


SAMPLE_FIELDS = [
    "profile_id",
    "phenotype_index_name",
    "species",
    "condition",
    "timepoint",
    "sample_id",
    "individual_id",
    "replicate_id",
    "replicate_n",
    "index_value",
    "status",
    "message",
    "source_sample_ids",
]

GROUP_FIELDS = [
    "profile_id",
    "phenotype_index_name",
    "species",
    "condition",
    "timepoint",
    "replicate_n",
    "index_value",
    "status",
    "message",
    "source_sample_ids",
]

MANIFEST_FIELDS = [
    "profile_id",
    "profile_version",
    "normalization",
    "primary_index_name",
    "index_name",
    "is_primary",
    "formula",
    "aggregation",
    "contrast_count",
    "contrast_names",
    "qc_min_replicates_per_group",
    "qc_fail_on_missing_components",
    "qc_fail_on_sparse_groups",
    "qc_fail_on_unit_inconsistency",
    "sample_output",
    "group_output",
]


def unit_context(rows):
    first = rows[0]
    return {
        "species": first.get("species", ""),
        "condition": first.get("condition", ""),
        "timepoint": first.get("timepoint", ""),
        "individual_id": first.get("individual_id", ""),
        "replicate_id": first.get("replicate_id", ""),
    }


def source_sample_ids(rows):
    return ",".join(sorted({row.get("sample_id", "") for row in rows if row.get("sample_id", "")}))


def stable_sample_id(context):
    return "|".join(context[field] for field in ["species", "individual_id", "replicate_id", "condition", "timepoint"])


def calculate_samples(rows, profile, sample_output=None):
    index = phenotype_index(profile)
    components = profile_components(profile)
    if not components:
        raise RuntimeError("phenotype_index.components must not be empty")
    formula = str(index.get("formula", "")).strip()
    if not formula:
        raise RuntimeError("phenotype_index.formula must not be empty")
    tree, names = validate_formula_tree(formula, components)
    for component in components:
        if component not in names:
            stderr(f"WARNING\tphenotype_index\tComponent is listed but not used in formula: {component}")

    aggregation = normalize_aggregation(index.get("aggregation"))
    component_set = set(components)
    profile_name = str(index.get("name", "")).strip()
    pid = profile_id(profile)

    grouped = defaultdict(list)
    for row in rows:
        component = component_name_for_row(row, component_set)
        if component:
            grouped[replicate_id_for_row(row)].append(row)

    sample_rows = []
    fatal_errors = []

    for _, unit_rows in sorted(grouped.items()):
        context = unit_context(unit_rows)
        values_by_component = defaultdict(list)
        for row in unit_rows:
            component = component_name_for_row(row, component_set)
            value = parse_float(row.get("value"))
            if component and value is not None:
                values_by_component[component].append(value)

        missing = [component for component in components if component not in values_by_component]
        status = "OK"
        message = ""
        index_value = None

        if missing:
            status = "ERROR"
            message = "Missing required components: " + ",".join(missing)
            fatal_errors.append(f"{stable_sample_id(context)} {message}")
        else:
            component_values = {
                component: aggregate(values_by_component[component], aggregation)
                for component in components
            }
            try:
                index_value = evaluate_formula_tree(tree, component_values)
            except FormulaDivisionByZero as exc:
                status = "WARNING"
                message = str(exc)
            except FormulaError as exc:
                status = "ERROR"
                message = str(exc)
                fatal_errors.append(f"{stable_sample_id(context)} {message}")

        sample_rows.append(
            {
                "profile_id": pid,
                "phenotype_index_name": profile_name,
                "species": context["species"],
                "condition": context["condition"],
                "timepoint": context["timepoint"],
                "sample_id": stable_sample_id(context),
                "individual_id": context["individual_id"],
                "replicate_id": context["replicate_id"],
                "replicate_n": "1",
                "index_value": format_value(index_value),
                "status": status,
                "message": message,
                "source_sample_ids": source_sample_ids(unit_rows),
            }
        )

    if not sample_rows:
        fatal_errors.append("No phenotype rows matched profile components")

    if sample_output:
        write_tsv(sample_output, SAMPLE_FIELDS, sample_rows)
    return sample_rows, aggregation, fatal_errors


def calculate_groups(sample_rows, profile, aggregation, group_output=None):
    index = phenotype_index(profile)
    profile_name = str(index.get("name", "")).strip()
    pid = profile_id(profile)
    grouped = defaultdict(list)
    for row in sample_rows:
        key = (row["species"], row["condition"], row["timepoint"])
        grouped[key].append(row)

    group_rows = []
    for (species, condition, timepoint), rows in sorted(grouped.items()):
        values = []
        for row in rows:
            value = parse_float(row.get("index_value"))
            if value is not None and row.get("status") != "ERROR":
                values.append(value)
        index_value = aggregate(values, aggregation)
        status = "OK" if index_value is not None else "WARNING"
        message = "" if index_value is not None else "No non-missing replicate index values"
        group_rows.append(
            {
                "profile_id": pid,
                "phenotype_index_name": profile_name,
                "species": species,
                "condition": condition,
                "timepoint": timepoint,
                "replicate_n": str(len(values)),
                "index_value": format_value(index_value),
                "status": status,
                "message": message,
                "source_sample_ids": ",".join(sorted(row["sample_id"] for row in rows)),
            }
        )

    if group_output:
        write_tsv(group_output, GROUP_FIELDS, group_rows)
    return group_rows


def manifest_row(profile, index_def, primary, qc_policy, normalization, sample_output, group_output):
    study = profile.get("study") if isinstance(profile.get("study"), dict) else {}
    contrasts = [contrast for contrast in as_list(index_def.get("contrasts")) if isinstance(contrast, dict)]
    is_primary = index_def is primary
    return {
        "profile_id": profile_id(profile),
        "profile_version": norm(study.get("version")),
        "normalization": normalization,
        "primary_index_name": norm(primary.get("name")),
        "index_name": norm(index_def.get("name")),
        "is_primary": str(is_primary).lower(),
        "formula": norm(index_def.get("formula")),
        "aggregation": norm(index_def.get("aggregation")),
        "contrast_count": str(len(contrasts)),
        "contrast_names": ",".join(norm(contrast.get("name")) for contrast in contrasts if norm(contrast.get("name"))),
        "qc_min_replicates_per_group": str(qc_policy["min_replicates_per_group"]),
        "qc_fail_on_missing_components": str(qc_policy["fail_on_missing_components"]).lower(),
        "qc_fail_on_sparse_groups": str(qc_policy["fail_on_sparse_groups"]).lower(),
        "qc_fail_on_unit_inconsistency": str(qc_policy["fail_on_unit_inconsistency"]).lower(),
        "sample_output": sample_output,
        "group_output": group_output,
    }


def parse_args():
    parser = argparse.ArgumentParser(description="Calculate CAME phenotype index values.")
    parser.add_argument("--input", required=True)
    parser.add_argument("--study_profile", required=True)
    parser.add_argument("--sample_output", default="results/phenotype/index/phenotype_index_by_sample.tsv")
    parser.add_argument("--group_output", default="results/phenotype/index/phenotype_index_by_group.tsv")
    parser.add_argument("--indexes_sample_output", default="")
    parser.add_argument("--indexes_group_output", default="")
    parser.add_argument("--manifest_output", default="")
    parser.add_argument("--normalization", default="")
    return parser.parse_args()


def main():
    args = parse_args()
    if not args.indexes_sample_output:
        args.indexes_sample_output = os.path.join(os.path.dirname(args.sample_output) or ".", "phenotype_indexes_by_sample.tsv")
    if not args.indexes_group_output:
        args.indexes_group_output = os.path.join(os.path.dirname(args.group_output) or ".", "phenotype_indexes_by_group.tsv")
    if not args.manifest_output:
        args.manifest_output = os.path.join(os.path.dirname(args.group_output) or ".", "phenotype_processing_manifest.tsv")
    all_sample_rows = []
    all_group_rows = []
    manifest_rows = []
    fatal_errors = []
    try:
        _, rows = read_table(args.input)
        profile = load_profile(args.study_profile)
        indexes = profile_indexes(profile)
        primary = primary_index(profile)
        qc_policy = profile_qc_policy(profile)
        primary_sample_rows = []
        primary_group_rows = []
        for index_def in indexes:
            single_profile = dict(profile)
            single_profile["phenotype_index"] = index_def
            single_profile.pop("phenotype_indexes", None)
            sample_rows_for_index, aggregation, errors = calculate_samples(rows, single_profile)
            group_rows_for_index = calculate_groups(sample_rows_for_index, single_profile, aggregation)
            all_sample_rows.extend(sample_rows_for_index)
            all_group_rows.extend(group_rows_for_index)
            fatal_errors.extend(errors)
            if index_def is primary:
                primary_sample_rows = sample_rows_for_index
                primary_group_rows = group_rows_for_index
            manifest_rows.append(
                manifest_row(
                    profile,
                    index_def,
                    primary,
                    qc_policy,
                    args.normalization,
                    args.indexes_sample_output,
                    args.indexes_group_output,
                )
            )
        write_tsv(args.indexes_sample_output, SAMPLE_FIELDS, all_sample_rows)
        write_tsv(args.indexes_group_output, GROUP_FIELDS, all_group_rows)
        write_tsv(args.sample_output, SAMPLE_FIELDS, primary_sample_rows)
        write_tsv(args.group_output, GROUP_FIELDS, primary_group_rows)
        write_tsv(args.manifest_output, MANIFEST_FIELDS, manifest_rows)
    except Exception as exc:
        stderr(f"ERROR\tphenotype_index\t{exc}")
        return 1

    warnings = sum(1 for row in all_sample_rows + all_group_rows if row.get("status") == "WARNING")
    errors = sum(1 for row in all_sample_rows + all_group_rows if row.get("status") == "ERROR")
    print(f"CAME phenotype index summary: ERROR={errors} WARNING={warnings} samples={len(all_sample_rows)} groups={len(all_group_rows)} indexes={len(manifest_rows)}")
    for row in all_sample_rows + all_group_rows:
        if row.get("status") in {"ERROR", "WARNING"}:
            stderr(f"{row['status']}\t{row.get('sample_id', row.get('species', ''))}\t{row.get('message', '')}")
    for error in fatal_errors[:20]:
        stderr(f"ERROR\tphenotype_index\t{error}")
    return 1 if fatal_errors else 0


if __name__ == "__main__":
    sys.exit(main())
