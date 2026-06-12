#!/usr/bin/env python3
"""Validate a reciprocal-best orthology reference bundle manifest.

This is a contract validator for assets consumed by coordinate_projection and
future opt-in reference-preparation orchestration. It validates declared assets
and provenance, but it does not generate chains/nets or infer biological
orthology.
"""

from __future__ import annotations

import argparse
import csv
import os
import sys
from collections import Counter, defaultdict
from pathlib import Path

import check_seqname_concordance


SCHEMA_VERSION = "orthology_reference_bundle.v1"
MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}

REQUIRED_COLUMNS = [
    "schema_version",
    "bundle_id",
    "bundle_source",
    "source_species",
    "target_species",
    "source_assembly",
    "target_assembly",
    "asset_role",
    "asset_path",
    "asset_format",
    "orthology_lift_tool",
    "validation_status",
]
PROVENANCE_COLUMNS = ["tool_versions", "params_hash", "input_hashes", "created_at"]
REFERENCE_COLUMNS = [
    "source_fasta",
    "source_fai",
    "source_annotation_file",
    "target_fasta",
    "target_fai",
    "target_annotation_file",
]

ALLOWED_BUNDLE_SOURCES = {"external", "came_generated"}
ALLOWED_ASSET_ROLES = {
    "reciprocal_best_chain",
    "source_callable_mask",
    "target_callable_mask",
    "source_element_union",
    "hal_alignment",
}
ALLOWED_ASSET_FORMATS = {"chain", "bed", "hal"}
ROLE_FORMAT = {
    "reciprocal_best_chain": "chain",
    "source_callable_mask": "bed",
    "target_callable_mask": "bed",
    "source_element_union": "bed",
    "hal_alignment": "hal",
}
ALLOWED_LIFT_TOOLS = {"liftover", "halliftover"}
ALLOWED_VALIDATION_STATUSES = {"valid", "warning", "unvalidated"}

VALIDATION_FIELDS = [
    "severity",
    "bundle_id",
    "source_species",
    "target_species",
    "asset_role",
    "field",
    "status",
    "path",
    "message",
]
SEQNAME_REFERENCE_FIELDS = ["reference_id", "species", "fasta", "fai", "annotation_file"]


def norm(value: object) -> str:
    text = str(value if value is not None else "").strip()
    return "" if text.lower() in MISSING_VALUES else text


def lower_norm(value: object) -> str:
    return norm(value).lower()


def parse_bool(value: object) -> bool:
    return str(value).strip().lower() in {"1", "true", "t", "yes", "y"}


def infer_delimiter(path: Path) -> str:
    if path.suffix.lower() == ".csv":
        return ","
    if path.suffix.lower() == ".tsv":
        return "\t"
    with path.open(newline="") as handle:
        sample = handle.read(min(65536, path.stat().st_size))
    return "\t" if sample.count("\t") > sample.count(",") else ","


def read_table(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    delimiter = infer_delimiter(path)
    with path.open(newline="") as handle:
        reader = csv.DictReader(handle, delimiter=delimiter)
        raw_fields = reader.fieldnames or []
        fields = [norm(field) for field in raw_fields]
        rows: list[dict[str, str]] = []
        for row in reader:
            cleaned = {}
            for raw_field, field in zip(raw_fields, fields):
                cleaned[field] = norm(row.get(raw_field))
            rows.append(cleaned)
    return fields, rows


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


def add_record(
    records: list[dict[str, str]],
    severity: str,
    bundle_id: str,
    source_species: str,
    target_species: str,
    asset_role: str,
    field: str,
    status: str,
    path: str,
    message: str,
) -> None:
    records.append(
        {
            "severity": severity,
            "bundle_id": bundle_id,
            "source_species": source_species,
            "target_species": target_species,
            "asset_role": asset_role,
            "field": field,
            "status": status,
            "path": path,
            "message": message,
        }
    )


def resolve_path(value: str, base_dir: Path) -> str:
    text = norm(value)
    if not text or "://" in text or os.path.isabs(text):
        return text
    return str((base_dir / text).resolve())


def schema_row_valid(row: dict[str, str]) -> bool:
    return all(norm(row.get(column)) for column in REQUIRED_COLUMNS)


def row_context(row: dict[str, str]) -> tuple[str, str, str, str]:
    return (
        norm(row.get("bundle_id")),
        norm(row.get("source_species")),
        norm(row.get("target_species")),
        lower_norm(row.get("asset_role")),
    )


def validate_row(
    row: dict[str, str],
    records: list[dict[str, str]],
    check_paths: bool,
    base_dir: Path,
    row_number: int,
) -> dict[str, str]:
    prepared = dict(row)
    bundle_id, source_species, target_species, asset_role = row_context(row)
    asset_path = norm(row.get("asset_path"))
    resolved_asset_path = resolve_path(asset_path, base_dir)
    prepared["asset_path_resolved"] = resolved_asset_path

    for column in REQUIRED_COLUMNS:
        if not norm(row.get(column)):
            add_record(
                records,
                "ERROR",
                bundle_id,
                source_species,
                target_species,
                asset_role,
                column,
                "MISSING",
                "",
                f"Missing required value in row {row_number}: {column}",
            )

    schema_version = norm(row.get("schema_version"))
    if schema_version and schema_version != SCHEMA_VERSION:
        add_record(records, "ERROR", bundle_id, source_species, target_species, asset_role, "schema_version", "ERROR", "", f"Unsupported schema_version: {schema_version}")

    bundle_source = lower_norm(row.get("bundle_source"))
    if bundle_source and bundle_source not in ALLOWED_BUNDLE_SOURCES:
        add_record(records, "ERROR", bundle_id, source_species, target_species, asset_role, "bundle_source", "ERROR", "", f"Unsupported bundle_source: {row.get('bundle_source')}")

    if asset_role and asset_role not in ALLOWED_ASSET_ROLES:
        add_record(records, "ERROR", bundle_id, source_species, target_species, asset_role, "asset_role", "ERROR", "", f"Unsupported asset_role: {row.get('asset_role')}")

    asset_format = lower_norm(row.get("asset_format"))
    if asset_format and asset_format not in ALLOWED_ASSET_FORMATS:
        add_record(records, "ERROR", bundle_id, source_species, target_species, asset_role, "asset_format", "ERROR", resolved_asset_path, f"Unsupported asset_format: {row.get('asset_format')}")
    expected_format = ROLE_FORMAT.get(asset_role)
    if expected_format and asset_format and asset_format != expected_format:
        add_record(records, "ERROR", bundle_id, source_species, target_species, asset_role, "asset_format", "ERROR", resolved_asset_path, f"asset_role={asset_role} requires asset_format={expected_format}")

    lift_tool = lower_norm(row.get("orthology_lift_tool"))
    if lift_tool and lift_tool not in ALLOWED_LIFT_TOOLS:
        add_record(records, "ERROR", bundle_id, source_species, target_species, asset_role, "orthology_lift_tool", "ERROR", "", f"Unsupported orthology_lift_tool: {row.get('orthology_lift_tool')}")

    validation_status = lower_norm(row.get("validation_status"))
    if validation_status and validation_status not in ALLOWED_VALIDATION_STATUSES:
        add_record(records, "ERROR", bundle_id, source_species, target_species, asset_role, "validation_status", "ERROR", "", f"Unsupported validation_status: {row.get('validation_status')}")
    elif validation_status in {"warning", "unvalidated"}:
        add_record(records, "WARNING", bundle_id, source_species, target_species, asset_role, "validation_status", validation_status.upper(), resolved_asset_path, f"Bundle asset validation_status={validation_status}")

    missing_provenance = [column for column in PROVENANCE_COLUMNS if not norm(row.get(column))]
    if bundle_source == "came_generated":
        for column in missing_provenance:
            add_record(records, "ERROR", bundle_id, source_species, target_species, asset_role, column, "MISSING", "", f"CAME-generated bundle requires provenance field: {column}")
    elif bundle_source == "external" and missing_provenance:
        add_record(records, "WARNING", bundle_id, source_species, target_species, asset_role, "provenance", "OPTIONAL_MISSING", "", "External bundle omits optional CAME provenance field(s): " + ",".join(missing_provenance))

    if asset_path and check_paths:
        if "://" in asset_path:
            add_record(records, "WARNING", bundle_id, source_species, target_species, asset_role, "asset_path", "NOT_CHECKED", asset_path, "Remote URI asset_path was not checked locally")
        elif not os.path.exists(resolved_asset_path):
            add_record(records, "ERROR", bundle_id, source_species, target_species, asset_role, "asset_path", "MISSING", resolved_asset_path, "Declared asset_path does not exist")

    if schema_row_valid(row):
        add_record(records, "INFO", bundle_id, source_species, target_species, asset_role, "asset_path", "OK", resolved_asset_path, "Bundle asset row parsed")
    return prepared


def validate_required_columns(fields: list[str], records: list[dict[str, str]]) -> bool:
    ok = True
    if not fields:
        add_record(records, "ERROR", "", "", "", "", "header", "MISSING", "", "Manifest has no header")
        return False
    if len(fields) != len(set(fields)):
        add_record(records, "ERROR", "", "", "", "", "header", "ERROR", "", "Manifest has duplicate column names")
        ok = False
    for column in REQUIRED_COLUMNS:
        if column not in fields:
            add_record(records, "ERROR", "", "", "", "", column, "MISSING", "", "Missing required column")
            ok = False
    return ok


def validate_duplicate_roles(rows: list[dict[str, str]], records: list[dict[str, str]]) -> None:
    grouped: dict[tuple[str, str, str], list[dict[str, str]]] = defaultdict(list)
    for row in rows:
        source_species = norm(row.get("source_species"))
        target_species = norm(row.get("target_species"))
        asset_role = lower_norm(row.get("asset_role"))
        if source_species and target_species and asset_role:
            grouped[(source_species, target_species, asset_role)].append(row)
    for (source_species, target_species, asset_role), items in sorted(grouped.items()):
        if len(items) <= 1:
            continue
        signatures = {
            (
                norm(item.get("bundle_id")),
                norm(item.get("source_assembly")),
                norm(item.get("target_assembly")),
                lower_norm(item.get("asset_format")),
                lower_norm(item.get("orthology_lift_tool")),
                norm(item.get("asset_path_resolved")),
            )
            for item in items
        }
        bundle_id = norm(items[0].get("bundle_id"))
        if len(signatures) > 1:
            add_record(records, "ERROR", bundle_id, source_species, target_species, asset_role, "asset_role", "DUPLICATE_CONFLICT", "", f"Conflicting duplicate rows for {source_species}->{target_species} role {asset_role}")
        else:
            add_record(records, "WARNING", bundle_id, source_species, target_species, asset_role, "asset_role", "DUPLICATE", "", f"Duplicate identical rows for {source_species}->{target_species} role {asset_role}")


def validate_pair_requirements(rows: list[dict[str, str]], records: list[dict[str, str]]) -> None:
    pairs: dict[tuple[str, str], list[dict[str, str]]] = defaultdict(list)
    for row in rows:
        source_species = norm(row.get("source_species"))
        target_species = norm(row.get("target_species"))
        if source_species and target_species:
            pairs[(source_species, target_species)].append(row)

    for (source_species, target_species), items in sorted(pairs.items()):
        bundle_id = norm(items[0].get("bundle_id"))
        lift_tools = {lower_norm(item.get("orthology_lift_tool")) for item in items if lower_norm(item.get("orthology_lift_tool"))}
        if len(lift_tools) > 1:
            add_record(records, "ERROR", bundle_id, source_species, target_species, "", "orthology_lift_tool", "CONFLICT", "", f"Species pair has conflicting orthology_lift_tool values: {','.join(sorted(lift_tools))}")
            continue
        lift_tool = next(iter(lift_tools), "")
        roles = Counter(lower_norm(item.get("asset_role")) for item in items)
        if lift_tool == "liftover" and roles.get("reciprocal_best_chain", 0) < 1:
            add_record(records, "ERROR", bundle_id, source_species, target_species, "reciprocal_best_chain", "asset_role", "MISSING", "", "orthology_lift_tool=liftover requires a reciprocal_best_chain asset")
        if lift_tool == "halliftover" and roles.get("hal_alignment", 0) != 1:
            add_record(records, "ERROR", bundle_id, source_species, target_species, "hal_alignment", "asset_role", "ERROR", "", "orthology_lift_tool=halliftover requires exactly one hal_alignment asset for the species pair")


def complete_reference_record(rows: list[dict[str, str]], prefix: str, base_dir: Path, records: list[dict[str, str]]) -> dict[tuple[str, str], dict[str, str]]:
    result: dict[tuple[str, str], dict[str, str]] = {}
    fasta_field = f"{prefix}_fasta"
    fai_field = f"{prefix}_fai"
    annotation_field = f"{prefix}_annotation_file"
    species_field = f"{prefix}_species"
    assembly_field = f"{prefix}_assembly"
    for row in rows:
        values = {
            "fasta": norm(row.get(fasta_field)),
            "fai": norm(row.get(fai_field)),
            "annotation_file": norm(row.get(annotation_field)),
        }
        supplied = [key for key, value in values.items() if value]
        if supplied and len(supplied) != len(values):
            bundle_id, source_species, target_species, asset_role = row_context(row)
            add_record(records, "WARNING", bundle_id, source_species, target_species, asset_role, f"{prefix}_reference", "INCOMPLETE", "", f"Incomplete {prefix} FASTA/FAI/annotation fields; seqname concordance skipped for this row")
            continue
        if len(supplied) != len(values):
            continue
        species = norm(row.get(species_field))
        assembly = norm(row.get(assembly_field))
        key = (species, assembly)
        item = {
            "reference_id": f"{species}__{assembly}".replace(" ", "_"),
            "species": species,
            "fasta": resolve_path(values["fasta"], base_dir),
            "fai": resolve_path(values["fai"], base_dir),
            "annotation_file": resolve_path(values["annotation_file"], base_dir),
        }
        existing = result.get(key)
        if existing and existing != item:
            bundle_id, source_species, target_species, asset_role = row_context(row)
            add_record(records, "ERROR", bundle_id, source_species, target_species, asset_role, f"{prefix}_reference", "CONFLICT", "", f"Conflicting {prefix} reference paths for {species}/{assembly}")
        else:
            result[key] = item
    return result


def write_generated_reference_manifest(path: Path, rows: list[dict[str, str]]) -> None:
    write_tsv(path, SEQNAME_REFERENCE_FIELDS, rows)


def run_seqname_checks(args: argparse.Namespace, rows: list[dict[str, str]], records: list[dict[str, str]], base_dir: Path) -> None:
    seqname_manifest = norm(args.seqname_reference_manifest)
    generated_rows: list[dict[str, str]] = []
    if not seqname_manifest:
        has_reference_columns = any(any(norm(row.get(column)) for column in REFERENCE_COLUMNS) for row in rows)
        if has_reference_columns:
            generated = {}
            generated.update(complete_reference_record(rows, "source", base_dir, records))
            generated.update(complete_reference_record(rows, "target", base_dir, records))
            generated_rows = list(generated.values())
            if generated_rows:
                seqname_manifest_path = Path(args.outdir) / "seqname_reference_manifest.tsv"
                write_generated_reference_manifest(seqname_manifest_path, generated_rows)
                seqname_manifest = str(seqname_manifest_path)
    if not seqname_manifest:
        return

    seq_outdir = Path(args.outdir) / "seqname_concordance"
    argv = [
        "--reference_manifest",
        seqname_manifest,
        "--outdir",
        str(seq_outdir),
        "--check-paths",
        "true" if parse_bool(args.check_paths) else "false",
        "--strict",
        "false",
    ]
    if norm(args.alias_map):
        argv.extend(["--alias_map", resolve_path(norm(args.alias_map), base_dir)])
    check_seqname_concordance.main(argv)
    report_path = seq_outdir / "seqname_concordance.tsv"
    if not report_path.exists():
        add_record(records, "ERROR", "", "", "", "", "seqname_concordance", "MISSING", str(report_path), "Seqname concordance report was not written")
        return
    _, seq_rows = read_table(report_path)
    for seq_row in seq_rows:
        severity = norm(seq_row.get("severity"))
        if severity not in {"ERROR", "WARNING"}:
            continue
        add_record(
            records,
            severity,
            "",
            norm(seq_row.get("species")),
            "",
            "",
            "seqname_concordance",
            norm(seq_row.get("status")) or severity,
            "",
            norm(seq_row.get("message")),
        )


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--outdir", required=True)
    parser.add_argument("--check-paths", "--check_paths", default="false")
    parser.add_argument("--seqname-reference-manifest", "--seqname_reference_manifest", default="")
    parser.add_argument("--alias-map", "--alias_map", default="")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    outdir = Path(args.outdir)
    manifest = Path(args.manifest)
    check_paths = parse_bool(args.check_paths)
    records: list[dict[str, str]] = []
    rows: list[dict[str, str]] = []
    prepared_rows: list[dict[str, str]] = []

    if not manifest.exists():
        add_record(records, "ERROR", "", "", "", "", "manifest", "MISSING", str(manifest), "Bundle manifest does not exist")
    else:
        try:
            fields, rows = read_table(manifest)
            if validate_required_columns(fields, records):
                base_dir = manifest.resolve().parent
                if not rows:
                    add_record(records, "ERROR", "", "", "", "", "manifest", "EMPTY", str(manifest), "Manifest has no asset rows")
                for row_number, row in enumerate(rows, start=2):
                    prepared_rows.append(validate_row(row, records, check_paths, base_dir, row_number))
                validate_duplicate_roles(prepared_rows, records)
                validate_pair_requirements(prepared_rows, records)
                run_seqname_checks(args, prepared_rows, records, base_dir)
        except Exception as exc:
            add_record(records, "ERROR", "", "", "", "", "manifest", "ERROR", str(manifest), f"Could not validate bundle manifest: {exc}")

    validation_path = outdir / "orthology_reference_bundle_validation.tsv"
    warnings_path = outdir / "orthology_reference_bundle_warnings.tsv"
    write_tsv(validation_path, VALIDATION_FIELDS, records)
    warning_rows = [row for row in records if row["severity"] == "WARNING"]
    write_tsv(warnings_path, VALIDATION_FIELDS, warning_rows)
    counts = Counter(row["severity"] for row in records)
    print(
        "CAME orthology reference bundle validation: "
        f"ERROR={counts.get('ERROR', 0)} WARNING={counts.get('WARNING', 0)} INFO={counts.get('INFO', 0)}"
    )
    for row in records:
        if row["severity"] == "ERROR":
            print(f"ERROR\t{row['field']}\t{row['source_species']}\t{row['target_species']}\t{row['message']}", file=sys.stderr)
    return 1 if counts.get("ERROR", 0) else 0


if __name__ == "__main__":
    sys.exit(main())
