# Real-Mode Fixture Strategy

Stage 28 uses tiny local synthetic fixtures before public datasets. These fixtures are deterministic text files committed under `assets/test_data/real_mode_fixtures/`, and they exist to test CAME contracts: manifest parsing, reference path resolution, seqname concordance, paired FASTQ consistency, optional tool routing, and expected output files.

They are not biological benchmarks. Passing the fixture tests means the real-mode plumbing is executable for tiny inputs when tools are installed; it does not validate mapping quality, peak quality, variant-calling performance, or production suitability for a mammalian dataset.

## Local Fixtures First

Tiny synthetic fixtures make default tests reproducible and cheap. They avoid network access, avoid accession drift, keep CI independent of public mirrors, and make failure modes easier to diagnose. The fixture generator does not require STAR, Bowtie2, MACS3, BWA-MEM2, GATK, samtools, bedtools, FastQC, or public data.

The committed fixture set is intentionally small and text-only. Generated aligner indexes, BAMs, VCF indexes, and other binary outputs must not be committed.

## Optional Public Validation

ENCODE ATAC data are suitable for optional external validation because they have well-documented library strategies, common metadata conventions, and broad toolchain compatibility. Any ENCODE-based CAME validation should be curated manually, pinned to exact accessions and checksums, and kept outside default CI.

Pig `GSE143288 / PRJNA597497` is a candidate future non-model mammal integration fixture because it is closer to CAME's target mammalian use case than model-only examples. It still needs manual curation for sample metadata, reference compatibility, licensing, accession stability, and expected output scope before inclusion.

WGS public fixtures need accession-level manual vetting. Small-variant validation depends on read layout, platform, reference assembly, known-sites policy, coverage, sample identity, and variant-calling expectations, so CAME should not automatically download or infer WGS validation data.

## Curation Policy

Future curated fixture additions should:

- stay outside default tests unless tiny and local;
- use exact accessions, checksums, and provenance;
- document reference assembly and annotation versions;
- avoid automatic large downloads;
- assert output contracts separately from biological quality;
- require an explicit opt-in command or manual CI dispatch for external datasets.

NanoSeq and mutation profiling remain skipped. CNV/SV, ChIP, TOBIAS, HMMRATAC-based peak calling, HAL liftOver, and OU models also remain outside this fixture strategy.
