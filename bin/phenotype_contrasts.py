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
    profile_design,
    profile_indexes,
    profile_components,
    profile_contrasts,
    read_table,
    replicate_id_for_row,
    stderr,
    validate_design_fields,
    write_tsv,
)


LEGACY_INDEX_FIELDS = [
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

INDEX_FIELDS = [
    "contrast_name",
    "contrast_type",
    "species",
    "group_id",
    "group_strata_fields",
    "group_strata_values",
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

LEGACY_COMPONENT_FIELDS = ["trait"] + LEGACY_INDEX_FIELDS
COMPONENT_FIELDS = ["trait"] + INDEX_FIELDS
INDEX_LONG_FIELDS = ["phenotype_index_name"] + INDEX_FIELDS
AUDIT_FIELDS = [
    "contrast_name",
    "species",
    "strata_fields",
    "strata_values",
    "baseline_group_id",
    "response_group_id",
    "status",
    "message",
]


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


def available_group_dimensions(rows, group_key):
    dims = {field: set() for field in group_key}
    for row in rows:
        for field in group_key:
            value = row.get(field, "")
            if value:
                dims[field].add(value)
    return dims


def validate_contrast_labels(contrast, ctype, dims, name):
    conditions = dims.get("condition", set())
    timepoints = dims.get("timepoint", set())
    for field in ["baseline_condition", "response_condition", "control_condition", "treated_condition"]:
        validate_label(text(contrast.get(field)), conditions, "condition", name)
    for field in ["baseline_timepoint", "response_timepoint", "from_timepoint", "to_timepoint"]:
        validate_label(text(contrast.get(field)), timepoints, "timepoint", name)


def contrast_axis_values(contrast):
    name = require_label(contrast.get("name"), "name", "unnamed")
    ctype = contrast_type(contrast.get("type"))
    if ctype == "baseline_vs_response":
        return ctype, {
            "condition": require_label(contrast.get("baseline_condition"), "baseline_condition", name),
            "timepoint": require_label(contrast.get("baseline_timepoint"), "baseline_timepoint", name),
        }, {
            "condition": require_label(contrast.get("response_condition"), "response_condition", name),
            "timepoint": require_label(contrast.get("response_timepoint"), "response_timepoint", name),
        }
    if ctype == "condition_contrast":
        bc = text(contrast.get("baseline_condition")) or require_label(contrast.get("control_condition"), "control_condition", name)
        rc = text(contrast.get("response_condition")) or require_label(contrast.get("treated_condition"), "treated_condition", name)
        baseline = {"condition": bc}
        response = {"condition": rc}
        bt = text(contrast.get("baseline_timepoint"))
        rt = text(contrast.get("response_timepoint"))
        if bt or rt:
            baseline["timepoint"] = require_label(bt, "baseline_timepoint", name)
            response["timepoint"] = require_label(rt, "response_timepoint", name)
        return ctype, baseline, response
    if ctype == "timepoint_contrast":
        bt = text(contrast.get("from_timepoint")) or require_label(contrast.get("baseline_timepoint"), "baseline_timepoint", name)
        rt = text(contrast.get("to_timepoint")) or require_label(contrast.get("response_timepoint"), "response_timepoint", name)
        baseline = {"timepoint": bt}
        response = {"timepoint": rt}
        bc = text(contrast.get("baseline_condition"))
        rc = text(contrast.get("response_condition"))
        if bc or rc:
            baseline["condition"] = require_label(bc, "baseline_condition", name)
            response["condition"] = require_label(rc, "response_condition", name)
        return ctype, baseline, response
    raise RuntimeError(f"Unsupported contrast type: {ctype}")


def calculate_values(baseline, response):
    if baseline is None or response is None:
        return None, None, None
    difference = response - baseline
    fold = None if baseline == 0 else response / baseline
    log2_fold = math.log2(fold) if fold is not None and fold > 0 and baseline > 0 and response > 0 else None
    return difference, fold, log2_fold


def label_from_values(values):
    condition = values.get("condition", "")
    timepoint = values.get("timepoint", "")
    if condition and timepoint:
        return f"{condition}|{timepoint}"
    return condition or timepoint or "|".join(values[field] for field in sorted(values) if values[field])


def group_values_dict(group_key, key):
    return dict(zip(group_key, key))


def group_id_for_key(key):
    return "|".join(key)


def split_group_field(value):
    value = text(value)
    return value.split("|") if value else []


def group_key_from_row(row, expected_group_key):
    stored_key = split_group_field(row.get("phenotype_group_key"))
    stored_values = split_group_field(row.get("phenotype_group_id"))
    if stored_key:
        if len(stored_key) != len(stored_values):
            raise RuntimeError("phenotype group table has mismatched phenotype_group_key and phenotype_group_id fields")
        if set(stored_key) != set(expected_group_key):
            table_key = "|".join(stored_key)
            profile_key = "|".join(expected_group_key)
            raise RuntimeError(
                "phenotype group table was generated with a different phenotype_design.group_key; "
                f"table={table_key} profile={profile_key}"
            )
        values_by_field = dict(zip(stored_key, stored_values))
        return tuple(values_by_field.get(field, "") for field in expected_group_key)
    return tuple(row.get(field, "") for field in expected_group_key)


def validate_group_table_fields(fields, group_key):
    if "phenotype_group_key" in fields and "phenotype_group_id" in fields:
        return
    missing = [field for field in group_key if field not in fields]
    if missing:
        raise RuntimeError(
            "phenotype group table lacks phenotype_group_key metadata and required group column(s): "
            + ",".join(missing)
        )


def stratified_pairs(contrast, dims, observed, group_key):
    name = require_label(contrast.get("name"), "name", "unnamed")
    ctype, baseline_axes, response_axes = contrast_axis_values(contrast)
    axis_fields = set(baseline_axes) | set(response_axes)
    missing_axes = sorted(field for field in axis_fields if field not in group_key)
    if missing_axes:
        raise RuntimeError(
            f"Contrast {name} requires group_key field(s): " + ",".join(missing_axes)
        )
    validate_contrast_labels(contrast, ctype, dims, name)
    strata_fields = [field for field in group_key if field not in axis_fields and field != "species"]
    species_idx = group_key.index("species")
    combos = sorted(
        {
            (key[species_idx], tuple(group_values_dict(group_key, key).get(field, "") for field in strata_fields))
            for key in observed
        }
    )
    for species, strata_values in combos:
        base_values = {"species": species}
        response_values = {"species": species}
        base_values.update(dict(zip(strata_fields, strata_values)))
        response_values.update(dict(zip(strata_fields, strata_values)))
        base_values.update(baseline_axes)
        response_values.update(response_axes)
        baseline_key = tuple(base_values.get(field, "") for field in group_key)
        response_key = tuple(response_values.get(field, "") for field in group_key)
        baseline_present = baseline_key in observed
        response_present = response_key in observed
        if not baseline_present and not response_present:
            continue
        yield {
            "contrast_type": ctype,
            "species": species,
            "strata_fields": strata_fields,
            "strata_values": strata_values,
            "baseline_key": baseline_key,
            "response_key": response_key,
            "baseline_axes": baseline_axes,
            "response_axes": response_axes,
            "baseline_present": baseline_present,
            "response_present": response_present,
        }


def audit_row(contrast, pair):
    if pair["baseline_present"] and pair["response_present"]:
        status = "PAIRED"
        message = ""
    elif pair["baseline_present"]:
        status = "UNPAIRED_BASELINE"
        message = "Baseline group has no matching response group within the same strata"
    else:
        status = "UNPAIRED_RESPONSE"
        message = "Response group has no matching baseline group within the same strata"
    return {
        "contrast_name": text(contrast.get("name")),
        "species": pair["species"],
        "strata_fields": "|".join(pair["strata_fields"]),
        "strata_values": "|".join(pair["strata_values"]),
        "baseline_group_id": group_id_for_key(pair["baseline_key"]) if pair["baseline_present"] else "",
        "response_group_id": group_id_for_key(pair["response_key"]) if pair["response_present"] else "",
        "status": status,
        "message": message,
    }


def contrast_row(contrast, pair, baseline_record, response_record):
    baseline_value = baseline_record.get("value") if baseline_record else None
    response_value = response_record.get("value") if response_record else None
    difference, fold, log2_fold = calculate_values(baseline_value, response_value)
    status = "OK" if difference is not None else "WARNING"
    message = "" if difference is not None else "Missing baseline or response value for species-specific contrast"
    baseline_label = label_from_values(pair["baseline_axes"])
    response_label = label_from_values(pair["response_axes"])
    strata_values = "|".join(pair["strata_values"])
    group_id_prefix = f"{pair['species']}|"
    if strata_values:
        group_id_prefix += f"{strata_values}|"
    return {
        "contrast_name": text(contrast.get("name")),
        "contrast_type": pair["contrast_type"],
        "species": pair["species"],
        "group_id": f"{group_id_prefix}{baseline_label}_vs_{response_label}",
        "group_strata_fields": "|".join(pair["strata_fields"]),
        "group_strata_values": strata_values,
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


def read_index_groups(path, group_key):
    fields, rows = read_table(path)
    validate_group_table_fields(fields, group_key)
    values = {}
    observed = set()
    for row in rows:
        key = group_key_from_row(row, group_key)
        observed.add(key)
        value = parse_float(row.get("index_value"))
        n = parse_float(row.get("replicate_n")) or 0
        values[key] = {"value": value, "n": int(n), "phenotype_group_id": row.get("phenotype_group_id", group_id_for_key(key))}
    return values, observed


def read_indexes_by_group(path, group_key):
    fields, rows = read_table(path)
    if "phenotype_index_name" not in fields:
        return {}, set()
    validate_group_table_fields(fields, group_key)
    values = {}
    observed = set()
    for row in rows:
        index_name = row.get("phenotype_index_name", "")
        key = group_key_from_row(row, group_key)
        observed.add((index_name, *key))
        value = parse_float(row.get("index_value"))
        n = parse_float(row.get("replicate_n")) or 0
        values[(index_name, *key)] = {"value": value, "n": int(n), "phenotype_group_id": row.get("phenotype_group_id", group_id_for_key(key))}
    return values, observed


def component_groups(rows, components, aggregation, replicate_key=None, group_key=None):
    group_key = group_key or ["species", "condition", "timepoint"]
    component_set = set(components)
    by_unit = defaultdict(list)
    for row in rows:
        component = component_name_for_row(row, component_set)
        value = parse_float(row.get("value"))
        if component and value is not None:
            key = (component, replicate_id_for_row(row, replicate_key=replicate_key))
            by_unit[key].append((row, value))

    by_group = defaultdict(list)
    for (component, _), items in by_unit.items():
        value = aggregate([value for _, value in items], aggregation)
        if value is None:
            continue
        first = items[0][0]
        key = (component, *(first.get(field, "") for field in group_key))
        by_group[key].append(value)

    values = {}
    observed = set()
    for key, grouped_values in by_group.items():
        component = key[0]
        group_tuple = key[1:]
        observed.add(group_tuple)
        values[(component, *group_tuple)] = {
            "value": aggregate(grouped_values, aggregation),
            "n": len(grouped_values),
        }
    return values, observed


def compute_index_contrasts(index_values, observed_pairs, dims, contrasts, group_key):
    output = []
    audit = []
    for contrast in contrasts:
        for pair in stratified_pairs(contrast, dims, observed_pairs, group_key):
            audit.append(audit_row(contrast, pair))
            if pair["baseline_present"] and pair["response_present"]:
                baseline_record = index_values.get(pair["baseline_key"])
                response_record = index_values.get(pair["response_key"])
                output.append(contrast_row(contrast, pair, baseline_record, response_record))
    return output, audit


def compute_component_contrasts(component_values, observed_pairs, dims, contrasts, components, group_key):
    output = []
    for component in components:
        for contrast in contrasts:
            for pair in stratified_pairs(contrast, dims, observed_pairs, group_key):
                if pair["baseline_present"] and pair["response_present"]:
                    baseline_record = component_values.get((component, *pair["baseline_key"]))
                    response_record = component_values.get((component, *pair["response_key"]))
                    row = contrast_row(contrast, pair, baseline_record, response_record)
                    row["trait"] = component
                    output.append(row)
    return output


def compute_long_index_contrasts(indexes_values, indexes_observed, dims, profile, group_key):
    output = []
    for index_def in profile_indexes(profile):
        index_name = text(index_def.get("name"))
        if not index_name:
            continue
        index_values = {
            key[1:]: record
            for key, record in indexes_values.items()
            for name in [key[0]]
            if name == index_name
        }
        observed_pairs = {
            key[1:]
            for key in indexes_observed
            for name in [key[0]]
            if name == index_name
        }
        contrasts = index_def.get("contrasts")
        if isinstance(contrasts, dict):
            contrasts = [contrasts]
        if not isinstance(contrasts, list):
            continue
        rows, _ = compute_index_contrasts(index_values, observed_pairs, dims, contrasts, group_key)
        for row in rows:
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
    parser.add_argument("--contrast_audit", default="")
    return parser.parse_args()


def main():
    args = parse_args()
    if not args.index_long_output:
        args.index_long_output = os.path.join(os.path.dirname(args.index_output) or ".", "phenotype_index_contrasts_long.tsv")
    if not args.contrast_audit:
        args.contrast_audit = os.path.join(os.path.dirname(args.index_output) or ".", "phenotype_contrast_pairs.tsv")
    try:
        phenotype_fields, phenotype_rows = read_table(args.phenotype_table)
        profile = load_profile(args.study_profile)
        design = profile_design(profile)
        validate_design_fields(phenotype_fields, design)
        group_key = design["group_key"]
        index = phenotype_index(profile)
        components = profile_components(profile)
        aggregation = normalize_aggregation(index.get("aggregation"))
        contrasts = profile_contrasts(profile)
        dims = available_group_dimensions(phenotype_rows, group_key)
        if args.indexes_by_group:
            indexes_values, indexes_observed = read_indexes_by_group(args.indexes_by_group, group_key)
            primary_name = text(index.get("name"))
            index_values = {key[1:]: record for key, record in indexes_values.items() if key[0] == primary_name}
            index_observed = {key[1:] for key in indexes_observed if key[0] == primary_name}
        else:
            index_values, index_observed = read_index_groups(args.index_by_group, group_key)
            indexes_values, indexes_observed = {}, set()
        component_values, component_observed = component_groups(
            phenotype_rows,
            components,
            aggregation,
            replicate_key=design["replicate_key"],
            group_key=group_key,
        )
        observed_pairs = index_observed | component_observed

        index_rows, audit_rows = compute_index_contrasts(index_values, observed_pairs, dims, contrasts, group_key)
        component_rows = compute_component_contrasts(component_values, observed_pairs, dims, contrasts, components, group_key)
        if args.indexes_by_group:
            index_long_rows = compute_long_index_contrasts(indexes_values, indexes_observed, dims, profile, group_key)
        else:
            index_name = text(index.get("name"))
            index_long_rows = [{"phenotype_index_name": index_name, **row} for row in index_rows]
    except Exception as exc:
        stderr(f"ERROR\tphenotype_contrasts\t{exc}")
        return 1

    write_tsv(args.index_output, LEGACY_INDEX_FIELDS, index_rows)
    write_tsv(args.component_output, LEGACY_COMPONENT_FIELDS, component_rows)
    write_tsv(args.index_long_output, INDEX_LONG_FIELDS, index_long_rows)
    write_tsv(args.contrast_audit, AUDIT_FIELDS, audit_rows)
    warnings = sum(1 for row in index_rows + component_rows if row["status"] == "WARNING")
    print(f"CAME phenotype contrast summary: ERROR=0 WARNING={warnings} index_rows={len(index_rows)} component_rows={len(component_rows)} index_long_rows={len(index_long_rows)}")
    for row in index_rows + component_rows:
        if row["status"] == "WARNING":
            stderr(f"WARNING\t{row['contrast_name']}\t{row['species']}\t{row['message']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
