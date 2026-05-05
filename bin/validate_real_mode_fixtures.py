#!/usr/bin/env python3
"""Validate tiny Stage 28 real-mode fixture files."""

from __future__ import annotations

import argparse
import csv
import hashlib
import os
import re
import sys
from pathlib import Path


VALIDATION_FIELDS = ["severity", "check_id", "subject", "message", "remediation"]
MANIFEST_FIELDS = ["path", "kind", "size_bytes", "sha256", "status"]
MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}
LOCAL_ABSOLUTE_PATTERNS = [
    re.compile(r"(^|[^A-Za-z0-9_])/" + "Users" + r"/[^ \t\n:'\"]+"),
    re.compile(r"(^|[^A-Za-z0-9_])/" + "home" + r"/[A-Za-z0-9._-]+/[^ \t\n:'\"]+"),
    re.compile(r"(^|[^A-Za-z0-9_])/" + "tmp" + r"/[^ \t\n:'\"]+"),
    re.compile(r"(^|[^A-Za-z0-9_])/" + "var/folders" + r"/[^ \t\n:'\"]+"),
    re.compile(r"[A-Za-z]:\\Users\\[^ \t\n:'\"]+"),
]
FORBIDDEN_SUFFIXES = {
    ".bam",
    ".bai",
    ".bt2",
    ".bt2l",
    ".bwt",
    ".pac",
    ".sa",
    ".tbi",
    ".idx",
    ".crai",
    ".cram",
}
FORBIDDEN_COMPOUND_SUFFIXES = {".vcf.gz", ".bcf.gz"}
EXPECTED_FILES = [
    "README.md",
    "tiny_reference/tiny.fa",
    "tiny_reference/tiny.fa.fai",
    "tiny_reference/tiny.dict",
    "tiny_reference/tiny.gtf",
    "tiny_reference/tiny.gff3",
    "tiny_reference/assembly_report.txt",
    "tiny_reference/alias_map.tsv",
    "tiny_reference/tiny.chrom.sizes",
    "tiny_reference/tiny.tss.bed",
    "tiny_reference/repeatmasker.bed",
    "tiny_reference/mappability.bed",
    "tiny_reference/blacklist.bed",
    "tiny_rna/tiny_rna_1_R1.fastq",
    "tiny_rna/tiny_rna_1_R2.fastq",
    "tiny_atac/tiny_atac_1_R1.fastq",
    "tiny_atac/tiny_atac_1_R2.fastq",
    "tiny_wgs/tiny_wgs_1_R1.fastq",
    "tiny_wgs/tiny_wgs_1_R2.fastq",
    "manifests/reference_manifest.tsv",
    "manifests/real_mode_metadata.tsv",
    "manifests/wgs_samplesheet.csv",
    "manifests/expected_output_contracts.tsv",
]
REFERENCE_PATH_FIELDS = {
    "assembly_report",
    "fasta",
    "fai",
    "dict",
    "sequence_dict",
    "annotation_file",
    "gtf",
    "gff3",
    "genome_fasta",
    "chrom_sizes",
    "tss_bed",
    "blacklist_bed",
    "repeatmasker_bed",
    "repeatmask_bed",
    "mappability_bed",
    "transcript_fasta",
    "star_index",
    "bwa_index",
    "bwa_index_prefix",
    "bowtie2_index",
}


def norm(value: object) -> str:
    text = str(value if value is not None else "").strip()
    return "" if text.lower() in MISSING_VALUES else text


def add(rows: list[dict[str, str]], severity: str, check_id: str, subject: str, message: str, remediation: str = "") -> None:
    rows.append(
        {
            "severity": severity,
            "check_id": check_id,
            "subject": subject,
            "message": message,
            "remediation": remediation,
        }
    )


def infer_delimiter(path: Path) -> str:
    if path.suffix.lower() == ".csv":
        return ","
    return "\t"


def read_table(path: Path, validation: list[dict[str, str]], check_id: str) -> tuple[list[str], list[dict[str, str]]]:
    if not path.exists():
        add(validation, "ERROR", check_id, path.as_posix(), "Table does not exist")
        return [], []
    try:
        with path.open(newline="", encoding="utf-8") as handle:
            reader = csv.DictReader(handle, delimiter=infer_delimiter(path))
            raw_fields = reader.fieldnames or []
            fields = [norm(field) for field in raw_fields]
            rows: list[dict[str, str]] = []
            for row_number, row in enumerate(reader, start=2):
                if None in row:
                    add(validation, "ERROR", check_id, f"{path}:{row_number}", "Row has more values than header columns")
                rows.append({field: norm(row.get(raw_field)) for raw_field, field in zip(raw_fields, fields)})
    except Exception as exc:
        add(validation, "ERROR", check_id, path.as_posix(), f"Could not read table: {exc}")
        return [], []
    if not fields:
        add(validation, "ERROR", check_id, path.as_posix(), "Table has no header")
    if len(fields) != len(set(fields)):
        add(validation, "ERROR", check_id, path.as_posix(), "Table has duplicate column names")
    return fields, rows


def write_tsv(path: Path, fields: list[str], rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
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


def rel(path: Path, root: Path) -> str:
    try:
        return path.relative_to(root).as_posix()
    except ValueError:
        return path.as_posix()


def file_kind(path: Path) -> str:
    name = path.name.lower()
    if name.endswith(".fastq") or name.endswith(".fq"):
        return "fastq"
    if name.endswith(".fa") or name.endswith(".fasta"):
        return "fasta"
    if name.endswith(".fai"):
        return "fai"
    if name.endswith(".gtf"):
        return "gtf"
    if name.endswith(".gff3"):
        return "gff3"
    if name.endswith(".dict"):
        return "sequence_dict"
    if name.endswith(".bed"):
        return "bed"
    if name.endswith(".csv"):
        return "csv"
    if name.endswith(".tsv"):
        return "tsv"
    if name.endswith(".md"):
        return "markdown"
    return "text"


def is_forbidden_generated_file(path: Path) -> bool:
    lower = path.name.lower()
    if any(lower.endswith(suffix) for suffix in FORBIDDEN_COMPOUND_SUFFIXES):
        return True
    if path.suffix.lower() in FORBIDDEN_SUFFIXES:
        return True
    if lower.endswith((".amb", ".ann")):
        return True
    return False


def check_expected_files(root: Path, validation: list[dict[str, str]]) -> None:
    for item in EXPECTED_FILES:
        path = root / item
        if path.is_file() and path.stat().st_size > 0:
            add(validation, "INFO", "expected_file", item, "Expected fixture file is present")
        else:
            add(validation, "ERROR", "expected_file", item, "Expected fixture file is missing or empty", "Regenerate fixtures with bin/make_real_mode_fixtures.py")


def check_file_inventory(root: Path, max_file_bytes: int, max_total_bytes: int, validation: list[dict[str, str]]) -> list[dict[str, str]]:
    manifest_rows: list[dict[str, str]] = []
    total = 0
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        size = path.stat().st_size
        total += size
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        status = "OK"
        subject = rel(path, root)
        if size > max_file_bytes:
            status = "ERROR"
            add(validation, "ERROR", "file_size", subject, f"Fixture file exceeds max-file-bytes ({size} > {max_file_bytes})", "Keep fixtures tiny or raise the validator threshold intentionally")
        if is_forbidden_generated_file(path):
            status = "ERROR"
            add(validation, "ERROR", "generated_binary", subject, "Generated binary/index-like file is not allowed in tiny fixtures", "Do not commit BAM, VCF index, aligner index, CRAM, or BCF outputs")
        data = path.read_bytes()
        if b"\x00" in data:
            status = "ERROR"
            add(validation, "ERROR", "text_only", subject, "Fixture file contains NUL bytes", "Store only tiny text fixtures")
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError:
            status = "ERROR"
            add(validation, "ERROR", "text_only", subject, "Fixture file is not UTF-8 text", "Store only tiny text fixtures")
            text = ""
        for line_number, line in enumerate(text.splitlines(), start=1):
            if any(pattern.search(line) for pattern in LOCAL_ABSOLUTE_PATTERNS):
                status = "ERROR"
                add(validation, "ERROR", "absolute_path", f"{subject}:{line_number}", "Local absolute path found in fixture content", "Use paths relative to the manifest file")
                break
        manifest_rows.append(
            {
                "path": subject,
                "kind": file_kind(path),
                "size_bytes": str(size),
                "sha256": digest,
                "status": status,
            }
        )
    if total > max_total_bytes:
        add(validation, "ERROR", "total_size", rel(root, root), f"Fixture tree exceeds max-total-bytes ({total} > {max_total_bytes})", "Keep Stage 28 fixtures small")
    else:
        add(validation, "INFO", "total_size", root.as_posix(), f"Fixture tree size is {total} bytes")
    return manifest_rows


def resolve_manifest_path(value: str, base: Path) -> Path:
    text = norm(value)
    if not text:
        return Path("")
    if "://" in text or os.path.isabs(text):
        return Path(text)
    return (base / text).resolve()


def check_relative_path(value: str, subject: str, validation: list[dict[str, str]]) -> None:
    text = norm(value)
    if not text:
        return
    if "://" in text or os.path.isabs(text):
        add(validation, "ERROR", "relative_paths", subject, f"Fixture path must be relative, found: {text}", "Use a path relative to the manifest file")


def parse_fasta_names(path: Path) -> set[str]:
    names: set[str] = set()
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            if line.startswith(">"):
                name = line[1:].strip().split()[0]
                if name:
                    names.add(name)
    return names


def parse_fai_names(path: Path) -> set[str]:
    names: set[str] = set()
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            if not line.strip() or line.startswith("#"):
                continue
            names.add(line.rstrip("\n").split("\t")[0])
    return names


def parse_annotation_names(path: Path) -> set[str]:
    names: set[str] = set()
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            if not line.strip() or line.startswith("#"):
                continue
            parts = line.rstrip("\n").split("\t")
            if parts:
                names.add(parts[0])
    return names


def check_reference_manifest(root: Path, validation: list[dict[str, str]]) -> set[str]:
    manifest = root / "manifests" / "reference_manifest.tsv"
    fields, rows = read_table(manifest, validation, "reference_manifest")
    present = set(fields)
    references: set[str] = set()
    for required in ["reference_id", "species", "fasta", "fai", "annotation_file"]:
        if required not in present:
            add(validation, "ERROR", "reference_manifest", required, "Required reference manifest column is absent")
    base = manifest.parent.resolve()
    for row_number, row in enumerate(rows, start=2):
        reference_id = norm(row.get("reference_id"))
        if not reference_id:
            add(validation, "ERROR", "reference_manifest", f"{manifest}:{row_number}", "reference_id is blank")
            continue
        if reference_id in references:
            add(validation, "ERROR", "reference_manifest", reference_id, "Duplicate reference_id")
        references.add(reference_id)
        for field in sorted(REFERENCE_PATH_FIELDS & present):
            value = norm(row.get(field))
            if not value:
                continue
            check_relative_path(value, f"reference_manifest:{field}:{row_number}", validation)
            if field in {"star_index", "bwa_index", "bwa_index_prefix", "bowtie2_index", "transcript_fasta"}:
                continue
            resolved = resolve_manifest_path(value, base)
            if not resolved.exists():
                add(validation, "ERROR", "reference_manifest_paths", f"{reference_id}:{field}", f"Declared path does not exist: {value}")
    if rows:
        first = rows[0]
        fasta = resolve_manifest_path(norm(first.get("fasta") or first.get("genome_fasta")), base)
        fai = resolve_manifest_path(norm(first.get("fai")), base)
        annotations = [
            resolve_manifest_path(norm(first.get(field)), base)
            for field in ["annotation_file", "gtf", "gff3"]
            if norm(first.get(field))
        ]
        if fasta.exists() and fai.exists():
            fasta_names = parse_fasta_names(fasta)
            fai_names = parse_fai_names(fai)
            if fasta_names != fai_names:
                add(validation, "ERROR", "seqname_concordance", "fasta_vs_fai", "FASTA and FAI sequence names differ")
            else:
                add(validation, "INFO", "seqname_concordance", "fasta_vs_fai", "FASTA and FAI sequence names match")
            for annotation in annotations:
                if not annotation.exists():
                    continue
                annotation_names = parse_annotation_names(annotation)
                missing = sorted(annotation_names - fasta_names)
                if missing:
                    add(validation, "ERROR", "seqname_concordance", rel(annotation, root), "Annotation seqnames are absent from FASTA: " + ", ".join(missing))
                elif annotation_names:
                    add(validation, "INFO", "seqname_concordance", rel(annotation, root), "Annotation seqnames are present in FASTA")
    return references


def fastq_records(path: Path, validation: list[dict[str, str]]) -> list[tuple[str, str]]:
    records: list[tuple[str, str]] = []
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except Exception as exc:
        add(validation, "ERROR", "fastq", path.as_posix(), f"Could not read FASTQ: {exc}")
        return records
    if len(lines) % 4 != 0:
        add(validation, "ERROR", "fastq", path.as_posix(), "FASTQ line count is not divisible by 4")
        return records
    for idx in range(0, len(lines), 4):
        header, sequence, plus, quality = lines[idx : idx + 4]
        row = idx // 4 + 1
        if not header.startswith("@"):
            add(validation, "ERROR", "fastq", f"{path}:{row}", "FASTQ header does not start with @")
        if plus != "+":
            add(validation, "ERROR", "fastq", f"{path}:{row}", "FASTQ separator line is not +")
        if len(sequence) != len(quality):
            add(validation, "ERROR", "fastq", f"{path}:{row}", "FASTQ sequence and quality lengths differ")
        if not re.fullmatch(r"[ACGTNacgtn]+", sequence or ""):
            add(validation, "ERROR", "fastq", f"{path}:{row}", "FASTQ sequence contains non-IUPAC DNA bases")
        records.append((header, sequence))
    if not records:
        add(validation, "ERROR", "fastq", path.as_posix(), "FASTQ has no records")
    return records


def paired_header_key(header: str) -> str:
    token = header[1:].split()[0] if header.startswith("@") else header.split()[0]
    return re.sub(r"([/_\.-])R?[12]$", "", token)


def check_fastq_pair(r1: Path, r2: Path, sample_id: str, validation: list[dict[str, str]]) -> None:
    if not r1.exists():
        add(validation, "ERROR", "fastq_paths", sample_id, f"fastq_1 does not exist: {r1}")
        return
    if not r2.exists():
        add(validation, "ERROR", "fastq_paths", sample_id, f"fastq_2 does not exist: {r2}")
        return
    r1_records = fastq_records(r1, validation)
    r2_records = fastq_records(r2, validation)
    if len(r1_records) != len(r2_records):
        add(validation, "ERROR", "fastq_pairing", sample_id, f"Paired FASTQ record counts differ: {len(r1_records)} vs {len(r2_records)}")
        return
    mismatches = [
        idx
        for idx, (left, right) in enumerate(zip(r1_records, r2_records), start=1)
        if paired_header_key(left[0]) != paired_header_key(right[0])
    ]
    if mismatches:
        add(validation, "ERROR", "fastq_pairing", sample_id, "Paired FASTQ headers are inconsistent at record(s): " + ",".join(map(str, mismatches[:10])))
    else:
        add(validation, "INFO", "fastq_pairing", sample_id, f"Paired FASTQ records match ({len(r1_records)} pairs)")


def check_sample_sheet(path: Path, references: set[str], source: str, validation: list[dict[str, str]]) -> None:
    fields, rows = read_table(path, validation, source)
    present = set(fields)
    for required in ["sample_id", "reference_id", "fastq_1", "fastq_2", "read_layout"]:
        if required not in present:
            add(validation, "ERROR", source, required, "Required sample sheet column is absent")
    base = path.parent.resolve()
    for row_number, row in enumerate(rows, start=2):
        sample_id = norm(row.get("sample_id")) or f"row{row_number}"
        reference_id = norm(row.get("reference_id"))
        if reference_id not in references:
            add(validation, "ERROR", source, f"{sample_id}:reference_id", f"Unknown reference_id: {reference_id}")
        for field in ["fastq_1", "fastq_2"]:
            check_relative_path(norm(row.get(field)), f"{source}:{sample_id}:{field}", validation)
        fastq_1 = resolve_manifest_path(norm(row.get("fastq_1")), base)
        fastq_2 = resolve_manifest_path(norm(row.get("fastq_2")), base)
        layout = norm(row.get("read_layout")).lower()
        if layout in {"paired", "paired_end", "paired-end", "pe"}:
            check_fastq_pair(fastq_1, fastq_2, sample_id, validation)
        elif layout in {"single", "single_end", "single-end", "se"}:
            if norm(row.get("fastq_2")):
                add(validation, "ERROR", source, f"{sample_id}:fastq_2", "Single-end fixture row must not provide fastq_2")
            elif not fastq_1.exists():
                add(validation, "ERROR", source, f"{sample_id}:fastq_1", f"FASTQ path does not exist: {fastq_1}")
        else:
            add(validation, "ERROR", source, f"{sample_id}:read_layout", f"Unsupported read_layout: {row.get('read_layout')}")


def check_contracts(root: Path, validation: list[dict[str, str]]) -> None:
    path = root / "manifests" / "expected_output_contracts.tsv"
    fields, rows = read_table(path, validation, "expected_output_contracts")
    for required in ["assay", "artifact", "required_pattern", "mode", "assertion"]:
        if required not in fields:
            add(validation, "ERROR", "expected_output_contracts", required, "Required contract column is absent")
    assays = {norm(row.get("assay")) for row in rows}
    missing = {"rna", "atac", "wgs", "reference_quality"} - assays
    if missing:
        add(validation, "ERROR", "expected_output_contracts", path.as_posix(), "Missing expected assay contract(s): " + ", ".join(sorted(missing)))
    elif rows:
        add(validation, "INFO", "expected_output_contracts", path.as_posix(), f"Loaded {len(rows)} expected contract row(s)")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture-dir", "--fixture_dir", default="assets/test_data/real_mode_fixtures")
    parser.add_argument("--outdir", default="results/real_mode_fixtures")
    parser.add_argument("--max-file-bytes", "--max_file_bytes", type=int, default=100_000)
    parser.add_argument("--max-total-bytes", "--max_total_bytes", type=int, default=1_000_000)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    root = Path(args.fixture_dir).resolve()
    outdir = Path(args.outdir)
    validation: list[dict[str, str]] = []
    if not root.is_dir():
        add(validation, "ERROR", "fixture_dir", root.as_posix(), "Fixture directory does not exist")
        manifest_rows: list[dict[str, str]] = []
    else:
        check_expected_files(root, validation)
        manifest_rows = check_file_inventory(root, args.max_file_bytes, args.max_total_bytes, validation)
        references = check_reference_manifest(root, validation)
        check_sample_sheet(root / "manifests" / "real_mode_metadata.tsv", references, "real_mode_metadata", validation)
        check_sample_sheet(root / "manifests" / "wgs_samplesheet.csv", references, "wgs_samplesheet", validation)
        check_contracts(root, validation)

    write_tsv(outdir / "fixture_validation.tsv", VALIDATION_FIELDS, validation)
    write_tsv(outdir / "fixture_manifest.tsv", MANIFEST_FIELDS, manifest_rows)
    errors = sum(1 for row in validation if row["severity"] == "ERROR")
    warnings = sum(1 for row in validation if row["severity"] == "WARNING")
    print(f"CAME real-mode fixture validation: ERROR={errors} WARNING={warnings} files={len(manifest_rows)}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
