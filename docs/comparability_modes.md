# CAME Comparability Modes

CAME exposes a `--comparability_mode` parameter that names how cross-condition or cross-system comparability is established for a given run. The mode is declared in the final report (Markdown and HTML) so the audit trail makes the basis of comparison explicit.

## Implemented values

Three values are currently implemented and accepted by the pipeline:

- `design_assumed` — default. CAME runs as a standard comparative-omics pipeline. No CEEG R2/R3 contract artifacts and no CEEG R4 comparability evidence artifacts are consumed.
- `ceeg_contract_checked` — CAME consumed CEEG R2/R3 contract artifacts (either user-supplied directories or generated through the optional orchestration interface). The report surfaces contract and mapping-artifact status from those artifacts.
- `ceeg_comparability_evidence_consumed` — CAME consumed CEEG R4 comparability evidence artifacts (CAME-I3). The report surfaces structured evidence-state status under a bound analysis context. R2/R3 artifacts may also be consumed in the same run; if so, both sections appear in the final report.

These are the only values accepted by `--comparability_mode`. Supplying any other value is an error.

## Meanings

### `design_assumed`

- Standard CAME mode. CAME runs without consuming CEEG comparability evidence.
- Cross-condition or cross-system comparability is assumed from the user's experimental design, supplied feature mappings, and input data.
- The final report states explicitly that no CEEG R2/R3 contract artifacts were consumed in this run.
- R1-only bundle import (i.e. setting `--ceeg_model_bundle` without supplying R2/R3 artifacts, R4 artifacts, or orchestration commands) is still compatible with `design_assumed`. R1 is bundle import / scaffold, not contract checking.

### `ceeg_contract_checked`

- CAME consumed CEEG R2/R3 contract artifacts in this run, either directly via `--ceeg_r2_overlay_dir` / `--ceeg_r3_mapping_dir`, or by orchestrating external CEEG validator commands via `--ceeg_orchestrate_contracts true`.
- The final report surfaces contract status, mapping-artifact status, validator exit codes, and adapter diagnostics.
- The final report's Comparability Mode section in `ceeg_contract_checked` runs reads, verbatim: *"CAME consumed CEEG R2/R3 contract artifacts in this run. These artifacts report contract and mapping-artifact status. R2/R3 contract artifacts do not substitute for R4 comparability-evidence reporting. They do not by themselves constitute R4 comparability validation or R5 admissibility validation."*

### `ceeg_comparability_evidence_consumed`

- CAME consumed CEEG R4 comparability evidence artifacts (CAME-I3) via `--ceeg_r4_comparability_dir <dir>`. The directory is read-only; CAME does not invoke the R4 validator.
- The final report surfaces R4 manifest fields, per-comparison evidence-state status, evidence counts, and limitation rows.
- The final report's Comparability Mode section in `ceeg_comparability_evidence_consumed` runs reads, verbatim: *"CAME consumed CEEG R4 comparability evidence artifacts in this run. These artifacts report structured evidence-state status under a bound analysis context. They do not validate biological comparability as a verdict, do not establish R5 admissibility, and do not alter CAME analysis outputs or candidate rankings."*
- R2/R3 artifacts may be supplied in the same run; the final report renders both sections side by side. R4 artifacts are not required to also engage R2/R3.
- CAME-I3 does not implement R4 orchestration. R4 orchestration may be added by a later CAME-I4 task if needed.

## Names not currently accepted

- **`ceeg_comparability_validated`** — not accepted. R4 does not validate biological comparability as a verdict; it reports evidence state. The `_validated` suffix would overclaim.
- **`ceeg_admissibility_validated`** — not accepted. R5 admissibility remains future and unscoped; no R5 design exists yet.

These names are not active enum values or reserved implementation values. They are not part of any allowed-values list, `choices=[...]` entry, params default, validator branch, or test fixture in CAME's code or tests.

## When to use each mode

- Use `design_assumed` for standard within-design comparative omics, including R1-only bundle import.
- Use `ceeg_contract_checked` when supplying CEEG R2/R3 contract artifacts, or when orchestrating the external CEEG R2/R3 validators through CAME.
- Use `ceeg_comparability_evidence_consumed` when supplying externally generated CEEG R4 comparability evidence artifacts via `--ceeg_r4_comparability_dir`.

CAME validates that the declared mode is consistent with the supplied inputs. Mixing `ceeg_contract_checked` with no R2/R3 inputs, mixing `design_assumed` with supplied R2/R3 inputs, R4 inputs, or orchestration commands, supplying R4 under `ceeg_contract_checked`, or omitting R4 under `ceeg_comparability_evidence_consumed`, is a parameter-validation error.

Consistency is enforced at two layers:

- **Input-flag layer (`main.nf`):** rejects any run whose declared `--comparability_mode` contradicts the supplied `--ceeg_r2_overlay_dir` / `--ceeg_r3_mapping_dir` / `--ceeg_r4_comparability_dir` / orchestration flags.
- **On-disk layer (`bin/render_final_report.py`):** the final-report renderer reads `results/ceeg_compatibility/ceeg_contract_summary.tsv` and `results/ceeg_compatibility/ceeg_r4_comparability_summary.tsv` and rejects any render whose declared mode contradicts the rows actually present on disk. The full (mode, R2/R3 rows present, R4 rows present) truth table is implemented as a single centralized lookup, so every invalid combination errors with a message that names the declared mode, which rows were found or missing, the relevant summary file path, and the corrective action. This catches re-rendering against a stale results directory.

## Anti-overclaim rules

This document does not restate or fork CAME's mapping-status invariants. Those are defined canonically in [`AGENTS.md`](../AGENTS.md), specifically:

- The "Non-Negotiable CAME/CEEG Boundary" section (around lines 53–69) — including: failed mapping is not biological absence; ambiguous mapping must not be collapsed silently; failed contracts are not biological inference; missing CEEG artifacts are not biological evidence.
- The "Semantic invariants" section (around lines 286–293) — including: `unknown` vs `unknown_unmappable` vs `absent`; association vs causation; direct vs indirect regulatory projection; provenance/evidence/confidence preservation.

The Track A / CAME-I3 rule documented here, and only here, is:

> **R2/R3 contract success is not R4 comparability-evidence consumption and does not substitute for R4 evidence-state reporting. R4 itself does not validate biological comparability; it reports structured evidence state. R2/R3 and R4 do not constitute R5 admissibility validation.** A `ceeg_contract_checked` declaration in the final report indicates that R2/R3 contract artifacts were consumed. A `ceeg_comparability_evidence_consumed` declaration indicates that CEEG R4 comparability evidence artifacts were consumed and reported as evidence state. Neither declaration by itself establishes that the underlying biological systems are comparable, equivalent, conserved, or admissible.

## Cross-references

- [`docs/ceeg_compatibility.md`](ceeg_compatibility.md) — CEEG R2/R3 contract-artifact consumption, orchestration parameters, exit-code semantics.
- [`docs/final_report.md`](final_report.md) — final-report structure and the placement of the Comparability Mode section.
- [`AGENTS.md`](../AGENTS.md) — controlling implementation contract for CAME's CEEG integration boundary.
