# CAME v0.1 Release Notes

CAME v0.1 prepares the repository for a public release of the phenotype-agnostic Nextflow DSL2 framework. The release focuses on validated interfaces, stub-mode orchestration, final reporting, release packaging, and documentation.

## Scope

The v0.1 release includes implemented validation, phenotype processing, phylogenetic/hypothesis modeling, bulk RNA-seq/ATAC-seq interfaces, differential omics, orthology projection, GRA analysis, phenotype-omics integration, candidate prioritization, functional interpretation, final reporting, release checks, and optional future-facing scaffold stages through Stage 20.

`--run_stage all` remains the v0.1 stub-oriented end-to-end path. It does not automatically include optional scaffold stages unless those stages were already explicitly part of the all-run design.

## Optional Scaffolds

The following stages are optional scaffolds and are not production implementations of their future analysis areas:

- `reference_prepare`: WGS-backed reference preparation scaffold.
- `coordinate_projection`: coordinate lift-over and regulatory-element orthology scaffold.
- `re_to_gene_inference`: regulatory-element-to-gene inference scaffold.
- `advanced_statistics`: future-facing advanced statistics scaffold and lightweight model-comparison interface.

Scaffold outputs are deterministic contract fixtures or limited interface outputs for validation and review. They should not be interpreted as production biological results.

## Skipped Work

NanoSeq and mutation profiling are intentionally skipped in v0.1. Documentation may mention future mutation-rate or ultra-accurate sequencing use cases, but CAME v0.1 does not implement NanoSeq processing or mutation profiling.

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

The v0.1 release gate is the stub-mode test matrix documented in `docs/ci_and_release.md` and `docs/release_checklist.md`. Real-mode smoke checks are optional and inventory-oriented unless run in an environment with all required tools and reference assets.

## Dependencies

Stub-mode tests require Java, Nextflow, Python, and a small R package set. Real-mode RNA-seq and ATAC-seq paths require external tools and prepared references as documented in `docs/installation.md`.

## Licensing And Citation

CAME v0.1 is distributed under `GPL-3.0-only`. Citation metadata is provided in `CITATION.cff`; TODO placeholders must be resolved before a final public tag.

## Known Limitations

- Stub-mode validation does not prove biological correctness.
- Real-mode production readiness depends on caller-provided data, references, and external tools.
- Optional scaffold stages are not production analysis implementations.
- NanoSeq and mutation profiling are not implemented.
- Orthology tables and regulatory-element-to-gene links are supplied inputs for the v0.1 all-run path.
