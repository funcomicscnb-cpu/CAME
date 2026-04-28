# Stress Tolerance Template Profile

This profile demonstrates how to represent an environmental stress study with the generic CAME study-profile schema. It is a template for authoring and testing profiles, not a biologically validated analysis.

## Phenotype Index

`stress_tolerance_index` combines four phenotype components:

- `survival_fraction`
- `recovery_rate`
- `damage_marker`
- `stress_intensity`

The formula uses only safe profile syntax:

```yaml
formula: "(survival_fraction + recovery_rate - damage_marker) / max(stress_intensity, 0.1)"
```

The denominator uses `max()` to avoid a zero denominator in example metadata.

## Contrast

The bundled example compares `ambient` at `0h` with `stress` at `6h` using the existing `baseline_vs_response` contrast type.

## Hypotheses

The profile includes:

- A direct hypothesis linking `phenotype_index_response` to `stress_resilience`.
- A residual hypothesis linking body-mass-adjusted `stress_resilience` to `phenotype_index_response`.

Both hypotheses use variables declared in the profile or supplied by species-trait metadata.

## Example Metadata

Use `assets/example_samplesheets/profile_examples/phenotype_samplesheet.csv` and `assets/example_samplesheets/profile_examples/species_traits.tsv` to validate or smoke-test this profile.

## Limitations

This profile is intentionally lightweight. It does not define new CAME analyses, encode stress biology in core logic, or validate that the selected components are biologically sufficient for a real study.
