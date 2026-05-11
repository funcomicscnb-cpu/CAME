# CEEG/CAME Semantic Invariants

This document states the semantic invariants that govern how CAME handles CEEG contract
artifacts. These invariants apply to all stages that consume CEEG outputs, beginning with
the optional `ceeg_compatibility` interface.

This document is explanatory only. It does not add validation behavior in CAME-I0.

---

## Mapping invariants

**Failed mapping is not biological absence.**
A feature that does not map to a target in R3 is an unresolved mapping, not evidence that
the feature is absent. Absence requires direct biological evidence, not mapping failure.

**Unmapped is not absent.**
Features in `unmapped_features.tsv` must be reported as unmapped. They must not be
silently dropped or treated as absent in downstream scoring, annotation, or reporting.

**Ambiguous mapping is not collapsed to one-to-one.**
Features in `ambiguous_mappings.tsv` have multiple candidate targets. They must be
preserved with all candidates. One-to-many mappings must not be collapsed into a single
resolved target without explicit documented reasoning, disambiguation logic, and a
separate output representing the collapsed result.

**Orthology is not identity.**
Orthologous features are homologous, not identical. Orthogroup membership does not imply
sequence identity, functional equivalence, or regulatory equivalence.

---

## Conservation invariants

**Mapping audit is not biological conservation.**
The R3 mapping contract validates the structure of a mapping run. It does not assess whether
features are functionally conserved between species. A passed R3 audit means the mapping
run was structurally valid; it says nothing about biological conservation.

**Direct regulatory projection is not functional conservation.**
`evidence_status=projected_direct` in a CEEG bundle means a regulatory element was aligned
to a reference using direct sequence methods. It does not mean the regulatory element is
functionally conserved. Functional conservation requires independent biological evidence.

**Association is not causation.**
Statistical associations between phenotype and regulatory/omics features do not imply
causal relationships.

---

## Identity and labeling invariants

**Same metadata label is not system congruence.**
Two nodes or systems sharing a `biological_system` label or ontology term do not
automatically represent congruent biological systems in different species. Congruence
requires explicit comparative evidence.

**Provenance, evidence, and confidence identifiers must be preserved.**
`run_id`, `ceeg_bundle_status`, `ceeg_schema_version`, `validator_name`, `validator_version`,
and `created_at` fields in CEEG manifests must be copied verbatim into CAME-side summaries.
They must not be modified, normalized, or dropped.

---

## CEEG exit-code invariants

| Exit code | Meaning | CAME treatment |
|---|---|---|
| 0 | Compatible / valid | Summarize as `compatible` or `valid`. |
| 1 | Invalid contract | Summarize as `invalid`. Fail or warn per `--ceeg_fail_on_contract_error`. |
| 2 | Fatal contract failure | Summarize as `fatal`. Fail or warn per `--ceeg_fail_on_contract_error`. |

Exit codes must not be coerced, normalized, or silently treated as 0.

---

## What CAME-I0 does not infer

CAME-I0 explicitly does not infer:

- Biological absence from failed mapping
- Conservation from mapping audit
- Functional equivalence from orthogroup co-membership
- Causal relationships from statistical associations
- System congruence from shared label
- One-to-one resolution from ambiguous mapping
- Indirect projection from direct projection evidence
