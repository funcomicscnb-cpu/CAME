# Metabolic Response Template Profile

This profile demonstrates how to represent a metabolic challenge study with the generic CAME study-profile schema. It is a template for authoring and testing profiles, not a biologically validated analysis.

## Phenotype Index

`metabolic_response_index` combines four phenotype components:

- `glucose_clearance`
- `lipid_mobilization`
- `oxygen_efficiency`
- `heat_output`

The formula uses only safe profile syntax:

```yaml
formula: "(glucose_clearance + lipid_mobilization + oxygen_efficiency) / max(heat_output, 0.1)"
```

The denominator uses `max()` to avoid a zero denominator in example metadata.

## Contrast

The bundled example compares `fed` at `0h` with `fasted` at `12h` using the existing `baseline_vs_response` contrast type.

## Hypotheses

The profile includes:

- A direct hypothesis linking `phenotype_index_response` to `metabolic_flexibility`.
- A residual hypothesis linking body-mass-adjusted `metabolic_flexibility` to `phenotype_index_response`.

Both hypotheses use variables declared in the profile or supplied by species-trait metadata.

## Example Metadata

Use `assets/example_samplesheets/profile_examples/phenotype_samplesheet.csv` and `assets/example_samplesheets/profile_examples/species_traits.tsv` to validate or smoke-test this profile.

## Limitations

This profile is intentionally lightweight. It does not define new CAME analyses, encode metabolic biology in core logic, or validate that the selected components are biologically sufficient for a real study.
