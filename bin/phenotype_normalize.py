#!/usr/bin/env python3
"""Normalize long-format CAME phenotype measurements."""

import argparse
import math
import os
import statistics
import sys
from collections import defaultdict

from phenotype_utils import (
    REPLICATE_KEY,
    format_value,
    load_profile,
    normalize_species_label,
    norm,
    parse_float,
    profile_design,
    read_table,
    stderr,
    validate_design_fields,
    write_tsv,
)


NORMALIZATION_MODES = {
    "none",
    "zscore_within_assay",
    "minmax_within_assay",
    "log10_if_positive",
    "median_center_within_assay",
}


def add_summary(rows, severity, scope, assay, measurement, metric, value, message):
    rows.append(
        {
            "severity": severity,
            "scope": scope,
            "assay": assay,
            "measurement": measurement,
            "metric": metric,
            "value": str(value),
            "message": message,
        }
    )


def clean_rows(fields, rows, summary):
    cleaned = []
    seen = set()
    duplicate_count = 0
    numeric_errors = []

    for idx, row in enumerate(rows, start=2):
        out = {field: row.get(field, "").strip() for field in fields}
        if "species" in out:
            out["species"] = normalize_species_label(out.get("species"))
        raw_value = out.get("value", "")
        out["raw_value"] = raw_value
        if raw_value != "":
            try:
                float(raw_value)
            except ValueError:
                numeric_errors.append((idx, raw_value))
        key = tuple((field, out.get(field, "")) for field in fields)
        if key in seen:
            duplicate_count += 1
            continue
        seen.add(key)
        cleaned.append(out)

    if duplicate_count:
        add_summary(
            summary,
            "WARNING",
            "table",
            "",
            "",
            "exact_duplicate_rows_removed",
            duplicate_count,
            "Exact duplicate phenotype rows were removed after cleaning",
        )
    if numeric_errors:
        for row_num, value in numeric_errors[:20]:
            add_summary(
                summary,
                "ERROR",
                "row",
                "",
                "",
                "non_numeric_value",
                row_num,
                f"Expected numeric value, found: {value}",
            )
    return cleaned, numeric_errors


def design_summary_rows(design, normalization):
    return [
        {"parameter": "replicate_key", "configured_value": "|".join(design["replicate_key"])},
        {"parameter": "normalization_scope", "configured_value": "|".join(design["normalization_scope"])},
        {"parameter": "normalization_mode", "configured_value": normalization},
    ]


def summary_scope_value(scope_columns):
    return "_".join(scope_columns)


def scope_field_value(scope_columns, key, field):
    if field not in scope_columns:
        return ""
    return key[scope_columns.index(field)]


def values_by_scope(rows, scope_columns):
    grouped = defaultdict(list)
    for idx, row in enumerate(rows):
        value = parse_float(row.get("raw_value"))
        if value is None:
            continue
        key = tuple(norm(row.get(col)) for col in scope_columns)
        grouped[key].append((idx, value))
    return grouped


def apply_normalization(rows, mode, summary, scope_columns):
    for row in rows:
        row["normalized_value"] = row.get("raw_value", "")
        row["value"] = row.get("raw_value", "")

    grouped = values_by_scope(rows, scope_columns)
    add_summary(summary, "INFO", "table", "", "", "normalization_mode", mode, "Selected normalization mode")

    if mode == "none":
        return

    scope_name = summary_scope_value(scope_columns)
    for key, items in sorted(grouped.items()):
        assay = scope_field_value(scope_columns, key, "assay")
        measurement = scope_field_value(scope_columns, key, "measurement")
        values = [value for _, value in items]
        if mode == "zscore_within_assay":
            mean = sum(values) / len(values)
            sd = math.sqrt(sum((value - mean) ** 2 for value in values) / len(values))
            transformed = [(idx, 0.0 if sd == 0 else (value - mean) / sd) for idx, value in items]
            add_summary(summary, "INFO", scope_name, assay, measurement, "mean", format_value(mean), "Z-score center")
            add_summary(summary, "INFO", scope_name, assay, measurement, "sd", format_value(sd), "Z-score scale")
        elif mode == "minmax_within_assay":
            minimum = min(values)
            maximum = max(values)
            span = maximum - minimum
            transformed = [(idx, 0.0 if span == 0 else (value - minimum) / span) for idx, value in items]
            add_summary(summary, "INFO", scope_name, assay, measurement, "min", format_value(minimum), "Min-max lower bound")
            add_summary(summary, "INFO", scope_name, assay, measurement, "max", format_value(maximum), "Min-max upper bound")
        elif mode == "log10_if_positive":
            transformed = []
            skipped = 0
            for idx, value in items:
                if value > 0:
                    transformed.append((idx, math.log10(value)))
                else:
                    transformed.append((idx, None))
                    skipped += 1
            if skipped:
                add_summary(
                    summary,
                    "WARNING",
                    scope_name,
                    assay,
                    measurement,
                    "log10_non_positive_values",
                    skipped,
                    "Non-positive values were set to NA for log10 normalization",
                )
        elif mode == "median_center_within_assay":
            median = statistics.median(values)
            transformed = [(idx, value - median) for idx, value in items]
            add_summary(summary, "INFO", scope_name, assay, measurement, "median", format_value(median), "Median center")
        else:
            raise RuntimeError(f"Unsupported normalization mode: {mode}")

        for idx, value in transformed:
            rows[idx]["normalized_value"] = format_value(value)
            rows[idx]["value"] = format_value(value)


def parse_args():
    parser = argparse.ArgumentParser(description="Normalize CAME phenotype measurements.")
    parser.add_argument("--input", "--phenotype_samplesheet", dest="input", required=True)
    parser.add_argument("--output", default="results/phenotype/tables/phenotype_long_normalized.tsv")
    parser.add_argument("--summary", default="results/phenotype/qc/normalization_summary.tsv")
    parser.add_argument("--study_profile", default="")
    parser.add_argument("--design_summary", default="results/phenotype/qc/phenotype_design_summary.tsv")
    parser.add_argument("--normalization", default="none", choices=sorted(NORMALIZATION_MODES))
    return parser.parse_args()


def main():
    args = parse_args()
    summary = []
    design = {"replicate_key": list(REPLICATE_KEY), "normalization_scope": ["assay", "measurement"]}
    if args.study_profile:
        try:
            design = profile_design(load_profile(args.study_profile))
        except Exception as exc:
            stderr(f"ERROR\tphenotype_normalize\tCould not load phenotype design: {exc}")
            return 1
    write_tsv(args.design_summary, ["parameter", "configured_value"], design_summary_rows(design, args.normalization))

    fields, rows = read_table(args.input)
    try:
        validate_design_fields(fields, design)
    except Exception as exc:
        stderr(f"ERROR\tphenotype_normalize\t{exc}")
        return 1
    if "value" not in fields:
        add_summary(summary, "ERROR", "table", "", "", "missing_column", "value", "Missing required value column")
        write_tsv(args.summary, ["severity", "scope", "assay", "measurement", "metric", "value", "message"], summary)
        return 1

    cleaned, numeric_errors = clean_rows(fields, rows, summary)
    add_summary(summary, "INFO", "table", "", "", "input_rows", len(rows), "Rows read from phenotype table")
    add_summary(summary, "INFO", "table", "", "", "output_rows", len(cleaned), "Rows written after cleaning")
    if len(cleaned) < 3:
        add_summary(
            summary, "WARNING", "table", "", "", "low_row_count", len(cleaned),
            f"Only {len(cleaned)} row(s) remain after cleaning; normalization statistics may be unreliable",
        )
    apply_normalization(cleaned, args.normalization, summary, design["normalization_scope"])

    output_fields = list(fields)
    for field in ["raw_value", "normalized_value"]:
        if field not in output_fields:
            output_fields.append(field)

    write_tsv(args.output, output_fields, cleaned)
    write_tsv(args.summary, ["severity", "scope", "assay", "measurement", "metric", "value", "message"], summary)

    error_count = len(numeric_errors)
    warning_count = sum(1 for row in summary if row["severity"] == "WARNING")
    print(f"CAME phenotype normalization summary: ERROR={error_count} WARNING={warning_count} rows={len(cleaned)}")
    for row in summary:
        if row["severity"] in {"ERROR", "WARNING"}:
            stderr(f"{row['severity']}\t{row['metric']}\t{row['message']}")
    return 1 if error_count else 0


if __name__ == "__main__":
    sys.exit(main())
