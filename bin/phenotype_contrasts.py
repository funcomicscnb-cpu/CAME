#!/usr/bin/env python3
"""Compute CAME phenotype index and component contrasts."""

import argparse
import math
import os
import sys
from collections import defaultdict

from phenotype_utils import (
    aggregate,
    component_name_for_row,
    format_value,
    load_profile,
    normalize_aggregation,
    parse_float,
    phenotype_index,
    profile_indexes,
    profile_components,
    profile_contrasts,
    read_table,
    replicate_id_for_row,
    stderr,
    write_tsv,
)


INDEX_FIELDS = [
    "contrast_name",
    "contrast_type",
    "species",
    "group_id",
    "baseline_label",
    "response_label",
    "difference",
    "fold_change",
    "log2_fold_change",
    "n_baseline",
    "n_response",
    "status",
    "message",
]

COMPONENT_FIELDS = ["trait"] + INDEX_FIELDS
INDEX_LONG_FIELDS = ["phenotype_index_name"] + INDEX_FIELDS


def text(value):
    return str(value if value is not None else "").strip()


def contrast_type(raw_type):
    ctype = text(raw_type)
    return "condition_contrast" if ctype == "treated_vs_control" else ctype


def require_label(value, field, contrast_name):
    label = text(value)
    if not label:
        raise RuntimeError(f"Contrast {contrast_name} is missing required field: {field}")
    return label


def validate_label(label, available, label_type, contrast_name):
    if label and label not in available:
        raise RuntimeError(f"Contrast {contrast_name} references missing {label_type}: {label}")


def available_sets(rows):
    return (
        {row.get("species", "") for row in rows if row.get("species", "")},
        {row.get("condition", "") for row in rows if row.get("condition", "")},
        {row.get("timepoint", "") for row in rows if row.get("timepoint", "")},
    )


def contrast_pairs(contrast, species, all_conditions, all_timepoints, observed_pairs):
    name = require_label(contrast.get("name"), "name", "unnamed")
    ctype = contrast_type(contrast.get("type"))
    pairs = []

    if ctype == "baseline_vs_response":
        bc = require_label(contrast.get("baseline_condition"), "baseline_condition", name)
        rc = require_label(contrast.get("response_condition"), "response_condition", name)
        bt = require_label(contrast.get("baseline_timepoint"), "baseline_timepoint", name)
        rt = require_label(contrast.get("response_timepoint"), "response_timepoint", name)
        validate_label(bc, all_conditions, "condition", name)
        validate_label(rc, all_conditions, "condition", name)
        validate_label(bt, all_timepoints, "timepoint", name)
        validate_label(rt, all_timepoints, "timepoint", name)
        pairs.append(((bc, bt), (rc, rt)))
    elif ctype == "condition_contrast":
        bc = text(contrast.get("baseline_condition")) or require_label(contrast.get("control_condition"), "control_condition", name)
        rc = text(contrast.get("response_condition")) or require_label(contrast.get("treated_condition"), "treated_condition", name)
        validate_label(bc, all_conditions, "condition", name)
        validate_label(rc, all_conditions, "condition", name)
        bt = text(contrast.get("baseline_timepoint"))
        rt = text(contrast.get("response_timepoint"))
        if bt or rt:
            bt = require_label(bt, "baseline_timepoint", name)
            rt = require_label(rt, "response_timepoint", name)
            validate_label(bt, all_timepoints, "timepoint", name)
            validate_label(rt, all_timepoints, "timepoint", name)
            pairs.append(((bc, bt), (rc, rt)))
        else:
            shared = sorted(
                timepoint
                for timepoint in all_timepoints
                if (species, bc, timepoint) in observed_pairs and (species, rc, timepoint) in observed_pairs
            )
            for timepoint in shared:
                pairs.append(((bc, timepoint), (rc, timepoint)))
            if not pairs:
                pairs.append(((bc, ""), (rc, "")))
    elif ctype == "timepoint_contrast":
        bt = text(contrast.get("from_timepoint")) or require_label(contrast.get("baseline_timepoint"), "baseline_timepoint", name)
        rt = text(contrast.get("to_timepoint")) or require_label(contrast.get("response_timepoint"), "response_timepoint", name)
        validate_label(bt, all_timepoints, "timepoint", name)
        validate_label(rt, all_timepoints, "timepoint", name)
        bc = text(contrast.get("baseline_condition"))
        rc = text(contrast.get("response_condition"))
        if bc or rc:
            bc = require_label(bc, "baseline_condition", name)
            rc = require_label(rc, "response_condition", name)
            validate_label(bc, all_conditions, "condition", name)
            validate_label(rc, all_conditions, "condition", name)
            pairs.append(((bc, bt), (rc, rt)))
        else:
            shared = sorted(
                condition
                for condition in all_conditions
                if (species, condition, bt) in observed_pairs and (species, condition, rt) in observed_pairs
            )
            for condition in shared:
                pairs.append(((condition, bt), (condition, rt)))
            if not pairs:
                pairs.append((("", bt), ("", rt)))
    else:
        raise RuntimeError(f"Unsupported contrast type: {ctype}")

    return ctype, pairs


def calculate_values(baseline, response):
    if baseline is None or response is None:
        return None, None, None
    difference = response - baseline
    fold = None if baseline == 0 else response / baseline
    log2_fold = math.log2(fold) if fold is not None and fold > 0 and baseline > 0 and response > 0 else None
    return difference, fold, log2_fold


def label(condition, timepoint):
    if condition and timepoint:
        return f"{condition}|{timepoint}"
    return condition or timepoint


def contrast_row(contrast, ctype, species, baseline_key, response_key, baseline_record, response_record):
    baseline_value = baseline_record.get("value") if baseline_record else None
    response_value = response_record.get("value") if response_record else None
    difference, fold, log2_fold = calculate_values(baseline_value, response_value)
    status = "OK" if difference is not None else "WARNING"
    message = "" if difference is not None else "Missing baseline or response value for species-specific contrast"
    baseline_label = label(*baseline_key)
    response_label = label(*response_key)
    return {
        "contrast_name": text(contrast.get("name")),
        "contrast_type": ctype,
        "species": species,
        "group_id": f"{species}|{baseline_label}_vs_{response_label}",
        "baseline_label": baseline_label,
        "response_label": response_label,
        "difference": format_value(difference),
        "fold_change": format_value(fold),
        "log2_fold_change": format_value(log2_fold),
        "n_baseline": str(baseline_record.get("n", 0) if baseline_record else 0),
        "n_response": str(response_record.get("n", 0) if response_record else 0),
        "status": status,
        "message": message,
    }


def read_index_groups(path):
    _, rows = read_table(path)
    values = {}
    observed = set()
    for row in rows:
        species = row.get("species", "")
        condition = row.get("condition", "")
        timepoint = row.get("timepoint", "")
        observed.add((species, condition, timepoint))
        value = parse_float(row.get("index_value"))
        n = parse_float(row.get("replicate_n")) or 0
        values[(species, condition, timepoint)] = {"value": value, "n": int(n)}
    return values, observed


def read_indexes_by_group(path):
    fields, rows = read_table(path)
    if "phenotype_index_name" not in fields:
        return {}, set()
    values = {}
    observed = set()
    for row in rows:
        index_name = row.get("phenotype_index_name", "")
        species = row.get("species", "")
        condition = row.get("condition", "")
        timepoint = row.get("timepoint", "")
        observed.add((index_name, species, condition, timepoint))
        value = parse_float(row.get("index_value"))
        n = parse_float(row.get("replicate_n")) or 0
        values[(index_name, species, condition, timepoint)] = {"value": value, "n": int(n)}
    return values, observed


def component_groups(rows, components, aggregation):
    component_set = set(components)
    by_unit = defaultdict(list)
    for row in rows:
        component = component_name_for_row(row, component_set)
        value = parse_float(row.get("value"))
        if component and value is not None:
            key = (component, replicate_id_for_row(row))
            by_unit[key].append((row, value))

    by_group = defaultdict(list)
    for (component, _), items in by_unit.items():
        value = aggregate([value for _, value in items], aggregation)
        if value is None:
            continue
        first = items[0][0]
        key = (component, first.get("species", ""), first.get("condition", ""), first.get("timepoint", ""))
        by_group[key].append(value)

    values = {}
    observed = set()
    for (component, species, condition, timepoint), group_values in by_group.items():
        observed.add((species, condition, timepoint))
        values[(component, species, condition, timepoint)] = {
            "value": aggregate(group_values, aggregation),
            "n": len(group_values),
        }
    return values, observed


def compute_index_contrasts(index_values, observed_pairs, species_values, conditions, timepoints, contrasts):
    output = []
    for contrast in contrasts:
        for species in sorted(species_values):
            ctype, pairs = contrast_pairs(contrast, species, conditions, timepoints, observed_pairs)
            for baseline, response in pairs:
                baseline_record = index_values.get((species, baseline[0], baseline[1]))
                response_record = index_values.get((species, response[0], response[1]))
                output.append(contrast_row(contrast, ctype, species, baseline, response, baseline_record, response_record))
    return output


def compute_component_contrasts(component_values, observed_pairs, species_values, conditions, timepoints, contrasts, components):
    output = []
    for component in components:
        for contrast in contrasts:
            for species in sorted(species_values):
                ctype, pairs = contrast_pairs(contrast, species, conditions, timepoints, observed_pairs)
                for baseline, response in pairs:
                    baseline_record = component_values.get((component, species, baseline[0], baseline[1]))
                    response_record = component_values.get((component, species, response[0], response[1]))
                    row = contrast_row(contrast, ctype, species, baseline, response, baseline_record, response_record)
                    row["trait"] = component
                    output.append(row)
    return output


def compute_long_index_contrasts(indexes_values, indexes_observed, species_values, conditions, timepoints, profile):
    output = []
    for index_def in profile_indexes(profile):
        index_name = text(index_def.get("name"))
        if not index_name:
            continue
        index_values = {
            (species, condition, timepoint): record
            for (name, species, condition, timepoint), record in indexes_values.items()
            if name == index_name
        }
        observed_pairs = {
            (species, condition, timepoint)
            for name, species, condition, timepoint in indexes_observed
            if name == index_name
        }
        contrasts = index_def.get("contrasts")
        if isinstance(contrasts, dict):
            contrasts = [contrasts]
        if not isinstance(contrasts, list):
            continue
        for row in compute_index_contrasts(index_values, observed_pairs, species_values, conditions, timepoints, contrasts):
            out = {"phenotype_index_name": index_name}
            out.update(row)
            output.append(out)
    return output


def parse_args():
    parser = argparse.ArgumentParser(description="Calculate CAME phenotype contrasts.")
    parser.add_argument("--phenotype_table", required=True)
    parser.add_argument("--study_profile", required=True)
    parser.add_argument("--index_by_group", required=True)
    parser.add_argument("--indexes_by_group", default="")
    parser.add_argument("--index_output", default="results/phenotype/contrasts/phenotype_index_contrasts.tsv")
    parser.add_argument("--component_output", default="results/phenotype/contrasts/component_trait_contrasts.tsv")
    parser.add_argument("--index_long_output", default="")
    return parser.parse_args()


def main():
    args = parse_args()
    if not args.index_long_output:
        args.index_long_output = os.path.join(os.path.dirname(args.index_output) or ".", "phenotype_index_contrasts_long.tsv")
    try:
        _, phenotype_rows = read_table(args.phenotype_table)
        profile = load_profile(args.study_profile)
        index = phenotype_index(profile)
        components = profile_components(profile)
        aggregation = normalize_aggregation(index.get("aggregation"))
        contrasts = profile_contrasts(profile)
        species_values, conditions, timepoints = available_sets(phenotype_rows)
        index_values, index_observed = read_index_groups(args.index_by_group)
        component_values, component_observed = component_groups(phenotype_rows, components, aggregation)
        observed_pairs = index_observed | component_observed

        index_rows = compute_index_contrasts(index_values, observed_pairs, species_values, conditions, timepoints, contrasts)
        component_rows = compute_component_contrasts(component_values, observed_pairs, species_values, conditions, timepoints, contrasts, components)
        if args.indexes_by_group:
            indexes_values, indexes_observed = read_indexes_by_group(args.indexes_by_group)
            index_long_rows = compute_long_index_contrasts(indexes_values, indexes_observed, species_values, conditions, timepoints, profile)
        else:
            index_name = text(index.get("name"))
            index_long_rows = [{"phenotype_index_name": index_name, **row} for row in index_rows]
    except Exception as exc:
        stderr(f"ERROR\tphenotype_contrasts\t{exc}")
        return 1

    write_tsv(args.index_output, INDEX_FIELDS, index_rows)
    write_tsv(args.component_output, COMPONENT_FIELDS, component_rows)
    write_tsv(args.index_long_output, INDEX_LONG_FIELDS, index_long_rows)
    warnings = sum(1 for row in index_rows + component_rows if row["status"] == "WARNING")
    print(f"CAME phenotype contrast summary: ERROR=0 WARNING={warnings} index_rows={len(index_rows)} component_rows={len(component_rows)} index_long_rows={len(index_long_rows)}")
    for row in index_rows + component_rows:
        if row["status"] == "WARNING":
            stderr(f"WARNING\t{row['contrast_name']}\t{row['species']}\t{row['message']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
