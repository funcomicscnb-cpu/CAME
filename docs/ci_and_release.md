# CI And Release

Stage 22 completes public v0.1 release preparation by combining CI hardening, local release-bundle validation, release metadata, licensing, citation metadata, and reproducibility reporting. It does not add biological analyses or change default pipeline behavior.

## CI Jobs

The GitHub Actions workflow in `.github/workflows/ci.yml` runs on pull requests and pushes to `main` or `master`.

- `fast-validation`: installs Java, Nextflow, Python dependencies, and minimal R dependencies; then runs Stage 14 packaging checks and lightweight regression tests.
- `end-to-end-stub`: installs the same lightweight runtime and runs the Stage 13 end-to-end stub orchestration test with nested regressions disabled.

CI intentionally does not install heavy real-mode bioinformatics tools and does not require DESeq2. Missing real-mode tools can appear as optional missing entries in `environment/tool_versions.tsv`.

Stage 15 real-mode smoke validation is available as an optional manual
`workflow_dispatch` job. That job runs `bash tests/test_real_mode_smoke.sh --soft`
as a compact inventory and skips unavailable real-mode execution paths.

## Local Test Matrix

Run Stage 14 checks:

```bash
python3 bin/print_versions.py
python3 bin/validate_release_bundle.py
bash tests/test_release_packaging.sh
```

Run the lightweight regression suite:

```bash
bash tests/test_metadata_validation.sh
bash tests/test_profile_examples.sh
bash tests/test_study_profile_validation.sh
bash tests/test_phenotype_processing.sh
bash tests/test_phylo_hypothesis.sh
bash tests/test_bulk_omics.sh
bash tests/test_differential_omics.sh
bash tests/test_orthology_projection.sh
bash tests/test_gra_analysis.sh
bash tests/test_phenotype_omics_integration.sh
bash tests/test_candidate_prioritization.sh
bash tests/test_functional_interpretation.sh
bash tests/test_final_report.sh
CAME_STAGE13_SKIP_REGRESSION=true bash tests/test_end_to_end_orchestration.sh
```

The full Stage 13 script without `CAME_STAGE13_SKIP_REGRESSION=true` also runs nested regressions and is useful before release tagging when runtime is acceptable.

Run optional Stage 15 real-mode smoke checks in an environment with bioinformatics
tools available:

```bash
python3 bin/check_real_mode_tools.py --outdir results/real_mode_smoke --mode soft
python3 bin/make_real_mode_smoke_data.py --outdir assets/test_data/real_mode_smoke
bash tests/test_real_mode_smoke.sh --soft
```

Use `--strict` when missing requested real-mode tools should fail the check.

## Release Checklist

1. Confirm `VERSION` and `CHANGELOG.md` match the intended tag.
2. Confirm `LICENSE` is GPL-3.0-only and `CITATION.cff` contains no fabricated authorship, repository, or release-date metadata.
3. Run `python3 bin/print_versions.py`.
4. Run `python3 bin/validate_release_bundle.py`.
5. Run all local tests listed above.
6. Run `--run_stage all` in stub mode with the bundled example assets.
7. Inspect `results/final/release_checks/release_bundle_validation.tsv`.
8. Inspect `results/final/release_checks/came_release_checks.tsv`.
9. Inspect `results/all/summary/came_all_run_summary.tsv`.
10. Review `results/final/report/came_final_report.html` and `.md`.

Resolve all `ERROR` records before tagging. `WARNING` records document optional or unavailable release evidence and should be reviewed.

## Tagging Procedure

```bash
git status --short
git tag -a v0.1.0 -m "CAME v0.1.0"
git push origin v0.1.0
```

Use the repository's normal review and approval process before pushing a release tag.

## v0.1 Acceptance Criteria

- Core regression tests and profile example tests pass in stub mode.
- Stage 15 soft real-mode smoke check passes or skips unavailable tool paths with warnings.
- `--run_stage all` completes with bundled example inputs and writes final reports.
- CI workflow, issue/PR templates, Dependabot config, environment files, installation docs, release docs, version metadata, GPL-3.0-only license, citation metadata, and changelog are present.
- `bin/print_versions.py` writes `environment/tool_versions.tsv`.
- `bin/validate_release_bundle.py` writes `results/final/release_checks/release_bundle_validation.tsv` with no `ERROR` records for the release bundle.
- Core logic remains phenotype-agnostic; profile-specific terms remain in profiles, docs, tests, examples, or generated outputs.
- NanoSeq and mutation profiling are documented as skipped, not implemented.
- Optional scaffold stages are documented as optional and not production biological analysis implementations.

## Known Limitations

- Stub-mode CI is the v0.1 release gate; real-mode execution beyond Stage 15 smoke checks must be validated in an environment with real data, references, and tools.
- `--resume_completed_stages` is documented/reporting only; actual process reuse uses Nextflow `-resume`.
- Stage status checks are presence/non-empty checks, not content hashing.
- DESeq2 is optional for smoke tests; fallback differential paths are expected when DESeq2 is absent.
- Authorship, public repository URL, release date, and copyright holder must be resolved before the final public tag.
