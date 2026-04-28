# Installation

This page describes a local CAME v0.1 setup. Stub-mode tests require only Java, Nextflow, Python, and a small R package set. Real-mode RNA-seq and ATAC-seq runs require additional command-line tools and reference assets.

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
- STAR (genome index generation requires ≥32 GB RAM for human-sized genomes)
- featureCounts from subread
- BWA
- samtools
- bedtools
- HMMRATAC

Stub mode does not require these tools.

## HMMRATAC Jar Handling

Stage 5 ATAC-seq real mode resolves HMMRATAC in this order:

1. `HMMRATAC` on `PATH`
2. `hmmratac` on `PATH`
3. `$CAME_HMMRATAC_JAR`
4. `--hmmratac_jar`
5. local jar names such as `HMMRATAC.jar`, `hmmratac.jar`, `tools/HMMRATAC.jar`, `environment/tools/HMMRATAC.jar`, or `environment/HMMRATAC.jar`

To copy an existing jar into the local environment tools directory:

```bash
bash environment/install_local.sh --install-hmmratac --hmmratac-jar /path/to/HMMRATAC.jar
```

HMMRATAC is available from its GitHub releases page (search `LiLabAtVT/HMMRATAC`). Download the `.jar` file and pass its path with `--hmmratac-jar`.

CAME does not substitute another tool for HMMRATAC.

## Version Report

```bash
python3 bin/print_versions.py
```

This writes `environment/tool_versions.tsv` and prints compact present/missing counts.

## Real-Mode Smoke Tests

Stage 15 provides optional real-mode smoke checks for the omics layer:

```bash
python3 bin/check_real_mode_tools.py --outdir results/real_mode_smoke --mode soft
python3 bin/make_real_mode_smoke_data.py --outdir assets/test_data/real_mode_smoke
bash tests/test_real_mode_smoke.sh --soft
```

`test_real_mode_smoke.sh` uses `pipefail` and requires **bash** (not plain `sh`). All other test scripts in `tests/` are POSIX-compatible sh.

Soft mode records missing tools as warnings and skips unavailable execution
paths. Strict mode fails when required tools for requested RNA-seq or ATAC-seq
smoke paths are absent:

```bash
bash tests/test_real_mode_smoke.sh --strict
```

See [real_mode_smoke_tests.md](real_mode_smoke_tests.md) for tool requirements,
HMMRATAC handling, and troubleshooting.

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

Real mode requires contrast-ready omics metadata, reference indexes, FASTQ files, and the external tools listed above. Orthology tables, regulatory-element orthology, and regulatory-element-to-gene links are supplied inputs; CAME does not infer them during v0.1 runs.

## Known Runtime Limitations

### Output Path Visibility on NFS and Symlinked Volumes

CAME checks for expected stage output files at workflow startup using `file().exists()` before launching processes. On NFS-mounted volumes or paths that include symbolic links with delayed metadata propagation, this check can fire before a previous stage's outputs are fully visible, causing a false-positive startup failure.

**Workaround:** Use an absolute local path for `--outdir` (not a symlink target), and run stages sequentially rather than in parallel when using networked storage. If CAME reports a missing output file that you can confirm exists on disk, re-run the command after a brief delay to allow the filesystem to propagate the path.
