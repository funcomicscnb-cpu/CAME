# Profile Authoring

CAME study profiles define the study-specific interpretation layer without changing core workflow behavior. A profile should describe phenotype components, contrasts, hypothesis variables, covariates, and report labels in data, not in Nextflow logic or core scripts.

The bundled profiles are templates. They validate syntax and wiring, but they are not biologically validated analyses.

## Anatomy Of A Profile

A study profile lives at `profiles/<profile_id>/study_profile.yaml` and uses these required sections:

```yaml
study:
  profile_id: my_profile
  name: My profile
  description: Short description.
  version: "1.0"

phenotype_index:
  name: my_response_index
  formula: "(component_a - component_b) / component_c"
  components:
    - component_a
    - component_b
    - component_c
  aggregation: mean_by_species_condition_timepoint
  contrasts:
    - name: baseline_vs_response
      type: baseline_vs_response
      baseline_condition: baseline
      response_condition: response
      baseline_timepoint: t0
      response_timepoint: t1

hypotheses:
  - name: trait_association
    model_type: phylogenetic_regression
    response: external_trait_alpha
    predictors:
      - phenotype_index_response
    covariates: []
    phylogenetic: true
    stratify_by: []

reporting:
  phenotype_label: Response index
  condition_label: Condition
  response_label: Response
  external_trait_label: External trait
  candidate_mechanism_label: Candidate mechanism
```

Common optional sections are `derived_variables`, `external_traits`, `covariates`, `mechanistic_proxies`, `condition_ranking`, `feature_association_targets`, and `notes`.

## Phenotype Components

List every phenotype measurement required by the index under `phenotype_index.components`. Each component must appear in phenotype metadata as either a `measurement` value or, for compatibility, an `assay` value.

Keep component names stable, ASCII, and formula-safe: start with a letter or underscore and use only letters, numbers, and underscores.

## Safe Formula Syntax

Profile formulas support:

- Component names declared in `phenotype_index.components`
- Numeric constants
- Parentheses
- Unary `+` and `-`
- `+`, `-`, `*`, and `/`
- `abs()`, `min()`, and `max()` with positional arguments

Unsupported syntax includes exponentiation, attribute access, imports, strings, comparisons, subscripts, keyword arguments, and arbitrary function calls. CAME parses formulas through a restricted AST and never evaluates raw profile text as Python code.

## Contrasts

Use contrast labels that exactly match `condition` and `timepoint` values in the phenotype samplesheet.

```yaml
contrasts:
  - name: challenge_response
    type: baseline_vs_response
    baseline_condition: control
    response_condition: challenge
    baseline_timepoint: 0h
    response_timepoint: 24h
```

Supported contrast types are `baseline_vs_response`, `condition_contrast`, `timepoint_contrast`, and `treated_vs_control`. The contrast direction is response minus baseline.

## Derived Variables

Declare variables that downstream workflows are expected to create before hypotheses reference them:

```yaml
derived_variables:
  - phenotype_index
  - phenotype_index_response
  - component_a_response
  - residual_external_trait_after_covariate_alpha
```

Component response names follow the existing convention `<component>_response`. Composite component response names can be formed from declared components, such as `component_a_component_b_response`.

## Hypotheses

A direct hypothesis relates one response to one or more predictors:

```yaml
- name: direct_trait_association
  model_type: phylogenetic_regression
  response: external_trait_alpha
  predictors:
    - phenotype_index_response
  covariates: []
  phylogenetic: true
  stratify_by: []
```

A residual hypothesis uses `model_type: residual_regression` and at least one covariate:

```yaml
- name: adjusted_trait_association
  model_type: residual_regression
  response: residual_external_trait_alpha_after_covariate_alpha
  predictors:
    - phenotype_index_response
  covariates:
    - covariate_alpha
  phylogenetic: true
  stratify_by: []
```

Responses, predictors, covariates, and strata must be resolvable from phenotype metadata, species-trait metadata, profile declarations, phenotype components, or `derived_variables`.

## Common Validation Errors

| error | fix |
| --- | --- |
| Missing required top-level section | Add `study`, `phenotype_index`, `hypotheses`, or `reporting`. |
| Formula variable is not listed in components | Add the variable to `components` or correct the formula. |
| Profile component is absent from phenotype metadata | Add rows whose `measurement` or `assay` matches the component. |
| Unsafe or unsupported formula element | Use only safe arithmetic and allowed functions. |
| Contrast condition not found | Align contrast labels with phenotype `condition` values. |
| Contrast timepoint not found | Align contrast labels with phenotype `timepoint` values. |
| Variable is not resolvable or declared as derived | Add a declaration, species-trait row, phenotype metadata value, or derived variable. |

## Testing A New Profile

Run the validator directly:

```bash
python3 bin/validate_study_profile.py \
  --study_profile profiles/my_profile/study_profile.yaml \
  --phenotype_samplesheet path/to/phenotype_samplesheet.csv \
  --species_traits path/to/species_traits.tsv \
  --output results/validation/my_profile_validation.tsv
```

Then run the phenotype processing checks on representative metadata:

```bash
python3 bin/phenotype_normalize.py \
  --input path/to/phenotype_samplesheet.csv \
  --output /tmp/came_profile_norm.tsv \
  --summary /tmp/came_profile_norm_summary.tsv

python3 bin/calc_phenotype_index.py \
  --input /tmp/came_profile_norm.tsv \
  --study_profile profiles/my_profile/study_profile.yaml \
  --sample_output /tmp/came_profile_index_by_sample.tsv \
  --group_output /tmp/came_profile_index_by_group.tsv

python3 bin/phenotype_contrasts.py \
  --phenotype_table /tmp/came_profile_norm.tsv \
  --study_profile profiles/my_profile/study_profile.yaml \
  --index_by_group /tmp/came_profile_index_by_group.tsv \
  --index_output /tmp/came_profile_index_contrasts.tsv \
  --component_output /tmp/came_profile_component_contrasts.tsv
```

Before sharing a profile, also run:

```bash
bash tests/test_profile_examples.sh
bash tests/test_study_profile_validation.sh
bash tests/test_phenotype_processing.sh
```

## Keeping Biology Out Of Core Logic

Do not add profile-specific terms or assumptions to `bin/`, `workflows/`, `subworkflows/`, `modules/`, `main.nf`, `nextflow.config`, or `lib/`. Put study-specific language in profile YAML, profile READMEs, docs, tests, example metadata, or generated outputs.

If a profile seems to require a new parser rule, new contrast behavior, or new model semantics, treat that as a core design change and review alternatives before implementation.
