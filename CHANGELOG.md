# Changelog

## 0.1.0

- Added Stage 22 public release preparation: GPL-3.0-only licensing, citation metadata, issue and pull request templates, Dependabot configuration, versioning policy, and v0.1 release notes.
- Hardened release bundle validation for release metadata, README links, SemVer parsing, GPL/CITATION fields, NanoSeq overclaim checks, and optional scaffold documentation.
- Preserved phenotype-agnostic core behavior, default `--run_stage all` behavior, and existing stage interfaces through Stage 20.
- Documented that optional scaffold stages are not production biological analysis implementations and that NanoSeq/mutation profiling is intentionally skipped for v0.1.
- Known limitations: stub-mode validation is the release gate, real-mode production readiness depends on caller-provided data and tools, and release-date/copyright fields still require final public-release decisions.
