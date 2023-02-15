#' import org.Hs.eg.db org.Hs.eg.db
NULL

# TODO remove these when function incorporated
# library(org.Hs.eg.db) # Organism.HomoSapiens.EntrezGene.DataBase

# library(fgsea)
# library(clusterProfiler)
# library(DOSE)
# library(ReactomePA)
# library(enrichplot)
# library(ggplot2)
# library(ggnewscale)
# library(ggupset)



#' Run GSEA and ORA.
#'
#' Run gene set enrichment and over representation analyses with clusterProfiler using fgsea.
#'
#' @param output_dir output directory for plots, string
#' @param dea_result_file Seurat differential expression analysis result object in .csv
#' @param cellRanger_ensembl_features CellRanger .csv file with mapping of Ensembl IDs to Ensembl gene symbols
#' @param lfc_threshold ORA differentially expressed genes log fold-change threshold, default: 1
#' @param seed set pseudorandomness, default: 42
#' @param swap_GSEA_groups invert log fold changes to visually swap upregulation/overrepresentation and downregulation/underrepresentation for GSEA, this is independent of positive/negative with ORA, default: FALSE
#' @param use_internal_universe TRUE: use DEA measured genes, FALSE: use clusterProfiler::ORA_db() specific genes, default: TRUE
#' @param p_adjust_method p-value multiple testing correction method, default: "BH" (Benjamini-Hochberg)
#' @param pval_cutoff GSEA/ORA term taken into account by p-val statistic
#' @param qval_cutoffGSEA/ORA term taken into account by q-val statistic
#' @param min_gene_set_size_gsea minimum gene set size for GSEA, default: 10
#' @param max_gene_set_size_gsea maximum gene set size for GSEA, default: 500
#' @param min_gene_set_size_ora minimum gene set size for ORA, default: 3
#' @param max_gene_set_size_ora maximum gene set size for ORA, default: NA
#' @param plot_n_category plot top n most significant terms, default: 30
#'
#' @example
#' run_fgsea(
#'   output_dir = "results/fgsea_GOuniverse_treeplot_KEGG_MSigDB_neurons_TPlabels/",
#'   dea_result_file = astrocyte_deg.csv,
#'   cellRanger_ensembl_features = "Ensembl genes.tsv",
#' )
#'
#' @description Setting a seed can be useful as FGSEA functions have stochasticity.
#'
#' @import org.Hs.eg.db org.Hs.eg.db
#'
#' @note
#' Notes during development
#'
#' # clusterProfiler vignette: https://yulab-smu.top/biomedical-knowledge-mining-book
#' # general intro ORA vs GSEA: https://www.pathwaycommons.org/guide/primers/data_analysis/gsea/
#' # use Entrez IDs with clusterProfiler etc to perform GSEA/ORA analyses with FGSEA
#' # Over-representation (enrichment) analysis (ORA): check DEG vs known biological relationship (via gene set)
#' ## will find genes where the difference is large and will fail where the difference is small, but evidenced in coordinated way in a set of related genes
#' ## limitations: 1) arbitrary user-defined inclusion criteria, 2) equal importance to each gene, 3) assume gene independance
#' # Gene set enrichment analysis (GSEA): unordered collection of related genes (sets)
#' ## Pathway: type of gene set if functional relations are ignored
#' ## gene set enrichment analysis (GSEA): aggregates the per gene statistics across genes within a gene set
#' ### overcoming ORA limitation, by detecting situations where all genes in a predefined set change in a small but coordinated way
#' ## steps
#' ### local gene-level statistic: adj-p-val / log fold change
#' ### global gene-set statistics: weighted running sum by ranked-list gene prevalence, Enrichment Score (ES) = max score
#' #### Normalized ES (NES): accounting for gene set size
#' ### significance testing & multiple testing correction
#' #### Type 1 error: family of hypotheses, chance of false positive (significant p-val)
#' ##### False Discovery Rate (FDR): fraction of rejected null hypothesis (Type 1 error) that are true (false negatives)
#' ###### https://www.pathwaycommons.org/guide/primers/statistics/multiple_testing/
#' ###### https://www.nature.com/articles/nbt1209-1135
#' ###### https://jtd.amegroups.com/article/view/13609/11598
#'
#' @export
run_fgsea <- function(
    output_dir, dea_result_file, cellRanger_ensembl_features,
    lfc_threshold = 1, seed = 42,
    swap_GSEA_groups = FALSE, use_internal_universe = TRUE,
    p_adjust_method = "BH", pval_cutoff = 1, qval_cutoff = 1,
    min_gene_set_size_gsea = 10, max_gene_set_size_gsea = 500,
    min_gene_set_size_ora = 3, max_gene_set_size_ora = NA,
    plot_n_category = 30, run_msigdb = FALSE,
    gsea_plot_folder = "gene_set_enrichment_analysis",
    ora_plot_folder = "over_representation_analysis") {

  ## set and create output directories
  dir.create(output_dir, recursive = TRUE)
  setwd(output_dir)

  fgsea_dbs <- c(
    "gene_ontology", "disease_ontology", "disease_gene_network",
    "wiki_pathways", "reactome_pathways", "KEGG", "molecular_signatures")
  for (db in fgsea_dbs) {
    dir.create(paste(gsea_plot_folder, db, sep = "/"), recursive = TRUE)
    dir.create(paste(ora_plot_folder, "upregulated", db, sep = "/"), recursive = TRUE)
    dir.create(paste(ora_plot_folder, "downregulated", db, sep = "/"), recursive = TRUE)
  }

  ## prep GSEA/ORA input
  # load DEA result
  dea_result <- read.csv2(dea_result_file)

  # TODO remove, this is a subset for quick testing
  dea_result <- dea_result[1:1000,]


  # DEVNOTE: non-unique/duplicate, as reconverting dates have multiple gene name options (e.g. MAR2/MARC2/MARCH2 --> 02/03/year)
  dea_result$X <- date2gene(gene_names = dea_result$X)

  ## DEVNOTE: don't remove '.' and everything after because of matching ENSEMBL IDs with ENSEMBL symbols at origin
  ## DEVNOTE: Normally remove for proper Ensembl gene version matching to Entrez
  ## dea_result$X <- sub("\\.[^.]*$", "", dea_result$X)
  # load CellRanger features - Ensembl genes and IDs
  ensembl_genes_ids <- read.delim(file = cellRanger_ensembl_features,
                                  col.names = c("ensembl_gene_id", "ensembl_gene_name", "gene_type"))
  # map enseml gene names to ensembl gene IDs from DEA result gene names
  dea_result$ensembl_id <- plyr::mapvalues(
    x = dea_result$X,
    from = ensembl_genes_ids$ensembl_gene_name,
    to = ensembl_genes_ids$ensembl_gene_id,
    warn_missing = FALSE)
  # map ENSEMBL IDs to ENTREZ IDs
  entrez_ids <- clusterProfiler::bitr(geneID = dea_result$ensembl_id, OrgDb = org.Hs.eg.db, fromType = "ENSEMBL", toType = "ENTREZID")

  fgsea_examine_unmapped_genes(
    gene_names = dea_result$X,
    dea_ensembl_ids = dea_result$ensembl_id,
    bitr_ensembl_ids = entrez_ids$ENSEMBL)

  ## prep GSEA input
  # get log fold-change (lfc)
  dea_ids_lfc <- dea_result$avg_log2FC
  # get Entrez names by matching Ensembl IDs
  names(dea_ids_lfc) <- plyr::mapvalues(x = dea_result$ensembl_id, from = entrez_ids$ENSEMBL, to = entrez_ids$ENTREZID)
  # remove NA
  dea_ids_lfc <- dea_ids_lfc[!is.na(names(dea_ids_lfc))]
  # swap signs to swap up/down regulation for GSEA visualization
  if (swap_GSEA_groups) {
    dea_ids_lfc <- dea_ids_lfc * -1
  }
  # sort decreasingly
  dea_ids_lfc <- sort(dea_ids_lfc, decreasing = TRUE)

  ## prep ORA input
  # subset DEA result to DEG result based on log fold-change threshold
  deg_ids <- dea_ids_lfc[dea_ids_lfc >= 1 | dea_ids_lfc <= -1]
  deg_ids_positive <- names(dea_ids_lfc[dea_ids_lfc >= lfc_threshold])
  deg_ids_negative <- names(dea_ids_lfc[dea_ids_lfc <= -lfc_threshold])
  # save ORA deg subset names
  deg_names_positive <- bitr(geneID = deg_ids_positive, OrgDb = org.Hs.eg.db, fromType = "ENTREZID", toType = "ENSEMBL")
  deg_names_negative <- bitr(geneID = deg_ids_negative, OrgDb = org.Hs.eg.db, fromType = "ENTREZID", toType = "ENSEMBL")

  deg_names_positive <- plyr::mapvalues(
    x = deg_names_positive$ENSEMBL,
    from = ensembl_genes_ids$ensembl_gene_id,
    to = ensembl_genes_ids$ensembl_gene_name,
    warn_missing = FALSE)
  deg_names_positive <- deg_names_positive[!grepl("^ENSG", deg_names_positive)]
  deg_names_negative <- plyr::mapvalues(
    x = deg_names_negative$ENSEMBL,
    from = ensembl_genes_ids$ensembl_gene_id,
    to = ensembl_genes_ids$ensembl_gene_name,
    warn_missing = FALSE)
  deg_names_negative <- deg_names_negative[!grepl("^ENSG", deg_names_negative)]
  write.csv2(deg_names_positive, file = paste(ora_plot_folder, "upregulated", "deg_subset_pos.csv", sep = "/"))
  write.csv2(deg_names_negative, file = paste(ora_plot_folder, "downregulated", "deg_subset_neg.csv", sep = "/"))

  # define background gene universe, either internal (all measured/measurable genes) or external (package function built-in)
  if (use_internal_universe) {
    universe <- names(dea_ids_lfc)
    go_universe = unique(sort(as.data.frame(org.Hs.egGO)$gene_id))

    fgsea_compare_DEG_GO_universe(
      deg_universe = universe,
      go_universe = go_universe,
      ensembl_genes_ids = ensembl_genes_ids)
  } else {
    universe <- NULL
  }

  # get molecular signatures databases
  if (run_msigdb) {
    msigdb.hs.h <- get_msigdb_term2gene(collection = 'h')
    msigdb.hs.c2.cp <- get_msigdb_term2gene(collection = 'c2', subcollection = 'CP')

  } else {
    msigdb.hs.h <- NULL
    msigdb.hs.c2.cp <- NULL
  }

  # Gene Set Enrichment Analyses (GSEA. full DEA list)
  gsea_results <- run_fgsea_gsea(
    dea_ids_lfc, min_gene_set_size_gsea, max_gene_set_size_gsea,
    pval_cutoff, p_adjust_method,
    msigdb.hs.h, msigdb.hs.c2.cp
  )
  # Over Representation Analyses (ORA, subset DEG list)
  ora_results_positive <- run_fgsea_ora(
    deg_ids_positive, posneg = "upregulated",
    min_gene_set_size_ora, max_gene_set_size_ora,
    pval_cutoff, p_adjust_method, qval_cutoff, universe,
    msigdb.hs.h, msigdb.hs.c2.cp
  )
  ora_results_negative <- run_fgsea_ora(
    deg_ids_negative, posneg = "downregulated",
    min_gene_set_size_ora, max_gene_set_size_ora,
    pval_cutoff, p_adjust_method, qval_cutoff, universe,
    msigdb.hs.h, msigdb.hs.c2.cp
  )
  # plot results
  all_results <- c(gsea_results, ora_results_positive, ora_results_negative)
  for (res_name in names(all_results)) {
    plot_fgsea_result(
      res = all_results[res_name][[1]],
      res_name = res_name,
      plot_n_category,
      dea_ids_lfc,
      gsea_plot_folder,
      ora_plot_folder
    )
  }
}



#' Fix Excel formatting genes to dates back to gene names.
#'
#' @param gene_names gene names (where some are dates) in character vector
#'
#' @return gene names in character vector
date2gene <- function(gene_names) {
  ## if .csv was saved in Excel, some gene names e.g. SEP2 become dates
  # get index of these genes
  excel_genes_ind <- grepl(x = gene_names, pattern = "^[A-Z][a-z]{2}/[0-9]{2}$")
  # get these genes
  excel_genes <- gene_names[excel_genes_ind]
  # convert back to original names from date names
  gene_names[excel_genes_ind] <- sapply(X = excel_genes, USE.NAMES = FALSE, FUN = function(X) {
    ss <- unlist(strsplit(X, split = '/'))
    paste0(toupper(ss[1]), as.integer(ss[2]))
  })
  return(unlist(gene_names))
}



#' Examine which and how many genes remain unmapped
#'
#' What using bitr package for mapping genes from e.g. Ensembl to ENTREZ ids
#' not all genes might be mapped. This function calculates the percentage of
#' unmapped genes and plots and saves a distribution of them.
#'
#' @param gene_names character vector with gene names
#' @param dea_ensembl_ids character vector with gene names from the DEA
#' @param bitr_ensembl_ids character vector with gene names from bitr
fgsea_examine_unmapped_genes <- function(gene_names, dea_ensembl_ids, bitr_ensembl_ids) {
  dir.create("gene_mapping_bitr")
  d <- dea_ensembl_ids
  b <- bitr_ensembl_ids

  ratio_mapped <- round(length(b)/(length(d)-sum(is.na(d)))*100, digits = 2)

  genes_not_mapped <- gene_names[d %in% d[!d %in% b]]
  write.csv2(x = genes_not_mapped, file = "gene_mapping_bitr/genes_not_mapped.csv")

  rank_genes_not_mapped <- which(d %in% d[!d %in% b])
  png("gene_mapping_bitr/distribution_rank_genes_not_mapped.png")
  hist(rank_genes_not_mapped, breaks = 200, main = paste0("bitr rank unmapped genes - %mapped: ", ratio_mapped))
  dev.off()
}



#' Compare all genes from the DEG analysis against the Gene Ontology database
#'
#' For GSEA and ORA a 'universe' of genes is used. This universe can be all
#' genes measured during your experiment or specifically all genes that are in
#' a specific database, here GO.
#' The overlapping and non overlapping genes are saved as .csv
#'
#' @param deg_universe character vector of all DEG genes
#' @param go_universe character vector of all GO genes
#' @param ensembl_genes_ids translation table with ensembl IDs and gene names
fgsea_compare_DEG_GO_universe <- function(deg_universe, go_universe, ensembl_genes_ids) {
  overlapping_gene_ids <- go_universe[go_universe %in% deg_universe]
  gene_ids_not_in_go <- go_universe[!go_universe %in% deg_universe]

  overlapping_gene_ids <- bitr(geneID = overlapping_gene_ids, OrgDb = org.Hs.eg.db, fromType = "ENTREZID", toType = "ENSEMBL")
  gene_ids_not_in_go <- bitr(geneID = gene_ids_not_in_go, OrgDb = org.Hs.eg.db, fromType = "ENTREZID", toType = "ENSEMBL")

  overlapping_gene_names <- plyr::mapvalues(
    x = overlapping_gene_ids$ENSEMBL,
    from = ensembl_genes_ids$ensembl_gene_id,
    to = ensembl_genes_ids$ensembl_gene_name,
    warn_missing = FALSE)
  gene_names_not_in_go <- plyr::mapvalues(
    x = gene_ids_not_in_go$ENSEMBL,
    from = ensembl_genes_ids$ensembl_gene_id,
    to = ensembl_genes_ids$ensembl_gene_name,
    warn_missing = FALSE)
  write.csv2(overlapping_gene_names, file = "DEG_GO_universe_overlapping_genes.csv")
  write.csv2(gene_names_not_in_go, file = "DEG_GO_universe_nonOverlapping_genes.csv")
}


#' Run GSEA
#'
#' Run GSEA for different databases: GO, KEGG, WP, Reactome Pathways,
#' DO, DGN & MsigDB.
#'
#' @param dea_ids_lfc named character vector with DEA ids and logfoldchanges
#' @param min_gene_set_size_gsea minimum geneSetSize
#' @param max_gene_set_size_gsea maximum geneSetSize
#' @param pval_cutoff p-value threshold
#' @param p_adjust_method p-value adjustment method: BH, ...
#' @param msigdb.hs.h dataframe with MsigDB Hallmarks Human gene sets
#' @param msigdb.hs.c2.cp dataframe with MsigDB C2 Curated Pathways gene sets
#'
#' @return list with all results
run_fgsea_gsea <- function(
    dea_ids_lfc, min_gene_set_size_gsea, max_gene_set_size_gsea,
    pval_cutoff, p_adjust_method,
    msigdb.hs.h, msigdb.hs.c2.cp) {

  # initialize results
  gsea_results <- list()

  gene_ontology_types <- c("GO-BP" = "BP",
                           "GO-MF" = "MF",
                           "GO-CC" = "CC")
  for (i in 1:length(gene_ontology_types)) {
    res_gse_go <- clusterProfiler::gseGO(
      geneList = dea_ids_lfc,
      ont = gene_ontology_types[i],
      OrgDb = org.Hs.eg.db,
      keyType = "ENTREZID",
      exponent = 1, # default: 1
      minGSSize = min_gene_set_size_gsea, # default: 10
      maxGSSize = max_gene_set_size_gsea, # default: 500
      pvalueCutoff = pval_cutoff, # default: 0.05
      eps = 0, # default: 1e-10
      verbose = TRUE,
      pAdjustMethod = p_adjust_method, # default: "BH" (Benjamini-Hochberg)
      seed = TRUE,
      by = "fgsea"
    )
    gsea_results[[paste0("GSEA-", names(gene_ontology_types)[i])]] <- res_gse_go
  }

  # Kyoto Encyclopedia of Genes and Genomes (KEGG)
  res_gse_kegg <- clusterProfiler::gseKEGG(
    geneList = dea_ids_lfc,
    organism = "hsa",
    keyType = "kegg", # "kegg", 'ncbi-geneid', 'ncib-proteinid' and 'uniprot'
    exponent = 1, # default: 1
    minGSSize = min_gene_set_size_gsea, # default: 10
    maxGSSize = max_gene_set_size_gsea, # default: 500
    pvalueCutoff = pval_cutoff, # default: 0.05
    pAdjustMethod = p_adjust_method,
    eps = 0, # default: 1e-10
    verbose = TRUE,
    use_internal_data = FALSE, # default: FALSE
    seed = TRUE,
    by = "fgsea"
  )
  gsea_results[["GSEA-KEGG"]] <- res_gse_kegg

  # WikiPathways
  res_gse_wp <- clusterProfiler::gseWP(
    geneList = dea_ids_lfc,
    organism = "Homo sapiens",
    pvalueCutoff = pval_cutoff,
    pAdjustMethod = p_adjust_method,
    minGSSize = min_gene_set_size_gsea,
    maxGSSize = max_gene_set_size_gsea
  )
  gsea_results[["GSEA-WP"]] <- res_gse_wp

  # Reactome Pathway Analysis
  res_gse_rp <- ReactomePA::gsePathway(
    geneList = dea_ids_lfc,
    organism = "human",
    exponent = 1, # default: 1
    minGSSize = min_gene_set_size_gsea, # default: 10
    maxGSSize = max_gene_set_size_gsea, # default: 500
    pvalueCutoff = pval_cutoff, # default: 0.05
    eps = 0, # default: 1e-10
    verbose = TRUE,
    pAdjustMethod = p_adjust_method, # default: "BH" (Benjamini-Hochberg)
    seed = TRUE,
    by = "fgsea"
  )
  gsea_results[["GSEA-RP"]] <- res_gse_rp

  # DiseaseOntology (DO)
  res_gse_do <- gseDO(
    geneList = dea_ids_lfc,
    exponent = 1, # default: 1
    minGSSize = min_gene_set_size_gsea, # default: 10
    maxGSSize = max_gene_set_size_gsea, # default: 500
    pvalueCutoff = pval_cutoff, # default: 0.05
    verbose = TRUE,
    pAdjustMethod = p_adjust_method, # default: "BH" (Benjamini-Hochberg)
    seed = TRUE,
    by = "fgsea"
  )
  gsea_results[["GSEA-DO"]] <- res_gse_do

  # Disease Gene Network (DGN)
  res_gse_dgn <- gseDGN(
    geneList = dea_ids_lfc,
    exponent = 1, # default: 1
    minGSSize = min_gene_set_size_gsea, # default: 10
    maxGSSize = max_gene_set_size_gsea, # default: 500
    pvalueCutoff = pval_cutoff, # default: 0.05
    verbose = TRUE,
    pAdjustMethod = p_adjust_method, # default: "BH" (Benjamini-Hochberg)
    seed = TRUE,
    by = "fgsea"
  )
  gsea_results[["GSEA-DGN"]] <- res_gse_dgn

  # Molecular Signatures Database - hallmarks (MSigDB hallmark gene sets)
  if (!is.null(msigdb.hs.h)) {
    res_gse_msdb_h <- clusterProfiler::GSEA(
      geneList = dea_ids_lfc,
      TERM2GENE = msigdb.hs.h,
      exponent = 1,
      minGSSize = min_gene_set_size_gsea, # default: 10
      maxGSSize = max_gene_set_size_gsea, # default: 500
      pvalueCutoff = pval_cutoff, # default: 0.05
      verbose = TRUE,
      pAdjustMethod = p_adjust_method, # default: "BH" (Benjamini-Hochberg)
      seed = TRUE,
      by = "fgsea"
    )
    gsea_results[["GSEA-MSDB-H"]] <- res_gse_msdb_h
  }


  # Molecular Signatures Database - C2 Canonical Pathways (MSigDB C2:CP)
  if (!is.null(msigdb.hs.c2.cp)) {
    res_gse_msdb_c2cp <- clusterProfiler::GSEA(
      geneList = dea_ids_lfc,
      TERM2GENE = msigdb.hs.c2.cp,
      exponent = 1,
      minGSSize = min_gene_set_size_gsea, # default: 10
      maxGSSize = max_gene_set_size_gsea, # default: 500
      pvalueCutoff = pval_cutoff, # default: 0.05
      verbose = TRUE,
      pAdjustMethod = p_adjust_method, # default: "BH" (Benjamini-Hochberg)
      seed = TRUE,
      by = "fgsea"
    )
    gsea_results[["GSEA-MSDB-C2CP"]] <- res_gse_msdb_c2cp
  }

  return(gsea_results)
}


#' Run ORA
#'
#' Run ORA for different databases: GO, KEGG, WP, Reactome Pathways,
#' DO, DGN & MsigDB.
#'
#' @param deg_names character vector with deg names
#' @param min_gene_set_size_ora minimum geneSetSize
#' @param max_gene_set_size_ora maximum geneSetSize
#' @param pval_cutoff p-value threshold
#' @param p_adjust_method p-value adjustment method: BH, ...
#' @param qval_cutoff
#' @param universe DEG/GO gene universe character vector
#' @param msigdb.hs.h dataframe with MsigDB Hallmarks Human gene sets
#' @param msigdb.hs.c2.cp dataframe with MsigDB C2 Curated Pathways gene sets
#'
#' @return ora_results list with all results
run_fgsea_ora <- function(
    deg_names, posneg, min_gene_set_size_ora, max_gene_set_size_ora,
    pval_cutoff, p_adjust_method, qval_cutoff, universe,
    msigdb.hs.h, msigdb.hs.c2.cp) {

  # initialize results
  ora_results <- list()

  go_universe = unique(sort(as.data.frame(org.Hs.egGO)$gene_id))
  gene_ontology_types <- c("GO-BP" = "BP",
                           "GO-MF" = "MF",
                           "GO-CC" = "CC")
  for (i in 1:length(gene_ontology_types)) {
    # DEG universe
    res_enrich_go <- clusterProfiler::enrichGO(
      gene = deg_names,
      OrgDb = org.Hs.eg.db,
      keyType = "ENTREZID",
      ont = gene_ontology_types[i],
      pvalueCutoff = pval_cutoff,
      pAdjustMethod = p_adjust_method, # default: "BH" (Benjamini-Hochberg)
      universe = universe,
      qvalueCutoff = qval_cutoff,
      minGSSize = min_gene_set_size_ora, # default: 10
      maxGSSize = max_gene_set_size_ora, # default: 500
      readable = FALSE, # default: FALSE
      pool = FALSE # default: FALSE
    )
    ora_results[[paste0("ORA-", names(gene_ontology_types)[i], "-DEGuniverse-", posneg)]] = res_enrich_go

    # GO gene universe
    res_enrich_go <- clusterProfiler::enrichGO(
      gene = deg_names,
      OrgDb = org.Hs.eg.db,
      keyType = "ENTREZID",
      ont = gene_ontology_types[i],
      pvalueCutoff = pval_cutoff,
      pAdjustMethod = p_adjust_method, # default: "BH" (Benjamini-Hochberg)
      universe = go_universe,
      qvalueCutoff = qval_cutoff,
      minGSSize = min_gene_set_size_ora, # default: 10
      maxGSSize = max_gene_set_size_ora, # default: 500
      readable = FALSE, # default: FALSE
      pool = FALSE # default: FALSE
    )
    ora_results[[paste0("ORA-", names(gene_ontology_types)[i], "-GOuniverse-", posneg)]] = res_enrich_go
  }

  # Kyoto Encyclopedia of Genes and Genomes (KEGG)
  res_enrich_kegg <- enrichKEGG(
    gene = deg_names,
    organism = "hsa",
    pvalueCutoff = pval_cutoff,
    pAdjustMethod = p_adjust_method,
    universe = universe,
    minGSSize = min_gene_set_size_ora, # default: 10
    maxGSSize = max_gene_set_size_ora, # default: 500
    qvalueCutoff = qval_cutoff, # default: 0.2
    use_internal_data = FALSE
  )
  ora_results[[paste0("ORA-KEGG-", posneg)]] = res_enrich_kegg

  # WikiPathways
  res_enrich_wp <- enrichWP(
    gene = deg_names,
    organism = "Homo sapiens",
    universe = universe,
    pvalueCutoff = pval_cutoff,
    pAdjustMethod = p_adjust_method,
    minGSSize = min_gene_set_size_ora,
    maxGSSize = max_gene_set_size_ora,
    qvalueCutoff = qval_cutoff)
  ora_results[[paste0("ORA-WP-", posneg)]] = res_enrich_wp

  # Reactome Pathway
  res_enrich_rp <- enrichPathway(
    gene = deg_names,
    organism = "human",
    universe = universe,
    pvalueCutoff = pval_cutoff,
    pAdjustMethod = p_adjust_method,
    minGSSize = min_gene_set_size_ora,
    maxGSSize = max_gene_set_size_ora,
    qvalueCutoff = qval_cutoff)
  ora_results[[paste0("ORA-RP-", posneg)]] = res_enrich_rp

  # Disease Ontology
  res_enrich_do <- enrichDO(
    gene = deg_names,
    universe = universe,
    ont = "DO",
    pvalueCutoff = pval_cutoff,
    pAdjustMethod = p_adjust_method,
    minGSSize = min_gene_set_size_ora,
    maxGSSize = max_gene_set_size_ora,
    qvalueCutoff = qval_cutoff,
    readable = FALSE)
  ora_results[[paste0("ORA-DO-", posneg)]] = res_enrich_do

  # Disease Gene Network
  res_enrich_dgn <- enrichDGN(
    gene = deg_names,
    universe = universe,
    pvalueCutoff = pval_cutoff,
    pAdjustMethod = p_adjust_method,
    minGSSize = min_gene_set_size_ora,
    maxGSSize = max_gene_set_size_ora,
    qvalueCutoff = qval_cutoff,
    readable = FALSE)
  ora_results[[paste0("ORA-DGN-", posneg)]] = res_enrich_dgn

  # Molecular Signatures Database - hallmarks (MSigDB hallmark gene sets)
  if (!is.null(msigdb.hs.h)) {
    res_enrich_msdb_h <- clusterProfiler::enricher(
      gene = deg_names,
      TERM2GENE = msigdb.hs.h,
      universe = universe,
      minGSSize = min_gene_set_size_ora, # default: 10
      maxGSSize = max_gene_set_size_ora, # default: 500
      qvalueCutoff = qval_cutoff,
      pvalueCutoff = pval_cutoff, # default: 0.05
      pAdjustMethod = p_adjust_method # default: "BH" (Benjamini-Hochberg)
    )
    ora_results[[paste0("ORA-MSDB-H-", posneg)]] = res_enrich_msdb_h
  }

  # Molecular Signatures Database - C2 Canonical Pathways (MSigDB C2:CP)
  if (!is.null(msigdb.hs.c2.cp)) {
    res_enrich_msdb_c2cp <- clusterProfiler::enricher(
      gene = deg_names,
      TERM2GENE = msigdb.hs.c2.cp,
      universe = universe,
      minGSSize = min_gene_set_size_ora, # default: 10
      maxGSSize = max_gene_set_size_ora, # default: 500
      qvalueCutoff = qval_cutoff,
      pvalueCutoff = pval_cutoff, # default: 0.05
      pAdjustMethod = p_adjust_method # default: "BH" (Benjamini-Hochberg)
    )
    ora_results[[paste0("ORA-MSDB-C2CP-", posneg)]] = res_enrich_msdb_c2cp
  }

  return(ora_results)
}


#' Plot GSEA and ORA results
#'
#' Create and save all different plot for FGSEA results. Heatplot, goplot,
#' ridgeplot, gseaplot, dotplot, cnetplot, upsetplot, emapplot and treeplot.
#'
#' @param res GSEA or ORA result
#' @param res_name name given to GSEA or ORA result
#' @param plot_n_category how many categories to plot
#' @param dea_ids_lfc named character vector with DEA IDs and logfoldchanges
#' @param gsea_plot_folder output folder basename for GSEA results
#' @param ora_plot_folderoutput folder basename for ORA results
plot_fgsea_result <- function(
    res, res_name, plot_n_category, dea_ids_lfc,
    gsea_plot_folder, ora_plot_folder) {
  message("plotting: ", res_name)
  # get db folder name by res name
  fgsea_dbs <- c(
    "gene_ontology" = "GO",
    "disease_ontology" = "DO",
    "disease_gene_network" = "DGN",
    "wiki_pathways" = "WP",
    "reactome_pathways" = "RP",
    "KEGG" = "KEGG",
    "molecular_signatures" = "MSDB")
  db_name <- strsplit(res_name, "-")[[1]][2]
  db_folder <- names(fgsea_dbs)[which(fgsea_dbs %in% db_name)]

  # prep results
  res_r <- setReadable(res, 'org.Hs.eg.db', 'ENTREZID')
  res_r_pt <- pairwise_termsim(res_r)
  res_df <- as.data.frame(res)

  if (class(res) == "enrichResult") {
    # set plot_folder name
    ora_posneg_folder <- tail(strsplit(res_name, "-")[[1]], n = 1)
    plot_folder <- paste(ora_plot_folder, ora_posneg_folder, db_folder, sep = "/")
    if (grepl("^GO:", as.data.frame(res)$ID[1])) {
      plot_folder <- paste(plot_folder, res@ontology, sep = "/")

      if (grepl("-GOuniverse-", res_name)) {
        plot_folder <- paste(plot_folder, "GOuniverse", sep = "/")
      } else {
        plot_folder <- paste(plot_folder, "DEGuniverse", sep = "/")
      }
    }
    if (grepl("-MSDB-", res_name)) {
      plot_folder <- paste(plot_folder, strsplit(res_name, "-")[[1]][3], sep = "/")
    }
    dir.create(plot_folder, recursive = TRUE)

    # check heatmap of terms with associated genes and associated log fold change
    p <- enrichplot::heatplot(res_r, foldChange = dea_ids_lfc, showCategory = plot_n_category) + ggplot2::theme_bw()
    p + ggplot2::theme(axis.text.x = element_text(angle = 90, hjust = 1))
    ggplot2::ggsave(paste(plot_folder, "heatmap_genes+lfc.png", sep = "/"), width = 30, height = 20, units = "cm")

    # GOplot specifically for Gene Ontology ORA
    if (grepl("^GO:", as.data.frame(res)$ID[1])) {
      enrichplot::goplot(res) + ggplot2::theme_bw()
      ggplot2::ggsave(paste(plot_folder, "goplot.png", sep = "/"), width = 30, height = 20, units = "cm")
    }
  }

  if (class(res) == "gseaResult") {
    # set plot_folder name
    plot_folder <- paste(gsea_plot_folder, db_folder, sep = "/")
    if (grepl("^GO:", as.data.frame(res)$ID[1])) {
      plot_folder <- paste(plot_folder, res@setType, sep = "/")
    }
    if (grepl("-MSDB-", res_name)) {
      plot_folder <- paste(plot_folder, strsplit(res_name, "-")[[1]][3], sep = "/")
    }
    dir.create(plot_folder, recursive = TRUE)

    enrichplot::ridgeplot(res) + ggplot2::theme_bw()
    ggplot2::ggsave(paste(plot_folder, "ridgeplot.png", sep = "/"), width = 30, height = 20, units = "cm")
    p <- enrichplot::dotplot(
      res,
      showCategory = plot_n_category/2,
      split=".sign",
      label_format = Inf)
    p + ggplot2::theme_bw()
    p + facet_grid(.~.sign)
    ggplot2::ggsave(paste(plot_folder, "dotplot_split.png", sep = "/"), width = 30, height = 20, units = "cm")

    gsea_shown <- 0
    while(gsea_shown < plot_n_category) {
      enrichplot::gseaplot2(res, geneSetID = res_df$ID[(gsea_shown+1):(gsea_shown+10)], pvalue_table = TRUE) + ggplot2::theme_bw()
      ggplot2::ggsave(paste(plot_folder, paste0("gseaplot2_categories_", gsea_shown+1,"-", gsea_shown+10, ".png"), sep = "/"), width = 30, height = 20, units = "cm")
      gsea_shown <- gsea_shown + 10
    }
  }

  ## plots for GSEA and ORA results
  # term vs gene ratio & p-adjust & gene count
  enrichplot::dotplot(
    res,
    showCategory = plot_n_category,
    label_format = Inf) + ggplot2::theme_bw()
  ggplot2::ggsave(paste(plot_folder, "dotplot_top.png", sep = "/"), width = 30, height = 20, units = "cm")
  # check network of terms with associated genes and amount of genes
  enrichplot::cnetplot(res_r, showCategory = plot_n_category) + ggplot2::theme_bw()
  ggplot2::ggsave(paste(plot_folder, "cnetplot_terms+genes.png", sep = "/"), width = 30, height = 20, units = "cm")
  # check relations between amount of genes on terms and term association
  enrichplot::upsetplot(res, n = 10)
  ggplot2::ggsave(paste(plot_folder, "upsetplot_terms+ngenes.png", sep = "/"))
  # check network of associated terms with gene amounts but not gene associations
  enrichplot::emapplot(res_r_pt) + ggplot2::theme_bw()
  ggplot2::ggsave(paste(plot_folder, "emapplot_terms+ngenes.png", sep = "/"), width = 30, height = 20, units = "cm")
  # terms grouped and semantically summarized
  enrichplot::treeplot(
    res_r_pt,
    showCategory = plot_n_category,
    label_format = 14)
  ggplot2::ggsave(paste(plot_folder, "treeplot.png", sep = "/"), width = 30, height = 20, units = "cm")
}



#' Get TERM2GENE dataframe for custom MSigDB collection/subcollection terms.
#'
#' The molecular signatures database (MSigDB) contains curated collections and
#' subcollection of gene sets. These can be used for comparison in GSEA/ORA
#' analyses.
#'
#' @param organism Either Homo Sapiems 'hs' or Mus Musculus 'mm'
#' @param collection The collection(s) must be one or more from
#' msigdb::listCollections()
#' @param subcollection The subcollection(s) must be one or more from
#' msigdb::listSubCollections()
#' @param id Either gene names 'SYM' or Entrez IDs 'EZID'
#' @param version 'latest' or one of msigdb::getMsigdbVersions()
#'
#' @return Dataframe with 'term' and 'gene' columns.
#'
#' @importFrom msigdb getMsigdbVersions getMsigdb subsetCollection
get_msigdb_term2gene <- function(
    organism = 'hs',
    collection = 'h',
    subcollection = c(),
    id = 'EZID',
    version = 'latest') {

  if (version == "latest") {
    version <- msigdb::getMsigdbVersions()[1]
  }

  msigdb <- msigdb::getMsigdb(org = organism, id = id, version = version)
  msigdb.sub <- msigdb::subsetCollection(msigdb, collection, subcollection)

  # list: name = term, values = EntrezIDs
  msigdb.sub = GSEABase::geneIds(msigdb.sub)

  # create term to gene dataframe
  term2gene <- DataFrame()
  for (name in names(msigdb.sub)) {
    term2gene <- rbind(term2gene, as.data.frame(cbind(name, msigdb.sub[[name]])))
  }
  colnames(term2gene) <- c("term", "gene")

  return(term2gene)
}



#' Overwrite namespace for enrichplot::group_tree function
#'
#' Added custom functionality to enrichplot::group_tree, I know playing with
#' namespace is not proper, however please fill me in on how to do this
#' without changing namespace!
#'
#' @description see enrichplot::group_tree for documentation
group_tree.adjusted <- function(hc, clus, d, offset_tiplab, nWords,
                                label_format_cladelab, label_format_tiplab,
                                offset, fontsize, group_color,
                                extend, hilight, cex_category,
                                ID_Cluster_mat = NULL, geneClusterPanel = NULL,
                                align, add_tippoint = TRUE, align_tiplab = TRUE, color = 'p.adjust') {
  message("running adjusted enrichplot:::group_tree()...")
  showCategory = length(d$count)

  group <- count <- NULL
  # cluster data
  dat <- data.frame(name = names(clus), cls=paste0("cluster_", as.numeric(clus)))
  grp <- apply(table(dat), 2, function(x) names(x[x == 1]))
  p <- ggtree(hc, hang=-1, branch.length = "none", show.legend=FALSE)
  # extract the most recent common ancestor
  noids <- lapply(grp, function(x) unlist(lapply(x, function(i) ggtree::nodeid(p, i))))
  roots <- unlist(lapply(noids, function(x) ggtree::MRCA(p, x)))
  # cluster data
  p <- ggtree::groupOTU(p, grp, "group") + aes_(color =~ group)
  rangeX <- max(p$data$x, na.rm=TRUE) - min(p$data$x, na.rm=TRUE)
  if (inherits(offset_tiplab, "rel")) {
    offset_tiplab <- unclass(offset_tiplab)
    if (geneClusterPanel == "pie" || is.null(geneClusterPanel)) {
      ## 1.5 * max(radius_of_pie)
      offset_tiplab <- offset_tiplab * 1.5 * max(sqrt(d$count / sum(d$count) * cex_category))
    }  else if (geneClusterPanel == "heatMap") {
      ## Close to the width of the tree
      offset_tiplab <- offset_tiplab * 0.16 * ncol(ID_Cluster_mat) * rangeX
    } else if (geneClusterPanel == "dotplot") {
      ## Close to the width of the tree
      offset_tiplab <- offset_tiplab * 0.09 * ncol(ID_Cluster_mat) * rangeX
    }
  }

  if (inherits(offset, "rel")) {
    offset <- unclass(offset)
    offset <- offset * rangeX * 1.2 + offset_tiplab
  }
  # max_nchar <- max(nchar(p$data$label), na.rm = TRUE)

  pdata <- data.frame(name = p$data$label, color2 = p$data$group)
  pdata <- pdata[!is.na(pdata$name), ]
  cluster_color <- unique(pdata$color2)
  n_color <- length(levels(cluster_color)) - length(cluster_color)
  if (!is.null(group_color)) {
    color2 <- c(rep("black", n_color), group_color)
    p <- p + scale_color_manual(values = color2, guide = 'none')
  }
  p <- p %<+% d


  if (!is.null(label_format_tiplab)) {
    label_func_tiplab <- default_labeller(label_format_tiplab)
    if (is.function(label_format_tiplab)) {
      label_func_tiplab <- label_format_tiplab
    }
    isTip <- p$data$isTip
    p$data$label[isTip] <-  label_func_tiplab(p$data$label[isTip])
  }

  p <- add_cladelab(p = p, nWords = nWords,
                    label_format_cladelab = label_format_cladelab,
                    offset = offset, roots = roots, fontsize = fontsize,
                    group_color = group_color, cluster_color = cluster_color,
                    pdata = pdata, extend = extend, hilight = hilight, align = align)



  # DEVNOTE: to add new labels: add a column to p$data where the first 30 (showCategory) rows need labels and the others NA
  # print(p$data)
  # print(p$data$count)



  # this is where p.adjust colored circles are added!
  if (add_tippoint) {
    p <- p + ggnewscale::new_scale_colour() +
      geom_tippoint(aes(color = color, size = count )) +
      scale_colour_continuous(low="red", high="blue", name = color,
                              guide = guide_colorbar(reverse = TRUE))


    ## DEVNOTES
    # check https://guangchuangyu.github.io/ggtree-book/chapter-ggtree.html ?

    # Convert GO ids to/from terms, then calculate up/down ratio based on geneRatio as 100%
    ## calculate for each GO:term, how to add to object and then get into this function?

    ## get data in this function by modifying the other function as well
    # add geneRatio for size and %up/downregulated for color (scaled from 0-100)
    # p <- p + ggnewscale::new_scale_colour() +
    #   # uncomment this for a next column of dots
    #   geom_point(aes(x+1, color = color, size = count)) +
    #   geom_text(aes(x+1, y, label = count), inherit.aes = T) +
    #   scale_color_gradientn(colours = c('green', 'white', 'purple'), name = color,
    #                           guide = guide_colorbar(reverse = TRUE))
  }
  ## add tiplab
  p <- p + geom_tiplab(offset = offset_tiplab + 1, hjust = 0,
                       show.legend = FALSE, align = align_tiplab, linesize = 0)
  return(p)
}
# changing namespace and environment of adjusted functions for overwriting originals
environment(group_tree.adjusted) <- asNamespace("enrichplot")
assignInNamespace("group_tree", group_tree.adjusted, ns = "enrichplot")











astrocyte_deg <-  "C:/Users/mauri/Desktop/Single Cell RNA Sequencing/Seurat/results/2022-11-01 14-02-50/integrated/BL_A + BL_C/DE_analysis/sample_markers/method=DESeq2-pct1=BL_C-pct2=BL_A - (nz-)p-val st 0.05.csv"
# neuronal_deg <- "C:/Users/mauri/Desktop/Single Cell RNA Sequencing/Seurat/results/Pipe_SCTv2_23-06 cluster_level_selection/integrated/BL_N + BL_C/after_selection_old/DE_analysis/sample_markers/method=DESeq2-pct1=BL_C-pct2=BL_N - (nz-)p-val st 0.05.csv"
run_fgsea(
  output_dir = "C:/Users/mauri/Desktop/Single Cell RNA Sequencing/Seurat/results/fgsea_GOuniverse_treeplot_KEGG_MSigDB_neurons_TPlabels/",
  dea_result_file = astrocyte_deg,
  cellRanger_ensembl_features = "C:/Users/mauri/Desktop/Single Cell RNA Sequencing/Seurat/data/Ensembl genes.tsv"
)