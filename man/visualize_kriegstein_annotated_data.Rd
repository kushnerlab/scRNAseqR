% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/annotation.R
\name{visualize_kriegstein_annotated_data}
\alias{visualize_kriegstein_annotated_data}
\title{Perform visualizations of annotated data from Kriegstein reference data.}
\usage{
visualize_kriegstein_annotated_data(
  sample_names,
  sample_files,
  output_dir,
  kriegstein_data_dir,
  kriegstein_annotated_input_dir,
  annotations = c("age", "structure", "custom.clusterv2"),
  annotations_to_plot = c("custom.clusterv2"),
  ref_aggr_strategy = "max"
)
}
\arguments{
\item{sample_names}{Character vector with sample names.}

\item{sample_files}{Character vector with sample .rds files.}

\item{output_dir}{String with output directory for results.}

\item{kriegstein_data_dir}{String with Kriegstein folder path, containing (custom.)meta.tsv and exprMatrix.tsv.gz.}

\item{kriegstein_annotated_input_dir}{String with Kriegstein input directory containing annotated data chunks.}

\item{annotations}{default: c("age", "structure", "custom.clusterv2"), annotations from meta features used for heatmap metadata.}

\item{annotations_to_plot}{default: c("custom.clusterv2"), annotations from meta features used for individual heatmaps.}

\item{ref_aggr_strategy}{default: "max", choose one of "max" or "mean".
"max" as SingleR intended (combineCommonResults), max.scores/max.labels across references.
"mean" custom for averaging scores (and labels) across references.}
}
\description{
Perform visualizations of annotated data from Kriegstein reference data.
}
\examples{
\dontshow{if (FALSE) (if (getRversion() >= "3.4") withAutoprint else force)(\{ # examplesIf}
kriegstein_data_dir <-  "path/to/Kriegstein_data/"

visualize_kriegstein_annotated_data(
  sample_names = c("A", "B"),
  sample_files = c(file.path("path", "to", "sampleA.rds"), file.path("path", "to", "sampleB.rds")),
  output_dir = file.path("path", "to", "results"),
  kriegstein_data_dir = kriegstein_data_dir,
  kriegstein_annotated_input_dir = file.path("path", "to", "kriegstein_annotated_Rdata"),
  annotations = c("age", "structure", "custom.clusterv2"),
  annotations_to_plot = c("custom.clusterv2"),
  ref_aggr_strategy = "max"
)
\dontshow{\}) # examplesIf}
}
