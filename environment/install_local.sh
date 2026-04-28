#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ENV_DIR="$ROOT_DIR/environment"
HMMRATAC_JAR=""

CHECK_ONLY=false
CREATE_ENV=false
INSTALL_R=false
INSTALL_HMMRATAC=false

usage() {
  cat <<'EOF'
Usage: environment/install_local.sh [options]

Options:
  --check-only                         Record detected tool/package versions only.
  --create-env                         Create the conda environment from environment/came_environment.yml.
  --create-conda-env                   Backward-compatible alias for --create-env.
  --install-r                          Install/check core R packages; DESeq2 is checked but optional.
  --install-r-with-deseq2              Install/check core R packages and attempt DESeq2.
  --install-hmmratac --hmmratac-jar P  Copy an existing HMMRATAC jar into environment/tools/.
  -h, --help                           Show this help.

The script uses conda and does not edit global shell configuration.
No installation is performed unless an explicit install flag is provided.
EOF
}

INSTALL_DESEQ2=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check-only) CHECK_ONLY=true ;;
    --create-env|--create-conda-env) CREATE_ENV=true ;;
    --install-r) INSTALL_R=true ;;
    --install-r-with-deseq2) INSTALL_R=true; INSTALL_DESEQ2=true ;;
    --install-hmmratac) INSTALL_HMMRATAC=true ;;
    --hmmratac-jar)
      shift
      HMMRATAC_JAR="${1:-}"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

record_versions() {
  python3 "$ROOT_DIR/bin/print_versions.py"
}

if [ "$CHECK_ONLY" = true ]; then
  record_versions
  exit 0
fi

if [ "$CREATE_ENV" = false ] && [ "$INSTALL_R" = false ] && [ "$INSTALL_HMMRATAC" = false ]; then
  echo "No install flags supplied; recording detected versions only."
  record_versions
  exit 0
fi

if [ "$CREATE_ENV" = true ]; then
  command -v conda >/dev/null 2>&1 || { echo "ERROR: conda is required for --create-env." >&2; exit 1; }
  conda env create -f "$ENV_DIR/came_environment.yml"
fi

if [ "$INSTALL_R" = true ]; then
  command -v Rscript >/dev/null 2>&1 || { echo "ERROR: Rscript is required for --install-r." >&2; exit 1; }
  if [ "$INSTALL_DESEQ2" = true ]; then
    Rscript "$ENV_DIR/install_r_packages.R" --install-core --install-deseq2
  else
    Rscript "$ENV_DIR/install_r_packages.R" --install-core --skip-deseq2
  fi
fi

if [ "$INSTALL_HMMRATAC" = true ]; then
  if [ -z "$HMMRATAC_JAR" ] || [ ! -f "$HMMRATAC_JAR" ]; then
    echo "ERROR: --install-hmmratac requires --hmmratac-jar PATH to an existing HMMRATAC jar." >&2
    exit 1
  fi
  mkdir -p "$ENV_DIR/tools"
  cp "$HMMRATAC_JAR" "$ENV_DIR/tools/HMMRATAC.jar"
  echo "Copied HMMRATAC jar to $ENV_DIR/tools/HMMRATAC.jar"
fi

record_versions
