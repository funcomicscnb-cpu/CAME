# CEEG Compatibility

`ceeg_compatibility` is an optional scaffold interface for consuming externally generated CEEG
R1/R2/R3 contract artifacts inside CAME. It is not part of the default `--run_stage all` path
and does not replace any production biological analysis stage.

CAME-I0 consumes read-only CEEG artifact directories and writes compact CAME-side summaries.
It does not call CEEG validators, does not perform candidate scoring, and does not infer
biological conservation or functional equivalence.

---

## Repository boundary

| Responsibility | Owner |
|---|---|
| R1/R2/R3 schemas and validation semantics | CEEG |
| R0/R1/R2/R3 validators and CLIs | CEEG |
| Generating R2/R3 artifact directories | CEEG (externally, before CAME invocation) |
| Reading and summarizing R2/R3 artifacts | CAME (this stage) |
| Biological inference, conservation scoring, admissibility | Neither — deferred or prohibited |

CAME does not vendor CEEG validators. CEEG validators must be run separately in the CEEG
repository before supplying the output directories to CAME.

---

## How to generate CEEG artifacts externally

Run the following commands from the CEEG repository root before invoking CAME.
CAME-I0 consumes the resulting output directories. It does not invoke CEEG validators.
Automatic validator invocation from within CAME is deferred to CAME-I1.

```bash
# From the CEEG repository root (e.g. cd ../CEEG)

# R1: validate the CEEG model bundle
python3 bin/validate_ceeg_model_bundle.py \
  --bundle-dir <ceeg_bundle_dir> \
  --out-dir <r1_validation_out> \
  --validation-mode development

# R2: run the CAME overlay validator
python3 bin/run_came_overlay.py \
  --run-dir <r2_run_dir> \
  --out-dir <r2_overlay_out> \
  --validation-mode development

# R3: run the mapping-contract validator
python3 bin/run_mapping_contract.py \
  --run-dir <r3_run_dir> \
  --out-dir <r3_mapping_out> \
  --validation-mode development
```

---

## Command

```bash
nextflow run . \
  --run_stage ceeg_compatibility \
  --ceeg_model_bundle <path/to/ceeg_bundle> \
  [--ceeg_r2_overlay_dir <path/to/r2_out>] \
  [--ceeg_r3_mapping_dir <path/to/r3_out>] \
  [--ceeg_validation_mode development] \
  [--ceeg_fail_on_contract_error true] \
  --ceeg_stub false
```

When `--ceeg_stub true`, CAME writes deterministic header-only output files and skips
processing. This is the safe default for testing and CI.

---

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `--ceeg_model_bundle` | `null` | Required. Path to the externally validated CEEG R1 bundle directory. |
| `--enable_ceeg_compatibility` | `false` | When true, also runs ceeg_compatibility alongside `--run_stage validation`. |
| `--ceeg_stub` | `false` | When true, writes header-only outputs and skips processing. |
| `--ceeg_r2_overlay_dir` | `null` | Optional. Path to an externally generated R2 CAME overlay output directory. |
| `--ceeg_r3_mapping_dir` | `null` | Optional. Path to an externally generated R3 mapping-contract output directory. |
| `--ceeg_validation_mode` | `development` | Mirrors the CEEG `--validation-mode` value for provenance recording. |
| `--ceeg_fail_on_contract_error` | `true` | When true, a non-zero CEEG validator exit code recorded in R2/R3 manifests causes CAME to fail. |
| `--ceeg_validator_cmd` | — | Reserved for a future stage (CAME-I1) that will invoke CEEG CLIs from within CAME. Not wired in I0. |

---

## Expected R2 artifacts

R2 is the CAME overlay validator output, produced by `bin/run_came_overlay.py` in CEEG.

**Full output (exit 0 or 1)**:
- `came_report_manifest.json` — required for CAME-I0 R2 summary
- `compatibility_summary.json` — consumed when present
- `validation_summary.tsv`
- `run_warnings.tsv`
- `run_provenance.tsv`
- `run_activities.tsv`
- `final_report.md`

**Fatal output only (exit 2)**:
- `came_report_manifest.json` — required
- `validation_summary.tsv`
- `final_report.md`

When R2 exit code is 2, `compatibility_summary.json` is absent. CAME records this in the
contract summary without treating it as an adapter error.

---

## Expected R3 artifacts

R3 is the mapping-contract validator output, produced by `bin/run_mapping_contract.py` in CEEG.

**Full output (exit 0)**:
- `mapping_report_manifest.json` — required for CAME-I0 R3 summary
- `mapping_summary.tsv` — required for mapping summary
- `unmapped_features.tsv` — required for unmapped feature report
- `ambiguous_mappings.tsv` — required for ambiguous mapping report
- `run_mapping_results.tsv`
- `run_mapping_matches.tsv`
- `validation_summary.tsv`
- `final_report.md`

**Error/fatal output (exit 1 or 2)**:
- `mapping_report_manifest.json` — required
- Remaining files may be header-only or absent

---

## CAME-side outputs

Outputs are written to `results/ceeg_compatibility/`:

| File | Description |
|---|---|
| `ceeg_contract_summary.tsv` | One row per consumed artifact (R2, R3). Columns: `artifact_type`, `artifact_path`, `status`, `exit_code`, `validator_name`, `validator_version`, `run_id`, `message`. |
| `ceeg_mapping_summary.tsv` | Mapping counts from R3. Columns: `run_id`, `total_features`, `mapped_count`, `ambiguous_count`, `failed_count`, `source_artifact`. |
| `ceeg_unmapped_features.tsv` | R3 unmapped features pass-through plus `source_artifact` and `interpretation_note`. |
| `ceeg_ambiguous_mappings.tsv` | R3 ambiguous mappings pass-through plus `source_artifact` and `interpretation_note`. |
| `ceeg_compatibility_warnings.tsv` | Adapter-level warnings. Columns: `severity`, `source`, `message`. |
| `ceeg_outputs_manifest.tsv` | Manifest of all CAME-I0 output files. |

The `interpretation_note` for unmapped features is always:
> `failed mapping is not biological absence`

The `interpretation_note` for ambiguous mappings is always:
> `ambiguous mapping is not collapsed to one-to-one`

A header-only ceeg_contract_summary.tsv (and related outputs) indicates that no R2/R3 artifact directories were supplied. It is not a contract-validation failure.

---

## Failure semantics

CEEG exit codes are preserved and summarized in `ceeg_contract_summary.tsv`:

| CEEG exit code | Meaning | CAME behavior with `--ceeg_fail_on_contract_error true` |
|---|---|---|
| 0 | Compatible / valid | No action |
| 1 | Invalid contract | CAME fails after writing outputs |
| 2 | Fatal contract failure | CAME fails after writing outputs |

When `--ceeg_fail_on_contract_error false`, both exit 1 and exit 2 are summarized as warnings
and CAME continues. The exit code distinction is preserved in the summary.

---

## Anti-overclaim rules

The following inferences are explicitly prohibited in this stage and all downstream uses of
its outputs:

- Failed mapping is not biological absence.
- Unmapped is not absent.
- Ambiguous mapping is not collapsed to one-to-one.
- Orthology is not identity.
- Mapping audit is not biological conservation.
- Direct regulatory projection is not functional conservation.
- Association is not causation.
- Same metadata label is not system congruence.

See also `docs/ceeg_invariants.md`.

---

## Relationship to existing CAME stages

- Not part of `--run_stage all`.
- Does not replace orthology projection.
- Does not replace GRA analysis.
- Does not replace candidate prioritization.
- Does not feed final reporting in I0.
- Does not change real-mode RNA/ATAC/WGS behavior.

---

## Deferred items

The following are intentionally out of scope for CAME-I0:

- Calling CEEG CLIs (`bin/run_came_overlay.py`, `bin/run_mapping_contract.py`) from within
  CAME — deferred to CAME-I1.
- Artifact-only mode without `--ceeg_model_bundle`.
- Final-report integration (`results/final/report/` rendering of CEEG contract status).
- Candidate-prioritization use of R2/R3 outputs.
- Orthology/GRA/phenotype-omics use of R3 mapping summaries.
- R4 admissibility/biological-comparability scoring.
- R3 `relation_type` controlled vocabulary.
- Real biological benchmarks.
