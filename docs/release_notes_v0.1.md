# CAME v0.1 Release Notes

CAME v0.1 prepares the repository for a public release of the phenotype-agnostic Nextflow DSL2 framework. The release focuses on validated interfaces, stub-mode orchestration, final reporting, release packaging, real-mode operational contracts, and documentation. Its release label is **advanced beta for expert users**.

## Scope

The v0.1 release includes implemented validation, phenotype processing, phylogenetic/hypothesis modeling, bulk RNA-seq/ATAC-seq interfaces, differential omics, orthology projection, GRA analysis, phenotype-omics integration, candidate prioritization, functional interpretation, final reporting, release checks, and optional interfaces.

`--run_stage all` remains the v0.1 core end-to-end path. It warns that `reference_prepare`, `reference_quality`, `wgs_variants`, `coordinate_projection`, `orthology_reference_prepare`, `re_to_gene_inference`, `advanced_statistics`, and `ceeg_compatibility` are excluded and must be run explicitly when needed.

## Optional Interfaces

The following commands are optional interfaces and are not production implementations of their analysis areas:

- `reference_prepare`: WGS-backed reference preparation interface.
- `coordinate_projection`: coordinate lift-over and regulatory-element orthology interface.
- `orthology_reference_prepare`: external reciprocal-best orthology reference-bundle orchestration and validation interface.
- `re_to_gene_inference`: regulatory-element-to-gene inference interface.
- `advanced_statistics`: optional advanced statistics and lightweight model-comparison interface.
- `ceeg_compatibility`: optional CEEG contract artifact consumption interface; requires `--ceeg_model_bundle` and optionally consumes externally generated `--ceeg_r2_overlay_dir` and `--ceeg_r3_mapping_dir` artifact directories.

Stub outputs are deterministic contract fixtures for validation and review. They should not be interpreted as production biological results.

## Skipped Work

NanoSeq and mutation profiling are intentionally skipped in v0.1. Documentation may mention mutation-rate or ultra-accurate sequencing use cases, but CAME v0.1 does not implement NanoSeq processing or mutation profiling.

## Minimal Example

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

## Expected Outputs

Key release outputs include:

- `results/all/summary/came_all_run_summary.tsv`
- `results/final/manifest/came_outputs_manifest.tsv`
- `results/final/provenance/came_run_provenance.tsv`
- `results/final/report/came_final_report.html`
- `results/final/report/came_final_report.md`
- `results/final/release_checks/release_bundle_validation.tsv`

## Testing Status

The v0.1 release gate includes the stub-mode test matrix documented in `docs/ci_and_release.md` and `docs/release_checklist.md`, plus container-backed strict execution of the committed tiny real-mode fixtures when the release image is built.

The lightweight differential-omics regression tests permit fallback; passing them does not establish successful DESeq2 fitting. Successful fitting and DESeq2 field consistency are tested separately by the strict oracle suite `tests/test_deseq2_consistency.R`, run in the locked `real-mode-ci` image with the R/DESeq2 versions from the committed Conda lock and, optionally, in the `deseq2-validation` job with the current R release (see `docs/ci_and_release.md`). These same-package comparisons and output-contract checks do not establish biological accuracy. Result rows and `differential_summary.tsv` record the method used; fallback reproduced with older local R/DESeq2 versions does not establish which method ran in CI.

## Dependencies

Stub-mode tests require Java, Nextflow, Python, and a small R package set. Real-mode RNA-seq, ATAC-seq, and WGS paths require external tools and prepared references as documented in `docs/installation.md`. Docker/Apptainer/Singularity profiles default to `ghcr.io/funcomicscnb-cpu/came:<VERSION>`.

## Licensing And Citation

CAME v0.1 is distributed under `GPL-3.0-only`. Citation metadata is provided in `CITATION.cff` with David Juan as author and `https://github.com/funcomicscnb-cpu/CAME` as the public code repository. The confirmed v0.1.0 release date is 2026-10-15.

## Known Limitations

- Stub-mode validation does not prove biological correctness.
- Real-mode production readiness depends on caller-provided data, references, and external tools.
- WGS is per-sample only in v0.1: BQSR is not applied and joint genotyping is not performed.
- ATAC consensus peaks are bedtools-merge exploratory outputs; TSS enrichment is computed only when `tss_bed` is supplied, NRF/PBC require duplicate-position complexity output, and IDR remains an explicit opt-in limitation warning.
- PGLS defaults to a six-species minimum. Three-to-five-species PGLS is exploratory only when the threshold is deliberately lowered.
- Optional interfaces are not production analysis implementations.
- NanoSeq and mutation profiling are not implemented.
- Orthology tables and regulatory-element-to-gene links are supplied inputs for the v0.1 all-run path.
- Orthogroup differential summaries average mapped-feature fields without separating `method` or `status`, so a fitted DESeq2 effect and a descriptive effect from a filtered feature can be mixed in one orthogroup row. These summaries are not orthogroup-level DESeq2 fits, and their p-values are minima, not meta-analysis.
- DESeq2 effects are unshrunk. Large fitted effects, including those of sparse features passing the low-count filter, can propagate into candidate evidence, where differential scoring uses absolute effect size without a cap.
- The strict DESeq2 fixture is adversarial: it demonstrates that fitted and descriptive effects can disagree in sign, not how often this occurs in real studies.
