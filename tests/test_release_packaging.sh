#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
BAD_FILE="$ROOT_DIR/bin/release_packaging_bad_path_tmp.py"
trap 'rm -rf "$TMP_DIR"; rm -f "$BAD_FILE"' EXIT INT TERM

assert_file() {
  file="$1"
  message="$2"
  if [ ! -s "$file" ]; then
    echo "FAIL: $message" >&2
    exit 1
  fi
}

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
  if grep -Eq "$pattern" "$file"; then
    cat "$file"
    echo "FAIL: $message" >&2
    exit 1
  fi
}

python3 "$ROOT_DIR/bin/print_versions.py" --output "$TMP_DIR/tool_versions.tsv" > "$TMP_DIR/print_versions.out" 2>&1
assert_file "$TMP_DIR/tool_versions.tsv" "print_versions.py did not write version table"
assert_grep '^python	cli	present' "$TMP_DIR/tool_versions.tsv" "Python version row missing"

VALIDATION_OUT="$TMP_DIR/release_bundle_validation.tsv"
python3 "$ROOT_DIR/bin/validate_release_bundle.py" --output "$VALIDATION_OUT" > "$TMP_DIR/validate.out" 2>&1
assert_file "$VALIDATION_OUT" "validate_release_bundle.py did not write validation table"
assert_grep '^run_stage_documentation	PASS' "$VALIDATION_OUT" "run_stage documentation check did not pass"
assert_grep '^workflow_files	PASS' "$VALIDATION_OUT" "required workflow file check did not pass"
assert_grep '^release_metadata_files	PASS' "$VALIDATION_OUT" "release metadata file check did not pass"
assert_grep '^license_gplv3	PASS' "$VALIDATION_OUT" "GPLv3 license check did not pass"
assert_grep '^citation_metadata	PASS' "$VALIDATION_OUT" "citation metadata check did not pass"
assert_grep '^version_parse	PASS' "$VALIDATION_OUT" "VERSION parse check did not pass"
assert_grep '^readme_release_links	PASS' "$VALIDATION_OUT" "README release links check did not pass"
assert_grep '^schema_files	PASS' "$VALIDATION_OUT" "schema file check did not pass"
assert_grep '^schema_sync	PASS' "$VALIDATION_OUT" "schema sync check did not pass"
assert_grep '^conda_linux_lock	PASS' "$VALIDATION_OUT" "conda linux lock check did not pass"
assert_grep '^nanoseq_not_advertised	PASS' "$VALIDATION_OUT" "NanoSeq overclaim check did not pass"
assert_grep '^optional_scaffold_docs	PASS' "$VALIDATION_OUT" "optional scaffold documentation check did not pass"
assert_grep '^real_mode_fixture_files	PASS' "$VALIDATION_OUT" "real-mode fixture packaging check did not pass"

for required in \
  "$ROOT_DIR/.github/workflows/ci.yml" \
  "$ROOT_DIR/.github/workflows/publish_container.yml" \
  "$ROOT_DIR/.github/ISSUE_TEMPLATE/bug_report.md" \
  "$ROOT_DIR/.github/ISSUE_TEMPLATE/feature_request.md" \
  "$ROOT_DIR/.github/PULL_REQUEST_TEMPLATE.md" \
  "$ROOT_DIR/.github/dependabot.yml" \
  "$ROOT_DIR/environment/came_environment.yml" \
  "$ROOT_DIR/environment/conda-linux-64.lock" \
  "$ROOT_DIR/environment/requirements.txt" \
  "$ROOT_DIR/environment/install_local.sh" \
  "$ROOT_DIR/environment/install_r_packages.R" \
  "$ROOT_DIR/LICENSE" \
  "$ROOT_DIR/CITATION.cff" \
  "$ROOT_DIR/README.md" \
  "$ROOT_DIR/CHANGELOG.md" \
  "$ROOT_DIR/docs/installation.md" \
  "$ROOT_DIR/docs/ci_and_release.md" \
  "$ROOT_DIR/docs/profile_authoring.md" \
  "$ROOT_DIR/docs/versioning.md" \
  "$ROOT_DIR/docs/release_notes_v0.1.md" \
  "$ROOT_DIR/docs/report_customization.md" \
  "$ROOT_DIR/docs/real_mode_fixture_strategy.md" \
  "$ROOT_DIR/templates/came_report.css" \
  "$ROOT_DIR/templates/came_report_template.html" \
  "$ROOT_DIR/templates/came_report_template.md" \
  "$ROOT_DIR/Dockerfile" \
  "$ROOT_DIR/.dockerignore" \
  "$ROOT_DIR/schemas/reference_manifest.schema.json" \
  "$ROOT_DIR/schemas/real_mode_metadata.schema.json" \
  "$ROOT_DIR/assets/schema/reference_manifest.schema.json" \
  "$ROOT_DIR/assets/schema/reference_manifest_legacy.schema.json" \
  "$ROOT_DIR/bin/collect_run_provenance.py" \
  "$ROOT_DIR/bin/make_real_mode_fixtures.py" \
  "$ROOT_DIR/bin/make_report_assets.py" \
  "$ROOT_DIR/bin/validate_real_mode_fixtures.py" \
  "$ROOT_DIR/tests/test_report_polish.sh" \
  "$ROOT_DIR/tests/test_real_mode_fixtures.sh" \
  "$ROOT_DIR/tests/test_profile_examples.sh" \
  "$ROOT_DIR/assets/test_data/real_mode_fixtures/README.md" \
  "$ROOT_DIR/assets/test_data/real_mode_fixtures/manifests/reference_manifest.tsv" \
  "$ROOT_DIR/assets/test_data/real_mode_fixtures/manifests/real_mode_metadata.tsv" \
  "$ROOT_DIR/assets/test_data/real_mode_fixtures/manifests/wgs_samplesheet.csv" \
  "$ROOT_DIR/assets/test_data/real_mode_fixtures/manifests/expected_output_contracts.tsv" \
  "$ROOT_DIR/VERSION"
do
  assert_file "$required" "required release packaging file missing: $required"
done

LIST_STAGES_OUT="$TMP_DIR/list_stages.out"
nextflow run "$ROOT_DIR" --list_stages true > "$LIST_STAGES_OUT" 2>&1
assert_grep 'run_stage.*maturity.*included_in_all.*real_mode_scope.*notes' "$LIST_STAGES_OUT" "--list_stages header missing"
assert_grep 'reference_prepare.*scaffold.*false' "$LIST_STAGES_OUT" "--list_stages missing reference_prepare scaffold row"
assert_grep 'wgs_variants.*production.*false' "$LIST_STAGES_OUT" "--list_stages missing wgs_variants optional row"
assert_grep 'all.*orchestration' "$LIST_STAGES_OUT" "--list_stages missing all orchestration row"

assert_grep 'GNU GENERAL PUBLIC LICENSE' "$ROOT_DIR/LICENSE" "LICENSE does not contain GPLv3 title"
assert_grep 'Version 3, 29 June 2007' "$ROOT_DIR/LICENSE" "LICENSE does not contain GPLv3 version"
assert_grep 'END OF TERMS AND CONDITIONS' "$ROOT_DIR/LICENSE" "LICENSE appears incomplete"

assert_grep '^cff-version:' "$ROOT_DIR/CITATION.cff" "CITATION.cff missing cff-version"
assert_grep '^title:' "$ROOT_DIR/CITATION.cff" "CITATION.cff missing title"
assert_grep '^message:' "$ROOT_DIR/CITATION.cff" "CITATION.cff missing message"
assert_grep '^version:' "$ROOT_DIR/CITATION.cff" "CITATION.cff missing version"
assert_grep '^date-released:' "$ROOT_DIR/CITATION.cff" "CITATION.cff missing date-released"
assert_grep '^authors:' "$ROOT_DIR/CITATION.cff" "CITATION.cff missing authors"
assert_grep '^repository-code:' "$ROOT_DIR/CITATION.cff" "CITATION.cff missing repository-code"
assert_grep '^abstract:' "$ROOT_DIR/CITATION.cff" "CITATION.cff missing abstract"
assert_grep '^keywords:' "$ROOT_DIR/CITATION.cff" "CITATION.cff missing keywords"
assert_grep '^license: GPL-3.0-only$' "$ROOT_DIR/CITATION.cff" "CITATION.cff missing GPL-3.0-only license"

if ! grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$|^[0-9]+\.[0-9]+\.[0-9]+-[0-9A-Za-z.-]+(\+[0-9A-Za-z.-]+)?$' "$ROOT_DIR/VERSION"; then
  cat "$ROOT_DIR/VERSION"
  echo "FAIL: VERSION is not parseable SemVer" >&2
  exit 1
fi

assert_grep 'v0.1' "$ROOT_DIR/docs/release_notes_v0.1.md" "release notes do not mention v0.1 scope"
assert_grep 'Known Limitations' "$ROOT_DIR/docs/release_notes_v0.1.md" "release notes missing limitations"
assert_grep 'NanoSeq and mutation profiling are not implemented' "$ROOT_DIR/docs/release_notes_v0.1.md" "release notes missing NanoSeq skipped status"
assert_grep 'GPL-3.0-only' "$ROOT_DIR/docs/release_notes_v0.1.md" "release notes missing license"
assert_grep 'Stub-mode validation is the v0.1 release gate' "$ROOT_DIR/docs/versioning.md" "versioning doc missing stub-mode release gate"

for doc in \
  "$ROOT_DIR/docs/versioning.md" \
  "$ROOT_DIR/docs/release_notes_v0.1.md" \
  "$ROOT_DIR/README.md" \
  "$ROOT_DIR/CHANGELOG.md"
do
  assert_not_grep '(^|[^A-Za-z0-9_])(/Users/|/home/[A-Za-z0-9._-]+/|/var/folders/|/tmp/)' "$doc" "release doc contains local absolute path: $doc"
done

if grep -Eiq 'implemented[[:alnum:][:space:][:punct:]]*NanoSeq|production[[:alnum:][:space:][:punct:]]*NanoSeq|implemented[[:alnum:][:space:][:punct:]]*mutation profiling' "$ROOT_DIR/README.md" "$ROOT_DIR/docs/"*.md; then
  echo "FAIL: docs contain an unsupported claim that NanoSeq or mutation profiling is implemented" >&2
  exit 1
fi

printf 'BAD_PATH = "%s"\n' '/Users/example/local.tsv' > "$BAD_FILE"
if python3 "$ROOT_DIR/bin/validate_release_bundle.py" --output "$TMP_DIR/bad_validation.tsv" > "$TMP_DIR/bad_validate.out" 2>&1; then
  cat "$TMP_DIR/bad_validation.tsv"
  echo "FAIL: release bundle validator should fail on a temporary local absolute path" >&2
  exit 1
fi
assert_grep '^absolute_path_scan	ERROR' "$TMP_DIR/bad_validation.tsv" "absolute path detector did not flag temporary bad file"
rm -f "$BAD_FILE"

bash "$ROOT_DIR/tests/test_metadata_validation.sh"
bash "$ROOT_DIR/tests/test_final_report.sh"

echo "release packaging tests passed"
