% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/UploadResultsToDatabase.R
\name{createResultsDataModel}
\alias{createResultsDataModel}
\title{Create the results data model tables on a database server.}
\usage{
createResultsDataModel(connectionDetails, schema)
}
\arguments{
\item{connectionDetails}{An object of type \code{connectionDetails} as created using the
\code{\link[DatabaseConnector]{createConnectionDetails}} function in the
DatabaseConnector package.}

\item{schema}{The schema on the postgres server where the tables will be created.}
}
\description{
Create the results data model tables on a database server.
}
\details{
Only PostgreSQL servers are supported.
}
