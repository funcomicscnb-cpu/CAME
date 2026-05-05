#!/usr/bin/env python3
"""Render compact CAME final reports from manifests, assets, and provenance."""

from __future__ import annotations

import argparse
import csv
import html
import os
import shutil
from pathlib import Path
from string import Template


STAGE_TITLES = [
    ("stage_01_metadata_validation", "Metadata Validation"),
    ("stage_02_study_profile_validation", "Study Profile Validation"),
    ("stage_03_phenotype_response", "Phenotype Response"),
    ("stage_04_phylogenetic_hypothesis", "Phylogenetic/Hypothesis Model"),
    ("stage_05_bulk_omics", "Bulk Omics"),
    ("stage_06_differential_omics", "Differential Omics"),
    ("stage_07_orthology_projection", "Orthology Projection"),
    ("stage_08_gra_analysis", "GRA Analysis"),
    ("stage_09_phenotype_omics_integration", "Phenotype-Omics Integration"),
    ("stage_10_candidate_prioritization", "Candidate Prioritization"),
    ("stage_11_functional_interpretation", "Functional Interpretation"),
]

SUMMARY_FILES = {
    "stage_01_metadata_validation": ["validation/metadata_validation_report.tsv"],
    "stage_02_study_profile_validation": ["validation/study_profile_validation_report.tsv"],
    "stage_03_phenotype_response": [
        "phenotype/qc/normalization_summary.tsv",
        "phenotype/qc/phenotype_qc_metrics.tsv",
        "phenotype/summary/phenotype_processing_manifest.tsv",
    ],
    "stage_04_phylogenetic_hypothesis": [
        "phylo/models/model_results.tsv",
        "hypotheses/hypothesis_test_summary.tsv",
    ],
    "stage_05_bulk_omics": [
        "omics/summary/omics_run_summary.tsv",
        "rnaseq/summary/rnaseq_summary.tsv",
        "atacseq/summary/atacseq_summary.tsv",
    ],
    "stage_06_differential_omics": ["differential_omics/summary/differential_omics_summary.tsv"],
    "stage_07_orthology_projection": ["orthology/summary/orthology_projection_summary.tsv"],
    "stage_08_gra_analysis": ["gra/summary/gra_analysis_summary.tsv"],
    "stage_09_phenotype_omics_integration": ["integration/summary/phenotype_omics_integration_summary.tsv"],
    "stage_10_candidate_prioritization": ["candidates/summary/candidate_prioritization_summary.tsv"],
    "stage_11_functional_interpretation": ["interpretation/summary/functional_interpretation_summary.tsv"],
}

KEY_LINKS = [
    ("Output manifest", "final/manifest/came_outputs_manifest.tsv"),
    ("Stage completion summary", "final/assets/stage_completion_summary.tsv"),
    ("Missing output warnings", "final/manifest/came_missing_outputs.tsv"),
    ("Run provenance", "final/provenance/came_run_provenance.tsv"),
    ("Parameter snapshot", "final/provenance/came_parameters_snapshot.tsv"),
    ("Report asset manifest", "final/assets/report_asset_manifest.tsv"),
    ("Release checks", "final/release_checks/came_release_checks.tsv"),
    ("Candidate ranking", "candidates/ranked/candidate_all_ranked.tsv"),
    ("Functional enrichment", "interpretation/enrichment/gene_set_enrichment.tsv"),
]

LIMITATIONS = [
    "Final reporting does not add biological analyses; it summarizes outputs already produced by prior stages.",
    "Missing upstream outputs mean evidence is unavailable for this report; they do not imply the stage was executed.",
    "Functional enrichment is offline overrepresentation testing and depends on supplied annotation and gene-set files.",
    "Coordinates are exported as supplied; no lift-over or coordinate conversion is performed.",
    "Orthology tables and regulatory-element-to-gene links are consumed, not inferred.",
]

FALLBACK_CSS = """body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 2rem; color: #18212f; line-height: 1.45; }
h1, h2, h3 { color: #12344d; }
a { color: #0b5cad; }
table { border-collapse: collapse; width: 100%; margin: 0.75rem 0 1.5rem; font-size: 0.92rem; }
th, td { border: 1px solid #d7dee8; padding: 0.42rem 0.55rem; text-align: left; vertical-align: top; }
th { background: #edf2f7; }
section { margin-bottom: 1.35rem; }
.meta, .note { color: #52616b; }
.status-completed { color: #166534; font-weight: 650; }
.status-warning { color: #92400e; font-weight: 650; }
.status-missing_optional { color: #6b7280; font-weight: 650; }
.status-failed-error { color: #991b1b; font-weight: 650; }
"""


def project_root() -> Path:
    return Path(__file__).resolve().parents[1]


def norm(value: object) -> str:
    return str(value if value is not None else "").strip()


def infer_delimiter(path: Path) -> str:
    if path.suffix.lower() in {".tsv", ".bed"}:
        return "\t"
    if path.suffix.lower() == ".csv":
        return ","
    with path.open(newline="") as handle:
        sample = handle.read(min(65536, os.path.getsize(path)))
    return "\t" if sample.count("\t") >= sample.count(",") else ","


def read_table(path: str | Path | None, limit: int | None = None) -> tuple[list[str], list[dict[str, str]]]:
    if not path:
        return [], []
    table_path = Path(path)
    if not table_path.is_file():
        return [], []
    with table_path.open(newline="") as handle:
        reader = csv.DictReader(handle, delimiter=infer_delimiter(table_path))
        fields = reader.fieldnames or []
        rows = []
        for row in reader:
            rows.append({field: norm(row.get(field)) for field in fields})
            if limit and len(rows) >= limit:
                break
    return fields, rows


def write_file(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def normalize_display_path(value: str, results_dir: Path) -> str:
    text = norm(value)
    if not text:
        return ""
    path = Path(text).expanduser()
    if not path.is_absolute():
        return text
    resolved = path.resolve()
    for base in [project_root(), results_dir]:
        try:
            return resolved.relative_to(base.resolve()).as_posix()
        except ValueError:
            continue
    return f"[external]/{resolved.name}"


def load_profile(path: str, results_dir: Path) -> dict[str, str]:
    profile = {"path": normalize_display_path(path, results_dir), "profile_id": "", "name": "", "description": ""}
    profile_path = Path(path)
    if not profile_path.exists():
        return profile
    try:
        import yaml  # type: ignore

        with profile_path.open() as handle:
            data = yaml.safe_load(handle) or {}
        metadata = {}
        if isinstance(data, dict):
            metadata = data.get("study") or data.get("metadata") or {}
        profile["profile_id"] = norm(metadata.get("profile_id"))
        profile["name"] = norm(metadata.get("name"))
        profile["description"] = norm(metadata.get("description"))
        return profile
    except Exception:
        pass

    current = ""
    for raw_line in profile_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if not raw_line.startswith((" ", "\t")) and line.endswith(":"):
            current = line[:-1]
            continue
        if current in {"study", "metadata"} and ":" in line:
            key, value = line.split(":", 1)
            key = key.strip()
            if key in profile:
                profile[key] = value.strip().strip("'\"")
    return profile


def relative_link(results_dir: Path, relative_path: str) -> str:
    target = results_dir / relative_path
    base = results_dir / "final" / "report"
    return os.path.relpath(target, base)


def status_counts(rows: list[dict[str, str]], field: str = "status") -> dict[str, int]:
    counts: dict[str, int] = {}
    for row in rows:
        value = norm(row.get(field)) or "NA"
        counts[value] = counts.get(value, 0) + 1
    return counts


def summarize_file(path: Path) -> str:
    fields, rows = read_table(path)
    if not rows:
        return "present; 0 data rows"
    if {"metric", "value"}.issubset(fields):
        metrics = [f"{row.get('metric')}: {row.get('value')}" for row in rows[:5]]
        suffix = "; ".join(metrics)
        if len(rows) > 5:
            suffix += f"; {len(rows) - 5} more metrics"
        return suffix
    if "severity" in fields:
        counts = status_counts(rows, "severity")
        return f"{len(rows)} rows; " + ", ".join(f"{key}={counts[key]}" for key in sorted(counts))
    if "status" in fields:
        counts = status_counts(rows)
        return f"{len(rows)} rows; " + ", ".join(f"{key}={counts[key]}" for key in sorted(counts))
    return f"{len(rows)} data rows"


def fallback_stage_assets(stage_summary_path: str | Path) -> list[dict[str, str]]:
    _, rows = read_table(stage_summary_path)
    output = []
    titles = dict(STAGE_TITLES)
    for row in rows:
        stage = row.get("stage", "")
        source_status = row.get("status", "")
        if source_status == "COMPLETE":
            status = "completed"
            message = "Expected compact outputs were present."
        elif source_status == "MISSING":
            status = "missing_optional"
            message = "No expected compact outputs were found; the stage may not have been run for this report."
        else:
            status = "warning"
            message = "Some expected outputs require review."
        output.append(
            {
                "stage": stage,
                "stage_title": titles.get(stage, stage),
                "status": status,
                "source_status": source_status,
                "expected_count": row.get("expected_count", "0"),
                "present_count": row.get("present_count", "0"),
                "missing_count": row.get("missing_count", "0"),
                "warning_count": "0",
                "error_count": "0",
                "message": message,
            }
        )
    return output


def stage_detail_sections(results_dir: Path, stage_assets: list[dict[str, str]]) -> list[dict[str, object]]:
    by_stage = {row.get("stage"): row for row in stage_assets}
    sections = []
    for stage, title in STAGE_TITLES:
        completion = by_stage.get(stage, {})
        details = []
        for rel_path in SUMMARY_FILES.get(stage, []):
            path = results_dir / rel_path
            if path.exists():
                details.append((rel_path, summarize_file(path), relative_link(results_dir, rel_path)))
        if not details:
            details.append(("", "No compact upstream summary file was available.", ""))
        sections.append(
            {
                "stage": stage,
                "title": title,
                "status": completion.get("status", "missing_optional"),
                "source_status": completion.get("source_status", "MISSING"),
                "expected": completion.get("expected_count", "0"),
                "present": completion.get("present_count", "0"),
                "missing": completion.get("missing_count", "0"),
                "warnings": completion.get("warning_count", "0"),
                "errors": completion.get("error_count", "0"),
                "message": completion.get("message", ""),
                "details": details,
            }
        )
    return sections


def numeric_key(value: str, default: float = 1.0) -> float:
    text = norm(value)
    if text.upper() == "NA" or not text:
        return default
    try:
        return float(text)
    except ValueError:
        return default


def fallback_top_candidates(results_dir: Path, limit: int) -> tuple[list[str], list[dict[str, str]], str]:
    path = results_dir / "candidates/ranked/candidate_all_ranked.tsv"
    fields, rows = read_table(path)
    if not rows:
        return [], [], "Candidate ranking table was not available."
    rows = sorted(rows, key=lambda row: numeric_key(row.get("rank", ""), default=10**9))[:limit]
    wanted = [
        "rank",
        "candidate_id",
        "candidate_type",
        "total_score",
        "n_evidence_types",
        "top_evidence_type",
        "top_contrast",
        "combined_direction",
    ]
    return [field for field in wanted if field in fields], rows, ""


def fallback_top_enrichment(results_dir: Path, limit: int) -> tuple[list[str], list[dict[str, str]], str]:
    path = results_dir / "interpretation/enrichment/gene_set_enrichment.tsv"
    fields, rows = read_table(path)
    rows = [
        row
        for row in rows
        if (not row.get("status") or row.get("status") == "OK") and norm(row.get("n_overlap")) not in {"", "0"}
    ]
    if not rows:
        return [], [], "Enrichment table was not available or had no enriched rows."
    rows = sorted(
        rows,
        key=lambda row: (
            numeric_key(row.get("padj")),
            numeric_key(row.get("p_value")),
            row.get("candidate_set", ""),
            row.get("gene_set_id", ""),
        ),
    )[:limit]
    wanted = ["candidate_set", "gene_set_id", "gene_set_name", "n_overlap", "p_value", "padj", "status"]
    return [field for field in wanted if field in fields], rows, ""


def preview_from_asset(path: str | None, fallback_func, results_dir: Path, limit: int) -> tuple[list[str], list[dict[str, str]], str]:
    fields, rows = read_table(path)
    if rows:
        present_rows = [row for row in rows if row.get("status") == "present"]
        if present_rows:
            visible_fields = [field for field in fields if field not in {"status", "message"}]
            return visible_fields, present_rows[:limit], ""
        message = next((row.get("message", "") for row in rows if row.get("message")), "Optional table was unavailable.")
        return [], [], message
    return fallback_func(results_dir, limit)


def status_class(status: str) -> str:
    return "status-" + status.replace("/", "-").replace(" ", "-").replace("_", "_")


def md_table(fields: list[str], rows: list[dict[str, str]]) -> str:
    if not fields:
        return ""
    output = ["|" + "|".join(fields) + "|", "|" + "|".join(["---"] * len(fields)) + "|"]
    for row in rows:
        output.append("|" + "|".join(norm(row.get(field)).replace("|", "\\|") for field in fields) + "|")
    return "\n".join(output)


def html_table(fields: list[str], rows: list[dict[str, str]]) -> str:
    if not fields:
        return ""
    header = "".join(f"<th>{html.escape(field)}</th>" for field in fields)
    body = []
    for row in rows:
        cells = "".join(f"<td>{html.escape(norm(row.get(field)))}</td>" for field in fields)
        body.append(f"<tr>{cells}</tr>")
    return f"<table><thead><tr>{header}</tr></thead><tbody>{''.join(body)}</tbody></table>"


def compact_provenance_rows(path: str | None) -> tuple[list[str], list[dict[str, str]]]:
    fields, rows = read_table(path)
    wanted_keys = {"version", "commit", "dirty", "timestamp_utc", "outdir", "nextflow", "python", "R", "snapshot_rows", "snapshot"}
    filtered = [row for row in rows if row.get("key") in wanted_keys or row.get("status") == "WARNING"]
    visible = [field for field in ["section", "key", "value", "status", "message"] if field in fields]
    if filtered:
        return visible, filtered[:20]
    return ["section", "key", "value", "status", "message"], [
        {"section": "provenance", "key": "run", "value": "", "status": "WARNING", "message": "Run provenance was unavailable."}
    ]


def compact_parameter_rows(path: str | None) -> tuple[list[str], list[dict[str, str]]]:
    fields, rows = read_table(path, limit=20)
    visible = [field for field in ["parameter", "value", "status", "message"] if field in fields]
    if rows:
        return visible, rows
    return ["parameter", "value", "status", "message"], [
        {"parameter": "params_snapshot", "value": "", "status": "WARNING", "message": "Parameter snapshot was unavailable."}
    ]


def release_counts(release_summary: list[dict[str, str]]) -> str:
    counts = {row.get("status"): row.get("count") for row in release_summary}
    return ", ".join(f"{key}={counts[key]}" for key in sorted(counts) if key) or "unavailable"


def build_markdown(profile: dict[str, str], sections: list[dict[str, object]], missing_rows: list[dict[str, str]], release_rows: list[dict[str, str]], release_summary: list[dict[str, str]], candidate_fields: list[str], candidate_rows: list[dict[str, str]], candidate_message: str, enrich_fields: list[str], enrich_rows: list[dict[str, str]], enrich_message: str, provenance_fields: list[str], provenance_rows: list[dict[str, str]], parameter_fields: list[str], parameter_rows: list[dict[str, str]], warning_fields: list[str], warning_rows: list[dict[str, str]], results_dir: Path) -> str:
    lines = [
        "# CAME Final Report",
        "",
        "## Study Profile",
        "",
        f"- Profile ID: {profile.get('profile_id') or 'unknown'}",
        f"- Name: {profile.get('name') or 'unknown'}",
        f"- Path: {profile.get('path')}",
    ]
    if profile.get("description"):
        lines.append(f"- Description: {profile['description']}")

    lines.extend(["", "## Status Legend", ""])
    lines.extend(
        [
            "- completed: expected compact outputs were present with no report-level warning counts",
            "- warning: expected outputs are partial or warning records were found",
            "- missing_optional: optional or upstream outputs were unavailable; report generation continued",
            "- failed/error: an error record was found and should be reviewed",
        ]
    )

    lines.extend(["", "## Run Provenance", "", md_table(provenance_fields, provenance_rows)])
    lines.extend(["", "## Parameters", "", md_table(parameter_fields, parameter_rows)])

    lines.extend(["", "## Stage Completion", ""])
    lines.append("|Stage|Status|Present|Missing|Warnings|Errors|")
    lines.append("|---|---|---:|---:|---:|---:|")
    for section in sections:
        lines.append(
            f"|{section['title']}|{section['status']}|{section['present']}/{section['expected']}|{section['missing']}|{section['warnings']}|{section['errors']}|"
        )

    lines.extend(["", "## Stage Summaries", ""])
    for section in sections:
        lines.append(f"### {section['title']}")
        lines.append("")
        lines.append(
            f"Status: {section['status']} ({section['present']} of {section['expected']} expected outputs present). {section['message']}"
        )
        for rel_path, summary, link in section["details"]:  # type: ignore[index]
            if rel_path:
                lines.append(f"- [{rel_path}]({link}): {summary}")
            else:
                lines.append(f"- {summary}")
        lines.append("")

    lines.extend(["## Release Checks", ""])
    lines.append(f"- Release check counts: {release_counts(release_summary)}")
    lines.append(f"- Release check errors present: {str(any(row.get('status') == 'ERROR' for row in release_rows)).lower()}")

    lines.extend(["", "## Top Candidates", ""])
    lines.append(md_table(candidate_fields, candidate_rows) if candidate_rows else candidate_message or "No candidate ranking table was available.")
    lines.extend(["", "## Top Enriched Gene Sets", ""])
    lines.append(md_table(enrich_fields, enrich_rows) if enrich_rows else enrich_message or "No enriched gene-set rows were available.")

    lines.extend(["", "## Warnings", ""])
    lines.append(f"- Missing expected upstream outputs: {len(missing_rows)}")
    lines.append(md_table(warning_fields, warning_rows[:20]) if warning_rows else "No warning groups were detected.")

    lines.extend(["", "## Key Outputs", ""])
    for label, rel_path in KEY_LINKS:
        target = results_dir / rel_path
        if target.exists():
            lines.append(f"- [{label}]({relative_link(results_dir, rel_path)})")

    lines.extend(["", "## Limitations", ""])
    for limitation in LIMITATIONS:
        lines.append(f"- {limitation}")
    lines.append("")
    return "\n".join(lines)


def build_html(profile: dict[str, str], sections: list[dict[str, object]], missing_rows: list[dict[str, str]], release_rows: list[dict[str, str]], release_summary: list[dict[str, str]], candidate_fields: list[str], candidate_rows: list[dict[str, str]], candidate_message: str, enrich_fields: list[str], enrich_rows: list[dict[str, str]], enrich_message: str, provenance_fields: list[str], provenance_rows: list[dict[str, str]], parameter_fields: list[str], parameter_rows: list[dict[str, str]], warning_fields: list[str], warning_rows: list[dict[str, str]], results_dir: Path) -> str:
    stage_rows = []
    for section in sections:
        status = str(section["status"])
        stage_rows.append(
            "<tr>"
            f"<td>{html.escape(str(section['title']))}</td>"
            f'<td class="{html.escape(status_class(status))}">{html.escape(status)}</td>'
            f"<td>{html.escape(str(section['present']))}/{html.escape(str(section['expected']))}</td>"
            f"<td>{html.escape(str(section['missing']))}</td>"
            f"<td>{html.escape(str(section['warnings']))}</td>"
            f"<td>{html.escape(str(section['errors']))}</td>"
            "</tr>"
        )
    stage_summaries = []
    for section in sections:
        details = []
        for rel_path, summary, link in section["details"]:  # type: ignore[index]
            if rel_path:
                details.append(f'<li><a href="{html.escape(link)}">{html.escape(rel_path)}</a>: {html.escape(summary)}</li>')
            else:
                details.append(f"<li>{html.escape(summary)}</li>")
        status = str(section["status"])
        stage_summaries.append(
            f"<section><h3>{html.escape(str(section['title']))}</h3>"
            f'<p>Status: <strong class="{html.escape(status_class(status))}">{html.escape(status)}</strong> '
            f"({html.escape(str(section['present']))} of {html.escape(str(section['expected']))} expected outputs present). "
            f"{html.escape(str(section['message']))}</p>"
            f"<ul>{''.join(details)}</ul></section>"
        )
    links = []
    for label, rel_path in KEY_LINKS:
        target = results_dir / rel_path
        if target.exists():
            links.append(f'<li><a href="{html.escape(relative_link(results_dir, rel_path))}">{html.escape(label)}</a></li>')
    limitations = "".join(f"<li>{html.escape(item)}</li>" for item in LIMITATIONS)
    warning_table = html_table(warning_fields, warning_rows[:20]) if warning_rows else "<p>No warning groups were detected.</p>"
    return f"""
<h1>CAME Final Report</h1>
<section>
<h2>Study Profile</h2>
<p><strong>Profile ID:</strong> {html.escape(profile.get('profile_id') or 'unknown')}<br>
<strong>Name:</strong> {html.escape(profile.get('name') or 'unknown')}<br>
<strong>Path:</strong> {html.escape(profile.get('path') or '')}</p>
<p class="meta">{html.escape(profile.get('description') or '')}</p>
</section>
<section>
<h2>Status Legend</h2>
<ul>
<li><strong class="status-completed">completed</strong>: expected compact outputs were present with no report-level warning counts</li>
<li><strong class="status-warning">warning</strong>: expected outputs are partial or warning records were found</li>
<li><strong class="status-missing_optional">missing_optional</strong>: optional or upstream outputs were unavailable; report generation continued</li>
<li><strong class="status-failed-error">failed/error</strong>: an error record was found and should be reviewed</li>
</ul>
</section>
<section>
<h2>Run Provenance</h2>
{html_table(provenance_fields, provenance_rows)}
</section>
<section>
<h2>Parameters</h2>
{html_table(parameter_fields, parameter_rows)}
</section>
<section>
<h2>Stage Completion</h2>
<table><thead><tr><th>Stage</th><th>Status</th><th>Present</th><th>Missing</th><th>Warnings</th><th>Errors</th></tr></thead><tbody>{''.join(stage_rows)}</tbody></table>
</section>
<section>
<h2>Stage Summaries</h2>
{''.join(stage_summaries)}
</section>
<section>
<h2>Release Checks</h2>
<ul>
<li>Release check counts: {html.escape(release_counts(release_summary))}</li>
<li>Release check errors present: {str(any(row.get('status') == 'ERROR' for row in release_rows)).lower()}</li>
</ul>
</section>
<section>
<h2>Top Candidates</h2>
{html_table(candidate_fields, candidate_rows) if candidate_rows else f'<p>{html.escape(candidate_message or "No candidate ranking table was available.")}</p>'}
</section>
<section>
<h2>Top Enriched Gene Sets</h2>
{html_table(enrich_fields, enrich_rows) if enrich_rows else f'<p>{html.escape(enrich_message or "No enriched gene-set rows were available.")}</p>'}
</section>
<section>
<h2>Warnings</h2>
<p>Missing expected upstream outputs: {len(missing_rows)}</p>
{warning_table}
</section>
<section>
<h2>Key Outputs</h2>
<ul>{''.join(links)}</ul>
</section>
<section>
<h2>Limitations</h2>
<ul>{limitations}</ul>
</section>
"""


def load_template(path: Path, fallback: str) -> Template:
    if path.is_file():
        return Template(path.read_text(encoding="utf-8"))
    return Template(fallback)


def copy_css(template_dir: Path, output_dir: Path) -> None:
    source = template_dir / "came_report.css"
    target = output_dir / "came_report.css"
    output_dir.mkdir(parents=True, exist_ok=True)
    if source.is_file():
        shutil.copyfile(source, target)
    else:
        write_file(target, FALLBACK_CSS)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--study_profile", required=True)
    parser.add_argument("--results_dir", required=True)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--stage_summary", required=True)
    parser.add_argument("--missing_outputs", required=True)
    parser.add_argument("--release_checks", required=True)
    parser.add_argument("--release_summary", required=True)
    parser.add_argument("--output_dir", required=True)
    parser.add_argument("--top_n", type=int, default=10)
    parser.add_argument("--template_dir", default=str(project_root() / "templates"))
    parser.add_argument("--provenance")
    parser.add_argument("--parameters")
    parser.add_argument("--asset_manifest")
    parser.add_argument("--asset_stage_completion")
    parser.add_argument("--asset_top_candidates")
    parser.add_argument("--asset_top_enriched_gene_sets")
    parser.add_argument("--asset_warning_summary")
    args = parser.parse_args(argv)

    results_dir = Path(args.results_dir).resolve()
    output_dir = Path(args.output_dir).resolve()
    template_dir = Path(args.template_dir).resolve()
    profile = load_profile(args.study_profile, results_dir)
    _, missing_rows = read_table(args.missing_outputs)
    _, release_rows = read_table(args.release_checks)
    _, release_summary_rows = read_table(args.release_summary)

    _, stage_asset_rows = read_table(args.asset_stage_completion)
    if not stage_asset_rows:
        stage_asset_rows = fallback_stage_assets(args.stage_summary)
    sections = stage_detail_sections(results_dir, stage_asset_rows)

    candidate_fields, candidate_rows, candidate_message = preview_from_asset(
        args.asset_top_candidates, fallback_top_candidates, results_dir, args.top_n
    )
    enrich_fields, enrich_rows, enrich_message = preview_from_asset(
        args.asset_top_enriched_gene_sets, fallback_top_enrichment, results_dir, args.top_n
    )
    provenance_fields, provenance_rows = compact_provenance_rows(args.provenance)
    parameter_fields, parameter_rows = compact_parameter_rows(args.parameters)
    warning_fields, warning_rows = read_table(args.asset_warning_summary)

    markdown_body = build_markdown(
        profile,
        sections,
        missing_rows,
        release_rows,
        release_summary_rows,
        candidate_fields,
        candidate_rows,
        candidate_message,
        enrich_fields,
        enrich_rows,
        enrich_message,
        provenance_fields,
        provenance_rows,
        parameter_fields,
        parameter_rows,
        warning_fields,
        warning_rows,
        results_dir,
    )
    html_body = build_html(
        profile,
        sections,
        missing_rows,
        release_rows,
        release_summary_rows,
        candidate_fields,
        candidate_rows,
        candidate_message,
        enrich_fields,
        enrich_rows,
        enrich_message,
        provenance_fields,
        provenance_rows,
        parameter_fields,
        parameter_rows,
        warning_fields,
        warning_rows,
        results_dir,
    )

    copy_css(template_dir, output_dir)
    html_template = load_template(
        template_dir / "came_report_template.html",
        "<!doctype html>\n<html lang=\"en\"><head><meta charset=\"utf-8\"><title>$title</title><link rel=\"stylesheet\" href=\"came_report.css\"></head><body>\n$body\n</body></html>\n",
    )
    md_template = load_template(template_dir / "came_report_template.md", "$body")
    html_report = html_template.safe_substitute(title="CAME Final Report", css_path="came_report.css", body=html_body)
    markdown = md_template.safe_substitute(title="CAME Final Report", body=markdown_body)

    write_file(output_dir / "came_final_report.md", markdown)
    write_file(output_dir / "came_final_report.html", html_report)
    print(f"CAME final report rendered: {output_dir / 'came_final_report.html'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
