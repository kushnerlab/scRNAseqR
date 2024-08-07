% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/FGSEA.R
\name{fgsea_compare_DEG_GO_universe}
\alias{fgsea_compare_DEG_GO_universe}
\title{Compare all genes from the DEG analysis against the Gene Ontology database}
\usage{
fgsea_compare_DEG_GO_universe(
  deg_universe,
  go_universe,
  ensembl_genes_ids,
  output_dir
)
}
\arguments{
\item{deg_universe}{character vector of all DEG genes}

\item{go_universe}{character vector of all GO genes}

\item{ensembl_genes_ids}{translation table with ensembl IDs and gene names}

\item{output_dir}{output directory for plots, string}
}
\description{
For GSEA and ORA a 'universe' of genes is used. This universe can be all
genes measured during your experiment or specifically all genes that are in
a specific database, here GO.
The overlapping and non overlapping genes are saved as .csv
}
