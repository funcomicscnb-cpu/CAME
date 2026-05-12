# CEEG Compatibility

`ceeg_compatibility` is an optional scaffold interface for consuming externally generated CEEG
R1/R2/R3 contract artifacts inside CAME. It is not part of the default `--run_stage all` path
and does not replace any production biological analysis stage.

CAME-I0 consumes read-only CEEG artifact directories and writes compact CAME-side summaries.
It does not call CEEG validators, does not perform candidate scoring, and does not infer
biological conservation or functional equivalence.

CAME-I2 adds optional command orchestration: when `--ceeg_orchestrate_contracts true`, CAME
invokes external CEEG validator CLIs and feeds the resulting directories to the I0 adapter.
CAME does not vendor CEEG validators or reimplement validation logic.

CAME also exposes a `--comparability_mode` parameter to make explicit whether the current run
consumed CEEG R2/R3 contract artifacts. Runs that consume R2/R3 (directly or via orchestration)
must declare `--comparability_mode ceeg_contract_checked`; standard CAME runs use the default
`design_assumed`. R2/R3 contract success is reported strictly as contract status; it is not R4
comparability validation and not R5 admissibility validation. See
[`comparability_modes.md`](comparability_modes.md) for the full vocabulary and rationale.

---

## Repository boundary

| Responsibility | Owner |
|---|---|
| R1/R2/R3 schemas and validation semantics | CEEG |
| R0/R1/R2/R3 validators and CLIs | CEEG |
| Generating R2/R3 artifact directories | CEEG (externally); or CAME optionally via CAME-I2 |
| Reading and summarizing R2/R3 artifacts | CAME (this stage) |
| Biological inference, conservation scoring, admissibility | Neither — deferred or prohibited |

CAME does not vendor CEEG validators. When using CAME-I2, users must install or provide
access to CEEG CLI paths. CAME invokes them as external programs.

---

## How to generate CEEG artifacts externally

Run the following commands from the CEEG repository root before invoking CAME.
CAME-I0 consumes the resulting output directories. It does not invoke CEEG validators.
Alternatively, use `--ceeg_orchestrate_contracts true` (CAME-I2) to have CAME invoke the
commands automatically.

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
| `--ceeg_stub` | `false` | When true, writes header-only outputs and skips processing. Always takes precedence over orchestration. |
| `--ceeg_r2_overlay_dir` | `null` | Optional. Path to an externally generated R2 CAME overlay output directory. Cannot be combined with `--ceeg_run_came_overlay_cmd`. |
| `--ceeg_r3_mapping_dir` | `null` | Optional. Path to an externally generated R3 mapping-contract output directory. Cannot be combined with `--ceeg_run_mapping_contract_cmd`. |
| `--ceeg_validation_mode` | `development` | Mirrors the CEEG `--validation-mode` value for provenance recording. |
| `--ceeg_fail_on_contract_error` | `true` | When true, a non-zero CEEG validator exit code recorded in R2/R3 manifests causes CAME to fail. |
| `--ceeg_orchestrate_contracts` | `false` | When true, CAME invokes external CEEG validator commands and generates R2/R3 artifact directories. Default off. Not included in `--run_stage all`. |
| `--ceeg_run_came_overlay_cmd` | `null` | Command prefix for the external R2 validator. CAME appends `--run-dir`, `--out-dir`, `--validation-mode`, and optionally `--created-at`. Example: `python3 /path/to/ceeg/bin/run_came_overlay.py`. |
| `--ceeg_run_mapping_contract_cmd` | `null` | Command prefix for the external R3 validator. CAME appends the same arguments. Example: `python3 /path/to/ceeg/bin/run_mapping_contract.py`. |
| `--ceeg_r2_run_dir` | `null` | Required when `--ceeg_run_came_overlay_cmd` is set. Path passed as `--run-dir` to the R2 validator. |
| `--ceeg_r3_run_dir` | `null` | Required when `--ceeg_run_mapping_contract_cmd` is set. Path passed as `--run-dir` to the R3 validator. |
| `--ceeg_validator_created_at` | `null` | Optional. When set, forwarded to CEEG CLIs as `--created-at`. Primarily useful for deterministic tests and reproducible fixture generation. Not required for production use. |
| `--ceeg_r4_comparability_dir` | `null` | Optional. Path to an externally generated CEEG R4 comparability evidence output directory (CAME-I3). Read-only consumption; CAME does not invoke the R4 validator. Requires `--comparability_mode ceeg_comparability_evidence_consumed`. |

---

## CAME-I2: Orchestrated Validator Invocation

When `--ceeg_orchestrate_contracts true`, CAME invokes the external CEEG validator CLIs,
writes generated R2/R3 output directories under `results/ceeg_compatibility/generated/`, and
then feeds those directories to the existing CAME-I0 consumption adapter.

### `--ceeg_stub true` always takes precedence

When `--ceeg_stub true` (the default), no external commands are invoked regardless of
`--ceeg_orchestrate_contracts`. Stub mode produces deterministic header-only outputs with
zero external dependencies.

### Generated output locations

- R2: `results/ceeg_compatibility/generated/r2_overlay/`
- R3: `results/ceeg_compatibility/generated/r3_mapping/`
- Command logs: `results/ceeg_compatibility/generated/r2_overlay/ceeg_command.log`
  and `results/ceeg_compatibility/generated/r3_mapping/ceeg_command.log`

### Command prefix contract

CAME constructs the full command by appending arguments to the supplied prefix:

```bash
# R2
<ceeg_run_came_overlay_cmd> \
  --run-dir <ceeg_r2_run_dir> \
  --out-dir <generated_r2_dir> \
  --validation-mode <ceeg_validation_mode> \
  [--created-at <ceeg_validator_created_at>]

# R3
<ceeg_run_mapping_contract_cmd> \
  --run-dir <ceeg_r3_run_dir> \
  --out-dir <generated_r3_dir> \
  --validation-mode <ceeg_validation_mode> \
  [--created-at <ceeg_validator_created_at>]
```

Command prefixes may include interpreter prefixes (e.g. `python3 /path/to/script.py`).
**Paths containing spaces are not guaranteed to work** unless the user handles shell quoting
correctly in the command string. Avoid paths with spaces for validator scripts.

### Exit code behavior

| Exit class | Meaning | CAME behavior |
|---|---|---|
| Validator exits 0, manifest exists | Completed successfully | CAME consumes generated artifact directory |
| Validator exits 1, manifest exists | CEEG validator reported invalid contract | CAME consumes artifact; `ceeg_fail_on_contract_error` controls workflow failure |
| Validator exits 2, manifest exists | CEEG validator reported fatal contract status | CAME consumes artifact; `ceeg_fail_on_contract_error` controls workflow failure |
| Validator exits 0/1/2, manifest missing | Orchestration error / incomplete artifact handoff | `check_ceeg_orchestration.py` exits 10; workflow fails |
| Validator exits other nonzero | Tooling or command-invocation failure | Workflow fails as orchestration/tooling failure, not as CEEG contract invalid/fatal |

Exit 10 from `bin/check_ceeg_orchestration.py` signals "recognized validator exit code, but
expected manifest missing." Exit 10 is not a CEEG validation result. Users should inspect
`ceeg_command.log` and the generated output directory when this occurs.

### Example command

```bash
nextflow run . \
  --run_stage ceeg_compatibility \
  --ceeg_model_bundle <path/to/ceeg_bundle> \
  --ceeg_orchestrate_contracts true \
  --ceeg_run_came_overlay_cmd "python3 /path/to/ceeg/bin/run_came_overlay.py" \
  --ceeg_r2_run_dir <path/to/r2_run_inputs> \
  --ceeg_run_mapping_contract_cmd "python3 /path/to/ceeg/bin/run_mapping_contract.py" \
  --ceeg_r3_run_dir <path/to/r3_run_inputs> \
  --ceeg_validation_mode development \
  --ceeg_stub false
```

### Conflict rules

- If both `--ceeg_r2_overlay_dir` and `--ceeg_run_came_overlay_cmd` are supplied,
  CAME fails before invoking any command.
- If both `--ceeg_r3_mapping_dir` and `--ceeg_run_mapping_contract_cmd` are supplied,
  CAME fails before invoking any command.
- CAME never silently prefers generated artifacts over supplied artifacts or vice versa.

---

## CAME-I3: R4 Comparability Evidence Consumption

CAME-I3 reads externally generated CEEG R4 comparability evidence artifacts and
summarizes them into CAME-side TSVs. CAME-I3 is **read-only consumption**. CAME does
not invoke the R4 validator. R4 orchestration is out of scope for CAME-I3 and may be
added by a later CAME-I4 task if needed.

**Required inputs** (under `--ceeg_r4_comparability_dir <dir>`):
- `comparability_report_manifest.json`
- `comparability_summary.tsv`
- `comparability_evidence.tsv`
- `comparability_limitations.tsv`

The F0e fatal-shape (`exit_code: 2`) artifact contains only the manifest and
`comparability_limitations.tsv`. CAME-I3 accepts that shape and emits a
single CAME diagnostic row so the failure remains visible.

**Required mode:** runs that supply `--ceeg_r4_comparability_dir` must declare
`--comparability_mode ceeg_comparability_evidence_consumed`. R2/R3 artifacts may also
be consumed in the same run; both sections appear in the final report.

**Stub-mode policy.** `--ceeg_stub true` means "do not invoke external validators." When
`--ceeg_r4_comparability_dir` is supplied alongside `--ceeg_stub true`, CAME still
consumes the supplied R4 directory (the summarizer is a pure parser, not a validator
invocation). When no R4 directory is supplied under stub mode, CAME writes header-only
R4 TSVs and does not fabricate evidence.

**Failure semantics.** A non-zero R4 manifest `exit_code` is recorded in the CAME
diagnostic row of `ceeg_r4_comparability_summary.tsv`. `CHECK_CEEG_CONTRACT_STATUS`
reads both `ceeg_contract_summary.tsv` and `ceeg_r4_comparability_summary.tsv`, takes
the maximum exit code, and fails the workflow after publication when
`--ceeg_fail_on_contract_error true`. The failure message identifies the source file
(R2/R3 summary or R4 summary) so the user can locate the responsible artifact.

**Anti-overclaim.** R4 reports structured evidence state under a bound analysis context.
CAME-I3 does not infer biological comparability, conservation, equivalence, or
absence from R4 evidence state. R4 `evidence_against_comparability` is not rendered
as "biologically absent" or "incomparable". The eight count columns
(`supporting_evidence_count` … `absent_count`) are preserved verbatim; `unknown`,
`unknown_unmappable`, and `absent` are not collapsed.

### CI and test strategy

CAME-I2 tests use local mock commands (`tests/fixtures/mock_ceeg_validator.sh`) rather
than a real CEEG repository checkout. The mock emits CAME-I0-compatible artifact schemas
and is not a substitute for CEEG validation. An opt-in real-CEEG integration test is
available at `tests/test_ceeg_external_integration.sh` (see below).

### External integration testing

`tests/test_ceeg_external_integration.sh` exercises the real cross-repository boundary:

```
CEEG validator CLI -> emitted R2/R3 artifacts -> CAME-I0 summarizer
```

It does **not** run the full Nextflow orchestration path
(`ORCHESTRATE_CEEG_VALIDATORS -> CONSUME_CEEG_CONTRACT_ARTIFACTS -> CHECK_CEEG_CONTRACT_STATUS`).
That path is already covered by mock-driven CAME tests. A real-CEEG full Nextflow E2E
profile is deferred.

**The test is skipped unless `CEEG_REPO` is set.** Default CAME CI is unaffected.

```bash
# Skip mode (default CI) — clean skip, exit 0
unset CEEG_REPO
bash tests/test_ceeg_external_integration.sh

# Real-CEEG mode
export CEEG_REPO=/path/to/ceeg
bash tests/test_ceeg_external_integration.sh
```

**Environment variables:**

| Variable | Default | Description |
|---|---|---|
| `CEEG_REPO` | — | Required. Path to a real CEEG checkout. Skipped if unset. |
| `CEEG_R2_RUN_DIR` | `$CEEG_REPO/examples/R2_came_overlay_valid/enabled` | R2 valid run dir. |
| `CEEG_R3_RUN_DIR` | `$CEEG_REPO/examples/R3_mapping_contract_valid/basic` | R3 valid run dir. |
| `CEEG_R2_INVALID_RUN_DIR` | `$CEEG_REPO/examples/R2_came_overlay_invalid/core/incompatible_contract_version` | R2 invalid run dir. |
| `CEEG_R3_INVALID_RUN_DIR` | `$CEEG_REPO/examples/R3_mapping_contract_invalid/core/invalid_mapping_status` | R3 invalid run dir. |
| `CEEG_R2_FATAL_RUN_DIR` | — | Optional. Fatal R2 run dir. Tested only if set; exit 2 empirically confirmed. |
| `CEEG_R3_FATAL_RUN_DIR` | — | Optional. Fatal R3 run dir. Tested only if set; exit 2 empirically confirmed. |
| `CEEG_VALIDATION_MODE` | `development` | Forwarded as `--validation-mode`. |
| `CEEG_CREATED_AT` | — | Optional. Forwarded as `--created-at` when set. |

**Coverage:** valid (exit 0), invalid (exit 1), and fatal (exit 2, if empirically confirmed).
Fatal fixture coverage is skipped if no fatal environment variable is set — mock-driven CAME
tests remain the current coverage for exit-2 orchestration behavior.

**Failure categories distinguished:**
- skipped: `CEEG_REPO` unset;
- failed: CLI missing or help surface changed;
- failed: chosen validation mode rejected by real CLI;
- failed: run dir missing;
- failed: expected artifacts absent after validator run;
- failed: CAME checker rejected the validator exit code;
- failed: CAME summarizer produced unexpected output or exit code;
- failed: `exit_code` column in summary does not match expected value.

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
| `ceeg_r4_comparability_summary.tsv` | CAME-I3. One row per R4 comparison, plus a single CAME diagnostic row when the R4 manifest reports `contract_error`. 28 columns including `artifact_type`, `validator_name`, `validator_version`, `status`, `exit_code`, `model_id`, `context_id`, `comparison_id`, `entity_scope`, `comparability_status`, `status_basis`, evidence counts, and `primary_limitation`. |
| `ceeg_r4_comparability_limitations.tsv` | CAME-I3. Pass-through of R4 `comparability_limitations.tsv` (8 columns). |
| `ceeg_r4_comparability_evidence.tsv` | CAME-I3. Pass-through copy of R4 `comparability_evidence.tsv` annotated with `source_artifact` and the constant `interpretation_note` `"R4 evidence state is not biological comparability validation."`. |
| `ceeg_r4_outputs_manifest.tsv` | CAME-I3 outputs manifest. |

When CAME-I2 orchestration generates artifacts, the generated directories are also written
under `results/ceeg_compatibility/generated/`.

The `interpretation_note` for unmapped features is always:
> `failed mapping is not biological absence`

The `interpretation_note` for ambiguous mappings is always:
> `ambiguous mapping is not collapsed to one-to-one`

A header-only ceeg_contract_summary.tsv (and related outputs) indicates that no R2/R3 artifact directories were supplied. It is not a contract-validation failure.

---

## Failure semantics

CEEG exit codes are preserved and summarized in `ceeg_contract_summary.tsv`.
`ceeg_contract_summary.tsv` is **always published** to `results/ceeg_compatibility/`
regardless of whether the pipeline subsequently fails.

| CEEG exit code | Meaning | CAME behavior with `--ceeg_fail_on_contract_error true` |
|---|---|---|
| 0 | Compatible / valid | No action |
| 1 | Invalid contract | Outputs published; CAME fails after publishing |
| 2 | Fatal contract failure | Outputs published; CAME fails after publishing |

When `--ceeg_fail_on_contract_error false`, both exit 1 and exit 2 are summarized as warnings
and CAME continues. The exit code distinction is preserved in the summary.

### Two distinct failure modes

**Contract-error failure** (`exit_code` 1 or 2 in a CEEG manifest): `CONSUME_CEEG_CONTRACT_ARTIFACTS`
always exits 0 and publishes all outputs. A downstream `CHECK_CEEG_CONTRACT_STATUS` process
reads `ceeg_contract_summary.tsv`, finds the nonzero exit code, and fails the workflow.
`results/ceeg_compatibility/ceeg_contract_summary.tsv` is on disk and readable.

**Python adapter crash** (unhandled exception in `summarize_ceeg_contract_artifacts.py` due to
a malformed input, permission error, or disk failure): `CONSUME_CEEG_CONTRACT_ARTIFACTS` itself
exits nonzero and outputs may not be published. The appropriate response is to inspect the
Nextflow work directory and report a bug — this failure mode is not a CEEG contract result.

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

## Final-report integration

CAME-I1 adds a compact "CEEG Contract Consumption" section to the CAME final report
(`results/final/report/came_final_report.html` and `.md`).

This section is contract-status reporting only:

- Fatal and invalid CEEG statuses (exit_code 1 or 2) are displayed as recorded; they are
  not reinterpreted by the final-report stage.
- The final-report stage exits 0 regardless of CEEG validator exit codes recorded in consumed
  artifacts. Final reporting is a renderer, not a validator gate.
- Because `CONSUME_CEEG_CONTRACT_ARTIFACTS` always exits 0 and publishes outputs before
  `CHECK_CEEG_CONTRACT_STATUS` enforces failure, the final report correctly renders the
  contract-failed status rather than the "no artifacts supplied" branch, even when
  `--ceeg_fail_on_contract_error true` and the contract was invalid.
- The final report does not infer conservation, equivalence, absence, comparability, or
  admissibility from CEEG outputs.
- Header-only CEEG compatibility output files indicate that no R2/R3 artifact directories were
  supplied. They are not a contract-validation failure.
- Missing `results/ceeg_compatibility/` is not a contract-validation failure.

---

## Relationship to existing CAME stages

- Not part of `--run_stage all`.
- Does not replace orthology projection.
- Does not replace GRA analysis.
- Does not replace candidate prioritization.
- Does not change real-mode RNA/ATAC/WGS behavior.

---

## Deferred items

The following are intentionally out of scope for CAME-I0/I1/I2:

- Real-CEEG full Nextflow E2E coverage for `--ceeg_orchestrate_contracts true` — the
  opt-in CLI+adapter test (`tests/test_ceeg_external_integration.sh`) covers the
  CEEG CLI → CAME-I0 boundary; full Nextflow orchestration path testing against a real
  CEEG checkout is deferred.
- Real CEEG fatal/exit-2 fixture coverage — mock-driven CAME tests cover exit-2 behavior;
  real fatal fixtures can be added via `CEEG_R2_FATAL_RUN_DIR` / `CEEG_R3_FATAL_RUN_DIR`
  once canonical CEEG fatal fixtures exist.
- Artifact-only mode without `--ceeg_model_bundle`.
- Candidate-prioritization use of R2/R3 outputs.
- Orthology/GRA/phenotype-omics use of R3 mapping summaries.
- R4/R5 admissibility/biological-comparability scoring.
- R3 `relation_type` controlled vocabulary.
- Version compatibility checks between CAME and CEEG validators.
- Real biological benchmarks.
