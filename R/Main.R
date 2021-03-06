# Copyright 2020 Observational Health Data Sciences and Informatics
#
# This file is part of ScyllaEstimation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#' Execute the Study
#'
#' @details
#' This function executes the ScyllaEstimation Study.
#'
#' The \code{createCohorts}, \code{synthesizePositiveControls}, \code{runAnalyses}, and \code{runDiagnostics} arguments
#' are intended to be used to run parts of the full study at a time, but none of the parts are considered to be optional.
#'
#' @param connectionDetails    An object of type \code{connectionDetails} as created using the
#'                             \code{\link[DatabaseConnector]{createConnectionDetails}} function in the
#'                             DatabaseConnector package.
#' @param cdmDatabaseSchema    Schema name where your patient-level data in OMOP CDM format resides.
#'                             Note that for SQL Server, this should include both the database and
#'                             schema name, for example 'cdm_data.dbo'.
#' @param cohortDatabaseSchema Schema name where intermediate data can be stored. You will need to have
#'                             write priviliges in this schema. Note that for SQL Server, this should
#'                             include both the database and schema name, for example 'cdm_data.dbo'.
#' @param cohortTable          The name of the table that will be created in the work database schema.
#'                             This table will hold the exposure and outcome cohorts used in this
#'                             study.
#' @param oracleTempSchema     Should be used in Oracle to specify a schema where the user has write
#'                             priviliges for storing temporary tables.
#' @param outputFolder         Name of local folder to place results; make sure to use forward slashes
#'                             (/). Do not use a folder on a network drive since this greatly impacts
#'                             performance.
#' @param databaseId           A short string for identifying the database (e.g.
#'                             'Synpuf').
#' @param databaseName         The full name of the database (e.g. 'Medicare Claims
#'                             Synthetic Public Use Files (SynPUFs)').
#' @param databaseDescription  A short description (several sentences) of the database.
#' @param verifyDependencies   Check whether correct package versions are installed?
#' @param createCohorts        Create the cohortTable table with the exposure and outcome cohorts?
#' @param runAnalyses          Perform the cohort method analyses?
#' @param computeBalance       Compute covariate balance?
#' @param packageResults       Should results be packaged for later sharing?
#' @param maxCores             How many parallel cores should be used? If more cores are made available
#'                             this can speed up the analyses.
#' @param minCellCount         The minimum number of subjects contributing to a count before it can be included
#'                             in packaged results.
#'
#' @examples
#' \dontrun{
#' connectionDetails <- createConnectionDetails(dbms = "postgresql",
#'                                              user = "joe",
#'                                              password = "secret",
#'                                              server = "myserver")
#'
#' execute(connectionDetails,
#'         cdmDatabaseSchema = "cdm_data",
#'         cohortDatabaseSchema = "study_results",
#'         cohortTable = "cohort",
#'         oracleTempSchema = NULL,
#'         outputFolder = "c:/temp/study_results",
#'         maxCores = 4)
#' }
#'
#' @export
execute <- function(connectionDetails,
                    cdmDatabaseSchema,
                    cohortDatabaseSchema = cdmDatabaseSchema,
                    cohortTable = "cohort",
                    oracleTempSchema = cohortDatabaseSchema,
                    outputFolder,
                    databaseId = "Unknown",
                    databaseName = "Unknown",
                    databaseDescription = "Unknown",
                    verifyDependencies = TRUE,
                    createCohorts = TRUE,
                    runAnalyses = TRUE,
                    computeBalance = TRUE,
                    packageResults = TRUE,
                    maxCores = 4,
                    minCellCount= 5) {
  if (!file.exists(outputFolder))
    dir.create(outputFolder, recursive = TRUE)

  ParallelLogger::addDefaultFileLogger(file.path(outputFolder, "log.txt"))
  ParallelLogger::addDefaultErrorReportLogger(file.path(outputFolder, "errorReportR.txt"))
  on.exit(ParallelLogger::unregisterLogger("DEFAULT_FILE_LOGGER", silent = TRUE))
  on.exit(ParallelLogger::unregisterLogger("DEFAULT_ERRORREPORT_LOGGER", silent = TRUE), add = TRUE)

  if (!is.null(getOption("andromedaTempFolder")) && !file.exists(getOption("andromedaTempFolder"))) {
    warning("andromedaTempFolder '", getOption("andromedaTempFolder"), "' not found. Attempting to create folder")
    dir.create(getOption("andromedaTempFolder"), recursive = TRUE)
  }

  if (verifyDependencies) {
    ParallelLogger::logInfo("Checking whether correct package versions are installed")
    verifyDependencies()
  }

  if (createCohorts) {
    ParallelLogger::logInfo("Creating exposure and outcome cohorts")
    createCohorts(connectionDetails = connectionDetails,
                  cdmDatabaseSchema = cdmDatabaseSchema,
                  cohortDatabaseSchema = cohortDatabaseSchema,
                  cohortTable = cohortTable,
                  oracleTempSchema = oracleTempSchema,
                  databaseId = databaseId,
                  outputFolder = outputFolder)
  }

  if (runAnalyses) {
    ParallelLogger::logInfo("Running CohortMethod analyses")
    runCohortMethod(connectionDetails = connectionDetails,
                    cdmDatabaseSchema = cdmDatabaseSchema,
                    cohortDatabaseSchema = cohortDatabaseSchema,
                    cohortTable = cohortTable,
                    oracleTempSchema = oracleTempSchema,
                    outputFolder = outputFolder,
                    maxCores = maxCores)
  }

  if (computeBalance) {
    ParallelLogger::logInfo("Computing covariate balance")
    computeCovariateBalance(outputFolder = outputFolder,
                            maxCores = maxCores)
  }
  if (packageResults) {
    ParallelLogger::logInfo("Packaging results")
    exportResults(outputFolder = outputFolder,
                  connectionDetails = connectionDetails,
                  cdmDatabaseSchema = cdmDatabaseSchema,
                  databaseId = databaseId,
                  databaseName = databaseName,
                  databaseDescription = databaseDescription,
                  minCellCount = minCellCount,
                  maxCores = maxCores)
  }

  invisible(NULL)
}

verifyDependencies <- function() {
  expected <- RJSONIO::fromJSON("renv.lock")
  expected <- dplyr::bind_rows(expected[[2]])
  basePackages <- rownames(installed.packages(priority = "base"))
  expected <- expected[!expected$Package %in% basePackages, ]
  observedVersions <- sapply(sapply(expected$Package, packageVersion), paste, collapse = ".")
  expectedVersions <- sapply(sapply(expected$Version, numeric_version), paste, collapse = ".")
  mismatchIdx <- which(observedVersions != expectedVersions)
  if (length(mismatchIdx) > 0) {

    lines <- sapply(mismatchIdx, function(idx) sprintf("- Package %s version %s should be %s",
                                                       expected$Package[idx],
                                                       observedVersions[idx],
                                                       expectedVersions[idx]))
    message <- paste(c("Mismatch between required and installed package versions. Did you forget to run renv::restore()?",
                       lines),
                     collapse = "\n")
    stop(message)
  }
}
