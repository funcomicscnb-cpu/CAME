# Final Report, Assets, And Provenance

CAME creates a polished final report for a run. It is a reporting and packaging workflow only: it consumes existing outputs, records what is present, warns about missing upstream files, captures run provenance, creates compact report assets, renders HTML and Markdown reports, and runs release-readiness checks.

It does not perform new biological analyses, infer orthology, infer regulatory-element-to-gene links, run online enrichment, or convert coordinates.

For complete v0.1 execution, prefer `--run_stage all`; it runs upstream stages, then invokes final reporting and writes an all-run summary.

## Command

```bash
nextflow run . \
  --run_stage final_report \
  --study_profile profiles/generic/study_profile.yaml \
  --outdir results
```

`--study_profile` is required so the report can identify the study profile. Upstream outputs are discovered under `--outdir`, which defaults to `results`.

End-to-end mode:

```bash
nextflow run . -resume \
  --run_stage all \
  --study_profile profiles/generic/study_profile.yaml \
  --phenotype_samplesheet assets/example_samplesheets/phenotype_samplesheet.csv \
  --omics_samplesheet assets/example_samplesheets/omics_samplesheet.csv \
  --species_traits assets/example_samplesheets/species_traits.tsv \
  --reference_manifest assets/example_samplesheets/reference_manifest.tsv \
  --phylogeny_manifest assets/example_samplesheets/phylogeny_manifest.tsv \
  --study_design assets/example_samplesheets/study_design.yaml \
  --orthologous_genes assets/example_samplesheets/orthologous_genes.tsv \
  --orthologous_res assets/example_samplesheets/orthologous_res.tsv \
  --re_to_gene_links assets/example_samplesheets/re_to_gene_links.tsv \
  --gene_annotations assets/example_samplesheets/gene_annotations.tsv \
  --gene_sets assets/example_samplesheets/gene_sets.tsv \
  --candidate_scoring_config assets/example_samplesheets/candidate_scoring_config.tsv \
  --omics_stub true \
  --omics_types rnaseq,atacseq \
  --outdir results
```

## Output Manifest

Final reporting scans common CAME output locations such as `validation/`, `phenotype/`, `phylo/`, `omics/`, `differential_omics/`, `orthology/`, `gra/`, `integration/`, `candidates/`, and `interpretation/`.

It writes:

- `results/final/manifest/came_outputs_manifest.tsv`
- `results/final/manifest/came_stage_completion_summary.tsv`
- `results/final/manifest/came_missing_outputs.tsv`

Files under `results/final/` are excluded from collection to avoid self-referential manifests. Missing expected upstream files are `WARNING` records and do not fail final reporting.

## Provenance And Assets

Final reporting writes:

- `results/final/provenance/came_run_provenance.tsv`
- `results/final/provenance/came_parameters_snapshot.tsv`
- `results/final/assets/stage_completion_summary.tsv`
- `results/final/assets/top_candidates.tsv`
- `results/final/assets/top_enriched_gene_sets.tsv`
- `results/final/assets/warning_summary.tsv`
- `results/final/assets/report_asset_manifest.tsv`

Provenance captures the CAME version, git commit and dirty status when available, Nextflow/Python/R versions, selected dependency statuses from `bin/print_versions.py`, outdir, timestamp, and a compact parameter snapshot. Missing git metadata, tools, or parameter snapshots produce `WARNING` rows instead of errors.

Asset tables are capped summaries for the report. Optional missing candidate or enrichment tables are marked `missing_optional` and do not stop rendering.

## Report Sections

The final report writes:

- `results/final/report/came_final_report.html`
- `results/final/report/came_final_report.md`
- `results/final/report/came_report.css`

Sections include study profile, status legend, run provenance, parameters, stage completion, stage summaries, release checks, top candidates, top enriched gene sets, warnings, key output links, and limitations. Large tables are linked instead of embedded. Output links are relative to `results/final/report/`.

Stage status labels mean:

- `completed`: expected compact outputs were present with no report-level warning counts.
- `warning`: expected outputs are partial or warning records were found.
- `missing_optional`: optional or upstream outputs were unavailable; report generation continued.
- `failed/error`: an error record was found and should be reviewed.

## Release Checks

Release checks write:

- `results/final/release_checks/came_release_checks.tsv`
- `results/final/release_checks/came_release_summary.tsv`
- `results/final/release_checks/came_release_status.txt`

Release `WARNING` records do not fail the workflow. Release `ERROR` records fail the Nextflow stage after report, provenance, assets, and check outputs have been written.

## Comparability Mode

The final report includes a "Comparability Mode" section immediately above the CEEG Contract
Consumption section. It declares whether the current run treats cross-condition or
cross-system comparability as assumed from experimental design (`design_assumed`, the default),
as informed by CEEG R2/R3 contract artifacts (`ceeg_contract_checked`), or as informed by
CEEG R4 comparability evidence artifacts (`ceeg_comparability_evidence_consumed`).

- `design_assumed`: the report states that no CEEG R2/R3 or R4 artifacts were consumed and
  that comparability is assumed by the supplied experimental design.
- `ceeg_contract_checked`: the report states that CEEG R2/R3 contract artifacts were consumed
  and explicitly notes that R2/R3 status is **not** R4 comparability validation and **not**
  R5 admissibility validation, and that R2/R3 contract artifacts do not substitute for R4
  comparability-evidence reporting.
- `ceeg_comparability_evidence_consumed`: the report states that CEEG R4 comparability evidence
  artifacts were consumed (CAME-I3) and explicitly notes that R4 reports structured evidence
  state under a bound analysis context, that it does not validate biological comparability as
  a verdict, does not establish R5 admissibility, and does not alter CAME analysis outputs or
  candidate rankings.

The mode is set by `--comparability_mode`. CAME's parameter validation rejects mode/input
combinations that are inconsistent (e.g. `ceeg_contract_checked` without supplied R2/R3
inputs, `ceeg_contract_checked` with supplied R4 inputs, or
`ceeg_comparability_evidence_consumed` without `--ceeg_r4_comparability_dir`). The
final-report renderer additionally cross-checks the declared mode against the R2/R3 contract
rows and R4 comparability rows actually present in `results/ceeg_compatibility/`, so a stale
results tree cannot be re-rendered with a contradictory mode. The renderer uses a centralized
(mode, R2/R3 rows present, R4 rows present) truth table and emits an error message that names
the declared mode, which rows were found or missing, the path of the relevant summary file,
and the corrective action. See [comparability_modes.md](comparability_modes.md) for the full
vocabulary.

## CEEG Contract Consumption

When CAME-I0 has been run (`--run_stage ceeg_compatibility`), the final report includes a
compact "CEEG Contract Consumption" section between Stage Summaries and Release Checks.

This section reports:

- R1 bundle scaffold status (yes/unknown);
- R2 overlay consumed: yes/no, with validator name, version, status, and exit code;
- R3 mapping audit consumed: yes/no, with validator name, version, status, and exit code;
- mapping counts (total features, mapped, ambiguous, failed) when R3 is consumed;
- CEEG adapter warnings;
- anti-overclaim notes (always present).

**When CEEG outputs are absent or header-only:**

If `results/ceeg_compatibility/` is absent, or if CAME-I0 was run without R2/R3 artifact
directories (producing header-only outputs), the section renders:

```
No CEEG R2 overlay or R3 mapping audit artifacts were supplied.
This is not a contract-validation failure.
```

This is not reported as an error, warning, or missing-data condition.

**Fatal and invalid CEEG statuses:**

Fatal (exit_code=2) and invalid (exit_code=1) CEEG statuses are displayed as recorded.
The final-report stage itself exits 0 regardless of CEEG validator exit codes in consumed
artifacts. Final reporting is a renderer, not a validator gate.

**Forbidden fields:**

The CEEG Contract Consumption section does not report: conservation scores, functional
equivalence, biological absence, biological comparability scores, admissibility status,
candidate scores, or any causal or statistical claims.

See [ceeg_invariants.md](ceeg_invariants.md) for the CEEG/CAME semantic-invariants statement
and [ceeg_compatibility.md](ceeg_compatibility.md) for CEEG artifact details.

## CEEG R4 Comparability Evidence

When CAME-I3 has been run with `--ceeg_r4_comparability_dir <dir>` and
`--comparability_mode ceeg_comparability_evidence_consumed`, the final report includes a
"CEEG R4 Comparability Evidence" section immediately after the CEEG Contract Consumption
section. The section is hidden when no R4 rows are present.

Fields are grouped into five subsections for readability. Markdown and HTML are
string-by-string parallel:

1. **Validator metadata** — R4 validator name, version, validation mode, created-at
   timestamp, manifest exit code.
2. **Context** — model ID, context ID, comparison count, comparison ID, left/right system
   IDs, entity scope.
3. **Evidence state** — manifest status, comparability status, status basis.
4. **Evidence counts** — supporting, weakening, mixed, unresolved, ambiguity, unknown,
   unknown-unmappable, and absent counts. These counts are preserved verbatim from the R4
   summary; `unknown`, `unknown_unmappable`, and `absent` are not collapsed.
5. **Limitations** — limitations count, primary limitation, and the top limitation rows
   (limit 10) sorted by severity then limitation_type.

The section ends with the verbatim anti-overclaim note: *"R4 reports structured
evidence-state status under a bound analysis context. It does not validate biological
comparability as a verdict, does not establish R5 admissibility, and does not alter CAME
analysis outputs or candidate rankings."*

When the R4 manifest reports `contract_error` (exit code 1 or 2), the section renders the
CAME-side diagnostic row produced by `summarize_ceeg_r4_comparability_artifacts.py`. The
diagnostic row exposes the manifest exit code so the user can see the failure even when
the upstream `comparability_summary.tsv` is empty or absent.

The R4 section never renders verdict phrasing such as "validated comparability",
"biologically comparable", "biologically incomparable", "admissible candidate",
"conserved candidate", "equivalent system", or "absent because unmappable".

## Limitations

- Final reporting summarizes available outputs and does not prove missing upstream stages were unnecessary.
- Stage completion is based on expected compact files, warning tables, and release records, not full biological validation.
- Functional enrichment remains simple offline overrepresentation testing.
- Background definition depends on supplied annotation and gene-set files.
- Coordinates are exported as supplied; no lift-over or coordinate conversion is performed.
- Orthology tables and regulatory-element-to-gene links are consumed, not inferred.

See [report_customization.md](report_customization.md) for template and CSS customization.
