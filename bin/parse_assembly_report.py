#!/usr/bin/env python3
"""Parse assembly reports or simple alias maps for Stage 26 reference quality."""

from __future__ import annotations

import argparse
import csv
import os
from pathlib import Path


MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}
ALIAS_FIELDS = [
    "reference_id",
    "sequence_name",
    "sequence_role",
    "assigned_molecule",
    "genbank_accession",
    "refseq_accession",
    "ucsc_style_name",
]
WARNING_FIELDS = ["severity", "reference_id", "source", "row", "message"]


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
        writer = csv.DictWriter(handle, fieldnames=fields, delimiter="\t", extrasaction="ignore", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def resolve_path(value: str, base_dir: Path) -> str:
    text = norm(value)
    if not text or "://" in text or os.path.isabs(text):
        return text
    return str((base_dir / text).resolve())


def add_warning(rows: list[dict[str, str]], severity: str, reference_id: str, source: str, row: int | str, message: str) -> None:
    rows.append({"severity": severity, "reference_id": reference_id, "source": source, "row": str(row or ""), "message": message})


def parse_simple_alias_map(reference_id: str, path: Path, warnings: list[dict[str, str]], strict: bool) -> list[dict[str, str]]:
    delimiter = infer_delimiter(str(path))
    with path.open(newline="") as handle:
        reader = csv.DictReader(handle, delimiter=delimiter)
        fields = reader.fieldnames or []
        normalized = {field.lower().replace("-", "_"): field for field in fields}
        required = "sequence_name"
        if required not in normalized:
            return []
        rows: list[dict[str, str]] = []
        for row_number, row in enumerate(reader, start=2):
            sequence_name = norm(row.get(normalized.get("sequence_name", "")))
            if not sequence_name:
                message = "Simple alias map row is missing sequence_name"
                add_warning(warnings, "ERROR" if strict else "WARNING", reference_id, str(path), row_number, message)
                continue
            rows.append(
                {
                    "reference_id": reference_id,
                    "sequence_name": sequence_name,
                    "sequence_role": norm(row.get(normalized.get("sequence_role", ""))),
                    "assigned_molecule": norm(row.get(normalized.get("assigned_molecule", ""))),
                    "genbank_accession": norm(row.get(normalized.get("genbank_accession", ""))),
                    "refseq_accession": norm(row.get(normalized.get("refseq_accession", ""))),
                    "ucsc_style_name": norm(row.get(normalized.get("ucsc_style_name", ""))),
                }
            )
    return rows


def parse_ncbi_report(reference_id: str, path: Path, warnings: list[dict[str, str]], strict: bool) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    with path.open() as handle:
        for row_number, line in enumerate(handle, start=1):
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) < 7:
                message = f"Malformed assembly report row: expected at least 7 tab-separated columns, found {len(parts)}"
                add_warning(warnings, "ERROR" if strict else "WARNING", reference_id, str(path), row_number, message)
                continue
            rows.append(
                {
                    "reference_id": reference_id,
                    "sequence_name": norm(parts[0]),
                    "sequence_role": norm(parts[1]) if len(parts) > 1 else "",
                    "assigned_molecule": norm(parts[2]) if len(parts) > 2 else "",
                    "genbank_accession": norm(parts[4]) if len(parts) > 4 else "",
                    "refseq_accession": norm(parts[6]) if len(parts) > 6 else "",
                    "ucsc_style_name": norm(parts[9]) if len(parts) > 9 else "",
                }
            )
    return rows


def parse_report(reference_id: str, path: Path, warnings: list[dict[str, str]], strict: bool) -> list[dict[str, str]]:
    simple = parse_simple_alias_map(reference_id, path, warnings, strict)
    if simple:
        return simple
    rows = parse_ncbi_report(reference_id, path, warnings, strict)
    if not rows:
        add_warning(warnings, "ERROR" if strict else "WARNING", reference_id, str(path), "", "Assembly report did not contain any parseable sequence rows")
    return rows


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference_manifest", required=True)
    parser.add_argument("--outdir", required=True)
    parser.add_argument("--check-paths", "--check_paths", default="false")
    parser.add_argument("--strict", default="false")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    outdir = Path(args.outdir)
    warnings: list[dict[str, str]] = []
    alias_rows: list[dict[str, str]] = []
    try:
        _, references = read_table(args.reference_manifest)
    except Exception as exc:
        add_warning(warnings, "ERROR", "", "reference_manifest", "", f"Could not read reference manifest: {exc}")
        references = []
    base_dir = Path(args.reference_manifest).resolve().parent
    check_paths = parse_bool(args.check_paths)
    strict = parse_bool(args.strict)
    for row in references:
        reference_id = norm(row.get("reference_id"))
        report_value = norm(row.get("assembly_report"))
        if not report_value:
            add_warning(warnings, "WARNING", reference_id, "assembly_report", "", "assembly_report is not declared")
            continue
        report_path = Path(resolve_path(report_value, base_dir))
        if not report_path.exists():
            severity = "ERROR" if check_paths else "WARNING"
            add_warning(warnings, severity, reference_id, report_value, "", "assembly_report path is not available; parsing skipped")
            continue
        alias_rows.extend(parse_report(reference_id, report_path, warnings, strict))

    write_tsv(outdir / "seqname_alias_map.tsv", ALIAS_FIELDS, alias_rows)
    write_tsv(outdir / "assembly_report_warnings.tsv", WARNING_FIELDS, warnings)
    errors = sum(1 for row in warnings if row["severity"] == "ERROR")
    print(f"CAME assembly report parsing: ERROR={errors} WARNING={sum(1 for row in warnings if row['severity'] == 'WARNING')}")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
