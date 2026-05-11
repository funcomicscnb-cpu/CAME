#!/usr/bin/env python3
"""QC summaries for normalized CAME phenotype measurements."""

import argparse
import math
import sys
from collections import Counter, defaultdict

from phenotype_utils import (
    component_name_for_row,
    format_value,
    load_profile,
    parse_float,
    profile_design,
    profile_indexes,
    profile_qc_policy,
    profile_components,
    read_table,
    replicate_id_for_row,
    stderr,
    validate_design_fields,
    write_tsv,
)


def metric(rows, severity, metric_name, value, message, **context):
    row = {
        "severity": severity,
        "metric": metric_name,
        "species": context.get("species", ""),
        "condition": context.get("condition", ""),
        "assay": context.get("assay", ""),
        "measurement": context.get("measurement", ""),
        "timepoint": context.get("timepoint", ""),
        "value": str(value),
        "message": message,
    }
    rows.append(row)


def percentile(sorted_values, q):
    if not sorted_values:
        return None
    pos = (len(sorted_values) - 1) * q
    low = math.floor(pos)
    high = math.ceil(pos)
    if low == high:
        return sorted_values[int(pos)]
    return sorted_values[low] + (sorted_values[high] - sorted_values[low]) * (pos - low)


def group_counts(rows, replicate_key=None, group_key=None):
    base_key_fields = ["species", "condition", "assay", "timepoint"]
    extra_fields = [f for f in (group_key or []) if f not in set(base_key_fields)]
    key_fields = base_key_fields + extra_fields
    grouped = defaultdict(lambda: {"rows": 0, "samples": set(), "replicates": set()})
    for row in rows:
        key = tuple(row.get(field, "") for field in key_fields)
        grouped[key]["rows"] += 1
        if row.get("sample_id"):
            grouped[key]["samples"].add(row.get("sample_id"))
        rep = replicate_id_for_row(row, replicate_key=replicate_key)
        if rep.strip("|"):
            grouped[key]["replicates"].add(rep)

    output = []
    for key_values, counts in sorted(grouped.items()):
        row_dict = dict(zip(key_fields, key_values))
        row_dict["row_count"] = counts["rows"]
        row_dict["unique_sample_ids"] = len(counts["samples"])
        row_dict["replicate_n"] = len(counts["replicates"])
        output.append(row_dict)
    return output, key_fields


def outlier_rows(rows):
    grouped = defaultdict(list)
    for idx, row in enumerate(rows):
        value = parse_float(row.get("value"))
        if value is not None:
            grouped[(row.get("assay", ""), row.get("measurement", ""))].append((idx, value))

    output = []
    for (assay, measurement), items in sorted(grouped.items()):
        if len(items) < 4:
            continue
        values = sorted(value for _, value in items)
        q1 = percentile(values, 0.25)
        q3 = percentile(values, 0.75)
        iqr = q3 - q1
        lower = q1 - 1.5 * iqr
        upper = q3 + 1.5 * iqr
        for idx, value in items:
            if value < lower or value > upper:
                row = rows[idx]
                output.append(
                    {
                        "sample_id": row.get("sample_id", ""),
                        "species": row.get("species", ""),
                        "condition": row.get("condition", ""),
                        "timepoint": row.get("timepoint", ""),
                        "assay": assay,
                        "measurement": measurement,
                        "value": format_value(value),
                        "outlier_method": "iqr",
                        "lower_bound": format_value(lower),
                        "upper_bound": format_value(upper),
                    }
                )
    return output


def build_metrics(fields, rows, index_components, qc_policy, replicate_key=None, group_key=None):
    metrics = []
    metric(metrics, "INFO", "row_count", len(rows), "Rows available for phenotype QC")
    group_key = group_key or ["species", "condition", "timepoint"]

    for field in fields:
        missing = sum(1 for row in rows if row.get(field, "") == "")
        metric(metrics, "INFO", "missing_values", missing, f"Missing values in {field}", measurement=field)

    sample_counts = Counter(row.get("sample_id", "") for row in rows if row.get("sample_id", ""))
    duplicate_sample_ids = [sample_id for sample_id, count in sample_counts.items() if count > 1]
    if duplicate_sample_ids:
        metric(
            metrics,
            "WARNING",
            "duplicated_sample_id",
            len(duplicate_sample_ids),
            "sample_id values appear on multiple phenotype rows; row-level sample IDs should be unique",
        )

    units_by_group = defaultdict(set)
    for row in rows:
        key = tuple(row.get(field, "") for field in group_key)
        units_by_group[key].add(replicate_id_for_row(row, replicate_key=replicate_key))
    min_rep = qc_policy["min_replicates_per_group"]
    for key_values, units in sorted(units_by_group.items()):
        group_values = dict(zip(group_key, key_values))
        replicate_n = len([unit for unit in units if unit.strip("|")])
        metric(
            metrics,
            "INFO",
            "replicate_count",
            replicate_n,
            "Replicate units in configured phenotype group",
            species=group_values.get("species", ""),
            condition=group_values.get("condition", ""),
            timepoint=group_values.get("timepoint", ""),
        )
        if replicate_n < min_rep:
            severity = "ERROR" if qc_policy["fail_on_sparse_groups"] else "WARNING"
            metric(
                metrics,
                severity,
                "sparse_group",
                replicate_n,
                f"Fewer than {min_rep} replicate unit(s) in configured phenotype group",
                species=group_values.get("species", ""),
                condition=group_values.get("condition", ""),
                timepoint=group_values.get("timepoint", ""),
            )

    for index_name, components in index_components:
        present_components = set()
        component_set = set(components)
        for row in rows:
            component = component_name_for_row(row, component_set)
            if component:
                present_components.add(component)
        for component in components:
            if component not in present_components:
                severity = "ERROR" if qc_policy["fail_on_missing_components"] else "WARNING"
                metric(metrics, severity, "missing_profile_component", component, f"Profile component is absent from phenotype table for index {index_name}", measurement=component)
            else:
                metric(metrics, "INFO", "profile_component_present", component, f"Profile component is present for index {index_name}", measurement=component)

    units_by_assay_measurement = defaultdict(set)
    for row in rows:
        key = (row.get("assay", ""), row.get("measurement", ""))
        if row.get("unit"):
            units_by_assay_measurement[key].add(row.get("unit"))
    for (assay, measurement), units in sorted(units_by_assay_measurement.items()):
        if len(units) > 1:
            severity = "ERROR" if qc_policy["fail_on_unit_inconsistency"] else "WARNING"
            metric(
                metrics,
                severity,
                "unit_inconsistency",
                ",".join(sorted(units)),
                "Multiple units found within assay/measurement",
                assay=assay,
                measurement=measurement,
            )

    return metrics


def parse_args():
    parser = argparse.ArgumentParser(description="QC normalized CAME phenotype measurements.")
    parser.add_argument("--input", required=True)
    parser.add_argument("--study_profile", required=True)
    parser.add_argument("--metrics", default="results/phenotype/qc/phenotype_qc_metrics.tsv")
    parser.add_argument("--outliers", default="results/phenotype/qc/outliers.tsv")
    parser.add_argument("--group_counts", default="results/phenotype/qc/group_counts.tsv")
    return parser.parse_args()


def main():
    args = parse_args()
    fields, rows = read_table(args.input)
    try:
        profile = load_profile(args.study_profile)
        design = profile_design(profile)
        validate_design_fields(fields, design)
        index_components = []
        for index in profile_indexes(profile):
            index_components.append((str(index.get("name", "")).strip(), [str(item).strip() for item in index.get("components", []) if str(item).strip()]))
        if not index_components:
            index_components = [("phenotype_index", profile_components(profile))]
        qc_policy = profile_qc_policy(profile)
    except Exception as exc:
        stderr(f"ERROR\tstudy_profile\t{exc}")
        return 1

    metrics = build_metrics(
        fields,
        rows,
        index_components,
        qc_policy,
        replicate_key=design["replicate_key"],
        group_key=design["group_key"],
    )
    counts, count_key_fields = group_counts(rows, replicate_key=design["replicate_key"], group_key=design["group_key"])
    outliers = outlier_rows(rows)

    write_tsv(
        args.metrics,
        ["severity", "metric", "species", "condition", "assay", "measurement", "timepoint", "value", "message"],
        metrics,
    )
    write_tsv(
        args.group_counts,
        count_key_fields + ["row_count", "unique_sample_ids", "replicate_n"],
        counts,
    )
    write_tsv(
        args.outliers,
        ["sample_id", "species", "condition", "timepoint", "assay", "measurement", "value", "outlier_method", "lower_bound", "upper_bound"],
        outliers,
    )

    errors = sum(1 for row in metrics if row["severity"] == "ERROR")
    warnings = sum(1 for row in metrics if row["severity"] == "WARNING")
    print(f"CAME phenotype QC summary: ERROR={errors} WARNING={warnings} outliers={len(outliers)}")
    for row in metrics:
        if row["severity"] in {"ERROR", "WARNING"}:
            stderr(f"{row['severity']}\t{row['metric']}\t{row['message']}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
