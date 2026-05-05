#!/usr/bin/env python3
"""Validate CAME v0.1 release packaging assets."""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import sys
from pathlib import Path


FIELDS = ["check_id", "status", "subject", "message", "remediation"]
TEXT_SUFFIXES = {"", ".config", ".csv", ".groovy", ".md", ".nf", ".py", ".R", ".r", ".sh", ".tsv", ".txt", ".yaml", ".yml"}

REQUIRED_WORKFLOWS = [
    "workflows/all.nf",
    "workflows/bulk_omics.nf",
    "workflows/candidate_prioritization.nf",
    "workflows/coordinate_projection.nf",
    "workflows/differential_omics.nf",
    "workflows/final_report.nf",
    "workflows/functional_interpretation.nf",
    "workflows/gra_analysis.nf",
    "workflows/orthology_projection.nf",
    "workflows/phenotype_omics_integration.nf",
    "workflows/phenotype_response.nf",
    "workflows/phylo_hypothesis.nf",
    "workflows/reference_prepare.nf",
]

REQUIRED_TESTS = [
    "tests/test_metadata_validation.sh",
    "tests/test_profile_examples.sh",
    "tests/test_study_profile_validation.sh",
    "tests/test_phenotype_processing.sh",
    "tests/test_phylo_hypothesis.sh",
    "tests/test_bulk_omics.sh",
    "tests/test_coordinate_projection.sh",
    "tests/test_differential_omics.sh",
    "tests/test_orthology_projection.sh",
    "tests/test_gra_analysis.sh",
    "tests/test_phenotype_omics_integration.sh",
    "tests/test_candidate_prioritization.sh",
    "tests/test_functional_interpretation.sh",
    "tests/test_final_report.sh",
    "tests/test_report_polish.sh",
    "tests/test_end_to_end_orchestration.sh",
    "tests/test_release_packaging.sh",
    "tests/test_real_mode_smoke.sh",
    "tests/test_real_mode_fixtures.sh",
    "tests/test_reference_preparation.sh",
]

REQUIRED_DOCS = [
    "README.md",
    "docs/installation.md",
    "docs/ci_and_release.md",
    "docs/input_formats.md",
    "docs/study_profiles.md",
    "docs/profile_authoring.md",
    "docs/phenotype_processing.md",
    "docs/phylogenetic_models.md",
    "docs/bulk_omics.md",
    "docs/coordinate_projection.md",
    "docs/differential_omics.md",
    "docs/orthology_projection.md",
    "docs/gra_analysis.md",
    "docs/phenotype_omics_integration.md",
    "docs/candidate_prioritization.md",
    "docs/functional_interpretation.md",
    "docs/final_report.md",
    "docs/report_customization.md",
    "docs/end_to_end_run.md",
    "docs/release_checklist.md",
    "docs/release_notes_v0.1.md",
    "docs/real_mode_smoke_tests.md",
    "docs/real_mode_fixture_strategy.md",
    "docs/reference_preparation.md",
    "docs/versioning.md",
]

REQUIRED_BIN = [
    "bin/collect_run_outputs.py",
    "bin/collect_run_provenance.py",
    "bin/check_real_mode_tools.py",
    "bin/make_real_mode_fixtures.py",
    "bin/make_report_assets.py",
    "bin/make_real_mode_smoke_data.py",
    "bin/make_synthetic_coordinate_projection_outputs.py",
    "bin/make_synthetic_reference_outputs.py",
    "bin/prepare_coordinate_projection_inputs.py",
    "bin/prepare_reference_inputs.py",
    "bin/render_final_report.py",
    "bin/summarize_coordinate_projection.py",
    "bin/summarize_reference_prepare.py",
    "bin/validate_real_mode_fixtures.py",
]

REQUIRED_TEMPLATES = [
    "templates/came_report.css",
    "templates/came_report_template.html",
    "templates/came_report_template.md",
]

REQUIRED_ENVIRONMENT = [
    "environment/came_environment.yml",
    "environment/conda-linux-64.lock",
    "environment/requirements.txt",
    "environment/install_local.sh",
    "environment/install_r_packages.R",
    "environment/tool_versions.tsv",
]

REQUIRED_SCHEMAS = [
    "schemas/reference_manifest.schema.json",
    "schemas/real_mode_metadata.schema.json",
    "assets/schema/reference_manifest.schema.json",
    "assets/schema/reference_manifest_legacy.schema.json",
]

REQUIRED_RELEASE_FILES = [
    ".github/workflows/ci.yml",
    ".github/workflows/publish_container.yml",
    ".github/ISSUE_TEMPLATE/bug_report.md",
    ".github/ISSUE_TEMPLATE/feature_request.md",
    ".github/PULL_REQUEST_TEMPLATE.md",
    ".github/dependabot.yml",
    "CITATION.cff",
    "LICENSE",
    "VERSION",
    "CHANGELOG.md",
    "Dockerfile",
    ".dockerignore",
]

REQUIRED_EXAMPLES = [
    "assets/example_samplesheets/phenotype_samplesheet.csv",
    "assets/example_samplesheets/profile_examples/phenotype_samplesheet.csv",
    "assets/example_samplesheets/profile_examples/species_traits.tsv",
    "assets/example_samplesheets/omics_samplesheet.csv",
    "assets/example_samplesheets/coordinate_projection_config.tsv",
    "assets/example_samplesheets/genome_alignment_manifest.tsv",
    "assets/example_samplesheets/regulatory_regions.tsv",
    "assets/example_samplesheets/species_traits.tsv",
    "assets/example_samplesheets/reference_manifest.tsv",
    "assets/example_samplesheets/reference_prepare_config.tsv",
    "assets/example_samplesheets/wgs_samplesheet.csv",
    "assets/example_samplesheets/phylogeny_manifest.tsv",
    "assets/example_samplesheets/study_design.yaml",
    "assets/example_samplesheets/orthologous_genes.tsv",
    "assets/example_samplesheets/orthologous_res.tsv",
    "assets/example_samplesheets/re_to_gene_links.tsv",
    "assets/example_samplesheets/gene_annotations.tsv",
    "assets/example_samplesheets/gene_sets.tsv",
    "assets/example_samplesheets/candidate_scoring_config.tsv",
    "assets/example_samplesheets/phylogeny/example_tree.nwk",
    "assets/test_data/real_mode_smoke/README.md",
    "assets/test_data/real_mode_smoke/rnaseq/.gitkeep",
    "assets/test_data/real_mode_smoke/atacseq/.gitkeep",
    "assets/test_data/real_mode_smoke/reference/.gitkeep",
    "assets/test_data/real_mode_fixtures/README.md",
    "assets/test_data/real_mode_fixtures/tiny_reference/tiny.fa",
    "assets/test_data/real_mode_fixtures/tiny_reference/tiny.fa.fai",
    "assets/test_data/real_mode_fixtures/tiny_reference/tiny.dict",
    "assets/test_data/real_mode_fixtures/tiny_reference/tiny.gtf",
    "assets/test_data/real_mode_fixtures/tiny_reference/tiny.gff3",
    "assets/test_data/real_mode_fixtures/tiny_reference/assembly_report.txt",
    "assets/test_data/real_mode_fixtures/tiny_reference/alias_map.tsv",
    "assets/test_data/real_mode_fixtures/tiny_reference/tiny.chrom.sizes",
    "assets/test_data/real_mode_fixtures/tiny_reference/tiny.tss.bed",
    "assets/test_data/real_mode_fixtures/tiny_reference/repeatmasker.bed",
    "assets/test_data/real_mode_fixtures/tiny_reference/mappability.bed",
    "assets/test_data/real_mode_fixtures/tiny_reference/blacklist.bed",
    "assets/test_data/real_mode_fixtures/tiny_rna/tiny_rna_1_R1.fastq",
    "assets/test_data/real_mode_fixtures/tiny_rna/tiny_rna_1_R2.fastq",
    "assets/test_data/real_mode_fixtures/tiny_atac/tiny_atac_1_R1.fastq",
    "assets/test_data/real_mode_fixtures/tiny_atac/tiny_atac_1_R2.fastq",
    "assets/test_data/real_mode_fixtures/tiny_wgs/tiny_wgs_1_R1.fastq",
    "assets/test_data/real_mode_fixtures/tiny_wgs/tiny_wgs_1_R2.fastq",
    "assets/test_data/real_mode_fixtures/manifests/reference_manifest.tsv",
    "assets/test_data/real_mode_fixtures/manifests/real_mode_metadata.tsv",
    "assets/test_data/real_mode_fixtures/manifests/wgs_samplesheet.csv",
    "assets/test_data/real_mode_fixtures/manifests/expected_output_contracts.tsv",
]

CORE_SCAN_ROOTS = ["main.nf", "nextflow.config", "lib", "bin", "workflows", "subworkflows", "modules"]
CORE_SCAN_EXCLUDE_FILES = {"bin/validate_release_bundle.py"}

PROFILE_PATTERNS = [
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

SEMVER_PATTERN = re.compile(
    r"^(0|[1-9]\d*)\."
    r"(0|[1-9]\d*)\."
    r"(0|[1-9]\d*)"
    r"(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?"
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$"
)

README_REQUIRED_LINKS = [
    ("installation", "docs/installation.md"),
    ("CI/release", "docs/ci_and_release.md"),
    ("profile authoring", "docs/profile_authoring.md"),
    ("final report", "docs/final_report.md"),
    ("versioning", "docs/versioning.md"),
    ("v0.1 release notes", "docs/release_notes_v0.1.md"),
]

CITATION_REQUIRED_FIELDS = [
    "cff-version",
    "title",
    "message",
    "version",
    "date-released",
    "authors",
    "repository-code",
    "abstract",
    "keywords",
]

SCAFFOLD_DOC_REQUIREMENTS = {
    "docs/reference_preparation.md": ["optional", "scaffold", "production", "not implemented"],
    "docs/coordinate_projection.md": ["optional", "scaffold", "production", "not implemented"],
    "docs/re_to_gene_inference.md": ["optional", "scaffold", "production", "not implemented"],
    "docs/advanced_statistics.md": ["optional", "scaffold", "not a production"],
}

NANOSEQ_OVERCLAIM_PATTERNS = [
    re.compile(r"\bnanoseq\b[^.\n]*(?:is|are|was|were)\s+implemented", re.IGNORECASE),
    re.compile(r"\bnanoseq\b[^.\n]*has\s+been\s+implemented", re.IGNORECASE),
    re.compile(r"\bimplemented\b[^.\n]*\bnanoseq\b", re.IGNORECASE),
    re.compile(r"\bnanoseq\b[^.\n]*production", re.IGNORECASE),
    re.compile(r"\bproduction\b[^.\n]*\bnanoseq\b", re.IGNORECASE),
    re.compile(r"\bmutation profiling\b[^.\n]*(?:is|are|was|were)\s+implemented", re.IGNORECASE),
    re.compile(r"\bmutation profiling\b[^.\n]*has\s+been\s+implemented", re.IGNORECASE),
    re.compile(r"\bimplemented\b[^.\n]*\bmutation profiling\b", re.IGNORECASE),
]

FIXTURE_FORBIDDEN_SUFFIXES = {
    ".bam",
    ".bai",
    ".bt2",
    ".bt2l",
    ".bwt",
    ".pac",
    ".sa",
    ".tbi",
    ".idx",
    ".cram",
    ".crai",
}
FIXTURE_FORBIDDEN_COMPOUND_SUFFIXES = {".vcf.gz", ".bcf.gz"}


def project_root() -> Path:
    return Path(__file__).resolve().parents[1]


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return path.read_text(encoding="utf-8", errors="ignore")


def add(rows: list[dict[str, str]], check_id: str, status: str, subject: str, message: str, remediation: str = "") -> None:
    rows.append(
        {
            "check_id": check_id,
            "status": status,
            "subject": subject,
            "message": message,
            "remediation": remediation,
        }
    )


def write_tsv(path: Path, rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS, delimiter="\t", extrasaction="ignore", quoting=csv.QUOTE_NONE, escapechar="\\", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def check_files(rows: list[dict[str, str]], root: Path, check_id: str, paths: list[str], label: str) -> None:
    missing = [path for path in paths if not (root / path).is_file()]
    if missing:
        for path in missing:
            add(rows, check_id, "ERROR", path, f"Missing required {label}.", "Add the file or update the release validator.")
    else:
        add(rows, check_id, "PASS", label, f"All {len(paths)} required {label} files are present.")


def check_version_file(rows: list[dict[str, str]], root: Path) -> None:
    path = root / "VERSION"
    if not path.is_file():
        add(rows, "version_parse", "ERROR", "VERSION", "VERSION is missing.", "Add a SemVer value such as 0.1.0.")
        return
    version = read_text(path).strip()
    if SEMVER_PATTERN.match(version):
        add(rows, "version_parse", "PASS", "VERSION", f"VERSION is parseable SemVer: {version}.")
    else:
        add(rows, "version_parse", "ERROR", "VERSION", f"VERSION is not parseable SemVer: {version!r}.", "Use MAJOR.MINOR.PATCH with optional prerelease/build metadata.")


def check_license(rows: list[dict[str, str]], root: Path) -> None:
    path = root / "LICENSE"
    if not path.is_file():
        add(rows, "license_gplv3", "ERROR", "LICENSE", "LICENSE is missing.", "Add the standard GNU GPL version 3 text.")
        return
    text = read_text(path)
    required = [
        "GNU GENERAL PUBLIC LICENSE",
        "Version 3, 29 June 2007",
        "Everyone is permitted to copy and distribute verbatim copies",
        "TERMS AND CONDITIONS",
        "END OF TERMS AND CONDITIONS",
    ]
    missing = [marker for marker in required if marker not in text]
    if missing:
        add(rows, "license_gplv3", "ERROR", "LICENSE", "LICENSE does not contain expected GPLv3 marker(s): " + ", ".join(missing), "Use the unmodified standard GPLv3 text.")
    else:
        add(rows, "license_gplv3", "PASS", "LICENSE", "LICENSE contains expected GNU GPLv3 markers.")


def check_citation(rows: list[dict[str, str]], root: Path) -> None:
    path = root / "CITATION.cff"
    if not path.is_file():
        add(rows, "citation_metadata", "ERROR", "CITATION.cff", "CITATION.cff is missing.", "Add citation metadata with TODO placeholders where facts are unknown.")
        return
    text = read_text(path)
    missing = [field for field in CITATION_REQUIRED_FIELDS if not re.search(rf"(?m)^{re.escape(field)}\s*:", text)]
    if missing:
        add(rows, "citation_metadata", "ERROR", "CITATION.cff", "Missing required citation field(s): " + ", ".join(missing), "Add the required CFF fields.")
        return
    if not re.search(r"(?m)^license\s*:\s*GPL-3\.0-only\s*$", text):
        add(rows, "citation_metadata", "ERROR", "CITATION.cff", "Citation license is not GPL-3.0-only.", "Set license: GPL-3.0-only.")
        return
    add(rows, "citation_metadata", "PASS", "CITATION.cff", "Required citation fields and GPL-3.0-only license are present.")


def check_readme_links(rows: list[dict[str, str]], root: Path) -> None:
    path = root / "README.md"
    if not path.is_file():
        add(rows, "readme_release_links", "ERROR", "README.md", "README.md is missing.", "Restore README.md.")
        return
    text = read_text(path)
    missing = []
    broken = []
    for label, rel in README_REQUIRED_LINKS:
        if f"]({rel})" not in text:
            missing.append(label)
        elif not (root / rel).is_file():
            broken.append(rel)
    if missing or broken:
        messages = []
        if missing:
            messages.append("Missing README link(s): " + ", ".join(missing))
        if broken:
            messages.append("Broken README link target(s): " + ", ".join(broken))
        add(rows, "readme_release_links", "ERROR", "README.md", "; ".join(messages), "Add release-facing README links and ensure targets exist.")
    else:
        add(rows, "readme_release_links", "PASS", "README.md", "README links to installation, CI/release, profile authoring, final report, versioning, and v0.1 release notes.")


def check_nanoseq_claims(rows: list[dict[str, str]], root: Path) -> None:
    text = docs_text(root)
    hits = []
    for pattern in NANOSEQ_OVERCLAIM_PATTERNS:
        for match in pattern.finditer(text):
            hits.append(match.group(0).strip())
    lower = text.lower()
    has_skip_statement = (
        "nanoseq and mutation profiling are intentionally skipped" in lower
        or "nanoseq and mutation profiling are not implemented" in lower
        or "does not implement nanoseq processing or mutation profiling" in lower
    )
    if hits:
        add(rows, "nanoseq_not_advertised", "ERROR", "README/docs", "Potential NanoSeq or mutation profiling overclaim: " + hits[0], "Describe NanoSeq/mutation profiling as skipped or future work only.")
    elif "nanoseq" in lower and not has_skip_statement:
        add(rows, "nanoseq_not_advertised", "ERROR", "README/docs", "NanoSeq is mentioned without a clear skipped/not-implemented statement.", "Add explicit skipped/not-implemented wording.")
    else:
        add(rows, "nanoseq_not_advertised", "PASS", "README/docs", "NanoSeq and mutation profiling are not advertised as implemented.")


def check_scaffold_docs(rows: list[dict[str, str]], root: Path) -> None:
    failures = []
    for rel, required_terms in SCAFFOLD_DOC_REQUIREMENTS.items():
        path = root / rel
        if not path.is_file():
            failures.append(f"{rel}: missing")
            continue
        text = read_text(path).lower()
        missing = [term for term in required_terms if term not in text]
        if missing:
            failures.append(f"{rel}: missing " + ", ".join(missing))
    if failures:
        for failure in failures:
            add(rows, "optional_scaffold_docs", "ERROR", failure, "Optional scaffold documentation is incomplete.", "Document optional/scaffold-only status and production limitations.")
    else:
        add(rows, "optional_scaffold_docs", "PASS", "optional scaffold docs", "Optional scaffold stages are documented as optional and not production implementations.")


def nf_files(root: Path) -> list[Path]:
    files = [root / "main.nf"]
    for directory in ["workflows", "subworkflows", "modules"]:
        base = root / directory
        if base.is_dir():
            files.extend(sorted(base.rglob("*.nf")))
    return [path for path in files if path.is_file()]


def resolve_include(source: Path, rel: str) -> Path:
    target = (source.parent / rel).resolve()
    if target.suffix:
        return target
    return target.with_suffix(".nf")


def check_nextflow_includes(rows: list[dict[str, str]], root: Path) -> None:
    include_re = re.compile(r"include\s*\{[^}]+\}\s*from\s*['\"]([^'\"]+)['\"]")
    missing = []
    checked = 0
    for source in nf_files(root):
        for match in include_re.finditer(read_text(source)):
            checked += 1
            target = resolve_include(source, match.group(1))
            if not target.is_file():
                missing.append((source.relative_to(root).as_posix(), match.group(1)))
    if missing:
        for source, rel in missing:
            add(rows, "nextflow_includes", "ERROR", f"{source}: {rel}", "Nextflow include target is missing.", "Restore or retarget the include.")
    else:
        add(rows, "nextflow_includes", "PASS", "Nextflow includes", f"All {checked} include target(s) resolve.")


def check_referenced_bin_scripts(rows: list[dict[str, str]], root: Path) -> None:
    patterns = [
        re.compile(r"\$\{projectDir\}/bin/([A-Za-z0-9_.-]+)"),
        re.compile(r"\$projectDir/bin/([A-Za-z0-9_.-]+)"),
    ]
    referenced = set()
    for source in nf_files(root):
        text = read_text(source)
        for pattern in patterns:
            referenced.update(pattern.findall(text))
    missing = sorted(script for script in referenced if not (root / "bin" / script).is_file())
    if missing:
        for script in missing:
            add(rows, "referenced_bin_scripts", "ERROR", f"bin/{script}", "Referenced bin script is missing.", "Restore the script or update the workflow command.")
    else:
        add(rows, "referenced_bin_scripts", "PASS", "bin scripts", f"All {len(referenced)} referenced bin script(s) exist.")


def allowed_stages(root: Path) -> list[str]:
    text = read_text(root / "main.nf")
    match = re.search(r"allowedStages\s*=\s*\[([^\]]+)\]", text, re.DOTALL)
    if match:
        return re.findall(r"['\"]([^'\"]+)['\"]", match.group(1))
    stages = re.findall(r"run_stage\s*:\s*['\"]([^'\"]+)['\"]", text)
    return list(dict.fromkeys(stages))


def docs_text(root: Path) -> str:
    parts = []
    for rel in ["README.md", "docs"]:
        path = root / rel
        if path.is_file():
            parts.append(read_text(path))
        elif path.is_dir():
            for doc in sorted(path.glob("*.md")):
                parts.append(read_text(doc))
    return "\n".join(parts)


def check_run_stage_docs(rows: list[dict[str, str]], root: Path) -> None:
    stages = allowed_stages(root)
    if not stages:
        add(rows, "run_stage_discovery", "ERROR", "main.nf", "Could not discover allowedStages.", "Keep allowedStages as a literal list or update the validator.")
        return
    add(rows, "run_stage_discovery", "PASS", "main.nf", f"Discovered {len(stages)} run_stage values.")
    text = docs_text(root)
    missing = [stage for stage in stages if f"--run_stage {stage}" not in text and f"`{stage}`" not in text]
    if missing:
        add(rows, "run_stage_documentation", "ERROR", "README/docs", "Undocumented run_stage values: " + ", ".join(missing), "Document every supported run_stage value.")
    else:
        add(rows, "run_stage_documentation", "PASS", "README/docs", "All run_stage values are documented.")


def iter_core_files(root: Path):
    for rel in CORE_SCAN_ROOTS:
        path = root / rel
        if path.is_file():
            candidates = [path]
        elif path.is_dir():
            candidates = [candidate for candidate in path.rglob("*") if candidate.is_file()]
        else:
            continue
        for candidate in candidates:
            rel_path = candidate.relative_to(root).as_posix()
            if rel_path in CORE_SCAN_EXCLUDE_FILES:
                continue
            if "__pycache__" in candidate.parts or candidate.suffix not in TEXT_SUFFIXES:
                continue
            yield candidate


def check_absolute_paths(rows: list[dict[str, str]], root: Path) -> None:
    hits = []
    for path in iter_core_files(root):
        rel = path.relative_to(root).as_posix()
        for line_number, line in enumerate(read_text(path).splitlines(), start=1):
            if line.strip().startswith("#!"):
                continue
            if any(pattern.search(line) for pattern in ABSOLUTE_PATH_PATTERNS):
                hits.append(f"{rel}:{line_number}")
    if hits:
        for hit in hits[:50]:
            add(rows, "absolute_path_scan", "ERROR", hit, "Local absolute path found in core logic.", "Use project-relative paths, params, or runtime inputs.")
        if len(hits) > 50:
            add(rows, "absolute_path_scan", "ERROR", "core logic", f"{len(hits) - 50} additional path matches omitted.")
    else:
        add(rows, "absolute_path_scan", "PASS", "core logic", "No local absolute paths found in core logic.")


def check_profile_terms(rows: list[dict[str, str]], root: Path) -> None:
    hits = []
    for path in iter_core_files(root):
        rel = path.relative_to(root).as_posix()
        for line_number, line in enumerate(read_text(path).splitlines(), start=1):
            for term_id, pattern in PROFILE_PATTERNS:
                if pattern.search(line):
                    hits.append((f"{rel}:{line_number}", term_id))
    if hits:
        for subject, term_id in hits[:50]:
            add(rows, "profile_term_scan", "ERROR", subject, f"Profile-specific term matched {term_id} in core logic.", "Move study-specific language to profiles, docs, tests, or examples.")
        if len(hits) > 50:
            add(rows, "profile_term_scan", "ERROR", "core logic", f"{len(hits) - 50} additional profile-term matches omitted.")
    else:
        add(rows, "profile_term_scan", "PASS", "core logic", "No forbidden profile-specific terms found in core logic.")


def check_stub_all_run_outputs(rows: list[dict[str, str]], root: Path, results_dir: Path) -> None:
    summary_dir = results_dir / "all" / "summary"
    status_file = summary_dir / "came_all_run_status.txt"
    final_html = results_dir / "final" / "report" / "came_final_report.html"
    final_md = results_dir / "final" / "report" / "came_final_report.md"
    final_css = results_dir / "final" / "report" / "came_report.css"
    manifest = results_dir / "final" / "manifest" / "came_outputs_manifest.tsv"
    provenance = results_dir / "final" / "provenance" / "came_run_provenance.tsv"
    parameters = results_dir / "final" / "provenance" / "came_parameters_snapshot.tsv"
    asset_manifest = results_dir / "final" / "assets" / "report_asset_manifest.tsv"
    stage_asset = results_dir / "final" / "assets" / "stage_completion_summary.tsv"
    release_checks = results_dir / "final" / "release_checks" / "came_release_checks.tsv"
    if not summary_dir.exists() and not status_file.exists():
        subject = results_dir.relative_to(root).as_posix() if results_dir.is_relative_to(root) else str(results_dir)
        add(rows, "stub_all_run_outputs", "WARNING", subject, "No stub all-run summary found; output validation was skipped.", "Run the stub all-run before release tagging.")
        return
    required = [status_file, final_html, final_md, final_css, manifest, provenance, parameters, asset_manifest, stage_asset, release_checks]
    missing = [path for path in required if not path.is_file() or path.stat().st_size == 0]
    for path in missing:
        add(rows, "stub_all_run_outputs", "ERROR", path.relative_to(root).as_posix() if path.is_relative_to(root) else str(path), "Expected stub all-run/final-report output is missing or empty.", "Run --run_stage all in stub mode.")
    if status_file.is_file() and "all_run_status\tCOMPLETE" not in read_text(status_file):
        add(rows, "stub_all_run_outputs", "ERROR", status_file.as_posix(), "Stub all-run status is not COMPLETE.", "Inspect results/all/summary and rerun failed stages.")
    if not missing and status_file.is_file() and "all_run_status\tCOMPLETE" in read_text(status_file):
        add(rows, "stub_all_run_outputs", "PASS", str(results_dir), "Stub all-run outputs and final report are present.")


def fixture_file_forbidden(path: Path) -> bool:
    lower = path.name.lower()
    if any(lower.endswith(suffix) for suffix in FIXTURE_FORBIDDEN_COMPOUND_SUFFIXES):
        return True
    if path.suffix.lower() in FIXTURE_FORBIDDEN_SUFFIXES:
        return True
    return lower.endswith((".amb", ".ann"))


def check_real_mode_fixtures(rows: list[dict[str, str]], root: Path) -> None:
    fixture_root = root / "assets" / "test_data" / "real_mode_fixtures"
    if not fixture_root.is_dir():
        add(rows, "real_mode_fixture_files", "ERROR", fixture_root.as_posix(), "Stage 28 fixture directory is missing.", "Generate tiny fixtures with bin/make_real_mode_fixtures.py.")
        return
    files = sorted(path for path in fixture_root.rglob("*") if path.is_file())
    if not files:
        add(rows, "real_mode_fixture_files", "ERROR", fixture_root.as_posix(), "Stage 28 fixture directory has no files.", "Generate tiny fixtures with bin/make_real_mode_fixtures.py.")
        return
    max_file_bytes = 100_000
    max_total_bytes = 1_000_000
    total_bytes = 0
    problems = 0
    for path in files:
        rel = path.relative_to(root).as_posix()
        size = path.stat().st_size
        total_bytes += size
        if size == 0:
            problems += 1
            add(rows, "real_mode_fixture_files", "ERROR", rel, "Fixture file is empty.", "Regenerate the fixture or remove it from the required fixture set.")
        if size > max_file_bytes:
            problems += 1
            add(rows, "real_mode_fixture_files", "ERROR", rel, f"Fixture file is too large ({size} bytes).", "Keep committed fixtures tiny and text-only.")
        if fixture_file_forbidden(path):
            problems += 1
            add(rows, "real_mode_fixture_files", "ERROR", rel, "Generated binary/index-like fixture file is not allowed.", "Do not commit BAM, VCF index, aligner index, CRAM, or BCF outputs.")
        data = path.read_bytes()
        if b"\x00" in data:
            problems += 1
            add(rows, "real_mode_fixture_files", "ERROR", rel, "Fixture file contains NUL bytes.", "Store only tiny UTF-8 text fixtures.")
            continue
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError:
            problems += 1
            add(rows, "real_mode_fixture_files", "ERROR", rel, "Fixture file is not UTF-8 text.", "Store only tiny UTF-8 text fixtures.")
            continue
        for line_number, line in enumerate(text.splitlines(), start=1):
            if any(pattern.search(line) for pattern in ABSOLUTE_PATH_PATTERNS):
                problems += 1
                add(rows, "real_mode_fixture_files", "ERROR", f"{rel}:{line_number}", "Local absolute path found in fixture content.", "Use manifest-relative fixture paths.")
                break
    if total_bytes > max_total_bytes:
        problems += 1
        add(rows, "real_mode_fixture_files", "ERROR", fixture_root.relative_to(root).as_posix(), f"Fixture tree is too large ({total_bytes} bytes).", "Keep committed Stage 28 fixtures compact.")
    if problems == 0:
        add(rows, "real_mode_fixture_files", "PASS", fixture_root.relative_to(root).as_posix(), f"Stage 28 fixtures are tiny text files with no local absolute paths ({len(files)} files, {total_bytes} bytes).")


def check_schema_sync(rows: list[dict[str, str]], root: Path) -> None:
    pairs = [
        (
            root / "schemas" / "reference_manifest.schema.json",
            root / "assets" / "schema" / "reference_manifest.schema.json",
        )
    ]
    for canonical, asset in pairs:
        subject = f"{canonical.relative_to(root).as_posix()} vs {asset.relative_to(root).as_posix()}"
        if not canonical.is_file() or not asset.is_file():
            add(rows, "schema_sync", "ERROR", subject, "Canonical or asset schema file is missing.", "Restore both schema files.")
            continue
        try:
            canonical_json = json.loads(read_text(canonical))
            asset_json = json.loads(read_text(asset))
        except json.JSONDecodeError as exc:
            add(rows, "schema_sync", "ERROR", subject, f"Schema JSON could not be parsed: {exc}", "Fix malformed JSON.")
            continue
        if canonical_json != asset_json:
            add(rows, "schema_sync", "ERROR", subject, "Same-named schemas diverge.", "Keep schemas/ as canonical and copy it to assets/schema/.")
        else:
            add(rows, "schema_sync", "PASS", subject, "Same-named reference manifest schemas are JSON-equivalent.")


def check_conda_lock(rows: list[dict[str, str]], root: Path) -> None:
    path = root / "environment" / "conda-linux-64.lock"
    if not path.is_file():
        add(rows, "conda_linux_lock", "ERROR", path.relative_to(root).as_posix(), "linux-64 explicit conda lock is missing.", "Generate it with conda-lock.")
        return
    text = read_text(path)
    problems = []
    if "# platform: linux-64" not in text:
        problems.append("missing linux-64 platform marker")
    if "@EXPLICIT" not in text:
        problems.append("missing @EXPLICIT marker")
    if "/t/" in text or "**********" in text:
        problems.append("contains auth-token URL segment")
    if "osx-arm64" in text or "osx-64" in text:
        problems.append("contains macOS package URLs")
    if "openjdk-" not in text:
        problems.append("missing openjdk package")
    required_packages = [
        "bioconductor-deseq2",
        "r-ape",
        "r-nlme",
        "star",
        "subread",
        "bowtie2",
        "macs3",
        "bwa-mem2",
        "samtools",
        "gatk4",
        "bedtools",
        "fastqc",
        "multiqc",
    ]
    missing_packages = [package for package in required_packages if f"/{package}-" not in text]
    if missing_packages:
        problems.append("missing required real-mode package(s): " + ", ".join(missing_packages))
    if not re.search(r"^# input_hash: [0-9a-f]{64}$", text, re.MULTILINE):
        problems.append("missing conda-lock input_hash marker")
    if problems:
        add(rows, "conda_linux_lock", "ERROR", path.relative_to(root).as_posix(), "; ".join(problems), "Regenerate the linux-64 explicit lock and strip auth tokens.")
    else:
        add(rows, "conda_linux_lock", "PASS", path.relative_to(root).as_posix(), "linux-64 explicit lock is present, auth-free, and includes required real-mode tools.")


def main(argv: list[str] | None = None) -> int:
    root = project_root()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-dir", default=str(root))
    parser.add_argument("--results-dir", default=str(root / "results"))
    parser.add_argument("--output", default=str(root / "results" / "final" / "release_checks" / "release_bundle_validation.tsv"))
    parser.add_argument("--no-fail", action="store_true", help="Write results but return zero even if ERROR records exist.")
    args = parser.parse_args(argv)

    project_dir = Path(args.project_dir).resolve()
    results_dir = Path(args.results_dir).resolve()
    rows: list[dict[str, str]] = []

    check_files(rows, project_dir, "workflow_files", REQUIRED_WORKFLOWS, "workflow")
    check_files(rows, project_dir, "test_files", REQUIRED_TESTS, "test")
    check_files(rows, project_dir, "documentation_files", REQUIRED_DOCS, "documentation")
    check_files(rows, project_dir, "bin_scripts", REQUIRED_BIN, "bin script")
    check_files(rows, project_dir, "report_templates", REQUIRED_TEMPLATES, "report template")
    check_files(rows, project_dir, "environment_files", REQUIRED_ENVIRONMENT, "environment")
    check_files(rows, project_dir, "schema_files", REQUIRED_SCHEMAS, "schema")
    check_files(rows, project_dir, "release_metadata_files", REQUIRED_RELEASE_FILES, "release metadata")
    check_files(rows, project_dir, "example_assets", REQUIRED_EXAMPLES, "example asset")
    check_license(rows, project_dir)
    check_citation(rows, project_dir)
    check_version_file(rows, project_dir)
    check_readme_links(rows, project_dir)
    check_nextflow_includes(rows, project_dir)
    check_referenced_bin_scripts(rows, project_dir)
    check_run_stage_docs(rows, project_dir)
    check_absolute_paths(rows, project_dir)
    check_profile_terms(rows, project_dir)
    check_nanoseq_claims(rows, project_dir)
    check_scaffold_docs(rows, project_dir)
    check_real_mode_fixtures(rows, project_dir)
    check_schema_sync(rows, project_dir)
    check_conda_lock(rows, project_dir)
    check_stub_all_run_outputs(rows, project_dir, results_dir)

    output = Path(args.output)
    write_tsv(output, rows)
    errors = sum(1 for row in rows if row["status"] == "ERROR")
    warnings = sum(1 for row in rows if row["status"] == "WARNING")
    print(f"Wrote {output}")
    print(f"release bundle checks: records={len(rows)} errors={errors} warnings={warnings}")
    return 0 if args.no_fail or errors == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
