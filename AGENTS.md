# Agent Instructions

You build and maintain the CAME pipeline.

CAME consumes CEEG reference models and CEEG contract artifacts as read-only priors. CAME owns query-specific analysis, mapping, filtering, reporting, and optional orchestration of external CEEG validator commands. CAME must not rebuild CEEG models or silently edit model bundles. This matches the existing CAME-side boundary: CAME consumes CEEG reference models as read-only priors and owns query-specific mapping, filtering, CEEG contract artifact consumption, and reports.

## Execution Model

CAME is a Nextflow DSL2 pipeline.

CAME is the study-analysis side of the CEEG/CAME system. It may consume CEEG model bundles and CEEG compatibility artifacts, but it must not become the CEEG model builder.

CAME stages should remain modular, testable, and explicit about whether they consume:
- user-supplied study inputs;
- CEEG model-bundle priors;
- CEEG contract artifacts;
- optional outputs produced by external CEEG validator CLIs.

Python/R scripts implement analysis, parsing, validation, summarization, and report-rendering logic. Nextflow orchestrates files, processes, caching, profiles, and reproducibility. Do not put complex biological or contract-parsing logic inline inside `.nf` files.

## CAME Owns

CAME owns:

- query-specific study analysis;
- study-specific omics and phenotype input handling;
- query-specific feature mapping;
- filtering by user-specified biological system or context;
- CAME-side compatibility checks for imported CEEG model bundles;
- consuming CEEG R2/R3 contract artifact directories;
- optional orchestration of external CEEG validator commands;
- CAME-side summaries of consumed CEEG artifacts;
- final-report rendering;
- CAME stub-mode behavior;
- CAME CI tests that do not require a real CEEG checkout.

## CAME Does Not Own

CAME does not own:

- CEEG model construction;
- CEEG validator semantics;
- CEEG schema ownership;
- CEEG biological system-congruence inference;
- synteny reconstruction;
- orthology/coding integration as CEEG model-building logic;
- direct or indirect regulatory projection as CEEG model-building logic;
- branch-event inference;
- CEEG module construction;
- CEEG model export;
- changing CEEG reference models.

## Non-Negotiable CAME/CEEG Boundary

CAME must not:

- vendor CEEG validator code;
- import CEEG Python modules;
- reimplement CEEG validation logic;
- silently edit CEEG model bundles;
- infer conservation, identity, equivalence, absence, comparability, or admissibility from failed contracts;
- infer biological absence from failed mappings;
- collapse ambiguous mappings silently;
- treat missing CEEG artifacts as biological evidence;
- add CEEG R4/R5 comparability or admissibility logic unless explicitly scoped in a future contract stage;
- wire CEEG contract status into candidate prioritization, GRA, phenotype-omics integration, orthology projection, or other analysis stages;
- add `ceeg_compatibility` to `--run_stage all`.

CAME may invoke CEEG tools only as external commands. CAME may inspect their emitted artifacts only through documented contract files.

## CEEG Compatibility Architecture

CAME currently supports the following CEEG integration layers.

### CAME-I0 — Contract Artifact Consumption

CAME-I0 consumes externally generated CEEG R2/R3 artifact directories.

The CAME-side adapter summarizes contract status and emitted artifacts, but it does not reinterpret CEEG validator findings. Contract status is reported as contract status, not as biological inference.

The sole artifact-consumption adapter is:

```text
CONSUME_CEEG_CONTRACT_ARTIFACTS
```

Do not create a parallel consumer unless a future design explicitly supersedes CAME-I0.

### CAME-I1 — Final Report Rendering

CAME-I1 renders CEEG contract-consumption status in the final report.

The report may show:

* supplied R2/R3 artifact directories;
* validator name and version;
* contract status;
* validator exit code;
* adapter diagnostics such as missing manifest or parse error;
* anti-overclaim notes.

The final report must distinguish:

* no CEEG artifacts supplied;
* supplied artifacts with successful contract status;
* supplied artifacts with invalid or fatal contract status;
* supplied artifact directory with adapter error;
* orchestration/tooling failure.

Do not render adapter errors as “no artifacts supplied.”

### CAME-I2 — Optional External Validator Orchestration

CAME-I2 optionally invokes external CEEG R2/R3 validator commands to generate artifacts before consuming them through CAME-I0.

CAME-I2 is an orchestration layer only.

Required architecture:

```text
ORCHESTRATE_CEEG_VALIDATORS
    -> effective R2/R3 selector files
    -> CONSUME_CEEG_CONTRACT_ARTIFACTS
    -> published results/ceeg_compatibility/*
    -> CHECK_CEEG_CONTRACT_STATUS
    -> optional nonzero workflow exit when ceeg_fail_on_contract_error=true
```

Required invariants:

* `ORCHESTRATE_CEEG_VALIDATORS` is always scheduled.
* External command invocation is gated internally.
* Effective path selector files are emitted:

  * `effective_r2_overlay_dir.txt`
  * `effective_r3_mapping_dir.txt`
* `CONSUME_CEEG_CONTRACT_ARTIFACTS` is called exactly once.
* `CONSUME_CEEG_CONTRACT_ARTIFACTS` remains the sole artifact-consumption adapter.
* `ORCHESTRATE_AND_CONSUME` must not be created.
* Contract-status failure is enforced after artifact publication.
* `results/ceeg_compatibility/ceeg_contract_summary.tsv` should be published before a fail-on-contract-error workflow exit.

## CEEG Orchestration Parameters

The optional CEEG orchestration interface uses explicit R2/R3 command parameters:

```groovy
params.ceeg_run_came_overlay_cmd     = null
params.ceeg_run_mapping_contract_cmd = null
params.ceeg_r2_run_dir               = null
params.ceeg_r3_run_dir               = null
params.ceeg_orchestrate_contracts    = false
params.ceeg_validator_created_at     = null
```

Semantics:

* `ceeg_orchestrate_contracts=false` by default.
* When orchestration is disabled, CAME consumes user-supplied artifact directories exactly as in CAME-I0/I1.
* When orchestration is enabled, users must supply the command and run directory for whichever R2/R3 artifact they want generated.
* `ceeg_stub=true` takes precedence over orchestration and prevents external command invocation.
* `ceeg_validator_created_at` is optional and forwarded as `--created-at` only when non-empty.
* `ceeg_validator_created_at` is primarily for deterministic testing and reproducible fixture generation, not ordinary production use.

CAME appends these arguments to external commands:

```text
--run-dir
--out-dir
--validation-mode
--created-at, only when supplied
```

Command values are shell-compatible prefixes, for example:

```bash
python3 /path/to/CEEG/bin/run_came_overlay.py
python3 /path/to/CEEG/bin/run_mapping_contract.py
```

Avoid validator script paths containing spaces unless shell quoting is handled carefully.

## CEEG Orchestration Exit Semantics

CAME distinguishes CEEG validator semantics from orchestration/tooling failure.

| External validator result | Manifest present? | CAME behavior                                                             |
| ------------------------- | ----------------: | ------------------------------------------------------------------------- |
| exit 0                    |               yes | proceed to artifact consumption                                           |
| exit 1                    |               yes | consume artifact and surface invalid contract status                      |
| exit 2                    |               yes | consume artifact and surface fatal contract status                        |
| exit 0/1/2                |                no | orchestration error; checker exits 10                                     |
| other nonzero             |               any | tooling or invocation failure; do not reinterpret as CEEG contract status |

Exit 10 is a CAME orchestration-layer signal for “recognized validator exit code, but expected manifest missing.” It is not a CEEG validation result.

## Contract-Status Failure Semantics

CAME has two distinct failure modes.

### Contract-status failure

A CEEG validator ran, emitted a manifest, and reported exit code 1 or 2.

Expected behavior:

* CAME consumes the artifact.
* CAME publishes `results/ceeg_compatibility/`.
* CAME writes `ceeg_contract_summary.tsv`.
* If `ceeg_fail_on_contract_error=true`, CAME fails after publication.
* Users can inspect the published summary and artifacts.

### Adapter, orchestration, or tooling failure

A command failed unexpectedly, a manifest was missing, or the CAME adapter crashed.

Expected behavior:

* The workflow may fail before normal contract-status reporting.
* Users may need to inspect the Nextflow work directory and command logs.
* Do not reinterpret these failures as CEEG biological findings.

## Stub Mode

`ceeg_stub=true` must remain zero-dependency.

When `ceeg_stub=true`:

* do not require CEEG validator commands;
* do not invoke external CEEG commands;
* preserve existing CAME stub behavior;
* do not manufacture biological or validator-derived content;
* do not silently change default stub outputs.

Stub mode may write selector files needed by the orchestration topology, but those selectors should preserve pass-through or empty behavior.

## Testing Requirements

Every CEEG/CAME integration change in CAME should include:

* direct unit tests for new scripts where practical;
* mock-driven tests that do not require a real CEEG checkout;
* regression tests for CAME-I0 artifact consumption;
* regression tests for CAME-I1 final-report rendering;
* stub-mode tests;
* negative tests for conflict detection and failure semantics where practical.

Default CAME CI must not require a real CEEG checkout.

A real-CEEG integration test may be added only as an optional external profile or opt-in shell test. It must not vendor CEEG into CAME.

## Documentation Requirements

When CAME changes CEEG integration behavior, update relevant docs to describe:

* parameter semantics;
* generated output locations;
* command-prefix contract;
* exit-code semantics;
* distinction between contract-status failure and tooling failure;
* stub-mode behavior;
* default-CI independence from CEEG checkout;
* CEEG/CAME ownership boundary.

## Cross-Repository Implementation Protocol

For any CEEG/CAME integration change, state explicitly:

1. Ownership

   * CEEG-owned: model construction, validation semantics, schemas, validator CLIs.
   * CAME-owned: query-specific analysis, artifact consumption, orchestration, reporting.

2. Boundary

   * CAME may invoke CEEG tools as external commands.
   * CAME must not import, vendor, or reimplement CEEG validators.
   * CEEG must not modify CAME results or implement CAME-specific study analysis.

3. Required tests

   * CEEG: validator/schema/unit tests for produced artifacts.
   * CAME: mock-driven tests independent of CEEG checkout.
   * Optional cross-repo: real CEEG checkout integration test outside default CI.

4. Semantic invariants

   * Preserve `unknown` versus `unknown_unmappable` versus `absent`.
   * Preserve association versus causation.
   * Preserve direct versus indirect regulatory projection.
   * Preserve provenance, evidence, confidence, `system_id`, and `model_id`.
   * Failed mapping is not biological absence.
   * Ambiguous mapping must not be collapsed silently.

5. Stop conditions

   * Stop if a change requires vendoring.
   * Stop if a change requires cross-imports.
   * Stop if a change requires silent schema drift.
   * Stop if default CAME CI would depend on a CEEG checkout.
   * Stop if biological interpretation would move to the wrong repository.

## Future Work Not Owned by Current CAME Integration

Do not implement these without a new explicit design:

* R4/R5 comparability or admissibility;
* candidate-prioritization use of CEEG contract outputs;
* orthology/GRA/phenotype-omics use of R3 mapping summaries;
* treating unmapped features as absence;
* controlled-vocabulary expansion without CEEG-side schema agreement;
* automatic CEEG model rebuilding from CAME;
* silent repair of CEEG bundles or artifacts.

## Review Checklist

Before committing CEEG/CAME integration changes in CAME, confirm:

* no CEEG validator vendoring;
* no CEEG Python imports;
* no CEEG model rebuilding;
* no default behavior change outside the scoped stage;
* no `ceeg_compatibility` inclusion in `--run_stage all`;
* no biological inference added from contract status;
* no analysis-stage integration;
* no ambiguous mapping collapse;
* no failed-mapping-as-absence behavior;
* CAME tests pass without a real CEEG checkout;
* docs describe user-visible failure modes.