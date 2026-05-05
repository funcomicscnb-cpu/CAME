#!/usr/bin/env python3
"""Run release-readiness checks for CAME final reporting."""

import argparse
import csv
import os
import re
from pathlib import Path


CHECK_FIELDS = ["check_id", "status", "subject", "message", "remediation"]
SUMMARY_FIELDS = ["status", "count"]

REQUIRED_STAGE12 = [
    "bin/collect_run_outputs.py",
    "bin/render_final_report.py",
    "bin/run_release_checks.py",
    "workflows/final_report.nf",
    "subworkflows/report_collection.nf",
    "subworkflows/report_rendering.nf",
    "subworkflows/release_checks.nf",
    "tests/test_final_report.sh",
    "docs/final_report.md",
    "docs/release_checklist.md",
]

REQUIRED_STAGE13 = [
    "bin/prepare_all_stub_omics_contrasts.py",
    "bin/check_stage_outputs.py",
    "bin/summarize_all_run.py",
    "workflows/all.nf",
    "subworkflows/stage_orchestration.nf",
    "subworkflows/validation.nf",
    "tests/test_end_to_end_orchestration.sh",
    "docs/end_to_end_run.md",
]

REQUIRED_STAGE16 = [
    "bin/collect_run_provenance.py",
    "bin/make_report_assets.py",
    "templates/came_report.css",
    "templates/came_report_template.html",
    "templates/came_report_template.md",
    "tests/test_report_polish.sh",
    "docs/report_customization.md",
]

REQUIRED_EXISTING_TESTS = [
    "tests/test_metadata_validation.sh",
    "tests/test_profile_examples.sh",
    "tests/test_study_profile_validation.sh",
    "tests/test_phenotype_processing.sh",
    "tests/test_phenotype_multi_index.sh",
    "tests/test_phylo_hypothesis.sh",
    "tests/test_bulk_omics.sh",
    "tests/test_differential_omics.sh",
    "tests/test_orthology_projection.sh",
    "tests/test_gra_analysis.sh",
    "tests/test_phenotype_omics_integration.sh",
    "tests/test_candidate_prioritization.sh",
    "tests/test_functional_interpretation.sh",
    "tests/test_end_to_end_orchestration.sh",
    "tests/test_real_mode_fixtures.sh",
]

REQUIRED_EXISTING_DOCS = [
    "docs/input_formats.md",
    "docs/study_profiles.md",
    "docs/profile_authoring.md",
    "docs/phenotype_processing.md",
    "docs/phylogenetic_models.md",
    "docs/bulk_omics.md",
    "docs/differential_omics.md",
    "docs/orthology_projection.md",
    "docs/gra_analysis.md",
    "docs/phenotype_omics_integration.md",
    "docs/candidate_prioritization.md",
    "docs/functional_interpretation.md",
    "docs/end_to_end_run.md",
    "docs/real_mode_fixture_strategy.md",
]

REQUIRED_ENVIRONMENT = [
    "environment/came_environment.yml",
    "environment/requirements.txt",
]

CORE_SCAN_PATHS = [
    "main.nf",
    "nextflow.config",
    "bin",
    "workflows",
    "subworkflows",
    "modules",
]

TEXT_EXTENSIONS = {
    "",
    ".config",
    ".csv",
    ".md",
    ".nf",
    ".py",
    ".r",
    ".R",
    ".sh",
    ".tsv",
    ".txt",
    ".yaml",
    ".yml",
}

PROFILE_TERM_PATTERNS = [
    ("profile_term_1", re.compile(r"\b" + "D" + "DR" + r"\b")),
    ("profile_term_2", re.compile(r"\b" + "Ro" + "R" + r"\b")),
    ("profile_term_3", re.compile(r"\b" + "D" + "DRstate" + r"\b")),
    ("profile_term_4", re.compile("D" + "NA damage", re.IGNORECASE)),
    ("profile_term_5", re.compile("robustness" + "-of-regulation", re.IGNORECASE)),
    ("profile_term_6", re.compile(r"\b" + "dd" + "r_")),
]

ABSOLUTE_PATH_PATTERNS = [
    re.compile(r"(^|[^A-Za-z0-9_])/" + "Users" + r"/[^ \t\n:'\"]+"),
    re.compile(r"(^|[^A-Za-z0-9_])/" + "home" + r"/[A-Za-z0-9._-]+/[^ \t\n:'\"]+"),
    re.compile(r"(^|[^A-Za-z0-9_])/" + "tmp" + r"/[^ \t\n:'\"]+"),
    re.compile(r"(^|[^A-Za-z0-9_])/" + "var/folders" + r"/[^ \t\n:'\"]+"),
    re.compile(r"[A-Za-z]:\\Users\\[^ \t\n:'\"]+"),
]

REQUIRED_STAGE28_FIXTURES = [
    "bin/make_real_mode_fixtures.py",
    "bin/validate_real_mode_fixtures.py",
    "assets/test_data/real_mode_fixtures/README.md",
    "assets/test_data/real_mode_fixtures/tiny_reference/tiny.fa",
    "assets/test_data/real_mode_fixtures/tiny_reference/tiny.fa.fai",
    "assets/test_data/real_mode_fixtures/tiny_reference/tiny.dict",
    "assets/test_data/real_mode_fixtures/tiny_reference/tiny.gtf",
    "assets/test_data/real_mode_fixtures/tiny_reference/tiny.gff3",
    "assets/test_data/real_mode_fixtures/manifests/reference_manifest.tsv",
    "assets/test_data/real_mode_fixtures/manifests/real_mode_metadata.tsv",
    "assets/test_data/real_mode_fixtures/manifests/wgs_samplesheet.csv",
    "assets/test_data/real_mode_fixtures/manifests/expected_output_contracts.tsv",
]


def write_tsv(path, fields, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, delimiter="\t", extrasaction="ignore", quoting=csv.QUOTE_NONE, escapechar="\\", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def record(rows, check_id, status, subject, message, remediation=""):
    rows.append(
        {
            "check_id": check_id,
            "status": status,
            "subject": subject,
            "message": message,
            "remediation": remediation,
        }
    )


def check_required_files(rows, project_dir, check_id, paths, subject):
    missing = [path for path in paths if not (project_dir / path).is_file()]
    if missing:
        for path in missing:
            record(rows, check_id, "ERROR", path, f"Missing required {subject} file.", "Add the file or update release checks.")
    else:
        record(rows, check_id, "PASS", subject, f"All {len(paths)} required {subject} files are present.")


def iter_core_files(project_dir):
    for rel in CORE_SCAN_PATHS:
        path = project_dir / rel
        if path.is_file():
            yield path
            continue
        if not path.is_dir():
            continue
        for root, dirs, files in os.walk(path):
            dirs[:] = [dirname for dirname in dirs if dirname not in {"__pycache__", ".git", ".nextflow"}]
            for filename in files:
                file_path = Path(root) / filename
                if file_path.suffix in TEXT_EXTENSIONS and file_path.is_file():
                    yield file_path


def read_text(path):
    try:
        return path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return path.read_text(encoding="utf-8", errors="ignore")


def check_manifest(rows, manifest):
    if Path(manifest).is_file():
        record(rows, "manifest_exists", "PASS", str(manifest), "Output manifest exists.")
    else:
        record(rows, "manifest_exists", "ERROR", str(manifest), "Output manifest is missing.", "Run output collection first.")


def check_run_stage_discovery(rows, project_dir):
    main_path = project_dir / "main.nf"
    if not main_path.exists():
        record(rows, "run_stage_discovery", "ERROR", "main.nf", "main.nf is missing.", "Restore main.nf.")
        return
    text = read_text(main_path)
    match = re.search(r"allowedStages\s*=\s*\[([^\]]+)\]", text, re.DOTALL)
    if not match:
        record(rows, "run_stage_discovery", "WARNING", "main.nf", "Could not discover run_stage values.", "Document supported run_stage values.")
        return
    values = re.findall(r"['\"]([^'\"]+)['\"]", match.group(1))
    missing_stages = [stage for stage in ["final_report", "all"] if stage not in values]
    if missing_stages:
        record(rows, "run_stage_discovery", "ERROR", "main.nf", f"Missing supported run_stage value(s): {', '.join(missing_stages)}.", "Add missing values to allowedStages.")
    else:
        record(rows, "run_stage_discovery", "PASS", "main.nf", f"Discovered {len(values)} run_stage values including final_report and all.")

    docs_text = ""
    for rel in ["docs/final_report.md", "docs/release_checklist.md", "docs/end_to_end_run.md"]:
        path = project_dir / rel
        if path.exists():
            docs_text += read_text(path) + "\n"
    missing_docs = [stage for stage in ["--run_stage final_report", "--run_stage all"] if stage not in docs_text]
    if not missing_docs:
        record(rows, "run_stage_documented", "PASS", "docs", "final_report and all run stages are documented.")
    else:
        record(rows, "run_stage_documented", "ERROR", "docs", f"Missing documentation text: {', '.join(missing_docs)}.", "Update run-stage docs.")


def check_profile_terms(rows, project_dir):
    hits = []
    for path in iter_core_files(project_dir):
        rel = path.relative_to(project_dir).as_posix()
        text = read_text(path)
        for line_number, line in enumerate(text.splitlines(), start=1):
            for term_id, pattern in PROFILE_TERM_PATTERNS:
                if pattern.search(line):
                    hits.append((rel, line_number, term_id))
    if hits:
        for rel, line_number, term_id in hits[:50]:
            record(
                rows,
                "profile_term_scan",
                "ERROR",
                f"{rel}:{line_number}",
                f"Profile-specific term matched {term_id} in core logic.",
                "Move study-specific language to profiles, docs, tests, examples, or generated results.",
            )
        if len(hits) > 50:
            record(rows, "profile_term_scan", "ERROR", "core logic", f"{len(hits) - 50} additional profile-term matches omitted.")
    else:
        record(rows, "profile_term_scan", "PASS", "core logic", "No profile-specific terms found in core logic paths.")


def check_absolute_paths(rows, project_dir):
    hits = []
    for path in iter_core_files(project_dir):
        rel = path.relative_to(project_dir).as_posix()
        text = read_text(path)
        for line_number, line in enumerate(text.splitlines(), start=1):
            stripped = line.strip()
            if stripped.startswith("#!"):
                continue
            for pattern in ABSOLUTE_PATH_PATTERNS:
                if pattern.search(line):
                    hits.append((rel, line_number))
                    break
    if hits:
        for rel, line_number in hits[:50]:
            record(
                rows,
                "absolute_path_scan",
                "ERROR",
                f"{rel}:{line_number}",
                "Obvious local absolute path found in tracked pipeline logic.",
                "Use project-relative paths, params, or Nextflow path inputs.",
            )
        if len(hits) > 50:
            record(rows, "absolute_path_scan", "ERROR", "core logic", f"{len(hits) - 50} additional path matches omitted.")
    else:
        record(rows, "absolute_path_scan", "PASS", "core logic", "No obvious local absolute paths found in core logic paths.")


def check_stage28_fixtures(rows, project_dir):
    missing = [path for path in REQUIRED_STAGE28_FIXTURES if not (project_dir / path).is_file()]
    if missing:
        for path in missing:
            record(rows, "stage28_fixture_files", "ERROR", path, "Missing required Stage 28 fixture file.", "Generate fixtures or update release checks.")
        return
    fixture_root = project_dir / "assets/test_data/real_mode_fixtures"
    total = 0
    problems = 0
    for path in sorted(fixture_root.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(project_dir).as_posix()
        size = path.stat().st_size
        total += size
        if size > 100_000:
            problems += 1
            record(rows, "stage28_fixture_files", "ERROR", rel, f"Fixture file is too large: {size} bytes.", "Keep Stage 28 fixtures tiny.")
        if path.name.lower().endswith((".bam", ".bai", ".bt2", ".bt2l", ".bwt", ".pac", ".sa", ".tbi", ".idx", ".vcf.gz", ".bcf.gz")):
            problems += 1
            record(rows, "stage28_fixture_files", "ERROR", rel, "Binary or generated index-like fixture file found.", "Do not commit generated real-mode outputs or aligner indexes.")
        text = read_text(path)
        for line_number, line in enumerate(text.splitlines(), start=1):
            if any(pattern.search(line) for pattern in ABSOLUTE_PATH_PATTERNS):
                problems += 1
                record(rows, "stage28_fixture_files", "ERROR", f"{rel}:{line_number}", "Local absolute path found in fixture content.", "Use manifest-relative fixture paths.")
                break
    if total > 1_000_000:
        problems += 1
        record(rows, "stage28_fixture_files", "ERROR", fixture_root.relative_to(project_dir).as_posix(), f"Fixture tree is too large: {total} bytes.", "Keep Stage 28 fixtures compact.")
    if problems == 0:
        record(rows, "stage28_fixture_files", "PASS", fixture_root.relative_to(project_dir).as_posix(), f"Stage 28 fixtures are present and compact ({total} bytes).")


def check_results_presence(rows, results_dir):
    path = Path(results_dir)
    if path.exists():
        record(rows, "results_dir_exists", "PASS", str(path), "Results directory exists.")
    else:
        record(
            rows,
            "results_dir_exists",
            "WARNING",
            str(path),
            "Results directory does not exist; final report may contain only missing-output warnings.",
            "Run upstream stages or provide the expected --outdir.",
        )


def summarize(rows):
    counts = {}
    for row in rows:
        counts[row["status"]] = counts.get(row["status"], 0) + 1
    return [{"status": key, "count": str(counts[key])} for key in sorted(counts)]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project_dir", required=True)
    parser.add_argument("--results_dir", required=True)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--output_dir", required=True)
    args = parser.parse_args(argv)

    project_dir = Path(args.project_dir).resolve()
    rows = []
    check_required_files(rows, project_dir, "stage12_files", REQUIRED_STAGE12, "Stage 12")
    check_required_files(rows, project_dir, "stage13_files", REQUIRED_STAGE13, "Stage 13")
    check_required_files(rows, project_dir, "stage16_files", REQUIRED_STAGE16, "Stage 16")
    check_required_files(rows, project_dir, "regression_tests", REQUIRED_EXISTING_TESTS, "regression test")
    check_required_files(rows, project_dir, "documentation", REQUIRED_EXISTING_DOCS, "documentation")
    check_required_files(rows, project_dir, "environment", REQUIRED_ENVIRONMENT, "environment")
    check_manifest(rows, args.manifest)
    check_results_presence(rows, args.results_dir)
    check_run_stage_discovery(rows, project_dir)
    check_absolute_paths(rows, project_dir)
    check_profile_terms(rows, project_dir)
    check_stage28_fixtures(rows, project_dir)

    output_dir = Path(args.output_dir).resolve()
    write_tsv(output_dir / "came_release_checks.tsv", CHECK_FIELDS, rows)
    write_tsv(output_dir / "came_release_summary.tsv", SUMMARY_FIELDS, summarize(rows))
    print(f"CAME release checks: records={len(rows)} errors={sum(1 for row in rows if row['status'] == 'ERROR')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
