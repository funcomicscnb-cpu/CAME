# Installation

This page describes a local CAME v0.1 setup. Stub-mode tests require Java, Nextflow, Python, and a small R package set. Real-mode RNA-seq, ATAC-seq, and optional WGS runs require additional command-line tools, reference assets, and tuned runtime resources.

## Conda Environment

```bash
conda env create -f environment/came_environment.yml
conda activate came
```

The environment file uses version ranges and includes Python, Nextflow, R, core R packages, Python packages, and feasible real-mode command-line tools. HMMRATAC is handled separately because deployments commonly use a jar file.

To create the environment through the helper:

```bash
bash environment/install_local.sh --create-env
```

The backward-compatible alias also works:

```bash
bash environment/install_local.sh --create-conda-env
```

The helper uses conda and does not edit global shell configuration.

## Java And Nextflow

CAME requires Java and Nextflow. The Nextflow version constraint is declared in `nextflow.config`.

```bash
java -version
nextflow -version
```

If Nextflow is not provided by conda, install it with the official Nextflow installer and place the executable on `PATH`.

## Python Dependencies

For an existing Python 3.10+ environment:

```bash
python3 -m pip install -r environment/requirements.txt
```

Required Python packages include `pyyaml`, `jsonschema`, `pandas`, `numpy`, and `scipy`. Most pipeline helper scripts use the standard library; SciPy is used only for optional hierarchical clustering fallback behavior.

## R Packages

Check installed R packages:

```bash
Rscript environment/install_r_packages.R --skip-deseq2
```

Install core R packages:

```bash
Rscript environment/install_r_packages.R --install-core --skip-deseq2
```

Core packages are `yaml`, `ape`, `nlme`, and `data.table`. DESeq2 is optional for smoke tests because CAME has deterministic fallback differential paths. To attempt DESeq2 installation:

```bash
Rscript environment/install_r_packages.R --install-core --install-deseq2
```

## Optional Real-Mode Tools

Real-mode bulk omics interfaces expect these tools on `PATH`:

- FastQC
- MultiQC
- STAR
- featureCounts from subread
- Bowtie2 and bowtie2-build
- MACS3
- samtools
- bedtools

Optional WGS small-variant real mode also expects:

- BWA-MEM2
- GATK 4

BWA and HMMRATAC are retained for legacy compatibility, but ATAC real mode uses Bowtie2 plus MACS3.

Stub mode does not require these tools.

## Nextflow Profiles

CAME provides clean profile hooks:

```bash
nextflow run . -profile conda ...
nextflow run . -profile docker ...
nextflow run . -profile apptainer ...
nextflow run . -profile singularity ...
```

The `conda` profile uses `environment/came_environment.yml` as a flexible local install file. Docker, Apptainer, and Singularity profiles default to `ghcr.io/funcomicscnb-cpu/came:<VERSION>`, where `<VERSION>` comes from the repository `VERSION` file. Override the image with `--container_image` when using a site-approved build.

An explicit linux-64 lock file is provided at `environment/conda-linux-64.lock` and is the reproducible source of truth for container builds. macOS users should continue to create local environments from `environment/came_environment.yml`.

For Slurm systems, use the portable scheduler profile and supply site values as needed:

```bash
nextflow run . -profile slurm --slurm_queue normal --slurm_account my_account ...
```

The Slurm profile sets only executor/account/queue hooks and leaves site-specific partitions, modules, and scratch behavior to local configuration.

## Resource Labels

`nextflow.config` defines these labels:

- `process_low`
- `process_medium`
- `process_high`
- `process_star_index`
- `process_star_align`
- `process_bowtie2_align`
- `process_bwa_mem2_index`
- `process_bwa_mem2_align`
- `process_variant_calling`
- `process_peak_calling`
- `process_counting`

The default local resources are conservative test-oriented values. Mammalian STAR indexing and alignment often need more memory and time than the defaults, depending on genome size, annotation density, read length, and read depth. Tune labels in a site-specific config for real datasets.

## HMMRATAC Jar Handling

The legacy ATAC-seq compatibility path resolves HMMRATAC in this order:

1. `HMMRATAC` on `PATH`
2. `hmmratac` on `PATH`
3. `$CAME_HMMRATAC_JAR`
4. `--hmmratac_jar`
5. local jar names such as `HMMRATAC.jar`, `hmmratac.jar`, `tools/HMMRATAC.jar`, `environment/tools/HMMRATAC.jar`, or `environment/HMMRATAC.jar`

To copy an existing jar into the local environment tools directory:

```bash
bash environment/install_local.sh --install-hmmratac --hmmratac-jar /path/to/HMMRATAC.jar
```

Production ATAC real mode does not use HMMRATAC.

## Version Report

```bash
python3 bin/print_versions.py
```

This writes `environment/tool_versions.tsv` and prints compact present or missing counts.

## Real-Mode Smoke Tests

CAME provides real-mode smoke and contract checks for the omics layer:

```bash
python3 bin/check_real_mode_tools.py --outdir results/real_mode_smoke --mode soft
python3 bin/make_real_mode_smoke_data.py --outdir assets/test_data/real_mode_smoke
bash tests/test_reference_assets.sh
bash tests/test_seqname_concordance.sh
bash tests/test_real_mode_smoke.sh --soft
bash tests/test_real_mode_core.sh
bash tests/test_real_rna_mode.sh
bash tests/test_real_atac_mode.sh
bash tests/test_real_mode_scaleout.sh
bash tests/test_real_qc_contracts.sh
```

`test_real_mode_smoke.sh` uses `pipefail` and requires bash. Soft mode records missing tools as warnings and skips unavailable execution paths. Strict mode fails when required tools for requested RNA-seq or ATAC-seq smoke paths are absent:

```bash
bash tests/test_real_mode_smoke.sh --strict
```

See [real_mode_smoke_tests.md](real_mode_smoke_tests.md) for tool requirements, HMMRATAC handling, and troubleshooting.

## Reference-Quality Checks

Reference-quality checks require only Python and Nextflow for the bundled tiny fixtures:

```bash
nextflow run . \
  --run_stage reference_quality \
  --reference_manifest assets/test_data/reference_quality/reference_manifest.tsv \
  --outdir results \
  --check_paths true
```

These checks validate declared reference assets, assembly-report aliases, FASTA/FAI consistency, FASTA/annotation seqname overlap, and BUSCO metadata thresholds. They do not run BUSCO, RepeatMasker, or mappability tools.

## WGS Small-Variant Checks

CAME WGS stub mode requires no external bioinformatics tools:

```bash
nextflow run . \
  --run_stage wgs_variants \
  --wgs_samplesheet assets/example_samplesheets/wgs_samplesheet.csv \
  --reference_manifest assets/example_samplesheets/reference_manifest.tsv \
  --wgs_mode stub \
  --outdir results
```

Real WGS mode requires BWA-MEM2, samtools, GATK, FastQC, FASTQ files, and local reference assets with FASTA, FAI, sequence dictionary, and BWA-MEM2 index or buildable FASTA. CAME does not run BQSR; missing known-sites resources warn unless `--require_known_sites true`.

## Stub-Mode First Test

Run the release packaging smoke test:

```bash
bash tests/test_release_packaging.sh
```

Run the end-to-end stub workflow:

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

## Real-Mode Notes

CAME real mode requires contrast-ready metadata, reference assets, FASTQ files, and the external tools listed above. STAR and Bowtie2 indexes are reused when present or generated under `--reference_cache_dir` when feasible. CAME WGS similarly reuses or builds BWA-MEM2 indexes. Orthology tables, regulatory-element orthology, and regulatory-element-to-gene links are supplied inputs; CAME does not infer them during v0.1 runs.

The Salmon RNA backend is declared but not implemented. Requesting it fails clearly in this release.

## Fixture Strategy

Use tiny local synthetic fixtures for routine local checks. Optional curated real-data fixtures can include a small ENCODE ATAC subset or a manually selected pig `GSE143288 / PRJNA597497` subset. Do not automatically download large public datasets in tests. WGS tests should use deterministic stub and contract fixtures unless a tiny local real-tool fixture is manually curated.

## Known Runtime Limitations

### Output Path Visibility on NFS and Symlinked Volumes

CAME checks for expected stage output files at workflow startup using `file().exists()` before launching processes. On NFS-mounted volumes or paths that include symbolic links with delayed metadata propagation, this check can fire before a previous stage's outputs are fully visible, causing a false-positive startup failure.

**Workaround:** Use an absolute local path for `--outdir` when possible, and run stages sequentially rather than in parallel when using networked storage. If CAME reports a missing output file that you can confirm exists on disk, rerun the command after a brief delay to allow the filesystem to propagate the path.
