# CAME Comparability Modes

CAME exposes a `--comparability_mode` parameter that names how cross-condition or cross-system comparability is established for a given run. The mode is declared in the final report (Markdown and HTML) so the audit trail makes the basis of comparison explicit.

## Implemented values

Only two values are currently implemented and accepted by the pipeline:

- `design_assumed` — default. CAME runs as a standard comparative-omics pipeline. CEEG R2/R3 contract artifacts are not consumed.
- `ceeg_contract_checked` — CAME consumed CEEG R2/R3 contract artifacts (either user-supplied directories or generated through the optional orchestration interface). The report surfaces contract and mapping-artifact status from those artifacts.

These are the only values accepted by `--comparability_mode`. Supplying any other value is an error.

## Meanings

### `design_assumed`

- Standard CAME mode. CAME runs without consuming CEEG comparability evidence.
- Cross-condition or cross-system comparability is assumed from the user's experimental design, supplied feature mappings, and input data.
- The final report states explicitly that no CEEG R2/R3 contract artifacts were consumed in this run.
- R1-only bundle import (i.e. setting `--ceeg_model_bundle` without supplying R2/R3 artifacts or orchestration commands) is still compatible with `design_assumed`. R1 is bundle import / scaffold, not contract checking.

### `ceeg_contract_checked`

- CAME consumed CEEG R2/R3 contract artifacts in this run, either directly via `--ceeg_r2_overlay_dir` / `--ceeg_r3_mapping_dir`, or by orchestrating external CEEG validator commands via `--ceeg_orchestrate_contracts true`.
- The final report surfaces contract status, mapping-artifact status, validator exit codes, and adapter diagnostics.
- The final report's Comparability Mode section in `ceeg_contract_checked` runs reads, verbatim: *"CAME consumed CEEG R2/R3 contract artifacts in this run. These artifacts report contract and mapping-artifact status. They do not by themselves constitute R4 comparability validation or R5 admissibility validation."*

## Future modes (not implemented)

### Naming convention

Future CAME mode names must reflect what CAME actually consumed or validated:

- **`_consumed` suffix** for layers that consume an evidence-reporting contract. CAME consumed the artifact; the artifact reports evidence state, not a verdict. Using `_consumed` keeps the mode name honest about that.
- **`_validated` suffix** only when the underlying contract semantics explicitly justify a validation claim. A `_validated` mode would assert that CAME (via the consumed contract) validated the thing it names.

R4 (currently in CEEG-side design at [CEEG `docs/r4_comparability_contract.md`](../../CEEG/docs/r4_comparability_contract.md)) is an **evidence-bearing comparability contract**. It emits structured evidence states (e.g. `evidence_supports_comparability`, `evidence_against_comparability`, `evidence_insufficient_for_comparability`, `comparability_not_assessable`) and explicitly does not emit verdicts: per CEEG R4 §1.1, "R4 statuses describe the state of evidence regarding a comparability hypothesis under a bound analysis context. They are not assertions about the systems or entities themselves."

R4 is therefore evidence-state reporting, not biological comparability validation. A future CAME mode consuming R4 artifacts must use the `_consumed` form.

### Proposed future name (non-authoritative)

When R4 consumption is added (future CAME-I3 stage), the proposed name is:

```text
ceeg_comparability_evidence_consumed
```

Rationale:

- uses the `_consumed` suffix, correct for an evidence-reporting layer;
- is **semantic** (describes what was consumed: comparability evidence) rather than R-layer-numbered, matching the precedent of `ceeg_contract_checked` (which does not encode `r2_r3` in the user-facing name);
- remains forward-compatible if future contract revisions preserve evidence-state semantics.

The earlier draft placeholder `ceeg_r4_evidence_consumed` (sketched in CEEG R4 §13) is **rejected** as the final name. It is layer-numbered rather than semantic, and bakes the R-layer identifier into a user-facing mode in a way the existing CAME vocabulary does not.

### Names not currently accepted

- **`ceeg_comparability_validated`** — not accepted. R4 does not validate biological comparability as a verdict; it reports evidence state. The `_validated` suffix would overclaim.
- **`ceeg_admissibility_validated`** — not accepted. R5 admissibility remains future and unscoped; no R5 design exists yet.

None of these names — proposed or rejected — are active enum values or reserved implementation values. They appear only in this future-prose section. They are not part of any allowed-values list, `choices=[...]` entry, params default, validator branch, or test fixture in CAME's code or tests. Reconciliation against CEEG's R4 design must complete and the F0e R4 fixture packet must stabilize before any CAME-I3 prompt is authored or any of these names is promoted to an active value.

## When to use each mode

- Use `design_assumed` for standard within-design comparative omics, including R1-only bundle import.
- Use `ceeg_contract_checked` when supplying CEEG R2/R3 contract artifacts, or when orchestrating the external CEEG R2/R3 validators through CAME.

CAME validates that the declared mode is consistent with the supplied inputs. Mixing `ceeg_contract_checked` with no R2/R3 inputs, or `design_assumed` with supplied R2/R3 inputs or orchestration commands, is a parameter-validation error.

Consistency is enforced at two layers:

- **Input-flag layer (`main.nf`):** rejects any run whose declared `--comparability_mode` contradicts the supplied `--ceeg_r2_overlay_dir` / `--ceeg_r3_mapping_dir` / orchestration flags.
- **On-disk layer (`bin/render_final_report.py`):** the final-report renderer also reads `results/ceeg_compatibility/ceeg_contract_summary.tsv` and rejects any render whose declared mode contradicts the R2/R3 rows actually present on disk. This catches the case where a user re-runs `--run_stage final_report` against an existing results directory: a stale `ceeg_contract_checked` results tree cannot be re-rendered as `design_assumed`, and vice versa, without an explicit mode change or a clean results tree.

## Anti-overclaim rules

This document does not restate or fork CAME's mapping-status invariants. Those are defined canonically in [`AGENTS.md`](../AGENTS.md), specifically:

- The "Non-Negotiable CAME/CEEG Boundary" section (around lines 53–69) — including: failed mapping is not biological absence; ambiguous mapping must not be collapsed silently; failed contracts are not biological inference; missing CEEG artifacts are not biological evidence.
- The "Semantic invariants" section (around lines 286–293) — including: `unknown` vs `unknown_unmappable` vs `absent`; association vs causation; direct vs indirect regulatory projection; provenance/evidence/confidence preservation.

The Track A–specific rule documented here, and only here, is:

> **R2/R3 contract success is not R4 comparability-evidence consumption and does not substitute for R4 evidence-state reporting. R4 itself does not validate biological comparability; it reports structured evidence state. R2/R3 and R4 do not constitute R5 admissibility validation.** A `ceeg_contract_checked` declaration in the final report indicates that contract artifacts were consumed. It does not by itself establish that the underlying biological systems are comparable.

## Cross-references

- [`docs/ceeg_compatibility.md`](ceeg_compatibility.md) — CEEG R2/R3 contract-artifact consumption, orchestration parameters, exit-code semantics.
- [`docs/final_report.md`](final_report.md) — final-report structure and the placement of the Comparability Mode section.
- [`AGENTS.md`](../AGENTS.md) — controlling implementation contract for CAME's CEEG integration boundary.
