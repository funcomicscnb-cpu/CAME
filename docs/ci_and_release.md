# CI And Release

The v0.1 CI and release checks focus on deterministic stub-mode behavior, package metadata, and lightweight real-mode contract checks. Per-sample real-mode routing and QC contract tests run without requiring heavy bioinformatics tools in default CI.

## CI Jobs

The GitHub Actions workflow in `.github/workflows/ci.yml` runs on pull requests, on pushes to `main` or `master`, and on manual `workflow_dispatch`. Pushes to other branches do not trigger it by themselves; they run CI only through the `pull_request` event of an open pull request.

- `fast-validation`: installs Java, Nextflow, Python dependencies, and minimal R dependencies; then runs packaging checks and lightweight regression tests.
- `end-to-end-stub`: installs the same lightweight runtime and runs the end-to-end stub orchestration test with nested regressions disabled.
- `real-mode-ci`: builds the local Docker image from the current commit, verifies Java/Nextflow and strict real-mode tool availability, runs `tests/test_real_mode_fixtures.sh --strict` inside the image, then runs the locked-image DESeq2 checks described below.

The default lightweight jobs do not install heavy real-mode bioinformatics tools and do not require DESeq2. Real-tool fixture execution is isolated in the container-backed `real-mode-ci` job.

`tests/test_deseq2_consistency.R` is a strict DESeq2 oracle suite. It requires DESeq2 and successful fits: absence or unexpected fallback fails. A fixed heterogeneous count fixture tests RNA/ATAC and eligible integer-sum GRA against independently constructed DESeq2 fits, with keyed field and exact missingness comparisons at tolerance `1e-8` (relative error for p-values and adjusted p-values; absolute error divided by `max(1, abs(reference))` for other fields). It covers compositional imbalance, filtering, ordering, batch omission/adjustment and forced fallback, including fallback labels for filtered rows. Per-case counts of missing p-values, missing adjusted p-values and finite p-values with missing adjusted p-values are written to `missingness.tsv`; independent-filter-only missingness may be zero in a given DESeq2 version, provided CAME and the oracle agree exactly. Invocation, `sessionInfo()` and R/DESeq2 versions are recorded before the DESeq2 availability check, so a missing package fails with evidence (`outcome.txt` reads `FAIL DESeq2 unavailable`; otherwise `INCOMPLETE` until `PASS`). These same-package comparisons establish the tested field contracts, not production biological validity. Lightweight regression checks remain usable without DESeq2.

The suite runs in two distinct environments:

- Locked-image validation (`real-mode-ci`, every workflow trigger: pull requests, pushes to `main`/`master`, and `workflow_dispatch`): after the strict fixtures, and also when they fail provided the image built, the job runs the strict suite, `tests/test_differential_omics.sh` and `tests/test_gra_analysis.sh` inside `came-test:pr`, using the source packaged in the image and the R/DESeq2 versions resolved from the committed `environment/conda-linux-64.lock`. Only `$RUNNER_TEMP/came-real-mode-evidence/deseq2-locked-image/` is mounted (at `/evidence`); no host source is overlaid. It retains packaged SHA-256 hashes of the two differential R scripts, the strict test, its fixture, both shell tests and the lock; the locked and installed `r-base`/`bioconductor-deseq2` records; strict-suite versions, comparisons, missingness counts, oracle outputs and command logs; and per-check logs and exit statuses. Provenance is checked before the tests: `sha256sum` must succeed and record all seven hashes, the lock must contain exactly one record each for `r-base` and `bioconductor-deseq2`, and `conda list` must succeed and list exactly one installed record for each. Failures are written to `provenance-diagnostics.txt` and `provenance-exit-status.txt` (0 complete, 1 incomplete); partial outputs are kept. Incomplete provenance fails the step, but all three checks still run. Recorded versions are not compared to the lock in CI; that comparison belongs to evidence review. Each check runs through `tee` with its own exit status preserved, and the step fails if provenance is incomplete or any check fails. Files created by the container's root user are made world-readable (`chmod -R a+rX`) inside this subdirectory only, and are uploaded by the existing always-run `real-mode-evidence-*` artifact.
- Optional current-release validation (`deseq2-validation`, `workflow_dispatch` only): installs the current R release via `r-lib/actions/setup-r` and resolves Bioconductor packages at run time, possibly from an `actions/cache` entry. Its R and DESeq2 versions are therefore not locked; they are recorded in `results/deseq2-validation/versions.txt` and `sessionInfo.txt` and uploaded as `deseq2-evidence-*`. Agreement in this job does not imply agreement in the locked image, or vice versa.

Real-mode smoke validation is also available as an optional manual `workflow_dispatch` job. That job runs `bash tests/test_real_mode_smoke.sh --soft` as a compact inventory and skips unavailable real-mode execution paths.

## Local Test Matrix

Run release checks:

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

Run real-mode routing and QC contract checks:

```bash
bash tests/test_real_mode_core.sh
bash tests/test_real_rna_mode.sh
bash tests/test_real_atac_mode.sh
bash tests/test_real_mode_scaleout.sh
bash tests/test_real_qc_contracts.sh
python3 -m py_compile bin/*.py
```

Run optional real-mode smoke checks in an environment with bioinformatics tools available:

```bash
python3 bin/check_real_mode_tools.py --outdir results/real_mode_smoke --mode soft
python3 bin/make_real_mode_smoke_data.py --outdir assets/test_data/real_mode_smoke
bash tests/test_real_mode_smoke.sh --soft
bash tests/test_real_mode_fixtures.sh --soft
```

Use `--strict` when missing requested real-mode tools should fail the check. The CAME tests also check that missing-tool failures occur for intended tool availability reasons, not malformed metadata or broken Nextflow wiring.

Generate the linux-64 container lock after changing `environment/came_environment.yml`:

```bash
conda-lock lock -f environment/came_environment.yml -p linux-64 -k explicit --filename-template environment/conda-{platform}.lock --micromamba --strip-auth
```

An environment solved on Linux from the same YAML can also be frozen with
`conda list --explicit --md5`. Both formats are accepted: the release checker
requires one `@EXPLICIT` marker, the linux-64 platform header, and auth-free
HTTPS package URLs for linux-64/noarch artifacts with lowercase 32-character
MD5 checksums, matching the image’s Conda 24.5.0
[explicit URL parser](https://github.com/conda/conda/blob/24.5.0/conda/misc.py).
Uppercase MD5 and bare or prefixed SHA256 fragments are rejected. Exports
containing `# no URL for:` omission comments are incomplete and rejected. Explicit exports do not capture pip-installed packages.
The optional `conda-lock` `input_hash` comment is generator metadata, not a
Conda explicit-format requirement or proof that the lock matches the YAML.
Preserve any metadata emitted by the generator; do not manufacture it when
exporting an existing environment. Lock validation does not replace building
the image and executing its strict fixtures.

Build the release image locally:

```bash
docker build -t came-test:pr .
docker run --rm came-test:pr nextflow -version
docker run --rm came-test:pr python3 bin/check_real_mode_tools.py --mode strict --omics-types rnaseq,atacseq,wgs
docker run --rm -v "$PWD:/came" -w /came came-test:pr bash tests/test_real_mode_fixtures.sh --strict
```

The publish workflow pulls the pushed `ghcr.io/funcomicscnb-cpu/came:<VERSION>` image, records the repo digest, runs the strict real-mode tool inventory, and executes the strict fixture test inside the published image before uploading container metadata.

## Fixture Strategy

Default CI uses tiny synthetic fixtures and routing checks. It should not download large public datasets or require STAR, Bowtie2, MACS3, BWA-MEM2, GATK, samtools, bedtools, FastQC, featureCounts, or MultiQC in normal pull-request jobs.

CAME fixtures live under `assets/test_data/real_mode_fixtures/` and are generated by:

```bash
python3 bin/make_real_mode_fixtures.py --outdir assets/test_data/real_mode_fixtures --force
python3 bin/validate_real_mode_fixtures.py --fixture-dir assets/test_data/real_mode_fixtures
```

The fixture tests assert contracts, not biological quality. Optional ENCODE ATAC, pig `GSE143288 / PRJNA597497`, and WGS public-data fixtures require manual accession-level curation, checksums, and explicit opt-in execution outside default CI.

## Release Checklist

1. Confirm `VERSION` and `CHANGELOG.md` match the intended tag.
2. Confirm `LICENSE` is GPL-3.0-only and `CITATION.cff` contains no fabricated release-date, affiliation, or identifier metadata.
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
- CAME soft real-mode smoke checks pass or skip unavailable tool paths with warnings.
- Real-mode routing and QC contract tests pass.
- Real-mode fixture generation and soft validation pass; unavailable external real-mode tools skip only executable fixture paths.
- Container-backed strict real-mode fixture CI passes against the committed tiny fixtures.
- `--run_stage all` completes with bundled example inputs and writes final reports.
- CI workflow, issue/PR templates, Dependabot config, environment files, installation docs, release docs, version metadata, GPL-3.0-only license, citation metadata, and changelog are present.
- `bin/print_versions.py` writes `environment/tool_versions.tsv`.
- `bin/validate_release_bundle.py` writes `results/final/release_checks/release_bundle_validation.tsv` with no `ERROR` records for the release bundle.
- Core logic remains phenotype-agnostic; profile-specific terms remain in profiles, docs, tests, examples, or generated outputs.
- NanoSeq and mutation profiling are documented as skipped, not implemented.
- Optional interfaces are documented as optional and not production biological analysis implementations.

## Known Limitations

- Stub-mode CI is the default release gate; real-mode execution beyond smoke and routing tests must be validated in an environment with real data, references, tools, and mammalian-scale resources.
- CAME is a hardened baseline, not a production-certified non-model mammal multi-omics platform.
- `--resume_completed_stages` is documented/reporting only; actual process reuse uses Nextflow `-resume`.
- Stage status checks are presence/non-empty checks, not content hashing.
- DESeq2 is optional for smoke tests; fallback differential paths are expected when DESeq2 is absent.
- Release metadata is confirmed: release date `2026-10-15` and exact notice `Copyright (C) 2026 David Juan`; GPL-3.0-only remains unchanged. This records metadata decisions, not completion of tagging or publication. Existing container-publication behavior is unchanged.
