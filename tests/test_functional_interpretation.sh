#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

assert_grep() {
  pattern="$1"
  file="$2"
  message="$3"
  if ! grep -q "$pattern" "$file"; then
    cat "$file"
    echo "FAIL: $message" >&2
    exit 1
  fi
}

assert_header_contains() {
  file="$1"
  field="$2"
  message="$3"
  head -n 1 "$file" | tr '\t' '\n' | grep -qx "$field" || {
    cat "$file"
    echo "FAIL: $message" >&2
    exit 1
  }
}

assert_nonempty_rows() {
  file="$1"
  message="$2"
  awk 'NR>1{found=1} END{exit found?0:1}' "$file" || {
    cat "$file"
    echo "FAIL: $message" >&2
    exit 1
  }
}

FIX="$TMP_DIR/fixtures"
mkdir -p "$FIX"

cat > "$FIX/candidate_genes_ranked.tsv" <<'EOF'
rank	candidate_id	candidate_type	total_score	n_evidence_types	n_contrasts	n_species	top_evidence_type	top_contrast	mean_effect_size	combined_direction	support_summary	linked_gene_orthogroup_id	linked_re_orthogroup_id	linked_gra_id
1	OG_GENE_0001	gene	10	3	1	2	phenotype_expression_association	baseline_vs_response	1.2	up	phenotype_expression_association:1		OG_RE_0001	GRA_OG_GENE_0001
2	OG_GENE_0002	gene	9	2	1	2	differential_expression	baseline_vs_response	0.8	up	differential_expression:1		OG_RE_0002	GRA_OG_GENE_0002
3	OG_GENE_0006	gene	2	1	1	1	differential_expression	baseline_vs_response	0.1	up	differential_expression:1			
EOF

cat > "$FIX/candidate_res_ranked.tsv" <<'EOF'
rank	candidate_id	candidate_type	total_score	n_evidence_types	n_contrasts	n_species	top_evidence_type	top_contrast	mean_effect_size	combined_direction	support_summary	linked_gene_orthogroup_id	linked_re_orthogroup_id	linked_gra_id
1	OG_RE_0001	regulatory_element	9	3	1	2	phenotype_accessibility_association	baseline_vs_response	1.1	up	phenotype_accessibility_association:1	OG_GENE_0001		GRA_OG_GENE_0001
2	OG_RE_0002	regulatory_element	8	2	1	2	differential_accessibility	baseline_vs_response	0.7	up	differential_accessibility:1			GRA_OG_GENE_0002
3	OG_RE_MISSING	regulatory_element	7	1	1	1	differential_accessibility	baseline_vs_response	0.5	up	differential_accessibility:1	OG_GENE_0005		
EOF

cat > "$FIX/candidate_gras_ranked.tsv" <<'EOF'
rank	candidate_id	candidate_type	total_score	n_evidence_types	n_contrasts	n_species	top_evidence_type	top_contrast	mean_effect_size	combined_direction	support_summary	linked_gene_orthogroup_id	linked_re_orthogroup_id	linked_gra_id
1	GRA_OG_GENE_0001	gra	8	3	1	2	phenotype_gra_association	baseline_vs_response	1.3	up	phenotype_gra_association:1	OG_GENE_0001	OG_RE_0001	
2	GRA_OG_GENE_0004	gra	6	2	1	2	differential_gra_activity	baseline_vs_response	0.4	up	differential_gra_activity:1			
EOF

cat > "$FIX/candidate_all_ranked.tsv" <<'EOF'
rank	candidate_id	candidate_type	total_score	n_evidence_types	n_contrasts	n_species	top_evidence_type	top_contrast	mean_effect_size	combined_direction	support_summary	linked_gene_orthogroup_id	linked_re_orthogroup_id	linked_gra_id
1	OG_GENE_0001	gene	10	3	1	2	phenotype_expression_association	baseline_vs_response	1.2	up	phenotype_expression_association:1		OG_RE_0001	GRA_OG_GENE_0001
2	OG_GENE_0002	gene	9	2	1	2	differential_expression	baseline_vs_response	0.8	up	differential_expression:1		OG_RE_0002	GRA_OG_GENE_0002
3	OG_RE_0001	regulatory_element	9	3	1	2	phenotype_accessibility_association	baseline_vs_response	1.1	up	phenotype_accessibility_association:1	OG_GENE_0001		GRA_OG_GENE_0001
4	GRA_OG_GENE_0001	gra	8	3	1	2	phenotype_gra_association	baseline_vs_response	1.3	up	phenotype_gra_association:1	OG_GENE_0001	OG_RE_0001	
5	OG_RE_0002	regulatory_element	8	2	1	2	differential_accessibility	baseline_vs_response	0.7	up	differential_accessibility:1			GRA_OG_GENE_0002
6	OG_RE_MISSING	regulatory_element	7	1	1	1	differential_accessibility	baseline_vs_response	0.5	up	differential_accessibility:1	OG_GENE_0005		
7	GRA_OG_GENE_0004	gra	6	2	1	2	differential_gra_activity	baseline_vs_response	0.4	up	differential_gra_activity:1			
EOF

cat > "$FIX/gene_annotations.tsv" <<'EOF'
gene_orthogroup_id	gene_symbol	description	species	source_gene_id	chrom	start	end	strand	biotype	external_id	notes
OG_GENE_0001	SynGene1	Top synthetic gene	orthogroup	gene_0001	chr1	100	900	+	protein_coding	SYN:1	
OG_GENE_0002	SynGene2	Second synthetic gene	orthogroup	gene_0002	chr2	100	900	-	protein_coding	SYN:2	
OG_GENE_0003	SynGene3	Background synthetic gene	orthogroup	gene_0003	chr3	100	900	+	protein_coding	SYN:3	
OG_GENE_0004	SynGene4	Linked GRA fallback gene	orthogroup	gene_0004	chr4	100	900	-	protein_coding	SYN:4	
OG_GENE_0005	SynGene5	Missing coordinate linked gene	orthogroup	gene_0005	chr5	100	900	+	protein_coding	SYN:5	
OG_GENE_0006	SynGene6	Low score gene	orthogroup	gene_0006	chr6	100	900	-	protein_coding	SYN:6	
OG_GENE_0007	SynGene7	Background gene	orthogroup	gene_0007	chr7	100	900	+	protein_coding	SYN:7	
OG_GENE_0008	SynGene8	Background gene	orthogroup	gene_0008	chr8	100	900	-	protein_coding	SYN:8	
EOF

cat > "$FIX/gene_annotations_minimal.tsv" <<'EOF'
gene_orthogroup_id	gene_symbol
OG_GENE_0001	SynGene1
OG_GENE_0002	SynGene2
OG_GENE_0003	SynGene3
OG_GENE_0004	SynGene4
OG_GENE_0005	SynGene5
OG_GENE_0006	SynGene6
OG_GENE_0007	SynGene7
OG_GENE_0008	SynGene8
EOF

cat > "$FIX/gene_sets.tsv" <<'EOF'
gene_set_id	gene_set_name	gene_orthogroup_id	gene_set_source	description	category	notes
GS_TOP	Top two genes	OG_GENE_0001	synthetic	test set	response	
GS_TOP	Top two genes	OG_GENE_0002	synthetic	test set	response	
GS_LINKED	Linked fallback genes	OG_GENE_0004	synthetic	test set	regulatory	
GS_LINKED	Linked fallback genes	OG_GENE_0005	synthetic	test set	regulatory	
GS_BACKGROUND	Background genes	OG_GENE_0006	synthetic	test set	background	
GS_BACKGROUND	Background genes	OG_GENE_0007	synthetic	test set	background	
GS_BACKGROUND	Background genes	OG_GENE_0008	synthetic	test set	background	
GS_MIXED	Mixed genes	OG_GENE_0001	synthetic	test set	mixed	
GS_MIXED	Mixed genes	OG_GENE_0008	synthetic	test set	mixed	
EOF

cat > "$FIX/feature_to_orthogroup_map.tsv" <<'EOF'
feature_type	species	feature_id	orthogroup_id	mapping_status	n_mapped_orthogroups	is_ambiguous	ambiguity_reason	gene_symbol	human_anchor_id	transcript_id	chrom	start	end	human_anchor_region	re_type	orthology_type	orthology_confidence	source	notes
regulatory_element	Mus_musculus	re_0001	OG_RE_0001	mapped	1	false		SynRE1	ANCHOR_RE_1	TX_RE_1	chr1	100	200	anchor	enhancer	one_to_one	high	test	
regulatory_element	Danio_rerio	re_0002	OG_RE_0002	mapped	1	false		SynRE2	ANCHOR_RE_2	TX_RE_2	chr2	300	450	anchor	promoter	one_to_one	high	test	
regulatory_element	Mus_musculus	re_bad	OG_RE_BAD	mapped	1	false		SynREBad	ANCHOR_RE_BAD	TX_RE_BAD	chr3	900	800	anchor	enhancer	one_to_one	high	test	
gene	Mus_musculus	gene_0001	OG_GENE_0001	mapped	1	false		SynGene1											
EOF

cat > "$FIX/gene_regulatory_architectures.tsv" <<'EOF'
gra_id	gene_orthogroup_id	feature_type	n_res	n_links	n_species	species_members	link_types	mapping_status	is_ambiguous	ambiguity_reason
GRA_OG_GENE_0001	OG_GENE_0001	gene_regulatory_architecture	1	1	2	orthogroup	promoter	mapped	false	
GRA_OG_GENE_0002	OG_GENE_0002	gene_regulatory_architecture	1	1	2	orthogroup	proximal	mapped	false	
GRA_OG_GENE_0004	OG_GENE_0004	gene_regulatory_architecture	1	1	1	orthogroup	curated	mapped	false	
EOF

cat > "$FIX/gra_re_membership.tsv" <<'EOF'
gra_id	gene_orthogroup_id	re_orthogroup_id	link_type	species_members	n_species	n_res	mapping_status	is_ambiguous	source_gene_feature_ids	source_re_feature_ids	distance_to_tss	contact_score	link_confidence	source	notes
GRA_OG_GENE_0001	OG_GENE_0001	OG_RE_0001	promoter	orthogroup	2	1	mapped	false	gene_0001	re_0001	100	0.9	0.9	test	
GRA_OG_GENE_0002	OG_GENE_0002	OG_RE_0002	proximal	orthogroup	2	1	mapped	false	gene_0002	re_0002	200	0.8	0.8	test	
GRA_OG_GENE_0004	OG_GENE_0004	OG_RE_MISSING	curated	orthogroup	1	1	mapped	false	gene_0004	re_missing	300	0.7	0.7	test	
EOF

INPUT_OUT="$TMP_DIR/input"
python3 "$ROOT_DIR/bin/prepare_enrichment_inputs.py" \
  --candidate_genes "$FIX/candidate_genes_ranked.tsv" \
  --candidate_res "$FIX/candidate_res_ranked.tsv" \
  --candidate_gras "$FIX/candidate_gras_ranked.tsv" \
  --candidate_all "$FIX/candidate_all_ranked.tsv" \
  --gene_annotations "$FIX/gene_annotations.tsv" \
  --gene_sets "$FIX/gene_sets.tsv" \
  --gra_re_membership "$FIX/gra_re_membership.tsv" \
  --gene_regulatory_architectures "$FIX/gene_regulatory_architectures.tsv" \
  --top_n 2 \
  --min_score 6 \
  --output_dir "$INPUT_OUT" > "$TMP_DIR/prepare.out" 2>&1
test -s "$INPUT_OUT/candidate_gene_sets.tsv"
test -s "$INPUT_OUT/enrichment_background.tsv"
test -s "$INPUT_OUT/enrichment_input_warnings.tsv"
assert_grep 'regulatory_element_linked_genes' "$INPUT_OUT/candidate_gene_sets.tsv" "RE-linked gene set missing"
assert_grep 'gra_linked_genes' "$INPUT_OUT/candidate_gene_sets.tsv" "GRA-linked gene set missing"
assert_grep 'gra_tables' "$INPUT_OUT/candidate_gene_sets.tsv" "GRA fallback link source missing"

MIN_WARN="$TMP_DIR/input_minimal"
python3 "$ROOT_DIR/bin/prepare_enrichment_inputs.py" \
  --candidate_genes "$FIX/candidate_genes_ranked.tsv" \
  --candidate_res "$FIX/candidate_res_ranked.tsv" \
  --candidate_gras "$FIX/candidate_gras_ranked.tsv" \
  --candidate_all "$FIX/candidate_all_ranked.tsv" \
  --gene_annotations "$FIX/gene_annotations_minimal.tsv" \
  --gene_sets "$FIX/gene_sets.tsv" \
  --gra_re_membership "$FIX/gra_re_membership.tsv" \
  --gene_regulatory_architectures "$FIX/gene_regulatory_architectures.tsv" \
  --top_n 2 \
  --output_dir "$MIN_WARN" > "$TMP_DIR/prepare_minimal.out" 2>&1
assert_grep 'Missing optional annotation column' "$MIN_WARN/enrichment_input_warnings.tsv" "missing optional annotation warning absent"

ENRICH_OUT="$TMP_DIR/enrichment"
python3 "$ROOT_DIR/bin/run_gene_set_enrichment.py" \
  --candidate_gene_sets "$INPUT_OUT/candidate_gene_sets.tsv" \
  --enrichment_background "$INPUT_OUT/enrichment_background.tsv" \
  --gene_sets "$FIX/gene_sets.tsv" \
  --output_dir "$ENRICH_OUT" > "$TMP_DIR/enrich.out" 2>&1
test -s "$ENRICH_OUT/gene_set_enrichment.tsv"
test -s "$ENRICH_OUT/enrichment_warnings.tsv"
assert_header_contains "$ENRICH_OUT/gene_set_enrichment.tsv" "padj" "enrichment output missing padj"
assert_grep 'GS_TOP' "$ENRICH_OUT/gene_set_enrichment.tsv" "expected synthetic gene set absent"
awk 'BEGIN{FS="\t"} NR==1{for(i=1;i<=NF;i++) h[$i]=i; next} $h["candidate_set"]=="genes" && $h["gene_set_id"]=="GS_TOP" && $h["n_overlap"]=="2" && $h["status"]=="OK"{ok=1} END{exit ok?0:1}' "$ENRICH_OUT/gene_set_enrichment.tsv" || {
  cat "$ENRICH_OUT/gene_set_enrichment.tsv"
  echo "FAIL: expected genes/GS_TOP enrichment overlap missing" >&2
  exit 1
}
awk 'BEGIN{FS="\t"} NR==1{for(i=1;i<=NF;i++) h[$i]=i; next} $h["padj"]!="NA" && ($h["padj"]<0 || $h["padj"]>1){bad=1} END{exit bad?1:0}' "$ENRICH_OUT/gene_set_enrichment.tsv" || {
  cat "$ENRICH_OUT/gene_set_enrichment.tsv"
  echo "FAIL: padj values must be bounded between 0 and 1" >&2
  exit 1
}

if python3 "$ROOT_DIR/bin/run_gene_set_enrichment.py" \
  --candidate_gene_sets "$INPUT_OUT/candidate_gene_sets.tsv" \
  --enrichment_background "$INPUT_OUT/enrichment_background.tsv" \
  --gene_sets "$TMP_DIR/missing_gene_sets.tsv" \
  --output_dir "$TMP_DIR/missing_gene_sets_out" > "$TMP_DIR/missing_gene_sets.out" 2>&1; then
  cat "$TMP_DIR/missing_gene_sets.out"
  echo "FAIL: missing gene_sets expected failure" >&2
  exit 1
fi
assert_grep 'Missing required table' "$TMP_DIR/missing_gene_sets.out" "missing gene_sets diagnostic absent"

DISJOINT_SETS="$FIX/gene_sets_disjoint.tsv"
cat > "$DISJOINT_SETS" <<'EOF'
gene_set_id	gene_set_name	gene_orthogroup_id	gene_set_source	description	category	notes
GS_DISJOINT	Disjoint set	OG_GENE_0007	synthetic	no overlap with candidates	background
GS_DISJOINT	Disjoint set	OG_GENE_0008	synthetic	no overlap with candidates	background
EOF
DISJOINT_OUT="$TMP_DIR/enrichment_disjoint"
python3 "$ROOT_DIR/bin/run_gene_set_enrichment.py" \
  --candidate_gene_sets "$INPUT_OUT/candidate_gene_sets.tsv" \
  --enrichment_background "$INPUT_OUT/enrichment_background.tsv" \
  --gene_sets "$DISJOINT_SETS" \
  --output_dir "$DISJOINT_OUT" > "$TMP_DIR/enrich_disjoint.out" 2>&1
test -s "$DISJOINT_OUT/gene_set_enrichment.tsv"
assert_header_contains "$DISJOINT_OUT/gene_set_enrichment.tsv" "padj" "disjoint enrichment missing padj column"
awk 'BEGIN{FS="\t"} NR==1{for(i=1;i<=NF;i++) h[$i]=i; next} $h["n_overlap"]+0 > 0 {bad=1} END{exit bad?1:0}' "$DISJOINT_OUT/gene_set_enrichment.tsv" || {
  cat "$DISJOINT_OUT/gene_set_enrichment.tsv"
  echo "FAIL: disjoint enrichment produced unexpected overlaps" >&2
  exit 1
}

BED_OUT="$TMP_DIR/bed"
python3 "$ROOT_DIR/bin/export_regulatory_regions.py" \
  --candidate_res "$FIX/candidate_res_ranked.tsv" \
  --candidate_gras "$FIX/candidate_gras_ranked.tsv" \
  --feature_to_orthogroup_map "$FIX/feature_to_orthogroup_map.tsv" \
  --gra_re_membership "$FIX/gra_re_membership.tsv" \
  --top_n 3 \
  --min_score 6 \
  --output_dir "$BED_OUT" > "$TMP_DIR/bed.out" 2>&1
test -s "$BED_OUT/candidate_res.bed"
test -s "$BED_OUT/gra_linked_candidate_res.bed"
test -s "$BED_OUT/regulatory_region_export_warnings.tsv"
assert_header_contains "$BED_OUT/candidate_res.bed" "support_summary" "candidate RE BED missing support_summary"
assert_grep 'OG_RE_0001' "$BED_OUT/candidate_res.bed" "coordinate-present RE not exported"
assert_grep 'OG_RE_MISSING' "$BED_OUT/regulatory_region_export_warnings.tsv" "missing coordinate warning absent"

SUMMARY_OUT="$TMP_DIR/summary"
python3 "$ROOT_DIR/bin/summarize_candidate_interpretation.py" \
  --candidate_genes_ranked "$FIX/candidate_genes_ranked.tsv" \
  --candidate_res_ranked "$FIX/candidate_res_ranked.tsv" \
  --candidate_gras_ranked "$FIX/candidate_gras_ranked.tsv" \
  --gene_annotations "$FIX/gene_annotations.tsv" \
  --candidate_gene_sets "$INPUT_OUT/candidate_gene_sets.tsv" \
  --enrichment_background "$INPUT_OUT/enrichment_background.tsv" \
  --enrichment_input_warnings "$INPUT_OUT/enrichment_input_warnings.tsv" \
  --gene_set_enrichment "$ENRICH_OUT/gene_set_enrichment.tsv" \
  --enrichment_warnings "$ENRICH_OUT/enrichment_warnings.tsv" \
  --candidate_res_bed "$BED_OUT/candidate_res.bed" \
  --gra_linked_candidate_res_bed "$BED_OUT/gra_linked_candidate_res.bed" \
  --regulatory_region_export_warnings "$BED_OUT/regulatory_region_export_warnings.tsv" \
  --output_dir "$SUMMARY_OUT" > "$TMP_DIR/summary.out" 2>&1
test -s "$SUMMARY_OUT/candidate_gene_interpretation.tsv"
test -s "$SUMMARY_OUT/candidate_re_interpretation.tsv"
test -s "$SUMMARY_OUT/candidate_gra_interpretation.tsv"
test -s "$SUMMARY_OUT/functional_interpretation_summary.tsv"
test -s "$SUMMARY_OUT/functional_interpretation_outputs_manifest.tsv"
assert_grep 'n_enrichment_results' "$SUMMARY_OUT/functional_interpretation_summary.tsv" "summary missing enrichment metric"

NF_OUT="$TMP_DIR/nf_results"
mkdir -p "$NF_OUT/candidates/ranked" "$NF_OUT/orthology" "$NF_OUT/gra/tables"
cp "$FIX/candidate_genes_ranked.tsv" "$NF_OUT/candidates/ranked/candidate_genes_ranked.tsv"
cp "$FIX/candidate_res_ranked.tsv" "$NF_OUT/candidates/ranked/candidate_res_ranked.tsv"
cp "$FIX/candidate_gras_ranked.tsv" "$NF_OUT/candidates/ranked/candidate_gras_ranked.tsv"
cp "$FIX/candidate_all_ranked.tsv" "$NF_OUT/candidates/ranked/candidate_all_ranked.tsv"
cp "$FIX/feature_to_orthogroup_map.tsv" "$NF_OUT/orthology/feature_to_orthogroup_map.tsv"
cp "$FIX/gene_regulatory_architectures.tsv" "$NF_OUT/gra/tables/gene_regulatory_architectures.tsv"
cp "$FIX/gra_re_membership.tsv" "$NF_OUT/gra/tables/gra_re_membership.tsv"

if ! nextflow run "$ROOT_DIR" \
  --run_stage functional_interpretation \
  --outdir "$NF_OUT" \
  --gene_annotations "$FIX/gene_annotations.tsv" \
  --gene_sets "$FIX/gene_sets.tsv" \
  --functional_interpretation_top_n 3 > "$TMP_DIR/nf_stage11.out" 2>&1; then
  cat "$TMP_DIR/nf_stage11.out"
  echo "FAIL: Nextflow functional_interpretation failed" >&2
  exit 1
fi
test -s "$NF_OUT/interpretation/input/candidate_gene_sets.tsv"
test -s "$NF_OUT/interpretation/enrichment/gene_set_enrichment.tsv"
test -s "$NF_OUT/interpretation/regulatory_regions/candidate_res.bed"
test -s "$NF_OUT/interpretation/summary/functional_interpretation_summary.tsv"
assert_nonempty_rows "$NF_OUT/interpretation/summary/candidate_gene_interpretation.tsv" "Nextflow gene interpretation has no rows"
awk 'BEGIN{FS="\t"} NR==1{for(i=1;i<=NF;i++) h[$i]=i; next} $h["output_name"]=="candidate_gene_interpretation" && $h["status"]=="present"{ok=1} END{exit ok?0:1}' "$NF_OUT/interpretation/summary/functional_interpretation_outputs_manifest.tsv" || {
  cat "$NF_OUT/interpretation/summary/functional_interpretation_outputs_manifest.tsv"
  echo "FAIL: interpretation manifest did not mark summary outputs present" >&2
  exit 1
}

if rg 'DDR|RoR' \
  "$ROOT_DIR/bin/prepare_enrichment_inputs.py" \
  "$ROOT_DIR/bin/run_gene_set_enrichment.py" \
  "$ROOT_DIR/bin/export_regulatory_regions.py" \
  "$ROOT_DIR/bin/summarize_candidate_interpretation.py" \
  "$ROOT_DIR/workflows/functional_interpretation.nf" \
  "$ROOT_DIR/subworkflows/gene_set_enrichment.nf" \
  "$ROOT_DIR/subworkflows/regulatory_region_export.nf" \
  "$ROOT_DIR/subworkflows/candidate_interpretation.nf" >/dev/null 2>&1; then
  echo "FAIL: Stage 11 core files contain profile-specific terms" >&2
  exit 1
fi

echo "functional interpretation tests passed"
