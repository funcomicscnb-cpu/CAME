# CAME Versioning Policy

CAME uses semantic versioning for public releases: `MAJOR.MINOR.PATCH`.

## Version Meaning

- `MAJOR` changes may break public command-line behavior, documented input contracts, or output table contracts.
- `MINOR` changes add compatible features, optional stages, documentation, or output fields that do not break existing v0.x contracts.
- `PATCH` changes fix bugs, documentation mistakes, packaging issues, or tests without changing expected workflow behavior.

`v0.1.0` is the first public release-preparation version. It validates the repository shape, example metadata, stub-mode orchestration, final reporting, and documented interfaces. It is not a promise that every optional scaffold is a production biological analysis.

## Updating VERSION

The root `VERSION` file is the source of truth for the software version shown in release metadata and provenance. Before tagging a release:

1. Update `VERSION` to the intended SemVer value.
2. Update `CHANGELOG.md` with the same version.
3. Update release notes when the public scope changes.
4. Run the release-bundle validator and packaging tests.

## Changelog Policy

`CHANGELOG.md` should summarize user-visible changes by version. Each release entry should call out major implemented stages, documentation or packaging changes, compatibility notes, and known limitations. Do not describe future work as completed.

## Stub Mode And Real Mode

Stub-mode validation is the v0.1 release gate. It exercises workflow orchestration and report generation with deterministic synthetic or placeholder data.

Real-mode production readiness is narrower. Real-mode runs require caller-provided data, references, indexes, and external tools. A stage is production-ready only when the documentation says it performs the real analysis and the tests cover the relevant path.

## Optional Scaffold Stages

Optional scaffold stages define future-facing interfaces, validation rules, stub outputs, and summaries. They are not part of the default v0.1 `--run_stage all` path unless explicitly documented otherwise. Scaffold outputs are contract fixtures for wiring and review; they must not be presented as production biological results.
