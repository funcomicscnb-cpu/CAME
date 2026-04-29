# Real-Mode Fixtures

These Stage 28 fixtures are tiny synthetic contract fixtures for CAME real-mode plumbing.
They are deterministic, local, and safe to keep in git. They are not biological benchmarks.

Generated contents:

- `tiny_reference/`: FASTA, FAI, sequence dictionary, GTF, GFF3, assembly report, alias map, and small BED helpers.
- `tiny_rna/`: paired RNA FASTQ files.
- `tiny_atac/`: paired ATAC FASTQ files.
- `tiny_wgs/`: paired WGS FASTQ files.
- `manifests/`: reference, real-mode metadata, WGS sample sheet, and expected contract records.

Regenerate with:

```bash
python3 bin/make_real_mode_fixtures.py --outdir assets/test_data/real_mode_fixtures --force
```
