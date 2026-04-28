# Stage 13: End-to-End Run

Stage 13 adds `--run_stage all` for a complete CAME v0.1 stub or real run. It orchestrates existing stages in dependency order and does not add biological analyses.

## Command

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

`--study_design` is required because Stage 1 metadata validation requires it. `-resume` is recommended for reruns.

## Execution Order

1. metadata and study profile validation
2. phenotype response
3. phylogenetic and hypothesis modeling
4. bulk omics
5. differential omics
6. orthology projection
7. GRA analysis
8. phenotype-omics integration
9. candidate prioritization
10. functional interpretation
11. final report and release checks

## Outputs

The usual stage outputs are written under `--outdir`. Stage 13 also writes:

- `results/all/stage_status/<stage>_status.tsv`
- `results/all/summary/came_all_run_summary.tsv`
- `results/all/summary/came_all_outputs_manifest.tsv`
- `results/all/summary/came_all_run_status.txt`

The final report remains under:

- `results/final/report/came_final_report.html`
- `results/final/report/came_final_report.md`

## Reuse Behavior

`--resume_completed_stages` defaults to `true`, but Stage 13 does not skip complete stages at compile time. All stages are scheduled so partial outputs are not silently accepted. Use Nextflow `-resume` to reuse completed process work.

The stage status files report structural completeness only: expected files are present and non-empty. They do not validate input freshness or content hashes.

In `--omics_stub true` all-run mode, the example omics sample sheet is adapted after bulk omics by duplicating synthetic count columns into the first supported contrast labels from the study profile. This keeps the bundled single-timepoint omics example usable for downstream orchestration tests. Real mode does not perform this adaptation; real omics metadata must contain executable baseline/response groups.

## Real-Mode Notes

Set `--omics_stub false` only when reference assets, FASTQ files, and external tools are available. Real RNA-seq and ATAC-seq execution requires the tools declared in the environment files. PGLS model types require the R packages `ape` and `nlme`.

## Troubleshooting

- `MISSING` means no required outputs for that stage were found under `--outdir`.
- `PARTIAL` means at least one expected output is present but one or more required outputs are missing; rerun the workflow and inspect upstream logs.
- If release checks fail, inspect `results/final/release_checks/came_release_checks.tsv`.
- If the all-run assertion fails, inspect `results/all/summary/came_all_run_summary.tsv` and the per-stage files in `results/all/stage_status/`.
