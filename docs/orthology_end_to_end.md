# CAME Reciprocal-Best Orthology: End-to-End

This walkthrough ties together the optional reciprocal-best orthology stack —
reference preparation, coordinate projection, review, and adoption into a main
CAME run. It is the operational counterpart to the component references:

- Method, engine, output schemas, QC/structural vocabularies, chain validation:
  [reciprocal_best_orthology.md](reciprocal_best_orthology.md)
- Stage inputs, bundle interface, stub mode: [coordinate_projection.md](coordinate_projection.md)
- External bundle-generator orchestration: [orthology_reference_prepare.md](orthology_reference_prepare.md)

The whole path is **optional and opt-in**. It is not part of `--run_stage all`,
and feeding its results into a main run is an explicit, user-initiated step. CAME
orchestrates external lift-over tools and validates contracts; it does not own
synteny reconstruction and never treats a failed mapping as biological absence.

## Overview

```
(1) reference prep            (2) projection                 (3) review + adopt        (4) main run
external generator      →     coordinate_projection    →     promote reviewed     →    nextflow run with
(halSynteny/axtChain/         real mode (liftOver or         primary loci to a         --orthologous_res
 chainNet → bundle)           halLiftover) → QC'd            stable orthologous_res    <adopted file>
   ↑ CAME orchestrates          orthologous regions            .adopted.tsv
   ↓ + validates bundle
```

## Prerequisites

Real mode requires external tools on `PATH` (CAME does not install them):

| `orthology_lift_tool` | tools | source |
| --- | --- | --- |
| `liftover` | UCSC `liftOver`, `chainSwap` | Bioconda (`environment/orthology_tools.yml`), or UCSC precompiled binaries |
| `halliftover` | `halLiftover` | build the HAL toolkit or use Cactus (not on Bioconda) |

`environment/orthology_tools.yml` covers the `liftover` path on **linux-64**
(Bioconda has no `ucsc-*` builds for osx-arm64):

```bash
conda env create -f environment/orthology_tools.yml   # liftOver, chainSwap, python
conda activate came-orthology-tools
python3 bin/check_orthology_tools.py --lift-tool liftover --mode strict
```

`halLiftover` is not installable via that env (the HAL toolkit is not on
Bioconda); obtain it by building <https://github.com/ComparativeGenomicsToolkit/hal>
or via Cactus. On an ARM Mac, run the env inside a linux-64 container
(`docker run --platform linux/amd64 ...`) or download UCSC binaries directly.

Generating the reciprocal-best chains and callable masks themselves (halSynteny,
axtChain, chainNet, netChainSubset, netSyntenic) is done by an **external**
generator; CAME only orchestrates and validates it.

## (1) Reference preparation — produce a validated bundle

Either supply an externally produced bundle, or orchestrate a user-supplied
generator command through the opt-in stage:

```bash
nextflow run . \
  --run_stage orthology_reference_prepare \
  --orthology_reference_prepare_stub false \
  --orthology_reference_prepare_cmd "python3 /path/to/your_bundle_generator.py" \
  --orthology_reference_prepare_run_dir /path/to/generator_run_dir \
  --outdir results
```

CAME appends `--run-dir`/`--out-dir` (and `--created-at` when set) to the
command, then validates the emitted `bundle/orthology_reference_bundle.tsv` with
`bin/validate_orthology_reference_bundle.py`. Reports are published before any
failure; a missing generated manifest exits with the orchestration signal **10**.

The standalone helpers can also be run directly to post-process external
chain/net output:

```bash
python3 bin/define_reciprocal_best_chains.py \
  --target-net-chains t.netchains.chain --query-net-chains q.netchains.chain \
  --raw-chains raw.chain --out-chains reciprocal_best.chain
python3 bin/build_callable_mask.py \
  --reference-fills ref_level1.bed --query-fills-projected qry_level1_to_ref.bed \
  --out callable_mask.bed
```

## (2) Coordinate projection — define orthologous regions

Consume the bundle (per-pair assets selected automatically), or pass loose
inputs:

```bash
nextflow run . \
  --run_stage coordinate_projection \
  --regulatory_regions regions.tsv \
  --orthology_reference_bundle_manifest bundle/orthology_reference_bundle.tsv \
  --coordinate_projection_stub false \
  --outdir results
```

This scatters per `(projection_id, source_species, target_species)`, projects
forward and back through the real lift-over tools, filters by the callable mask,
selects a best contig, measures round-trip recovery, classifies structure, and
gathers a deterministic `region_orthology_summary.tsv`, `projected_regions.tsv`,
`orthologous_region_blocks.tsv`, and `inferred_orthologous_res.tsv` under
`results/coordinate_projection/`.

`inferred_orthologous_res.tsv` is a **review artifact** — inspect it; it is not
auto-consumed downstream.

## (3) Review and adopt — produce `orthologous_res.adopted.tsv`

After reviewing the QC summary, promote the high-confidence primary loci to a
stable orthology table:

```bash
python3 bin/promote_orthologous_res.py \
  --region-summary results/coordinate_projection/region_orthology_summary.tsv \
  --projected-regions results/coordinate_projection/projected_regions.tsv \
  --orthologous-genes your_orthologous_genes.tsv \
  --output-dir results/coordinate_projection/adopted
```

This emits `orthologous_res.adopted.tsv` with stable source-anchor orthogroup ids
(`OG_RE_RB_<source_species>_<feature_id>`), enforces the single-source
star-shaped precondition, preserves ambiguity/confidence/provenance, reports
adopted-vs-excluded counts, and (with `--orthologous-genes`) runs the existing
`validate_orthology_tables.py` so the result is known-compatible with the main
pipeline. Regulatory orthology only; gene orthology stays your own table.

## (4) Main run — opt in via `--orthologous_res`

Pass the adopted table to a normal CAME run:

```bash
nextflow run . \
  --run_stage orthology_projection \
  --orthologous_genes your_orthologous_genes.tsv \
  --orthologous_res results/coordinate_projection/adopted/orthologous_res.adopted.tsv \
  ... other inputs ...
```

Nothing in steps 1–3 is wired into `--run_stage all`; this final step is where you
explicitly choose to use the reviewed orthology.

## Validation and maturity

- Default CI is binary-free (mock lift-over shims). Real `liftOver`/`chainSwap`
  behavior is covered by the **opt-in** `orthology-real-tools` CI job and
  `tests/test_orthology_real_tools.sh` (run with `--strict` against the pinned
  `environment/orthology_tools.yml`).
- The `coordinate_projection` and `orthology_reference_prepare` stages are
  labelled `basic` maturity. Promotion to `production` is gated on the opt-in
  real-tool job passing green; the `halliftover` path additionally awaits a real
  HAL fixture before any production claim. Bundle consumption currently assumes a
  local/shared filesystem and shards pair-level (not region-level). Bundle-declared
  optional assets (callable masks, element union, HAL) are selected per
  `(source_species, target_species)` pair; loose non-bundle asset parameters remain
  run-wide fallbacks.
