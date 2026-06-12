#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

PYTHON=${PYTHON:-python3}
RUNNER="$ROOT_DIR/bin/run_orthology_reference_prepare.py"
FIXTURE_DIR="$ROOT_DIR/assets/test_data/orthology_reference_bundle"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

assert_file() {
  [ -s "$1" ] || fail "$2"
}

assert_grep() {
  local pattern="$1"
  local file="$2"
  local message="$3"
  if ! grep -Eq "$pattern" "$file"; then
    cat "$file" >&2
    fail "$message"
  fi
}

assert_no_grep() {
  local pattern="$1"
  local file="$2"
  local message="$3"
  if grep -Eq "$pattern" "$file"; then
    cat "$file" >&2
    fail "$message"
  fi
}

cat > "$TMP_DIR/mock_bundle_generator.py" <<'PY'
#!/usr/bin/env python3
import argparse
import shutil
from pathlib import Path


parser = argparse.ArgumentParser()
parser.add_argument("--run-dir", required=True)
parser.add_argument("--out-dir", required=True)
parser.add_argument("--created-at", default="")
args = parser.parse_args()

run_dir = Path(args.run_dir)
out_dir = Path(args.out_dir)
out_dir.mkdir(parents=True, exist_ok=True)
for name in ("alignments", "masks", "elements"):
    shutil.copytree(run_dir / name, out_dir / name, dirs_exist_ok=True)
shutil.copy2(run_dir / "manifest_external_liftover.tsv", out_dir / "orthology_reference_bundle.tsv")
(out_dir / "generator_seen_created_at.txt").write_text(args.created_at + "\n")
PY
chmod +x "$TMP_DIR/mock_bundle_generator.py"

cat > "$TMP_DIR/no_manifest_generator.py" <<'PY'
#!/usr/bin/env python3
import argparse
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--run-dir", required=True)
parser.add_argument("--out-dir", required=True)
args = parser.parse_args()
Path(args.out_dir).mkdir(parents=True, exist_ok=True)
PY
chmod +x "$TMP_DIR/no_manifest_generator.py"

cat > "$TMP_DIR/failing_generator.py" <<'PY'
#!/usr/bin/env python3
raise SystemExit(3)
PY
chmod +x "$TMP_DIR/failing_generator.py"

cat > "$TMP_DIR/bad_manifest_generator.py" <<'PY'
#!/usr/bin/env python3
import argparse
import csv
import shutil
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--run-dir", required=True)
parser.add_argument("--out-dir", required=True)
args = parser.parse_args()
run_dir = Path(args.run_dir)
out_dir = Path(args.out_dir)
out_dir.mkdir(parents=True, exist_ok=True)
for name in ("alignments", "masks", "elements"):
    shutil.copytree(run_dir / name, out_dir / name, dirs_exist_ok=True)
rows = list(csv.DictReader((run_dir / "manifest_external_liftover.tsv").open(), delimiter="\t"))
fields = list(rows[0].keys())
rows[0]["schema_version"] = "orthology_reference_bundle.v0"
with (out_dir / "orthology_reference_bundle.tsv").open("w", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=fields, delimiter="\t", lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
PY
chmod +x "$TMP_DIR/bad_manifest_generator.py"

STUB_OUT="$TMP_DIR/direct_stub"
"$PYTHON" "$RUNNER" --output-dir "$STUB_OUT" --stub true > "$TMP_DIR/direct_stub.log" 2>&1
assert_file "$STUB_OUT/bundle/orthology_reference_bundle.tsv" "stub bundle manifest missing"
assert_file "$STUB_OUT/orthology_reference_bundle_validation.tsv" "stub validation report missing"
assert_file "$STUB_OUT/orthology_reference_prepare_summary.tsv" "stub summary missing"
assert_grep '^mode	stub$' "$STUB_OUT/orthology_reference_prepare_summary.tsv" "stub summary did not record mode"
assert_grep '^status	STUB$' "$STUB_OUT/orthology_reference_prepare_summary.tsv" "stub summary did not record STUB status"
assert_grep 'STUB.*header-only bundle manifest' "$STUB_OUT/orthology_reference_bundle_validation.tsv" "stub validation did not describe header-only bundle"
if [ -e "$STUB_OUT/orthology_reference_prepare_command.log" ]; then
  fail "stub mode should not write an external command log"
fi

PREFLIGHT_OUT="$TMP_DIR/direct_preflight"
set +e
"$PYTHON" "$RUNNER" \
  --output-dir "$PREFLIGHT_OUT" \
  --stub false \
  --command "$PYTHON $TMP_DIR/mock_bundle_generator.py" \
  --run-dir "$TMP_DIR/does_not_exist" > "$TMP_DIR/direct_preflight.log" 2>&1
PREFLIGHT_STATUS=$?
set -e
if [ "$PREFLIGHT_STATUS" -ne 2 ]; then
  cat "$PREFLIGHT_OUT/orthology_reference_bundle_validation.tsv" >&2 || true
  fail "direct preflight failure should exit 2"
fi
assert_file "$PREFLIGHT_OUT/orthology_reference_bundle_validation.tsv" "direct preflight validation report missing"
assert_grep 'Run directory does not exist' "$PREFLIGHT_OUT/orthology_reference_bundle_validation.tsv" "specific preflight diagnostic absent"
assert_no_grep 'External orthology reference bundle command exited' "$PREFLIGHT_OUT/orthology_reference_bundle_validation.tsv" "preflight diagnostic was overwritten"
if [ -e "$PREFLIGHT_OUT/orthology_reference_prepare_command.log" ]; then
  fail "preflight failure should not write a command log"
fi

EXT_OUT="$TMP_DIR/direct_external"
"$PYTHON" "$RUNNER" \
  --output-dir "$EXT_OUT" \
  --stub false \
  --command "$PYTHON $TMP_DIR/mock_bundle_generator.py" \
  --run-dir "$FIXTURE_DIR" \
  --created-at "2026-01-02T03:04:05Z" \
  --check-paths true > "$TMP_DIR/direct_external.log" 2>&1
assert_file "$EXT_OUT/bundle/orthology_reference_bundle.tsv" "external bundle manifest missing"
assert_file "$EXT_OUT/bundle/generator_seen_created_at.txt" "mock generator did not receive created_at"
assert_grep '^2026-01-02T03:04:05Z$' "$EXT_OUT/bundle/generator_seen_created_at.txt" "created_at was not forwarded"
assert_file "$EXT_OUT/orthology_reference_prepare_command.log" "external command log missing"
assert_file "$EXT_OUT/orthology_reference_bundle_validation.tsv" "external validation report missing"
assert_no_grep '^ERROR	' "$EXT_OUT/orthology_reference_bundle_validation.tsv" "valid external bundle emitted errors"
assert_grep '^mode	external$' "$EXT_OUT/orthology_reference_prepare_summary.tsv" "external summary did not record mode"
assert_grep '^status	OK$' "$EXT_OUT/orthology_reference_prepare_summary.tsv" "external summary did not record OK status"
assert_grep 'boundary: CAME orchestration only' "$EXT_OUT/orthology_reference_prepare_command.log" "command log missing boundary note"

NO_MANIFEST_OUT="$TMP_DIR/direct_no_manifest"
if "$PYTHON" "$RUNNER" \
  --output-dir "$NO_MANIFEST_OUT" \
  --stub false \
  --command "$PYTHON $TMP_DIR/no_manifest_generator.py" \
  --run-dir "$FIXTURE_DIR" > "$TMP_DIR/direct_no_manifest.log" 2>&1; then
  fail "external command that omits manifest should fail"
fi
assert_file "$NO_MANIFEST_OUT/orthology_reference_bundle_validation.tsv" "missing-manifest case did not write validation report"
assert_grep 'did not write .*orthology_reference_bundle.tsv' "$NO_MANIFEST_OUT/orthology_reference_bundle_validation.tsv" "missing-manifest error absent"
assert_no_grep 'Traceback' "$TMP_DIR/direct_no_manifest.log" "missing-manifest case produced traceback"

FAIL_OUT="$TMP_DIR/direct_fail"
if "$PYTHON" "$RUNNER" \
  --output-dir "$FAIL_OUT" \
  --stub false \
  --command "$PYTHON $TMP_DIR/failing_generator.py" \
  --run-dir "$FIXTURE_DIR" > "$TMP_DIR/direct_fail.log" 2>&1; then
  fail "failing external command should fail"
fi
assert_file "$FAIL_OUT/orthology_reference_prepare_command.log" "failing command log missing"
assert_grep 'External orthology reference bundle command exited 3' "$FAIL_OUT/orthology_reference_bundle_validation.tsv" "external failure diagnostic absent"
assert_no_grep 'Traceback' "$TMP_DIR/direct_fail.log" "external failure produced traceback"

NF_STUB_OUT="$TMP_DIR/nf_stub_results"
nextflow run "$ROOT_DIR" \
  --run_stage orthology_reference_prepare \
  --orthology_reference_prepare_stub true \
  --outdir "$NF_STUB_OUT" > "$TMP_DIR/nf_stub.log" 2>&1
assert_file "$NF_STUB_OUT/orthology_reference_prepare/bundle/orthology_reference_bundle.tsv" "Nextflow stub bundle manifest missing"
assert_file "$NF_STUB_OUT/orthology_reference_prepare/orthology_reference_prepare_summary.tsv" "Nextflow stub summary missing"
assert_grep '^status	STUB$' "$NF_STUB_OUT/orthology_reference_prepare/orthology_reference_prepare_summary.tsv" "Nextflow stub summary did not record STUB"

NF_EXT_OUT="$TMP_DIR/nf_external_results"
nextflow run "$ROOT_DIR" \
  --run_stage orthology_reference_prepare \
  --orthology_reference_prepare_stub false \
  --orthology_reference_prepare_cmd "$PYTHON $TMP_DIR/mock_bundle_generator.py" \
  --orthology_reference_prepare_run_dir "$FIXTURE_DIR" \
  --orthology_reference_prepare_created_at "2026-01-02T03:04:05Z" \
  --outdir "$NF_EXT_OUT" > "$TMP_DIR/nf_external.log" 2>&1
assert_file "$NF_EXT_OUT/orthology_reference_prepare/bundle/orthology_reference_bundle.tsv" "Nextflow external bundle manifest missing"
assert_file "$NF_EXT_OUT/orthology_reference_prepare/orthology_reference_bundle_validation.tsv" "Nextflow external validation report missing"
assert_no_grep '^ERROR	' "$NF_EXT_OUT/orthology_reference_prepare/orthology_reference_bundle_validation.tsv" "Nextflow external validation emitted errors"
assert_grep '^status	OK$' "$NF_EXT_OUT/orthology_reference_prepare/orthology_reference_prepare_summary.tsv" "Nextflow external summary did not record OK"

NF_BAD_OUT="$TMP_DIR/nf_bad_manifest_results"
if nextflow run "$ROOT_DIR" \
  --run_stage orthology_reference_prepare \
  --orthology_reference_prepare_stub false \
  --orthology_reference_prepare_cmd "$PYTHON $TMP_DIR/bad_manifest_generator.py" \
  --orthology_reference_prepare_run_dir "$FIXTURE_DIR" \
  --outdir "$NF_BAD_OUT" > "$TMP_DIR/nf_bad_manifest.log" 2>&1; then
  fail "Nextflow invalid generated manifest should fail after publishing validation"
fi
assert_file "$NF_BAD_OUT/orthology_reference_prepare/orthology_reference_bundle_validation.tsv" "invalid manifest validation report was not published"
assert_grep 'Unsupported schema_version' "$NF_BAD_OUT/orthology_reference_prepare/orthology_reference_bundle_validation.tsv" "invalid manifest error absent from published validation"
assert_grep 'orthology_reference_prepare failed with exit code' "$TMP_DIR/nf_bad_manifest.log" "checker failure diagnostic absent"

if nextflow run "$ROOT_DIR" \
  --run_stage orthology_reference_prepare \
  --orthology_reference_prepare_stub false \
  --orthology_reference_prepare_run_dir "$FIXTURE_DIR" \
  --outdir "$TMP_DIR/nf_missing_cmd_results" > "$TMP_DIR/nf_missing_cmd.log" 2>&1; then
  fail "Nextflow real mode without command should fail validation"
fi
assert_grep 'requires --orthology_reference_prepare_cmd' "$TMP_DIR/nf_missing_cmd.log" "missing command validation diagnostic absent"

nextflow run "$ROOT_DIR" --list_stages true > "$TMP_DIR/list_stages.log" 2>&1
assert_grep 'orthology_reference_prepare	basic	false' "$TMP_DIR/list_stages.log" "orthology_reference_prepare not listed as excluded basic stage"

echo "orthology_reference_prepare tests passed"
