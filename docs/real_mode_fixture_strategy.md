# Real-Mode Fixture Strategy

CAME uses tiny local synthetic fixtures before public datasets. These fixtures are deterministic text files committed under `assets/test_data/real_mode_fixtures/`, and they exist to test CAME contracts: manifest parsing, reference path resolution, seqname concordance, paired FASTQ consistency, optional tool routing, and expected output files.

They are not biological benchmarks. Passing the fixture tests means the real-mode plumbing is executable for tiny inputs when tools are installed; it does not validate mapping quality, peak quality, variant-calling performance, or production suitability for a mammalian dataset.

## Local Fixtures First

Tiny synthetic fixtures make default tests reproducible and cheap. They avoid network access, avoid accession drift, keep CI independent of public mirrors, and make failure modes easier to diagnose. The fixture generator does not require STAR, Bowtie2, MACS3, BWA-MEM2, GATK, samtools, bedtools, FastQC, or public data.

The committed fixture set is intentionally small and text-only. Generated aligner indexes, BAMs, VCF indexes, and other binary outputs must not be committed.

## Optional Public Validation

ENCODE ATAC data are suitable for optional external validation because they have well-documented library strategies, common metadata conventions, and broad toolchain compatibility. Any ENCODE-based CAME validation should be curated manually, pinned to exact accessions and checksums, and kept outside default CI.

Pig `GSE143288 / PRJNA597497` is a candidate non-model mammal integration fixture because it is closer to CAME's target mammalian use case than model-only examples. It still needs manual curation for sample metadata, reference compatibility, licensing, accession stability, and expected output scope before inclusion.

WGS public fixtures need accession-level manual vetting. Small-variant validation depends on read layout, platform, reference assembly, known-sites policy, coverage, sample identity, and variant-calling expectations, so CAME should not automatically download or infer WGS validation data.

## Curation Policy

Curated fixture additions should:

- stay outside default tests unless tiny and local;
- use exact accessions, checksums, and provenance;
- document reference assembly and annotation versions;
- avoid automatic large downloads;
- assert output contracts separately from biological quality;
- require an explicit opt-in command or manual CI dispatch for external datasets.

NanoSeq and mutation profiling remain skipped. CNV/SV, ChIP, TOBIAS, HMMRATAC-based peak calling, HAL liftOver, and OU models also remain outside this fixture strategy.

## Fixture resources and retained CI evidence

`tests/test_real_mode_fixtures.sh` generates a temporary config and explicitly
passes it to reference-quality, RNA, ATAC, and WGS Nextflow runs. Its name selector
(`withName: '.*'`) takes precedence over production resource labels: each task
requests 1 CPU and 4 GB, with one local task scheduled at a time. This is for tiny
fixtures only. STAR already uses small-reference indexing parameters; the 4 GB
allowance is retained for JVM-backed FastQC/GATK and other tools without changing
their arguments or heap settings. Actual locked-image execution remains the
acceptance check for runtime sufficiency. Production defaults are unchanged.

Local runs still remove their owned scratch directory by default. Optional
`--evidence-dir DIR` creates a unique `fixtures.*` child under DIR, retaining the
resource config, runtime tool inventory with versions, harness/Nextflow logs,
resource traces, validation tables, and failed/incomplete-task command diagnostics
including redirected tool logs. It never deletes DIR or overwrites existing runs.
The text selection is limited to 200 files, 256 KiB per file, and 16 MiB total;
`retention.json` records the original fixture exit status, sizes, truncation
selection, and omitted-file count. Logs retain tails; tables retain heads. No
indexes, BAMs, or general work-directory archives are retained. The owned scratch
directory is removed after capture, including on failure. Capture failure fails an
otherwise successful test but never replaces an existing fixture failure status.

The nonpublishing `real-mode-ci` job runs the fixture script packaged in the built
image, mounting only evidence storage outside `/came`. Its always-run artifact
upload retains evidence for seven days, including source SHA, lock SHA256, direct
runner/container architecture, image inspection, Nextflow version, strict runtime
tool inventory, fixture console log and exit status, plus the bounded diagnostic
selection. The local image ID is a config digest; `RepoDigests` are recorded
separately and may be empty for this unpublished image. Neither identifies an
unperformed registry publication. A successful inventory alone does not establish
RNA/ATAC/WGS execution or biological validity.

Focused host/mock checks: `python3 tests/test_fixture_harness.py`. These exercise
actual Nextflow selector precedence when Nextflow is available, but they do not
substitute for locked-image real-tool execution.
