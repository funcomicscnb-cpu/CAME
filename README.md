# CAME

CAME, Comparative Analysis of Multi-omics Evolution, is a phenotype-agnostic Nextflow DSL2 framework for comparative multi-omics studies across species.

The bundled profiles are examples. Core workflow logic is not tied to one phenotype or study system.

Bundled study-profile templates include `generic`, `ddr_ror`, `immune_response`, `metabolic_response`, and `stress_tolerance`. The biological profiles are authoring examples, not biologically validated analyses.

## Release Status

Current release metadata targets `v0.1.0`. This release prepares the public repository package, stub-mode orchestration, final reports, and release checks. It does not add new biological analyses, implement NanoSeq or mutation profiling, or change default `--run_stage all` behavior.

CAME is distributed under `GPL-3.0-only`. Citation metadata is available in [CITATION.cff](CITATION.cff); the public repository is `https://github.com/funcomicscnb-cpu/CAME`, and the release date is still unset.

## Quick Install

Requirements for the stub-mode test path:

- Java 11 or newer
- Nextflow 22.10.0 or newer
- Python 3.10 or newer
- R with the `yaml` package for hypothesis/profile tests

Create the conda environment when conda is available:

```bash
conda env create -f environment/came_environment.yml
conda activate came
```

Or install Python-only dependencies into an existing environment:

```bash
python3 -m pip install -r environment/requirements.txt
```

Check detected runtime versions:

```bash
bash environment/install_local.sh --check-only
```

See [docs/installation.md](docs/installation.md) for full installation notes, optional real-mode tools, R packages, and HMMRATAC jar handling.

## Quick Start

The command below runs in **stub mode** (`--omics_stub true`), which is the default. Stub mode exercises the full orchestration and reporting pipeline using synthetic omics data. No FASTQ files, reference indexes, or external bioinformatics tools (STAR, BWA, featureCounts, HMMRATAC) are required. See [docs/installation.md](docs/installation.md) for real-mode setup.

```bash
nextflow run . -resume \
  --run_stage all \
  --study_profile profiles/generic/study_profile.yaml \
  --phenotype_samplesheet assets/example_samplesheets/phenotype_samplesheet.csv \
  --omics_samplesheet assets/example_samplesheets/omics_samplesheet.csv \
  --species_traits assets/example_samplesheets/species_traits.tsv \
  --reference_manifest assets/example_samplesheets/reference_manifest.tsv \
  --phylogeny_manifest assets/example_samplesheets/phylogeny_manifest.tsv \
  --study_design assets/example_samplesheets/study_design.yaml \
  --orthologous_genes assets/example_samplesheets/orthologous_genes.tsv \
  --orthologous_res assets/example_samplesheets/orthologous_res.tsv \
  --re_to_gene_links assets/example_samplesheets/re_to_gene_links.tsv \
  --gene_annotations assets/example_samplesheets/gene_annotations.tsv \
  --gene_sets assets/example_samplesheets/gene_sets.tsv \
  --candidate_scoring_config assets/example_samplesheets/candidate_scoring_config.tsv \
  --omics_stub true \
  --omics_types rnaseq,atacseq \
  --outdir results
```

The stub run exercises orchestration and report generation without real FASTQ files, reference indexes, or heavy bioinformatics tools.

Final reports are written to `results/final/report/` with linked provenance and compact report assets under `results/final/provenance/` and `results/final/assets/`.

## Supported Run Stages

| Stage | Command value |
| --- | --- |
| Metadata and study-profile validation | `--run_stage validation` |
| Phenotype processing | `--run_stage phenotype_response` |
| Phylogenetic and hypothesis modeling | `--run_stage phylo_hypothesis` |
| Bulk RNA-seq/ATAC-seq interface | `--run_stage bulk_omics` |
| Differential omics | `--run_stage differential_omics` |
| Orthology projection | `--run_stage orthology_projection` |
| GRA analysis | `--run_stage gra_analysis` |
| Phenotype-omics integration | `--run_stage phenotype_omics_integration` |
| Candidate prioritization | `--run_stage candidate_prioritization` |
| Functional interpretation | `--run_stage functional_interpretation` |
| Final reporting and release checks | `--run_stage final_report` |
| Optional reference preparation scaffold | `--run_stage reference_prepare` |
| Optional coordinate projection scaffold | `--run_stage coordinate_projection` |
| Optional RE-to-gene inference scaffold | `--run_stage re_to_gene_inference` |
| Optional advanced statistics scaffold | `--run_stage advanced_statistics` |
| End-to-end orchestration | `--run_stage all` |

Optional scaffold stages define future-facing interfaces and validation outputs. They are not production implementations and are not automatically run by the v0.1 `--run_stage all` path unless explicitly documented for that path.

## Documentation

- Input formats: [docs/input_formats.md](docs/input_formats.md)
- Study profiles: [docs/study_profiles.md](docs/study_profiles.md)
- Profile authoring: [docs/profile_authoring.md](docs/profile_authoring.md)
- End-to-end runs: [docs/end_to_end_run.md](docs/end_to_end_run.md)
- Optional reference preparation: [docs/reference_preparation.md](docs/reference_preparation.md)
- Optional coordinate projection: [docs/coordinate_projection.md](docs/coordinate_projection.md)
- Optional RE-to-gene inference: [docs/re_to_gene_inference.md](docs/re_to_gene_inference.md)
- Optional advanced statistics scaffold: [docs/advanced_statistics.md](docs/advanced_statistics.md)
- Final reports: [docs/final_report.md](docs/final_report.md)
- Report customization: [docs/report_customization.md](docs/report_customization.md)
- CI and release process: [docs/ci_and_release.md](docs/ci_and_release.md)
- Release checklist: [docs/release_checklist.md](docs/release_checklist.md)
- Versioning policy: [docs/versioning.md](docs/versioning.md)
- v0.1 release notes: [docs/release_notes_v0.1.md](docs/release_notes_v0.1.md)

## Known Limits

- `--resume_completed_stages` is reporting/documentation only; reuse is through Nextflow `-resume`.
- Stage status checks are file presence/non-empty checks, not freshness or content hashes.
- Optional scaffold stages such as `re_to_gene_inference` and `advanced_statistics` are not run by `--run_stage all`.
- Real mode requires real contrast-ready metadata, reference assets, FASTQ files, and external tools.
- NanoSeq and mutation profiling are not implemented in v0.1.
