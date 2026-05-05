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

assert_not_grep() {
  pattern="$1"
  file="$2"
  message="$3"
  if grep -q "$pattern" "$file"; then
    cat "$file"
    echo "FAIL: $message" >&2
    exit 1
  fi
}

assert_file() {
  file="$1"
  message="$2"
  if [ ! -s "$file" ]; then
    echo "FAIL: $message" >&2
    exit 1
  fi
}

RESULTS="$TMP_DIR/results"
mkdir -p "$RESULTS/validation" "$RESULTS/final/release_checks"

cat > "$RESULTS/validation/metadata_validation_report.tsv" <<'EOF'
severity	rule_id	source	field	row	message	suggestion
INFO		validation			ok	n/a
EOF

cat > "$RESULTS/validation/study_profile_validation_report.tsv" <<'EOF'
severity	rule_id	source	field	row	message	suggestion
INFO		study_profile			ok	n/a
EOF

cat > "$RESULTS/final/release_checks/came_release_checks.tsv" <<'EOF'
check_id	status	subject	message	remediation
stage16_files	PASS	Stage 16	present	
optional_review	WARNING	final_report	review optional warnings	
EOF

cat > "$RESULTS/final/release_checks/came_release_summary.tsv" <<'EOF'
status	count
PASS	1
WARNING	1
EOF

python3 "$ROOT_DIR/bin/collect_run_outputs.py" \
  --results_dir "$RESULTS" \
  --output_dir "$RESULTS/final/manifest" > "$TMP_DIR/collect.out" 2>&1
assert_file "$RESULTS/final/manifest/came_outputs_manifest.tsv" "manifest missing"
assert_file "$RESULTS/final/manifest/came_stage_completion_summary.tsv" "stage summary missing"
assert_file "$RESULTS/final/manifest/came_missing_outputs.tsv" "missing output summary missing"

NO_GIT_PROJECT="$TMP_DIR/no_git_project"
mkdir -p "$NO_GIT_PROJECT"
printf '0.1-test\n' > "$NO_GIT_PROJECT/VERSION"
python3 "$ROOT_DIR/bin/collect_run_provenance.py" \
  --project_dir "$NO_GIT_PROJECT" \
  --results_dir "$RESULTS" \
  --output_dir "$TMP_DIR/no_git_provenance" > "$TMP_DIR/no_git_provenance.out" 2>&1
assert_file "$TMP_DIR/no_git_provenance/came_run_provenance.tsv" "no-git provenance missing"
assert_file "$TMP_DIR/no_git_provenance/came_parameters_snapshot.tsv" "no-git params missing"
assert_grep '^git	commit		WARNING' "$TMP_DIR/no_git_provenance/came_run_provenance.tsv" "no-git provenance should warn"
assert_grep '^params_snapshot		WARNING' "$TMP_DIR/no_git_provenance/came_parameters_snapshot.tsv" "missing params should warn"

PARAMS="$TMP_DIR/params.tsv"
cat > "$PARAMS" <<EOF
parameter	value
study_profile	$ROOT_DIR/profiles/generic/study_profile.yaml
outdir	$RESULTS
EOF

if command -v git >/dev/null 2>&1; then
  GIT_PROJECT="$TMP_DIR/git_project"
  mkdir -p "$GIT_PROJECT"
  printf '0.1-test\n' > "$GIT_PROJECT/VERSION"
  git -C "$GIT_PROJECT" init > "$TMP_DIR/git_init.out" 2>&1
  git -C "$GIT_PROJECT" config user.email came@example.invalid
  git -C "$GIT_PROJECT" config user.name CAME
  git -C "$GIT_PROJECT" add VERSION
  git -C "$GIT_PROJECT" commit -m init > "$TMP_DIR/git_commit.out" 2>&1
  python3 "$ROOT_DIR/bin/collect_run_provenance.py" \
    --project_dir "$GIT_PROJECT" \
    --results_dir "$RESULTS" \
    --output_dir "$TMP_DIR/git_provenance" > "$TMP_DIR/git_provenance.out" 2>&1
  assert_grep '^git	commit	[0-9a-f]' "$TMP_DIR/git_provenance/came_run_provenance.tsv" "git commit missing from provenance"
fi

python3 "$ROOT_DIR/bin/collect_run_provenance.py" \
  --project_dir "$ROOT_DIR" \
  --results_dir "$RESULTS" \
  --output_dir "$RESULTS/final/provenance" \
  --params_snapshot "$PARAMS" > "$TMP_DIR/project_provenance.out" 2>&1
assert_file "$RESULTS/final/provenance/came_run_provenance.tsv" "provenance missing"
assert_file "$RESULTS/final/provenance/came_parameters_snapshot.tsv" "parameter snapshot missing"
assert_grep '^study_profile	profiles/generic/study_profile.yaml' "$RESULTS/final/provenance/came_parameters_snapshot.tsv" "project path was not normalized"
assert_not_grep "$ROOT_DIR" "$RESULTS/final/provenance/came_parameters_snapshot.tsv" "parameter snapshot leaked project absolute path"

python3 "$ROOT_DIR/bin/make_report_assets.py" \
  --results_dir "$RESULTS" \
  --manifest "$RESULTS/final/manifest/came_outputs_manifest.tsv" \
  --stage_summary "$RESULTS/final/manifest/came_stage_completion_summary.tsv" \
  --missing_outputs "$RESULTS/final/manifest/came_missing_outputs.tsv" \
  --release_checks "$RESULTS/final/release_checks/came_release_checks.tsv" \
  --release_summary "$RESULTS/final/release_checks/came_release_summary.tsv" \
  --output_dir "$RESULTS/final/assets" > "$TMP_DIR/assets.out" 2>&1
assert_file "$RESULTS/final/assets/report_asset_manifest.tsv" "asset manifest missing"
assert_file "$RESULTS/final/assets/stage_completion_summary.tsv" "stage asset missing"
assert_file "$RESULTS/final/assets/top_candidates.tsv" "top candidates asset missing"
assert_file "$RESULTS/final/assets/top_enriched_gene_sets.tsv" "top enrichment asset missing"
assert_file "$RESULTS/final/assets/warning_summary.tsv" "warning asset missing"
assert_grep 'missing_optional' "$RESULTS/final/assets/top_candidates.tsv" "missing candidate table should be optional"
assert_grep 'missing_optional' "$RESULTS/final/assets/top_enriched_gene_sets.tsv" "missing enrichment table should be optional"

python3 "$ROOT_DIR/bin/render_final_report.py" \
  --study_profile "$ROOT_DIR/profiles/generic/study_profile.yaml" \
  --results_dir "$RESULTS" \
  --manifest "$RESULTS/final/manifest/came_outputs_manifest.tsv" \
  --stage_summary "$RESULTS/final/manifest/came_stage_completion_summary.tsv" \
  --missing_outputs "$RESULTS/final/manifest/came_missing_outputs.tsv" \
  --release_checks "$RESULTS/final/release_checks/came_release_checks.tsv" \
  --release_summary "$RESULTS/final/release_checks/came_release_summary.tsv" \
  --output_dir "$RESULTS/final/report" \
  --template_dir "$ROOT_DIR/templates" \
  --provenance "$RESULTS/final/provenance/came_run_provenance.tsv" \
  --parameters "$RESULTS/final/provenance/came_parameters_snapshot.tsv" \
  --asset_manifest "$RESULTS/final/assets/report_asset_manifest.tsv" \
  --asset_stage_completion "$RESULTS/final/assets/stage_completion_summary.tsv" \
  --asset_top_candidates "$RESULTS/final/assets/top_candidates.tsv" \
  --asset_top_enriched_gene_sets "$RESULTS/final/assets/top_enriched_gene_sets.tsv" \
  --asset_warning_summary "$RESULTS/final/assets/warning_summary.tsv" > "$TMP_DIR/render.out" 2>&1
assert_file "$RESULTS/final/report/came_final_report.html" "HTML report missing"
assert_file "$RESULTS/final/report/came_final_report.md" "Markdown report missing"
assert_file "$RESULTS/final/report/came_report.css" "CSS missing"
assert_grep 'Run Provenance' "$RESULTS/final/report/came_final_report.html" "provenance section missing"
assert_grep 'href="came_report.css"' "$RESULTS/final/report/came_final_report.html" "external CSS link missing"
assert_grep 'missing_optional' "$RESULTS/final/report/came_final_report.html" "missing optional status absent"
assert_grep 'Run Provenance' "$RESULTS/final/report/came_final_report.md" "Markdown provenance section missing"
assert_not_grep 'href="/' "$RESULTS/final/report/came_final_report.html" "HTML contains absolute href"
assert_not_grep "$TMP_DIR" "$RESULTS/final/report/came_final_report.html" "HTML leaked temporary absolute path"

NF_OUT="$TMP_DIR/nf_results"
mkdir -p "$NF_OUT"
cp -R "$RESULTS/." "$NF_OUT/"
rm -rf "$NF_OUT/final"
if ! nextflow run "$ROOT_DIR" \
  --run_stage final_report \
  --study_profile "$ROOT_DIR/profiles/generic/study_profile.yaml" \
  --outdir "$NF_OUT" > "$TMP_DIR/nf_final_report.out" 2>&1; then
  cat "$TMP_DIR/nf_final_report.out"
  echo "FAIL: Nextflow final_report failed" >&2
  exit 1
fi
assert_file "$NF_OUT/final/provenance/came_run_provenance.tsv" "Nextflow provenance missing"
assert_file "$NF_OUT/final/assets/report_asset_manifest.tsv" "Nextflow asset manifest missing"
assert_file "$NF_OUT/final/report/came_report.css" "Nextflow CSS missing"
assert_grep 'Run Provenance' "$NF_OUT/final/report/came_final_report.html" "Nextflow report missing provenance"

echo "report polish tests passed"
