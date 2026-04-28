# Immune Response Template Profile

This profile demonstrates how to represent an immune challenge study with the generic CAME study-profile schema. It is a template for authoring and testing profiles, not a biologically validated analysis.

## Phenotype Index

`immune_response_index` combines four phenotype components:

- `pathogen_clearance`
- `cytokine_signal`
- `tissue_damage`
- `inflammation_baseline`

The formula uses only safe profile syntax:

```yaml
formula: "(pathogen_clearance + cytokine_signal - tissue_damage) / max(inflammation_baseline, 0.1)"
```

The denominator uses `max()` to avoid a zero denominator in example metadata.

## Contrast

The bundled example compares `unexposed` at `0h` with `immune_challenge` at `24h` using the existing `baseline_vs_response` contrast type.

## Hypotheses

The profile includes:

- A direct hypothesis linking `phenotype_index_response` to `infection_resistance`.
- A residual hypothesis linking body-mass-adjusted `infection_resistance` to `phenotype_index_response`.

Both hypotheses use variables declared in the profile or supplied by species-trait metadata.

## Example Metadata

Use `assets/example_samplesheets/profile_examples/phenotype_samplesheet.csv` and `assets/example_samplesheets/profile_examples/species_traits.tsv` to validate or smoke-test this profile.

## Limitations

This profile is intentionally lightweight. It does not define new CAME analyses, encode immune biology in core logic, or validate that the selected components are biologically sufficient for a real study.
