# CAME Study Profiles

CAME study profiles define the study-specific interpretation layer. They describe phenotype indexes, component traits, contrasts, hypothesis variables, covariates, external evolutionary traits, and report labels without hardcoding a phenotype into the core pipeline.

The validator checks structure and resolvability. Downstream phenotype and modeling workflows consume the same profile declarations through generic code paths.

## File Layout

Profiles live under `profiles/<profile_id>/study_profile.yaml`. Bundled profiles include:

- `profiles/generic/study_profile.yaml`
- `profiles/ddr_ror/study_profile.yaml`
- `profiles/immune_response/study_profile.yaml`
- `profiles/metabolic_response/study_profile.yaml`
- `profiles/stress_tolerance/study_profile.yaml`
- `profiles/generic_test/study_profile.yaml`
- `profiles/ddr_ror_test/study_profile.yaml`

The biological profiles are templates for profile authoring and smoke testing. They are not biologically validated analyses.

## Required Sections

```yaml
study:
  profile_id:
  name:
  description:
  version:

phenotype_index:
  name:
  formula:
  components:
  aggregation:
  contrasts:

hypotheses:
  - name:
    description:
    model_type:
    response:
    predictors:
    covariates:
    phylogenetic:
    stratify_by:

reporting:
  phenotype_label:
  condition_label:
  response_label:
  external_trait_label:
  candidate_mechanism_label:
```

Optional sections include `derived_variables`, `external_traits`, `covariates`, `mechanistic_proxies`, `condition_ranking`, `feature_association_targets`, `phenotype_design`, and `notes`.
Profiles may also include optional `phenotype_indexes` and `phenotype_qc` sections.

## Formula Rules

`phenotype_index.formula` supports simple arithmetic over component names: `+`, `-`, `*`, `/`, unary signs, numbers, parentheses, and safe `abs`, `min`, and `max` calls.

The validator rejects exponentiation, attribute access, string constants, imports, and other executable syntax. It never evaluates the formula. Every variable used in the formula must be listed in `phenotype_index.components`, and every component must appear as a `measurement` or `assay` value in the phenotype samplesheet.

## Multiple Phenotype Indexes

`phenotype_index` remains the compatibility definition consumed by existing downstream workflows. A profile can additionally define `phenotype_indexes` to calculate several indexes in one phenotype-processing run:

```yaml
phenotype_indexes:
  - name: secondary_index
    formula: "component_a + component_b"
    components: [component_a, component_b]
    aggregation: mean
    contrasts:
      - name: baseline_vs_response
        type: baseline_vs_response
        baseline_condition: baseline
        response_condition: response
        baseline_timepoint: t0
        response_timepoint: t1
  - name: primary_index
    primary: true
    formula: "(component_a - component_b) / component_c"
    components: [component_a, component_b, component_c]
    aggregation: mean
    contrasts:
      - name: baseline_vs_response
        type: baseline_vs_response
        baseline_condition: baseline
        response_condition: response
        baseline_timepoint: t0
        response_timepoint: t1
```

If `phenotype_indexes` is present, at most one entry may set `primary: true`. If no primary is marked, the first entry is primary. The top-level `phenotype_index` must duplicate the selected primary index definition so compatibility consumers see the same formula, components, aggregation, and contrasts.

## Phenotype QC Gates

Optional `phenotype_qc` settings can promote selected QC warnings to errors:

```yaml
phenotype_qc:
  min_replicates_per_group: 2
  fail_on_missing_components: false
  fail_on_sparse_groups: false
  fail_on_unit_inconsistency: false
```

## Phenotype Design

`phenotype_design` can configure replicate identity, group aggregation, and normalization scope:

```yaml
phenotype_design:
  replicate_key:
    - species
    - individual_id
    - replicate_id
    - condition
    - timepoint
    - batch
  group_key:
    - species
    - condition
    - timepoint
    - tissue
  normalization_scope:
    - assay
```

All keys are optional. Defaults are `species`, `individual_id`, `replicate_id`, `condition`, `timepoint` for replicate identity; `species`, `condition`, `timepoint` for group aggregation; and `assay`, `measurement` for normalization scope. Custom fields must exist as phenotype samplesheet columns. `group_key` must include `species`, and every `group_key` field must also be present in `replicate_key`.

`group_key` controls group-level phenotype index aggregation, sparse-group QC checks, and contrast stratification. For example, adding `tissue` makes baseline/response contrasts pair only within the same species and tissue. Contrast generation also requires `group_key` to include the contrast axes it compares, such as `condition` and `timepoint` for `baseline_vs_response`.

## Derived Variables

Downstream workflows produce variables such as:

```yaml
derived_variables:
  - phenotype_index
  - phenotype_index_response
  - component_response
```

The validator allows hypotheses to reference declared derived variables. Downstream workflows populate supported derived variables through generic profile-driven code paths.

## Contrasts

Contrasts define which phenotype metadata values downstream workflows will compare. Supported contrast types are:

- `baseline_vs_response`
- `treated_vs_control`
- `timepoint_contrast`
- `condition_contrast`

Condition fields such as `baseline_condition`, `response_condition`, `control_condition`, and `treated_condition` must match phenotype samplesheet `condition` values when present. Timepoint fields such as `baseline_timepoint`, `response_timepoint`, `from_timepoint`, and `to_timepoint` must match phenotype samplesheet `timepoint` values when present.

## Hypotheses

Each hypothesis must include `name`, `model_type`, `response`, and `predictors`. Variables are resolvable if they are present in phenotype metadata, species trait metadata, profile declarations, phenotype index components, or `derived_variables`.

`phylogenetic` must be boolean when present. `covariates` and `stratify_by` are optional arrays of variable names.

## Generic Example

The generic profile defines:

```yaml
phenotype_index:
  name: composite_response_index
  formula: "(component_a - component_b) / component_c"
  components:
    - component_a
    - component_b
    - component_c
```

It uses abstract traits and covariates so the profile can validate the study profile mechanism without implying any biological domain.

## Template Examples

CAME includes several concrete profile templates:

| profile | purpose |
| --- | --- |
| `generic` | Abstract schema and validation template. |
| `ddr_ror` | DNA damage response and robustness-of-regulation example. |
| `immune_response` | Immune challenge response template. |
| `metabolic_response` | Metabolic challenge response template. |
| `stress_tolerance` | Environmental stress response template. |

Use `assets/example_samplesheets/profile_examples/` to validate or smoke-test the immune, metabolic, and stress templates.

## DDR/RoR Example

The DDR/RoR profile is a biological example. It defines:

```yaml
phenotype_index:
  name: DDRstate
  formula: "(viability - apoptosis - senescence) / (viability + apoptosis)"
  components:
    - viability
    - apoptosis
    - senescence
```

Example hypotheses include associations between viability response and maximum longevity, and residual cancer prevalence models adjusted for body mass or longevity. These terms live in the example profile and example documentation, not in core Nextflow logic.

## Creating a New Profile

To create a profile for a new phenotype or study system:

1. Copy the generic profile directory:
   ```bash
   cp -r profiles/generic profiles/my_study
   ```
2. Edit `profiles/my_study/study_profile.yaml`: update `study.profile_id`, `study.name`, `phenotype_index.formula`, `phenotype_index.components`, contrast definitions, hypotheses, and reporting labels.
3. Validate the profile against your phenotype and species-trait metadata:
   ```bash
   python3 bin/validate_study_profile.py \
     --study_profile profiles/my_study/study_profile.yaml \
     --phenotype_samplesheet path/to/phenotype_samplesheet.csv \
     --species_traits path/to/species_traits.tsv \
     --output results/validation/my_study_profile_report.tsv
   ```
4. Check the report for ERROR rows. Warnings do not block execution.
5. Pass the profile to any stage with `--study_profile profiles/my_study/study_profile.yaml`.

For a fuller authoring checklist, see [profile_authoring.md](profile_authoring.md).

## Validation

Run directly:

```bash
python3 bin/validate_study_profile.py \
  --study_profile profiles/ddr_ror/study_profile.yaml \
  --phenotype_samplesheet assets/example_samplesheets/phenotype_samplesheet.csv \
  --species_traits assets/example_samplesheets/species_traits.tsv \
  --output results/validation/study_profile_validation_report.tsv
```

Run with Nextflow:

```bash
nextflow run . --validate_only true \
  --study_profile profiles/ddr_ror/study_profile.yaml \
  --phenotype_samplesheet assets/example_samplesheets/phenotype_samplesheet.csv \
  --omics_samplesheet assets/example_samplesheets/omics_samplesheet.csv \
  --species_traits assets/example_samplesheets/species_traits.tsv \
  --reference_manifest assets/example_samplesheets/reference_manifest.tsv \
  --phylogeny_manifest assets/example_samplesheets/phylogeny_manifest.tsv \
  --study_design assets/example_samplesheets/study_design.yaml
```

The report is a TSV with `severity`, `rule_id`, `source`, `field`, `row`, `message`, and `suggestion`.

## Common Errors

| error | fix |
| --- | --- |
| Missing required top-level section | Add `study`, `phenotype_index`, `hypotheses`, or `reporting`. |
| Formula variable is not listed in components | Add the variable to `components` or correct the formula. |
| Profile component is absent from phenotype metadata | Add phenotype rows with matching `measurement` or `assay` values. |
| Unsafe or unsupported formula element | Use simple arithmetic only. |
| Contrast condition not found | Align contrast condition names with phenotype samplesheet `condition`. |
| Variable is not resolvable or declared as derived | Add a profile declaration, species trait row, phenotype metadata value, or derived variable. |

## Downstream Use

CAME uses profiles to compute phenotype indexes, calculate contrast responses, build model matrices, fit phylogenetic and non-phylogenetic hypothesis models, and label report context. Profile content remains data-driven: adding a new profile should not require editing core analysis code.
