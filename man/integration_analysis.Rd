% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/samples_integration.R
\name{integration_analysis}
\alias{integration_analysis}
\title{Analysis of integrated samples}
\usage{
integration_analysis(
  integrated,
  output_dir,
  sample_name,
  features_of_interest,
  sample_names = NULL
)
}
\arguments{
\item{integrated}{Integrated Seurat object}

\item{output_dir}{Package home directory, used to create output directory for results.}

\item{sample_name}{name of integrated sample, combined of samples_names}

\item{features_of_interest}{gene of interest}

\item{sample_names}{names of samples to be integrated}
}
\description{
Analysis of integrated samples
}
