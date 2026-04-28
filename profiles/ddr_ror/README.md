# DDR/RoR Example Study Profile

This profile is a biological example for CAME's study-profile system. It shows how DNA damage response and robustness-of-regulation terms can live in a profile, example metadata, documentation, and tests while the validator, workflow, and core scripts remain phenotype-agnostic.

The profile is not required by CAME core logic and is not a biologically validated analysis template.

## Phenotype Index

`DDRstate` is calculated from three profile components:

- `viability`
- `apoptosis`
- `senescence`

The formula uses only the current safe arithmetic syntax:

```yaml
formula: "(viability - apoptosis - senescence) / (viability + apoptosis)"
```

Every formula variable is also listed in `phenotype_index.components`, and the bundled example phenotype metadata contains matching `measurement` values.

## Contrast

The profile defines one `baseline_vs_response` contrast:

- baseline: `control` at `0h`
- response: `damage` at `24h`

CAME interprets the response direction as response minus baseline in the generic phenotype contrast code path.

## Hypotheses

The hypotheses are explicit profile-level examples:

- `viability_longevity_association`: direct association between `viability_response` and `max_longevity`.
- `cancer_body_mass_residual_viability`: residual association between body-mass-adjusted `cancer_prevalence` and `viability_response`.
- `cancer_longevity_residual_apoptosis_senescence`: residual association between longevity-adjusted `cancer_prevalence` and `apoptosis_senescence_response`.

These variables are resolved from profile declarations, phenotype contrasts, or species-trait metadata. They do not create profile-specific branches in CAME core logic.

## Limitations

- The profile is an example of profile syntax and profile-scoped interpretation.
- It does not validate assay design, disease biology, or causal mechanisms.
- Real studies should review component definitions, contrast direction, covariates, phylogenetic coverage, and metadata quality before using the profile.
- DDR/RoR-specific terms should remain in profile files, docs, tests, examples, or generated outputs.
