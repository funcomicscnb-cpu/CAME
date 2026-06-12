#!/usr/bin/env python3
"""Promote reviewed reciprocal-best regulatory projections to orthologous_res.tsv.

This is an explicit adoption bridge. It converts star-shaped, single-source
reciprocal-best coordinate-projection outputs into a stable regulatory
orthology table for later use via ``--orthologous_res``. It does not infer
biological absence from failed mappings and does not handle general N-by-N
orthogroup reconciliation.
"""

from __future__ import annotations

import argparse
import csv
import re
import subprocess
import sys
from collections import Counter, defaultdict
from pathlib import Path


MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}
ORTHOLOGOUS_RES_FIELDS = [
    "species",
    "feature_id",
    "orthogroup_id",
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
REPORT_FIELDS = ["severity", "source", "field", "feature_id", "message"]
REQUIRED_SUMMARY_COLUMNS = [
    "projection_id",
    "source_species",
    "target_species",
    "source_feature_id",
    "region_type",
    "source_chrom",
    "source_start",
    "source_end",
    "competing_target_contigs",
    "forward_status",
    "roundtrip_qc",
    "structural_class",
    "high_confidence_primary",
]
REQUIRED_PROJECTED_COLUMNS = [
    "projection_id",
    "source_feature_id",
    "target_species",
    "target_chrom",
    "target_start",
    "target_end",
    "projection_status",
]
ALLOWED_ORTHOLOGY_TYPES = {"one_to_one", "one_to_many", "many_to_one"}
ALLOWED_ORTHOLOGY_CONFIDENCE = {"high", "medium", "low"}
CONFIDENCE_RANK = {"high": 0, "medium": 1, "low": 2}


def norm(value: object) -> str:
    text = str(value if value is not None else "").strip()
    return "" if text.lower() in MISSING_VALUES else text


def infer_delimiter(path: Path) -> str:
    if path.suffix.lower() == ".csv":
        return ","
    if path.suffix.lower() == ".tsv":
        return "\t"
    with path.open(newline="") as handle:
        sample = handle.read(min(65536, path.stat().st_size))
    return "\t" if sample.count("\t") > sample.count(",") else ","


def read_table(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    if not path.exists():
        raise OSError(f"File does not exist: {path}")
    delimiter = infer_delimiter(path)
    with path.open(newline="") as handle:
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


def read_required_table(path: Path, label: str, report: list[dict[str, str]]) -> tuple[list[str], list[dict[str, str]]]:
    try:
        return read_table(path)
    except OSError as exc:
        add_report(report, "ERROR", label, "path", "", str(exc))
        return [], []


def write_tsv(path: Path, fields: list[str], rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=fields,
            delimiter="\t",
            extrasaction="ignore",
            quoting=csv.QUOTE_NONE,
            escapechar="\\",
            lineterminator="\n",
        )
        writer.writeheader()
        writer.writerows(rows)


def add_report(records: list[dict[str, str]], severity: str, source: str, field: str, feature_id: str, message: str) -> None:
    records.append(
        {
            "severity": severity,
            "source": source,
            "field": field,
            "feature_id": feature_id,
            "message": message,
        }
    )


def safe_id(value: str) -> str:
    text = re.sub(r"[^A-Za-z0-9_.-]+", "_", value).strip("_")
    return text or "unknown"


def stable_orthogroup_id(source_species: str, feature_id: str) -> str:
    return f"OG_RE_RB_{safe_id(source_species)}_{safe_id(feature_id)}"


def confidence_for(row: dict[str, str]) -> str:
    if norm(row.get("high_confidence_primary")).lower() == "true":
        return "high"
    if norm(row.get("roundtrip_qc")) in {"HIGH_CONFIDENCE", "LOW_RECOVERY"}:
        return "medium"
    return "low"


def orthology_type_for(row: dict[str, str]) -> str:
    if norm(row.get("competing_target_contigs")) not in {"", "0", "1"}:
        return "one_to_many"
    return "one_to_one"


def require_columns(fields: list[str], required: list[str], label: str, report: list[dict[str, str]]) -> None:
    present = set(fields)
    for column in required:
        if column not in present:
            add_report(report, "ERROR", label, column, "", "Missing required column")


def selected_summary_rows(rows: list[dict[str, str]], selection: str) -> list[dict[str, str]]:
    selected = []
    for row in rows:
        if norm(row.get("structural_class")) == "missing":
            continue
        if selection == "primary" and norm(row.get("high_confidence_primary")).lower() != "true":
            continue
        selected.append(row)
    return selected


def validate_star_shape(summary_rows: list[dict[str, str]], report: list[dict[str, str]]) -> None:
    source_species = sorted({norm(row.get("source_species")) for row in summary_rows if norm(row.get("source_species"))})
    if not source_species:
        add_report(report, "ERROR", "region_orthology_summary", "source_species", "", "No source species values found")
    elif len(source_species) > 1:
        add_report(
            report,
            "ERROR",
            "region_orthology_summary",
            "source_species",
            "",
            "Star-shaped promotion supports exactly one source species; found: " + ",".join(source_species),
        )


def projected_index(rows: list[dict[str, str]], report: list[dict[str, str]]) -> dict[tuple[str, str, str], dict[str, str]]:
    grouped: dict[tuple[str, str, str], list[dict[str, str]]] = defaultdict(list)
    for row in rows:
        if norm(row.get("projection_status")) != "OK":
            continue
        key = (norm(row.get("projection_id")), norm(row.get("source_feature_id")), norm(row.get("target_species")))
        grouped[key].append(row)
    index = {}
    for key, values in sorted(grouped.items()):
        usable = [row for row in values if norm(row.get("target_chrom")) and norm(row.get("target_start")) and norm(row.get("target_end"))]
        if len(usable) > 1:
            add_report(report, "ERROR", "projected_regions", "projection_id,source_feature_id,target_species", key[1], f"Multiple OK projected rows for {key[0]}:{key[1]}->{key[2]}")
        elif usable:
            index[key] = usable[0]
    return index


def validate_anchor_consistency(rows: list[dict[str, str]], feature_id: str, report: list[dict[str, str]]) -> None:
    keys = {
        (
            norm(row.get("source_species")),
            norm(row.get("source_chrom")),
            norm(row.get("source_start")),
            norm(row.get("source_end")),
            norm(row.get("region_type")),
        )
        for row in rows
    }
    if len(keys) > 1:
        add_report(report, "ERROR", "region_orthology_summary", "source anchor", feature_id, "Conflicting source anchor metadata across selected projections")
    targets = Counter(norm(row.get("target_species")) for row in rows if norm(row.get("target_species")))
    duplicates = sorted(target for target, count in targets.items() if count > 1)
    if duplicates:
        add_report(report, "ERROR", "region_orthology_summary", "target_species", feature_id, "Multiple selected projections for target species: " + ",".join(duplicates))


def aggregate_type(rows: list[dict[str, str]]) -> str:
    return "one_to_many" if any(orthology_type_for(row) == "one_to_many" for row in rows) else "one_to_one"


def aggregate_confidence(rows: list[dict[str, str]]) -> str:
    return min((confidence_for(row) for row in rows), key=lambda value: CONFIDENCE_RANK[value])


def build_adopted_rows(summary_rows: list[dict[str, str]], projected_rows: list[dict[str, str]], report: list[dict[str, str]]) -> list[dict[str, str]]:
    validate_star_shape(summary_rows, report)
    selected = selected_summary_rows(summary_rows, "primary")
    if not selected:
        add_report(report, "ERROR", "region_orthology_summary", "high_confidence_primary", "", "No high-confidence primary loci available for adoption")
        return []
    pindex = projected_index(projected_rows, report)
    by_feature: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in selected:
        by_feature[norm(row.get("source_feature_id"))].append(row)

    output = []
    for feature_id in sorted(by_feature):
        rows = sorted(by_feature[feature_id], key=lambda row: (norm(row.get("target_species")), norm(row.get("projection_id"))))
        validate_anchor_consistency(rows, feature_id, report)
        anchor = rows[0]
        source_species = norm(anchor.get("source_species"))
        orthogroup_id = stable_orthogroup_id(source_species, feature_id)
        human_anchor = f"{norm(anchor.get('source_chrom'))}:{norm(anchor.get('source_start'))}-{norm(anchor.get('source_end'))}"
        source_type = aggregate_type(rows)
        source_confidence = aggregate_confidence(rows)
        target_count = len(rows)
        output.append(
            {
                "species": source_species,
                "feature_id": feature_id,
                "orthogroup_id": orthogroup_id,
                "chrom": norm(anchor.get("source_chrom")),
                "start": norm(anchor.get("source_start")),
                "end": norm(anchor.get("source_end")),
                "human_anchor_region": human_anchor,
                "re_type": norm(anchor.get("region_type")),
                "orthology_type": source_type,
                "orthology_confidence": source_confidence,
                "source": "reciprocal_best_orthology_adopted",
                "notes": f"source anchor; selected_targets={target_count}; stable_id=source_species+feature_id",
            }
        )
        seen_targets = set()
        for row in rows:
            target_species = norm(row.get("target_species"))
            if target_species in seen_targets:
                continue
            seen_targets.add(target_species)
            key = (norm(row.get("projection_id")), feature_id, target_species)
            target = pindex.get(key)
            if not target:
                add_report(report, "ERROR", "projected_regions", "projection_status", feature_id, f"Selected primary locus lacks OK projected coordinates for {key[0]}->{target_species}")
                continue
            notes = "|".join(
                [
                    f"projection_id={norm(row.get('projection_id'))}",
                    norm(row.get("forward_status")),
                    norm(row.get("roundtrip_qc")),
                    norm(row.get("structural_class")),
                    "adopted projected span",
                ]
            )
            output.append(
                {
                    "species": target_species,
                    "feature_id": f"{target_species}.{feature_id}.recip_best",
                    "orthogroup_id": orthogroup_id,
                    "chrom": norm(target.get("target_chrom")),
                    "start": norm(target.get("target_start")),
                    "end": norm(target.get("target_end")),
                    "human_anchor_region": human_anchor,
                    "re_type": norm(row.get("region_type")),
                    "orthology_type": orthology_type_for(row),
                    "orthology_confidence": confidence_for(row),
                    "source": "reciprocal_best_orthology_adopted",
                    "notes": notes,
                }
            )
    return output


def validate_controlled_values(rows: list[dict[str, str]], report: list[dict[str, str]]) -> None:
    for row in rows:
        feature_id = norm(row.get("feature_id"))
        otype = norm(row.get("orthology_type"))
        confidence = norm(row.get("orthology_confidence"))
        if otype not in ALLOWED_ORTHOLOGY_TYPES:
            add_report(report, "ERROR", "orthologous_res.adopted", "orthology_type", feature_id, f"Unsupported orthology_type: {otype}")
        if confidence not in ALLOWED_ORTHOLOGY_CONFIDENCE:
            add_report(report, "ERROR", "orthologous_res.adopted", "orthology_confidence", feature_id, f"Unsupported orthology_confidence: {confidence}")


def count_by_confidence(rows: list[dict[str, str]]) -> Counter:
    counts = Counter(confidence_for(row) for row in rows)
    return Counter({level: counts.get(level, 0) for level in ("high", "medium", "low")})


def format_counts(counts: Counter) -> str:
    return ";".join(f"{key}={counts.get(key, 0)}" for key in sorted(counts))


def report_promotion_counts(summary_rows: list[dict[str, str]], adopted_rows: list[dict[str, str]], report: list[dict[str, str]]) -> None:
    selected = selected_summary_rows(summary_rows, "primary")
    missing = [row for row in summary_rows if norm(row.get("structural_class")) == "missing"]
    excluded_non_primary = [
        row
        for row in summary_rows
        if norm(row.get("structural_class")) != "missing"
        and norm(row.get("high_confidence_primary")).lower() != "true"
    ]
    adopted_confidence = Counter(norm(row.get("orthology_confidence")) for row in adopted_rows)
    add_report(
        report,
        "INFO",
        "promotion_counts",
        "summary_rows",
        "",
        (
            f"total={len(summary_rows)};selected_primary={len(selected)};"
            f"excluded_total={len(summary_rows) - len(selected)};"
            f"excluded_missing={len(missing)};excluded_non_primary={len(excluded_non_primary)}"
        ),
    )
    add_report(
        report,
        "INFO",
        "promotion_counts",
        "excluded_confidence_distribution",
        "",
        format_counts(count_by_confidence(excluded_non_primary)),
    )
    add_report(
        report,
        "INFO",
        "promotion_counts",
        "adopted_confidence_distribution",
        "",
        format_counts(Counter({level: adopted_confidence.get(level, 0) for level in ("high", "medium", "low")})),
    )
    add_report(
        report,
        "INFO",
        "promotion_counts",
        "adopted_rows",
        "",
        f"rows={len(adopted_rows)};orthogroups={len({norm(row.get('orthogroup_id')) for row in adopted_rows if norm(row.get('orthogroup_id'))})}",
    )


def run_downstream_validator(args: argparse.Namespace, adopted_path: Path, report: list[dict[str, str]]) -> None:
    if not norm(args.orthologous_genes):
        add_report(report, "WARNING", "validate_orthology_tables", "orthologous_genes", "", "Downstream orthology validation skipped because --orthologous-genes was not supplied")
        return
    validation_output = Path(args.validation_output) if norm(args.validation_output) else Path(args.output_dir) / "orthologous_res_adopted.validation.tsv"
    cmd = [
        sys.executable,
        str(Path(__file__).resolve().parent / "validate_orthology_tables.py"),
        "--orthologous_genes",
        args.orthologous_genes,
        "--orthologous_res",
        str(adopted_path),
        "--output",
        str(validation_output),
    ]
    if norm(args.omics_samplesheet):
        cmd.extend(["--omics_samplesheet", args.omics_samplesheet])
    result = subprocess.run(cmd, text=True, capture_output=True, check=False)
    if result.returncode:
        add_report(report, "ERROR", "validate_orthology_tables", "orthologous_res", "", "Downstream orthology validator rejected adopted table; see " + str(validation_output))
        if result.stderr:
            add_report(report, "ERROR", "validate_orthology_tables", "stderr", "", result.stderr.strip().splitlines()[-1])
    else:
        add_report(report, "INFO", "validate_orthology_tables", "orthologous_res", "", "Downstream orthology validator accepted adopted table: " + str(validation_output))


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--region-summary", "--region_summary", required=True)
    parser.add_argument("--projected-regions", "--projected_regions", required=True)
    parser.add_argument("--inferred-orthologous-res", "--inferred_orthologous_res", default="")
    parser.add_argument("--orthologous-genes", "--orthologous_genes", default="")
    parser.add_argument("--omics-samplesheet", "--omics_samplesheet", default="")
    parser.add_argument("--output-dir", "--output_dir", required=True)
    parser.add_argument("--output", default="")
    parser.add_argument("--validation-output", "--validation_output", default="")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    outdir = Path(args.output_dir)
    report: list[dict[str, str]] = []
    output_path = Path(args.output) if norm(args.output) else outdir / "orthologous_res.adopted.tsv"
    report_path = outdir / "orthologous_res_promotion_report.tsv"
    outdir.mkdir(parents=True, exist_ok=True)

    summary_fields, summary_rows = read_required_table(Path(args.region_summary), "region_orthology_summary", report)
    projected_fields, projected_rows = read_required_table(Path(args.projected_regions), "projected_regions", report)
    require_columns(summary_fields, REQUIRED_SUMMARY_COLUMNS, "region_orthology_summary", report)
    require_columns(projected_fields, REQUIRED_PROJECTED_COLUMNS, "projected_regions", report)
    if norm(args.inferred_orthologous_res):
        inferred_path = Path(args.inferred_orthologous_res)
        if not inferred_path.exists():
            add_report(report, "ERROR", "inferred_orthologous_res", "path", "", f"File does not exist: {inferred_path}")
        else:
            _, inferred_rows = read_table(inferred_path)
            add_report(report, "INFO", "inferred_orthologous_res", "n_rows", "", f"Reviewed pairwise table rows available: {len(inferred_rows)}")
    if any(row["severity"] == "ERROR" for row in report):
        write_tsv(output_path, ORTHOLOGOUS_RES_FIELDS, [])
        write_tsv(report_path, REPORT_FIELDS, report)
        return 1

    adopted_rows = build_adopted_rows(summary_rows, projected_rows, report)
    validate_controlled_values(adopted_rows, report)
    has_promotion_errors = any(row["severity"] == "ERROR" for row in report)
    report_promotion_counts(summary_rows, [] if has_promotion_errors else adopted_rows, report)
    if not has_promotion_errors:
        write_tsv(output_path, ORTHOLOGOUS_RES_FIELDS, adopted_rows)
        run_downstream_validator(args, output_path, report)
    else:
        write_tsv(output_path, ORTHOLOGOUS_RES_FIELDS, [])
    write_tsv(report_path, REPORT_FIELDS, report)
    counts = Counter(row["severity"] for row in report)
    print(
        "CAME adopted regulatory orthology promotion: "
        f"ERROR={counts.get('ERROR', 0)} WARNING={counts.get('WARNING', 0)} rows={len(adopted_rows)} output={output_path}"
    )
    for row in report:
        if row["severity"] == "ERROR":
            print(f"ERROR\t{row['source']}\t{row['field']}\t{row['feature_id']}\t{row['message']}", file=sys.stderr)
    return 1 if counts.get("ERROR", 0) else 0


if __name__ == "__main__":
    sys.exit(main())
