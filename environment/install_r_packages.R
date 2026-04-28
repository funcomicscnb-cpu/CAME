#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
install_core <- "--install-core" %in% args || "--install" %in% args
install_deseq2 <- "--install-deseq2" %in% args || ("--install" %in% args && !("--skip-deseq2" %in% args))
skip_deseq2 <- "--skip-deseq2" %in% args

core_packages <- c("yaml", "ape", "nlme", "data.table")

version_or_missing <- function(package) {
  if (requireNamespace(package, quietly = TRUE)) {
    as.character(utils::packageVersion(package))
  } else {
    "missing"
  }
}

install_cran_missing <- function(packages) {
  missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing) > 0) {
    install.packages(missing, repos = "https://cloud.r-project.org")
  }
}

install_bioc_missing <- function(packages) {
  missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing) > 0) {
    if (!requireNamespace("BiocManager", quietly = TRUE)) {
      install.packages("BiocManager", repos = "https://cloud.r-project.org")
    }
    BiocManager::install(missing, ask = FALSE, update = FALSE)
  }
}

if (install_core) {
  install_cran_missing(core_packages)
}

if (install_deseq2 && !skip_deseq2) {
  tryCatch(
    install_bioc_missing(c("DESeq2")),
    error = function(e) {
      message("WARNING: DESeq2 installation failed; CAME tests can use fallback differential mode: ", conditionMessage(e))
    }
  )
}

cat("tool\tversion\tstatus\n")
cat("R\t", R.version.string, "\tpresent\n", sep = "")
for (pkg in core_packages) {
  ver <- version_or_missing(pkg)
  status <- ifelse(ver == "missing", "missing", "present")
  cat(pkg, "\t", ver, "\t", status, "\n", sep = "")
}
deseq2_version <- version_or_missing("DESeq2")
deseq2_status <- ifelse(deseq2_version == "missing", "optional_missing", "present")
cat("DESeq2\t", deseq2_version, "\t", deseq2_status, "\n", sep = "")
