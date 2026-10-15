# Changelog

## 0.1.0

- Corrected successful RNA/ATAC and integer-sum GRA DESeq2 rows to report the fitted response-versus-baseline effect and RNA/ATAC base mean alongside the same fit's statistics and p-values, preserving missing values and filtering semantics. Descriptive group means and global total-count-scaled files retain their existing definitions, now documented explicitly.
- Omit incomplete, single-level or non-estimable RNA/ATAC batch covariates with a warning, retaining all selected samples. Added strict independent DESeq2 oracle checks to the existing optional validation job and explicit 12-significant-digit result serialization.

- Confirmed release metadata: release date `2026-10-15`, exact notice `Copyright (C) 2026 David Juan`, and unchanged GPL-3.0-only licensing. These decisions do not assert that tagging or publication has occurred.

- Added Stage 22 public release preparation: GPL-3.0-only licensing, citation metadata, issue and pull request templates, Dependabot configuration, versioning policy, and v0.1 release notes.
- Hardened release bundle validation for release metadata, README links, SemVer parsing, GPL/CITATION fields, NanoSeq overclaim checks, and optional scaffold documentation.
- Added v0.1 real-usability hardening: canonical real-mode schemas, default CAME container image wiring, Slurm profile stubs, `--list_stages`, explicit `--run_stage all` excluded-stage warnings, strict real-tool fixture CI, and structured RNA/ATAC/WGS/PGLS limitation metadata.
- Added `correction_method` to differential RNA/ATAC and GRA activity outputs.
- Added WGS limitation fields `bqsr_applied`, `calling_mode`, and `joint_genotyping` to WGS QC and summary outputs.
- Preserved phenotype-agnostic core behavior, default `--run_stage all` behavior, and existing stage interfaces through Stage 20.
- Documented that optional scaffold stages are not production biological analysis implementations and that NanoSeq/mutation profiling is intentionally skipped for v0.1.
- Known limitations: stub-mode validation is the release gate, real-mode production readiness depends on caller-provided data and tools, and native locked-environment validation remains a separate release check.
