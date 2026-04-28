workflow GENE_ORTHOLOGY_PROJECTION {
    take:
    projected_counts
    projected_differential

    main:

    emit:
    counts = projected_counts
    differential = projected_differential
}
