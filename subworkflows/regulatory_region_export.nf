process EXPORT_FUNCTIONAL_REGULATORY_REGIONS {
    publishDir { "${params.outdir}/interpretation" }, mode: 'copy'

    input:
    path candidate_res
    path candidate_gras
    path feature_to_orthogroup_map
    path gra_re_membership
    val top_n
    val min_score

    output:
    path 'regulatory_regions/candidate_res.bed', emit: candidate_res_bed
    path 'regulatory_regions/gra_linked_candidate_res.bed', emit: gra_linked_candidate_res_bed
    path 'regulatory_regions/regulatory_region_export_warnings.tsv', emit: warnings

    script:
    def minScoreArg = min_score != null && min_score.toString().trim() ? "--min_score \"${min_score}\"" : ""
    """
    mkdir -p regulatory_regions
    python3 ${projectDir}/bin/export_regulatory_regions.py \\
      --candidate_res "${candidate_res}" \\
      --candidate_gras "${candidate_gras}" \\
      --feature_to_orthogroup_map "${feature_to_orthogroup_map}" \\
      --gra_re_membership "${gra_re_membership}" \\
      --top_n "${top_n}" \\
      ${minScoreArg} \\
      --output_dir regulatory_regions
    """
}

workflow REGULATORY_REGION_EXPORT {
    take:
    candidate_res
    candidate_gras
    feature_to_orthogroup_map
    gra_re_membership
    top_n
    min_score

    main:
    EXPORT_FUNCTIONAL_REGULATORY_REGIONS(
        candidate_res,
        candidate_gras,
        feature_to_orthogroup_map,
        gra_re_membership,
        top_n,
        min_score
    )

    emit:
    candidate_res_bed = EXPORT_FUNCTIONAL_REGULATORY_REGIONS.out.candidate_res_bed
    gra_linked_candidate_res_bed = EXPORT_FUNCTIONAL_REGULATORY_REGIONS.out.gra_linked_candidate_res_bed
    warnings = EXPORT_FUNCTIONAL_REGULATORY_REGIONS.out.warnings
}
