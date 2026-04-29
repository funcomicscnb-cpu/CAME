#!/usr/bin/env python3
"""Check FASTA, FAI, annotation, and alias-map sequence-name concordance."""

from __future__ import annotations

import argparse
import csv
import os
from pathlib import Path


MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}
CONCORDANCE_FIELDS = [
    "severity",
    "reference_id",
    "species",
    "comparison",
    "status",
    "overlap_fraction",
    "fasta_only",
    "fai_only",
    "annotation_only",
    "message",
]
WARNING_FIELDS = ["severity", "reference_id", "species", "comparison", "message"]


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


def add_result(
    rows: list[dict[str, str]],
    warnings: list[dict[str, str]],
    severity: str,
    reference_id: str,
    species: str,
    comparison: str,
    status: str,
    message: str,
    overlap_fraction: str = "",
    fasta_only: list[str] | None = None,
    fai_only: list[str] | None = None,
    annotation_only: list[str] | None = None,
) -> None:
    rows.append(
        {
            "severity": severity,
            "reference_id": reference_id,
            "species": species,
            "comparison": comparison,
            "status": status,
            "overlap_fraction": overlap_fraction,
            "fasta_only": ",".join((fasta_only or [])[:10]),
            "fai_only": ",".join((fai_only or [])[:10]),
            "annotation_only": ",".join((annotation_only or [])[:10]),
            "message": message,
        }
    )
    if severity in {"WARNING", "ERROR"}:
        warnings.append({"severity": severity, "reference_id": reference_id, "species": species, "comparison": comparison, "message": message})


def parse_fasta_names(path: Path) -> set[str]:
    names: set[str] = set()
    with path.open() as handle:
        for line in handle:
            if line.startswith(">"):
                name = line[1:].strip().split()[0]
                if name:
                    names.add(name)
    return names


def parse_fai_names(path: Path) -> set[str]:
    names: set[str] = set()
    with path.open() as handle:
        for line in handle:
            if not line.strip() or line.startswith("#"):
                continue
            names.add(line.rstrip("\n").split("\t")[0])
    return names


def parse_annotation_names(path: Path) -> set[str]:
    names: set[str] = set()
    with path.open() as handle:
        for line in handle:
            if not line.strip() or line.startswith("#"):
                continue
            parts = line.rstrip("\n").split("\t")
            if parts:
                names.add(parts[0])
    return names


def strip_chr(name: str) -> str:
    lower = name.lower()
    return name[3:] if lower.startswith("chr") else name


def chr_prefix_mismatch(left: set[str], right: set[str]) -> bool:
    return bool({strip_chr(name) for name in left} & {strip_chr(name) for name in right}) and not bool(left & right)


def alias_values(rows: list[dict[str, str]], reference_id: str) -> set[str]:
    values: set[str] = set()
    for row in rows:
        if norm(row.get("reference_id")) != reference_id:
            continue
        for field in ["sequence_name", "assigned_molecule", "genbank_accession", "refseq_accession", "ucsc_style_name"]:
            value = norm(row.get(field))
            if value:
                values.add(value)
    return values


def available_path(
    row: dict[str, str],
    base_dir: Path,
    aliases: list[str],
    check_paths: bool,
    reference_id: str,
    species: str,
    comparison: str,
    results: list[dict[str, str]],
    warnings: list[dict[str, str]],
) -> Path | None:
    _, value = choose(row, *aliases)
    if not value:
        add_result(results, warnings, "WARNING", reference_id, species, comparison, "NOT_DECLARED", f"Required path is not declared; checked {', '.join(aliases)}")
        return None
    path = Path(resolve_path(value, base_dir))
    if not path.exists():
        severity = "ERROR" if check_paths else "WARNING"
        status = "ERROR" if check_paths else "SKIPPED"
        add_result(results, warnings, severity, reference_id, species, comparison, status, f"Path is not available; content check skipped: {value}")
        return None
    return path


def compare_fasta_fai(reference_id: str, species: str, fasta_names: set[str], fai_names: set[str], results: list[dict[str, str]], warnings: list[dict[str, str]]) -> None:
    missing_in_fai = sorted(fasta_names - fai_names)
    extra_in_fai = sorted(fai_names - fasta_names)
    if missing_in_fai or extra_in_fai:
        add_result(
            results,
            warnings,
            "ERROR",
            reference_id,
            species,
            "fasta_vs_fai",
            "ERROR",
            "FASTA and FAI sequence names differ",
            fasta_only=missing_in_fai,
            fai_only=extra_in_fai,
        )
    else:
        add_result(results, warnings, "INFO", reference_id, species, "fasta_vs_fai", "OK", "FASTA and FAI sequence names match exactly")


def compare_fasta_annotation(
    reference_id: str,
    species: str,
    fasta_names: set[str],
    annotation_names: set[str],
    strict: bool,
    results: list[dict[str, str]],
    warnings: list[dict[str, str]],
) -> None:
    overlap = fasta_names & annotation_names
    fraction = len(overlap) / len(annotation_names) if annotation_names else 0.0
    annotation_only = sorted(annotation_names - fasta_names)
    fasta_only = sorted(fasta_names - annotation_names)
    if not annotation_names:
        add_result(results, warnings, "WARNING", reference_id, species, "fasta_vs_annotation", "SKIPPED", "Annotation file has no feature seqnames")
        return
    if not overlap:
        message = "FASTA and annotation have zero shared sequence names"
        if chr_prefix_mismatch(fasta_names, annotation_names):
            message += "; common chr-prefix mismatch detected (for example chr1 vs 1). Provide an assembly alias map or normalize seqnames before running real mode."
        else:
            message += f"; examples FASTA={','.join(sorted(fasta_names)[:3])} annotation={','.join(sorted(annotation_names)[:3])}"
        add_result(results, warnings, "ERROR", reference_id, species, "fasta_vs_annotation", "ERROR", message, f"{fraction:.6f}", fasta_only, annotation_only=annotation_only)
    elif annotation_only:
        severity = "ERROR" if strict and fraction < 0.5 else "WARNING"
        status = "ERROR" if severity == "ERROR" else "WARNING"
        add_result(
            results,
            warnings,
            severity,
            reference_id,
            species,
            "fasta_vs_annotation",
            status,
            f"FASTA and annotation partially overlap; {fraction:.2%} of annotation seqnames are present in FASTA",
            f"{fraction:.6f}",
            fasta_only,
            annotation_only=annotation_only,
        )
    else:
        add_result(results, warnings, "INFO", reference_id, species, "fasta_vs_annotation", "OK", "All annotation seqnames are present in FASTA", f"{fraction:.6f}")


def compare_annotation_alias(
    reference_id: str,
    species: str,
    annotation_names: set[str],
    aliases: set[str],
    results: list[dict[str, str]],
    warnings: list[dict[str, str]],
) -> None:
    if not aliases:
        add_result(results, warnings, "WARNING", reference_id, species, "annotation_vs_alias_map", "SKIPPED", "No alias-map rows available for reference")
        return
    missing = sorted(annotation_names - aliases)
    if missing:
        add_result(results, warnings, "WARNING", reference_id, species, "annotation_vs_alias_map", "WARNING", "Some annotation seqnames are absent from the alias map", annotation_only=missing)
    else:
        add_result(results, warnings, "INFO", reference_id, species, "annotation_vs_alias_map", "OK", "Annotation seqnames are represented in the alias map")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference_manifest", required=True)
    parser.add_argument("--outdir", required=True)
    parser.add_argument("--alias_map", default="")
    parser.add_argument("--check-paths", "--check_paths", default="false")
    parser.add_argument("--strict", default="false")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    outdir = Path(args.outdir)
    results: list[dict[str, str]] = []
    warnings: list[dict[str, str]] = []
    try:
        _, references = read_table(args.reference_manifest)
    except Exception as exc:
        add_result(results, warnings, "ERROR", "", "", "reference_manifest", "ERROR", f"Could not read reference manifest: {exc}")
        references = []
    alias_rows: list[dict[str, str]] = []
    if args.alias_map and os.path.exists(args.alias_map):
        _, alias_rows = read_table(args.alias_map)
    base_dir = Path(args.reference_manifest).resolve().parent
    check_paths = parse_bool(args.check_paths)
    strict = parse_bool(args.strict)
    for row in references:
        reference_id = norm(row.get("reference_id"))
        species = norm(row.get("species"))
        fasta_path = available_path(row, base_dir, ["fasta", "genome_fasta"], check_paths, reference_id, species, "fasta", results, warnings)
        fai_path = available_path(row, base_dir, ["fai"], check_paths, reference_id, species, "fai", results, warnings)
        annotation_path = available_path(row, base_dir, ["annotation_file", "annotation_gtf", "annotation_gff3", "gtf"], check_paths, reference_id, species, "annotation", results, warnings)
        fasta_names = parse_fasta_names(fasta_path) if fasta_path else set()
        fai_names = parse_fai_names(fai_path) if fai_path else set()
        annotation_names = parse_annotation_names(annotation_path) if annotation_path else set()
        if fasta_names and fai_names:
            compare_fasta_fai(reference_id, species, fasta_names, fai_names, results, warnings)
        if fasta_names and annotation_names:
            compare_fasta_annotation(reference_id, species, fasta_names, annotation_names, strict, results, warnings)
        if annotation_names:
            compare_annotation_alias(reference_id, species, annotation_names, alias_values(alias_rows, reference_id), results, warnings)

    write_tsv(outdir / "seqname_concordance.tsv", CONCORDANCE_FIELDS, results)
    write_tsv(outdir / "seqname_concordance_warnings.tsv", WARNING_FIELDS, warnings)
    errors = sum(1 for row in results if row["severity"] == "ERROR")
    print(f"CAME seqname concordance: ERROR={errors} WARNING={sum(1 for row in results if row['severity'] == 'WARNING')}")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
