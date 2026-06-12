# CAME Optional Orthology Reference Preparation

`orthology_reference_prepare` is an optional basic interface for producing a
versioned reciprocal-best orthology reference bundle manifest. It is not part of
the default `--run_stage all` path.

This stage is an orchestration and validation wrapper only. CAME does not
implement synteny reconstruction, chain/net generation, or HAL construction
inside this stage. In real mode, CAME invokes a user-supplied external command
that writes a bundle directory, then validates the emitted
`orthology_reference_bundle.tsv` with
`bin/validate_orthology_reference_bundle.py`.

## Boundary

| Responsibility | Owner |
| --- | --- |
| Synteny reconstruction, chain/net generation, HAL construction | External toolchain / future explicitly gated implementation |
| Reciprocal-best bundle manifest schema and CAME-side validation | CAME |
| Study-side coordinate projection using reviewed bundle assets | CAME `coordinate_projection` |
| CEEG model construction or reference-model editing | Not owned by this stage |

The stage mirrors CAME's external-orchestration pattern: it may invoke an
external command and inspect documented output files, but it does not vendor
external validator/generator code and does not infer biological absence from
missing or failed mappings.

## Command

Stub mode is the default and has no external dependencies:

```bash
nextflow run . \
  --run_stage orthology_reference_prepare \
  --orthology_reference_prepare_stub true
```

Real mode requires a command prefix and a run directory:

```bash
nextflow run . \
  --run_stage orthology_reference_prepare \
  --orthology_reference_prepare_stub false \
  --orthology_reference_prepare_cmd "python3 /path/to/make_orthology_bundle.py" \
  --orthology_reference_prepare_run_dir /path/to/reference_prep_inputs \
  --outdir results
```

The external command must write:

```text
<out-dir>/orthology_reference_bundle.tsv
```

where `<out-dir>` is supplied by CAME. Bundle asset paths should be local paths
relative to that bundle directory or absolute local paths. Remote URI assets are
not consumable by current `coordinate_projection` real mode.

## Parameters

| Parameter | Default | Description |
| --- | --- | --- |
| `--orthology_reference_prepare_stub` | `true` | When true, writes a header-only stub bundle manifest and skips external command invocation. |
| `--orthology_reference_prepare_cmd` | `null` | Command prefix for the external bundle generator. Required when stub is false. CAME appends `--run-dir` and `--out-dir`, plus `--created-at` when supplied. |
| `--orthology_reference_prepare_run_dir` | `null` | Directory passed to the external command as `--run-dir`. Required when stub is false. |
| `--orthology_reference_prepare_created_at` | `null` | Optional deterministic timestamp forwarded as `--created-at`; useful for reproducible fixtures. |
| `--orthology_reference_prepare_check_paths` | `true` | Passed to the bundle validator as `--check-paths`; keep true for local generated bundles. |

## Command Prefix Contract

CAME constructs the full external command as:

```bash
<orthology_reference_prepare_cmd> \
  --run-dir <orthology_reference_prepare_run_dir> \
  --out-dir <work>/bundle \
  [--created-at <orthology_reference_prepare_created_at>]
```

Command prefixes may include an interpreter prefix, such as
`python3 /path/to/script.py`. Avoid generator script paths containing spaces
unless the command prefix is shell-quote-safe.

## Outputs

Published under `results/orthology_reference_prepare/`:

| Path | Description |
| --- | --- |
| `bundle/orthology_reference_bundle.tsv` | Generated bundle manifest, or header-only manifest in stub mode. |
| `bundle/` | Bundle assets written by the external command. |
| `orthology_reference_bundle_validation.tsv` | Validation records from `validate_orthology_reference_bundle.py`, or a stub-mode INFO record. |
| `orthology_reference_bundle_warnings.tsv` | Warning subset of the validation report. |
| `orthology_reference_prepare_summary.tsv` | Stage mode, status, validation counts, command exit code, and boundary note. |
| `orthology_reference_prepare_outputs_manifest.tsv` | Inventory of published files. |
| `orthology_reference_prepare_command.log` | External command log; absent in stub mode. |

The generated bundle is intended for a later explicit run of
`coordinate_projection`:

```bash
nextflow run . \
  --run_stage coordinate_projection \
  --regulatory_regions regions.tsv \
  --orthology_reference_bundle_manifest results/orthology_reference_prepare/bundle/orthology_reference_bundle.tsv \
  --coordinate_projection_stub false
```

This handoff remains explicit. `orthology_reference_prepare` does not feed
`coordinate_projection` automatically and is not included in `--run_stage all`.

## Exit Behavior

| Case | Behavior |
| --- | --- |
| Stub mode | Writes header-only bundle contract files and exits 0. |
| External command exits 0 and manifest exists | Validates the manifest; exits nonzero if validation has ERROR rows. |
| External command exits nonzero | Writes `orthology_reference_prepare_command.log`, records an ERROR, and exits nonzero. |
| External command exits 0 but manifest is missing | Records an ERROR and exits 10. |
| Bundle validator reports ERROR rows | Writes validation outputs and exits nonzero. |

Warnings, including optional provenance omissions for external bundles, do not
cause failure. CAME-generated bundles are still held to the stricter provenance
requirements enforced by the bundle validator.

## Bundle Contract

The durable interface is the versioned manifest described by
`schemas/orthology_reference_bundle_manifest.schema.json` and validated by
`bin/validate_orthology_reference_bundle.py`.

Supported v1 asset roles:

- `reciprocal_best_chain`
- `source_callable_mask`
- `target_callable_mask`
- `source_element_union`
- `hal_alignment`

The validator checks required columns and values, supported enum values,
relative-path resolution, local path existence when requested, lift-tool asset
requirements, duplicate role conflicts, provenance requirements for
`bundle_source=came_generated`, and optional sequence-name concordance when
FASTA/FAI/annotation context is supplied.

## Limits

- This is not a production synteny-reconstruction implementation.
- CAME does not run `halSynteny`, `axtChain`, `chainNet`, or related tools
  directly in this ticket.
- Generated bundles are local-file oriented; cloud/object-storage portable
  bundle generation remains future work.
- Bundle generation is outside `--run_stage all`; users must run this stage and
  the later `coordinate_projection` handoff explicitly.
