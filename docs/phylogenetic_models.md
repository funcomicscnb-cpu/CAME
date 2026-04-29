# CAME Stage 4 Phylogenetic Models

Stage 4 adds comparative modeling and profile-defined hypothesis tests on top of Stage 3 phenotype-response outputs. The stage remains phenotype-agnostic: DDR/RoR is only an example profile, and core scripts resolve variables from profile declarations and metadata.

## Workflow

```bash
nextflow run . \
  --run_stage phylo_hypothesis \
  --study_profile profiles/ddr_ror/study_profile.yaml \
  --phenotype_samplesheet assets/example_samplesheets/phenotype_samplesheet.csv \
  --species_traits assets/example_samplesheets/species_traits.tsv \
  --phylogeny_manifest assets/example_samplesheets/phylogeny_manifest.tsv
```

If full Stage 1 inputs are supplied, the standard metadata validator runs. With the shorter Stage 4 command, CAME runs a Stage 4 metadata check for phenotype species, species traits, and phylogeny labels. The workflow then validates the study profile, runs phenotype response processing, prepares model-ready tables, fits generic phylogenetic models, and runs profile hypotheses.

## Model-Ready Inputs

`bin/prepare_phylo_inputs.py` consumes:

- `results/phenotype/index/phenotype_index_by_group.tsv`
- `results/phenotype/contrasts/phenotype_index_contrasts.tsv`
- `results/phenotype/contrasts/component_trait_contrasts.tsv`
- `--species_traits`
- `--phylogeny_manifest`
- `--study_profile`

It writes:

- `results/phylo/input/species_traits_wide.tsv`
- `results/phylo/input/phenotype_model_table.tsv`
- `results/phylo/input/hypothesis_model_table.tsv`

Long-format species traits are pivoted to one row per species. Trait values become variable columns, and unit/source/confidence metadata are preserved as `<variable>_unit`, `<variable>_source`, and `<variable>_confidence`.

Phenotype contrast variables use `response_metric: difference` by default. Profiles may set `response_metric` to `difference`, `fold_change`, or `log2_fold_change`. `phenotype_index_response` maps to the selected metric from phenotype index contrasts. Component variables such as `viability_response` map to component contrast rows. Composite names such as `apoptosis_senescence_response` are resolved by summing declared component responses when the name can be decomposed into profile components.

## Models

`bin/run_phylo_model.R` supports:

- `lm`: ordinary linear model.
- `pgls_brownian`: PGLS with Brownian correlation using `ape` and `nlme`.
- `pgls_pagel_lambda`: Pagel lambda PGLS when supported by installed `ape`/`nlme`.
- `phylo_anova`: validated placeholder that writes a warning because full phylo-ANOVA is deferred.

Phylogenetic models read Newick trees from `phylogeny_manifest`, match tips to species `phylogeny_label`, prune extra tree tips, report species absent from the tree, warn when PGLS has only 3-5 matched species, and fail if fewer than 3 species remain. Missing `ape` or `nlme` produces a clear dependency error for phylogenetic models. `lm` models do not require phylogenetic packages.

Generic model outputs:

- `results/phylo/models/model_results.tsv`
- `results/phylo/models/model_diagnostics.tsv`
- `results/phylo/models/model_residuals.tsv`
- `results/phylo/models/model_warnings.tsv`

## Hypothesis Syntax

Hypotheses are read from `study_profile.yaml`. Supported forms are:

```yaml
hypotheses:
  - name: direct_example
    model_type: direct_model
    response: external_trait_alpha
    predictors:
      - phenotype_index_response
    covariates: []
    phylogenetic: true

  - name: residual_example
    model_type: residual_model
    response: residual_external_trait_after_covariate
    predictors:
      - phenotype_index_response
    covariates:
      - covariate_alpha
    phylogenetic: true

  - name: multivariable_example
    model_type: multivariable_model
    response: external_trait_alpha
    predictors:
      - phenotype_index_response
    covariates:
      - covariate_alpha
    phylogenetic: false
```

Existing aliases such as `regression`, `phylogenetic_regression`, and `residual_regression` are supported for current profiles. If `phylogenetic: true`, CAME runs `lm` and `pgls_brownian` unless `model_types` or `phylogenetic_model` is declared. For residual hypotheses with `phylogenetic: true`, both residualization and the final residual association are phylogeny-aware, with separate `lm` and PGLS residuals/results.

Hypothesis outputs:

- `results/hypotheses/hypothesis_test_summary.tsv`
- `results/hypotheses/hypothesis_model_results.tsv`
- `results/hypotheses/hypothesis_residuals.tsv`
- `results/hypotheses/hypothesis_warnings.tsv`

## Limitations

Small species counts can produce unstable estimates, singular fits, or dependency on exact tree/species matching. CAME fails phylogenetic models with fewer than 3 matched species, but more species are recommended for interpretable comparative modeling. The current stage does not implement RNA-seq, ATAC-seq, GRA, omics integration, or full phylo-ANOVA.
