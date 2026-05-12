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

Future CEEG R4/R5 contracts may add additional `ceeg_*_validated` modes once their schemas and validator semantics are defined in a future, explicit design. Until then:

- No `ceeg_comparability_validated` value is accepted.
- No `ceeg_admissibility_validated` value is accepted.
- These names appear only in this future-prose paragraph. They are not part of any allowed-values list, enum, or `choices=[...]` entry in CAME's code or tests.

When a future R4 design lands (Track B), the proposed mode name must be compared against this vocabulary before any CAME-I3 R4 artifact-consumption stage is created.

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

> **R2/R3 contract success is not R4 biological comparability validation, and not R5 admissibility validation.** A `ceeg_contract_checked` declaration in the final report indicates that contract artifacts were consumed. It does not by itself establish that the underlying biological systems are comparable.

## Cross-references

- [`docs/ceeg_compatibility.md`](ceeg_compatibility.md) — CEEG R2/R3 contract-artifact consumption, orchestration parameters, exit-code semantics.
- [`docs/final_report.md`](final_report.md) — final-report structure and the placement of the Comparability Mode section.
- [`AGENTS.md`](../AGENTS.md) — controlling implementation contract for CAME's CEEG integration boundary.
