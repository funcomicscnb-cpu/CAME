# CAME Study Profiles

CAME study profiles define the study-specific interpretation layer. They describe phenotype indexes, component traits, contrasts, hypothesis variables, covariates, external evolutionary traits, and report labels without hardcoding a phenotype into the core pipeline.

The validator checks structure and resolvability. Later phenotype and modeling stages consume the same profile declarations through generic code paths.

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

Optional sections include `derived_variables`, `external_traits`, `covariates`, `mechanistic_proxies`, `condition_ranking`, `feature_association_targets`, and `notes`.

## Formula Rules

`phenotype_index.formula` supports simple arithmetic over component names: `+`, `-`, `*`, `/`, unary signs, numbers, parentheses, and safe `abs`, `min`, and `max` calls.

The validator rejects exponentiation, attribute access, string constants, imports, and other executable syntax. It never evaluates the formula. Every variable used in the formula must be listed in `phenotype_index.components`, and every component must appear as a `measurement` or `assay` value in the phenotype samplesheet.

## Derived Variables

Later stages will produce variables such as:

```yaml
derived_variables:
  - phenotype_index
  - phenotype_index_response
  - component_response
```

The validator allows hypotheses to reference declared derived variables. Later stages populate supported derived variables through generic profile-driven code paths.

## Contrasts

Contrasts define which phenotype metadata values later stages will compare. Supported contrast types are:

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

The report is a TSV with `severity`, `source`, `field`, `row`, and `message`.

## Common Errors

| error | fix |
| --- | --- |
| Missing required top-level section | Add `study`, `phenotype_index`, `hypotheses`, or `reporting`. |
| Formula variable is not listed in components | Add the variable to `components` or correct the formula. |
| Profile component is absent from phenotype metadata | Add phenotype rows with matching `measurement` or `assay` values. |
| Unsafe or unsupported formula element | Use simple arithmetic only. |
| Contrast condition not found | Align contrast condition names with phenotype samplesheet `condition`. |
| Variable is not resolvable or declared as derived | Add a profile declaration, species trait row, phenotype metadata value, or derived variable. |

## Later Stages

CAME uses profiles to compute phenotype indexes, calculate contrast responses, build model matrices, fit phylogenetic and non-phylogenetic hypothesis models, and label report context. Profile content remains data-driven: adding a new profile should not require editing core analysis code.
