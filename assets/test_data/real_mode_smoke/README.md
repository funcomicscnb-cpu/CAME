# Real-Mode Smoke Test Data

This directory is a scaffold for Stage 15 real-mode smoke fixtures.

The committed tree only keeps this README and placeholder directories. Generate
the tiny deterministic FASTQ, reference, GTF, chrom sizes, BED helper, and
manifests when needed:

```bash
python3 bin/make_real_mode_smoke_data.py --outdir assets/test_data/real_mode_smoke
```

Generated files are intentionally ignored so real-mode smoke validation can be
recreated without committing synthetic FASTQ or index artifacts.
