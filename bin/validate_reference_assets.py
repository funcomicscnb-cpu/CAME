#!/usr/bin/env python3
"""Validate Stage 26 reference assets declared in a CAME reference manifest."""

from __future__ import annotations

import argparse
import csv
import os
import re
import sys
from collections import Counter
from pathlib import Path


MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}
VALIDATION_FIELDS = ["severity", "reference_id", "species", "assay", "asset", "status", "path", "message"]
WARNING_FIELDS = ["severity", "reference_id", "species", "assay", "field", "message"]
SUMMARY_FIELDS = ["reference_id", "species", "assay_scope", "overall_status", "n_errors", "n_warnings"]

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
    "all": "all",
}

RECOMMENDED_ASSETS = {
    "assembly_report": ["assembly_report"],
    "repeatmask_bed": ["repeatmasker_bed", "repeatmask_bed"],
    "mappability_bed": ["mappability_bed"],
    "busco_lineage": ["busco_lineage"],
    "busco_score": ["busco_complete", "busco_score"],
    "blacklist_bed": ["blacklist_bed"],
}


def norm(value: object) -> str:
    text = str(value if value is not None else "").strip()
    return "" if text.lower() in MISSING_VALUES else text


def parse_bool(value: object) -> bool:
    return str(value).strip().lower() in {"1", "true", "t", "yes", "y"}


def infer_delimiter(path: str) -> str:
    ext = os.path.splitext(path)[1].lower()
    if ext == ".tsv":
        return "\t"
    if ext == ".csv":
        return ","
    with open(path, newline="") as handle:
        sample = handle.read(min(65536, os.path.getsize(path)))
    return "\t" if sample.count("\t") > sample.count(",") else ","


def read_table(path: str) -> tuple[list[str], list[dict[str, str]]]:
    delimiter = infer_delimiter(path)
    with open(path, newline="") as handle:
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


def parse_assays(raw: str) -> list[str]:
    assays: list[str] = []
    for item in str(raw or "").split(","):
        key = norm(item).lower()
        if not key:
            continue
        assay = ASSAY_ALIASES.get(key, key)
        if assay == "all":
            for expanded in ["rna", "atac", "wgs"]:
                if expanded not in assays:
                    assays.append(expanded)
            continue
        if assay not in {"rna", "atac", "wgs"}:
            raise SystemExit(f"ERROR: unsupported --assay value: {item}")
        if assay not in assays:
            assays.append(assay)
    return assays or ["rna", "atac"]


def choose(row: dict[str, str], *fields: str) -> tuple[str, str]:
    for field in fields:
        value = norm(row.get(field))
        if value:
            return field, value
    return fields[0] if fields else "", ""


def resolve_path(value: str, base_dir: Path) -> str:
    text = norm(value)
    if not text or "://" in text or os.path.isabs(text):
        return text
    return str((base_dir / text).resolve())


def path_exists(path: str, asset: str) -> bool:
    if not path:
        return False
    if os.path.exists(path):
        return True
    if asset == "star_index":
        return os.path.isdir(path) and os.path.exists(os.path.join(path, "SA"))
    if asset in {"bowtie2_index", "bowtie2_index_prefix"}:
        return any(os.path.exists(path + suffix) for suffix in [".1.bt2", ".1.bt2l"])
    if asset in {"bwa_index", "bwa_index_prefix"}:
        return any(os.path.exists(path + suffix) for suffix in [".amb", ".ann", ".bwt", ".pac", ".sa"])
    return False


def add_validation(
    rows: list[dict[str, str]],
    severity: str,
    reference_id: str,
    species: str,
    assay: str,
    asset: str,
    status: str,
    path: str,
    message: str,
) -> None:
    rows.append(
        {
            "severity": severity,
            "reference_id": reference_id,
            "species": species,
            "assay": assay,
            "asset": asset,
            "status": status,
            "path": path,
            "message": message,
        }
    )


def add_warning(
    rows: list[dict[str, str]],
    severity: str,
    reference_id: str,
    species: str,
    assay: str,
    field: str,
    message: str,
) -> None:
    rows.append(
        {
            "severity": severity,
            "reference_id": reference_id,
            "species": species,
            "assay": assay,
            "field": field,
            "message": message,
        }
    )


def check_asset(
    validation: list[dict[str, str]],
    warnings: list[dict[str, str]],
    row: dict[str, str],
    base_dir: Path,
    assay: str,
    asset: str,
    aliases: list[str],
    required: bool,
    check_paths: bool,
) -> bool:
    reference_id = norm(row.get("reference_id"))
    species = norm(row.get("species"))
    field, value = choose(row, *aliases)
    if not value:
        severity = "ERROR" if required else "INFO"
        status = "ERROR" if required else "NOT_DECLARED"
        message = f"{assay} requires {asset}" if required else f"{asset} is not declared"
        add_validation(validation, severity, reference_id, species, assay, asset, status, "", message)
        if required:
            add_warning(warnings, "ERROR", reference_id, species, assay, asset, message)
        return False
    resolved = resolve_path(value, base_dir)
    if check_paths and not path_exists(resolved, asset):
        message = f"Declared {asset} path does not exist: {value}"
        add_validation(validation, "ERROR", reference_id, species, assay, asset, "ERROR", value, message)
        add_warning(warnings, "ERROR", reference_id, species, assay, asset, message)
        return False
    add_validation(
        validation,
        "INFO",
        reference_id,
        species,
        assay,
        asset,
        "OK",
        value,
        f"{asset} declared via {field}",
    )
    return True


def parse_busco_score(value: str) -> float | None:
    text = norm(value)
    if not text:
        return None
    match = re.search(r"[-+]?\d+(?:\.\d+)?", text)
    if not match:
        return None
    try:
        return float(match.group(0))
    except ValueError:
        return None


def validate_busco(
    validation: list[dict[str, str]],
    warnings: list[dict[str, str]],
    row: dict[str, str],
    strict: bool,
    allow_low_quality_reference: bool,
) -> None:
    reference_id = norm(row.get("reference_id"))
    species = norm(row.get("species"))
    field, value = choose(row, "busco_complete", "busco_score")
    if not value:
        add_warning(warnings, "WARNING", reference_id, species, "all", "busco_score", "Recommended BUSCO score is absent")
        add_validation(validation, "WARNING", reference_id, species, "all", "busco_score", "NOT_DECLARED", "", "Recommended BUSCO score is absent")
        return
    score = parse_busco_score(value)
    if score is None:
        add_warning(warnings, "WARNING", reference_id, species, "all", field, f"BUSCO score is not numeric: {value}")
        add_validation(validation, "WARNING", reference_id, species, "all", "busco_score", "WARNING", value, "BUSCO score is not numeric")
        return
    if score < 70 and strict and not allow_low_quality_reference:
        message = f"BUSCO completeness {score:g} is below 70; strict mode treats this as a low-quality reference error"
        add_warning(warnings, "ERROR", reference_id, species, "all", field, message)
        add_validation(validation, "ERROR", reference_id, species, "all", "busco_score", "ERROR", value, message)
    elif score < 80:
        message = f"BUSCO completeness {score:g} is below 80; strong warning for reference completeness"
        add_warning(warnings, "WARNING", reference_id, species, "all", field, message)
        add_validation(validation, "WARNING", reference_id, species, "all", "busco_score", "WARNING", value, message)
    elif score < 90:
        message = f"BUSCO completeness {score:g} is below 90"
        add_warning(warnings, "WARNING", reference_id, species, "all", field, message)
        add_validation(validation, "WARNING", reference_id, species, "all", "busco_score", "WARNING", value, message)
    else:
        add_validation(validation, "INFO", reference_id, species, "all", "busco_score", "OK", value, f"BUSCO completeness {score:g}")


def validate_recommended_assets(
    validation: list[dict[str, str]],
    warnings: list[dict[str, str]],
    row: dict[str, str],
) -> None:
    reference_id = norm(row.get("reference_id"))
    species = norm(row.get("species"))
    for asset, aliases in RECOMMENDED_ASSETS.items():
        if asset == "busco_score":
            continue
        field, value = choose(row, *aliases)
        if not value:
            add_warning(warnings, "WARNING", reference_id, species, "all", asset, f"Recommended reference asset is absent: {asset}")
            add_validation(validation, "WARNING", reference_id, species, "all", asset, "NOT_DECLARED", "", f"Recommended asset is absent; checked aliases: {', '.join(aliases)}")
        else:
            add_validation(validation, "INFO", reference_id, species, "all", asset, "OK", value, f"Recommended asset declared via {field}")


def validate_row(
    row: dict[str, str],
    base_dir: Path,
    assays: list[str],
    check_paths: bool,
    strict: bool,
    allow_low_quality_reference: bool,
    validation: list[dict[str, str]],
    warnings: list[dict[str, str]],
) -> None:
    validate_recommended_assets(validation, warnings, row)
    validate_busco(validation, warnings, row, strict, allow_low_quality_reference)
    for assay in assays:
        fasta_ok = check_asset(validation, warnings, row, base_dir, assay, "fasta", ["fasta", "genome_fasta"], True, check_paths)
        check_asset(validation, warnings, row, base_dir, assay, "fai", ["fai"], True, check_paths)
        if assay == "rna":
            annotation_ok = check_asset(
                validation,
                warnings,
                row,
                base_dir,
                assay,
                "annotation",
                ["annotation_file", "annotation_gtf", "annotation_gff3", "gtf"],
                True,
                check_paths,
            )
            check_asset(validation, warnings, row, base_dir, assay, "star_index", ["star_index"], False, check_paths)
            if fasta_ok and annotation_ok and not norm(row.get("star_index")):
                add_validation(validation, "INFO", norm(row.get("reference_id")), norm(row.get("species")), assay, "star_index_or_buildable", "OK", "", "STAR index is not declared, but FASTA plus annotation are buildable")
        elif assay == "atac":
            check_asset(validation, warnings, row, base_dir, assay, "bowtie2_index", ["bowtie2_index", "bowtie2_index_prefix"], False, check_paths)
            if fasta_ok and not (norm(row.get("bowtie2_index")) or norm(row.get("bowtie2_index_prefix"))):
                add_validation(validation, "INFO", norm(row.get("reference_id")), norm(row.get("species")), assay, "bowtie2_index_or_buildable", "OK", "", "Bowtie2 index is not declared, but FASTA is buildable")
        elif assay == "wgs":
            check_asset(validation, warnings, row, base_dir, assay, "dict", ["dict", "sequence_dict"], True, check_paths)
            check_asset(validation, warnings, row, base_dir, assay, "bwa_index", ["bwa_index", "bwa_index_prefix"], False, check_paths)
            if fasta_ok and not (norm(row.get("bwa_index")) or norm(row.get("bwa_index_prefix"))):
                add_validation(validation, "INFO", norm(row.get("reference_id")), norm(row.get("species")), assay, "bwa_index_or_buildable", "OK", "", "BWA index is not declared, but FASTA is buildable")


def validate_manifest(fields: list[str], rows: list[dict[str, str]], validation: list[dict[str, str]], warnings: list[dict[str, str]]) -> None:
    for column in ["reference_id", "species"]:
        if column not in fields:
            add_warning(warnings, "ERROR", "", "", "all", column, f"Missing required manifest column: {column}")
            add_validation(validation, "ERROR", "", "", "all", column, "ERROR", "", f"Missing required manifest column: {column}")
    if "fasta" not in fields and "genome_fasta" not in fields:
        add_warning(warnings, "ERROR", "", "", "all", "fasta", "Missing required FASTA column: fasta or genome_fasta")
        add_validation(validation, "ERROR", "", "", "all", "fasta", "ERROR", "", "Missing required FASTA column: fasta or genome_fasta")
    if not rows:
        add_warning(warnings, "ERROR", "", "", "all", "rows", "Reference manifest has no rows")
        add_validation(validation, "ERROR", "", "", "all", "rows", "ERROR", "", "Reference manifest has no rows")
    counts = Counter(norm(row.get("reference_id")) for row in rows if norm(row.get("reference_id")))
    for reference_id, count in sorted(counts.items()):
        if count > 1:
            add_warning(warnings, "ERROR", reference_id, "", "all", "reference_id", f"Duplicate reference_id: {reference_id}")
            add_validation(validation, "ERROR", reference_id, "", "all", "reference_id", "ERROR", "", f"Duplicate reference_id: {reference_id}")


def summarize(rows: list[dict[str, str]], references: list[dict[str, str]], assays: list[str]) -> list[dict[str, str]]:
    result: list[dict[str, str]] = []
    for row in references:
        reference_id = norm(row.get("reference_id"))
        species = norm(row.get("species"))
        relevant = [item for item in rows if item["reference_id"] == reference_id or not item["reference_id"]]
        n_errors = sum(1 for item in relevant if item["severity"] == "ERROR")
        n_warnings = sum(1 for item in relevant if item["severity"] == "WARNING")
        status = "ERROR" if n_errors else ("WARNING" if n_warnings else "OK")
        result.append(
            {
                "reference_id": reference_id,
                "species": species,
                "assay_scope": ",".join(assays),
                "overall_status": status,
                "n_errors": str(n_errors),
                "n_warnings": str(n_warnings),
            }
        )
    if not references:
        n_errors = sum(1 for item in rows if item["severity"] == "ERROR")
        n_warnings = sum(1 for item in rows if item["severity"] == "WARNING")
        result.append({"reference_id": "", "species": "", "assay_scope": ",".join(assays), "overall_status": "ERROR", "n_errors": str(n_errors), "n_warnings": str(n_warnings)})
    return result


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference_manifest", required=True)
    parser.add_argument("--outdir", required=True)
    parser.add_argument("--check-paths", "--check_paths", default="false")
    parser.add_argument("--strict", default="false")
    parser.add_argument("--assay", default="rna,atac")
    parser.add_argument("--allow_low_quality_reference", default="false")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    outdir = Path(args.outdir)
    validation: list[dict[str, str]] = []
    warnings: list[dict[str, str]] = []
    try:
        fields, rows = read_table(args.reference_manifest)
    except Exception as exc:
        add_validation(validation, "ERROR", "", "", "all", "reference_manifest", "ERROR", args.reference_manifest, f"Could not read reference manifest: {exc}")
        add_warning(warnings, "ERROR", "", "", "all", "reference_manifest", f"Could not read reference manifest: {exc}")
        fields, rows = [], []
    assays = parse_assays(args.assay)
    base_dir = Path(args.reference_manifest).resolve().parent
    check_paths = parse_bool(args.check_paths)
    strict = parse_bool(args.strict)
    allow_low_quality_reference = parse_bool(args.allow_low_quality_reference)
    validate_manifest(fields, rows, validation, warnings)
    for row in rows:
        validate_row(row, base_dir, assays, check_paths, strict, allow_low_quality_reference, validation, warnings)

    write_tsv(outdir / "reference_asset_validation.tsv", VALIDATION_FIELDS, validation)
    write_tsv(outdir / "reference_asset_warnings.tsv", WARNING_FIELDS, warnings)
    write_tsv(outdir / "reference_asset_summary.tsv", SUMMARY_FIELDS, summarize(validation, rows, assays))
    errors = sum(1 for row in validation if row["severity"] == "ERROR")
    warn_count = sum(1 for row in validation if row["severity"] == "WARNING")
    print(f"CAME reference asset validation: ERROR={errors} WARNING={warn_count}")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
