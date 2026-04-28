# CAME v0.1 Release Checklist

This checklist describes the expected release state for CAME v0.1. Final reporting automates a subset of these checks and records the result in `results/final/release_checks/`.

## Release Criteria

- GPL-3.0-only `LICENSE`, `CITATION.cff`, `VERSION`, `CHANGELOG.md`, release notes, and versioning policy are present.
- GitHub issue templates, pull request template, CI workflow, and Dependabot configuration are present.
- Core regression tests and profile example tests pass.
- Stage 16 final reporting passes with `--run_stage final_report`.
- Stage 13 end-to-end orchestration passes with `--run_stage all`.
- Stage 22 release metadata, CI, installation, version reporting, and release bundle validation assets are present.
- The final output manifest, provenance tables, report assets, HTML report, Markdown report, CSS, release checks, and release summary are produced.
- The all-run summary and per-stage status TSVs are produced.
- Missing optional upstream outputs are warnings, not workflow failures.
- Core logic remains phenotype-agnostic; study-specific terms are limited to profiles, docs, tests, examples, and generated results.
- No obvious local absolute paths are present in tracked pipeline logic.
- Environment files are present and describe Python, Nextflow, R, and external tool dependencies.
- NanoSeq and mutation profiling are not described as implemented.
- Optional scaffold stages are documented as optional and scaffold-only, not production biological results.

## Test Commands

```bash
bash tests/test_final_report.sh
bash tests/test_report_polish.sh
bash tests/test_end_to_end_orchestration.sh
bash tests/test_functional_interpretation.sh
bash tests/test_candidate_prioritization.sh
bash tests/test_phenotype_omics_integration.sh
bash tests/test_gra_analysis.sh
bash tests/test_orthology_projection.sh
bash tests/test_differential_omics.sh
bash tests/test_bulk_omics.sh
bash tests/test_phylo_hypothesis.sh
bash tests/test_phenotype_processing.sh
bash tests/test_profile_examples.sh
bash tests/test_study_profile_validation.sh
bash tests/test_metadata_validation.sh
python3 -m py_compile bin/*.py
Rscript -e "for (f in list.files('bin', pattern='[.]R$', full.names=TRUE)) parse(file=f)"
```

Run the final-report workflow explicitly:

```bash
nextflow run . \
  --run_stage final_report \
  --study_profile profiles/generic/study_profile.yaml \
  --outdir results
```

Run the end-to-end workflow:

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

## Dependency Checks

- Confirm `nextflow -version` satisfies `nextflow.config`.
- Confirm Python dependencies in `environment/requirements.txt` are installable.
- Confirm the Conda environment in `environment/came_environment.yml` resolves.
- Confirm R and bioinformatics tools required by earlier stages are available for the workflows being released.
- Run `python3 bin/print_versions.py` and inspect `environment/tool_versions.tsv`.
- Run `python3 bin/validate_release_bundle.py` and inspect `results/final/release_checks/release_bundle_validation.tsv`.

## Documentation Checks

- Verify all supported `--run_stage` values are documented or discoverable from `main.nf`.
- Verify Stage 16 documentation explains manifest files, provenance, report assets, report sections, release checks, warning behavior, and limitations.
- Verify [versioning.md](versioning.md) and [release_notes_v0.1.md](release_notes_v0.1.md) match `VERSION` and `CHANGELOG.md`.
- Verify known limitations are stated without implying unsupported analyses were performed.
- Verify citation placeholders are intentional and not fabricated names, dates, institutions, or repository URLs.
- Verify the GPL-3.0-only license text is complete and unmodified.

## Known Limitations

- Final reporting does not perform new biological analyses.
- Offline enrichment depends on the supplied gene annotations and gene sets.
- Orthology and regulatory-element-to-gene links are consumed as inputs.
- Coordinates are not lifted over or converted.
- Partial upstream runs produce partial final reports with warnings.
- NanoSeq and mutation profiling are skipped in v0.1.
- Optional scaffold outputs are contract fixtures or limited interface outputs, not production biological results.

## Suggested Tag Procedure

1. Run the full test command list.
2. Run `--run_stage all` on the example stub inputs.
3. Run `--run_stage final_report` on a representative results directory if final reporting needs separate validation.
4. Inspect `results/final/release_checks/came_release_checks.tsv` and resolve all `ERROR` records.
5. Inspect `results/all/summary/came_all_run_summary.tsv`.
6. Review the final HTML and Markdown reports for missing or misleading sections.
7. Resolve TODO citation/repository/release-date/copyright decisions.
8. Create a version tag only after tests, release checks, and public metadata are clean.
