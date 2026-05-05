# Advanced Statistics

`advanced_statistics` is an optional workflow for comparing alternative statistical and phylogenetic model interfaces. It is not part of the default v0.1 `--run_stage all` path and does not replace phylogenetic/hypothesis modeling or phenotype-omics integration.

It is a compatibility interface, not a production replacement for the established v0.1 statistical workflows.

The workflow is phenotype-agnostic. Models are declared in a tabular config, and core logic does not hardcode example profile biology.

## Command

```bash
nextflow run . \
  --run_stage advanced_statistics \
  --advanced_model_config assets/example_samplesheets/advanced_model_config.tsv \
  --advanced_statistics_stub true
```

`--advanced_statistics_stub true` is the default. In stub mode, CAME validates inputs, resolves available upstream tables, writes manifests and warnings, and skips model fitting. This prevents optional advanced analyses from changing default v0.1 behavior.

Set `--advanced_statistics_stub false` only when you want to run currently supported lightweight models against available model-ready tables.

## Config Format

`assets/example_samplesheets/advanced_model_config.tsv` contains one row per requested model.

Required columns:

- `model_id`
- `analysis_target`
- `model_family`
- `enabled`

Optional columns:

- `response`
- `predictors`
- `covariates`
- `phylogenetic_model`
- `min_species`
- `notes`

Supported `enabled` values include true/false-style values such as `true`, `false`, `yes`, `no`, `1`, and `0`.

Recognized model families:

- `lm`
- `pgls_brownian`
- `pgls_pagel_lambda`
- `ou_placeholder`
- `robust_lm_placeholder`
- `multivariate_placeholder`
- `permutation_placeholder`

Placeholder families intentionally emit warning rows and no synthetic statistical results.

## Inputs

The workflow discovers upstream outputs under `--outdir` when present:

- CAME phenotype contrasts
- CAME hypothesis model tables and hypothesis results
- CAME phenotype-omics model tables
- species traits
- phylogeny manifests

Configured targets that are absent are marked `UNAVAILABLE` in:

- `results/advanced_statistics/input/advanced_model_manifest.tsv`
- `results/advanced_statistics/input/advanced_model_warnings.tsv`

Unavailable targets are warnings, not hard failures, unless the config itself is invalid.

## Outputs

Input preparation:

- `results/advanced_statistics/input/advanced_model_manifest.tsv`
- `results/advanced_statistics/input/advanced_model_warnings.tsv`

Model comparison:

- `results/advanced_statistics/models/model_comparison_results.tsv`
- `results/advanced_statistics/models/model_comparison_warnings.tsv`

Robustness checks:

- `results/advanced_statistics/robustness/robustness_check_results.tsv`
- `results/advanced_statistics/robustness/robustness_warnings.tsv`

Summary:

- `results/advanced_statistics/summary/advanced_statistics_summary.tsv`
- `results/advanced_statistics/summary/advanced_statistics_outputs_manifest.tsv`

## Interpretation Limits

Small species counts can make comparative models unstable. The workflow reports small-n warnings and does not treat placeholder methods as completed analyses.

In non-stub mode, currently supported fitting is limited to ordinary LM and PGLS variants when model-ready data, tree information, and R dependencies are available. AIC deltas are reported only when fitted models are comparable on the same response, predictors, term, and species count.

Species are not silently dropped. Missing model values, duplicate species rows, and tree-tip mismatches are reported as warnings or cause a model row to be skipped.

## Possible Extensions

Later versions may add production implementations for OU models, robust regression, multivariate response models, permutation tests, and richer target-specific filtering. These should remain optional and must not alter default outputs.
