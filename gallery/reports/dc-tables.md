# Descriptive tables

# Descriptive tables

Published

2026-10-28 09:17

A `dc-tables` job is the formatted descriptive table: every variable the
study reports, grouped under the section headings the SAS `%desc_tab`
lists carried as comments, categorical as `n (%)` and continuous in the
summary form you select. The default is median (15th, 85th percentile).
`%desc_tab` wrote the categorical and continuous tables as two RTF
files; `hv_tbl_summary()` writes one table with both. It describes; with
`BY` set it separates the groups into columns. `COMPARE` chooses whether
to test them; a p-value here is a prompt for an analysis, not a result.
The report shows the table in the report style, with each variable’s
column name beside its label while `SHOW_VARIABLE` is `TRUE`. The Word
file holds the same table in the manuscript style, under its caption, as
a journal receives it.

Code

``` r
# unnumbered: setup, and the box under the title
SUBJECT <- "cohort"
TYPE    <- "eda"
.in <- knitr::current_input(dir = TRUE)
suppressPackageStartupMessages({
  library(hvtiRutilities)
  library(hvtiRtables)
  library(hvtiPlotR)
  library(ggplot2)
})
if (utils::packageVersion("hvtiRtables") < "1.0.11") {
  stop("This job needs hvtiRtables >= 1.0.11 for hv_table_style(), the manuscript Word table, its page orientation and ",
       "summaries that a study's own sd() or median() cannot break; ",
       utils::packageVersion("hvtiRtables"), " is installed.", call. = FALSE)
}
if (utils::packageVersion("hvtiPlotR") < "2.7.14") {
  stop("This job needs hvtiPlotR >= 2.7.14 for hv_correlation_matrix(); ",
       utils::packageVersion("hvtiPlotR"), " is installed.", call. = FALSE)
}
# The study root is the nearest directory above this file holding _study.yml,
# so the job renders the same from the Render button, quarto render, or
# render_job(), at any depth, with no path in this document to edit.
# To render a job you have not finished, leave a chunk out with the chunk
# option skip, giving the reason in quotes, or call hvtiRtemplates::stop_here()
# in a chunk to leave out everything below it. A draft lists each one in a
# callout; a final render refuses them, as it refuses an unresolved marker.
# ?stop_here has more.
.job <- hvtiRtemplates:::.job_setup(SUBJECT, TYPE, envir = environment())
.root <- .job$root
set_path <- .job$set_path
.provenance_data <- list()
# Saves a figure as <name>.png, .pdf and .tiff in this set's graphs/ folder (or `kind`'s),
# under the SAVE_FIGURES and FIGURES study choices.
save_figure <- function(plot, name, width = 6, height = 4, kind = "graphs", linked = FALSE) {
  hvtiRtemplates:::.save_figure(plot, set_path(kind, paste0(name, ".png")), width, height,
                                SAVE_FIGURES, FIGURES, linked)
}
# The draft banners, if any, and the box under the title, after all the code above.
.job$notice
```

**final** · data `built` `built_20261028.parquet`, dated 2026-10-28 ·
rendered by gallery on gallery · hvtiRtemplates 1.5.3

## Study choices

Set the values in this chunk before rendering.

Code

``` r
# Demo: the registered dataset this job reads ("built" is the study dataset).
# MIGRATE-BEGIN: dc-tables-data
DATASET <- "built"
# MIGRATE-END: dc-tables-data

# Demo: an hvtiRdatabuild analysis set, or NULL to read the whole dataset.
ANALYSIS_SET <- NULL

# Demo: rows to keep, dplyr::filter() style, or NULL to keep every row:
#   WHERE <- quote(age >= 18)
#   WHERE <- rlang::exprs(age >= 18, hx_chf == 1)
WHERE <- NULL

# Demo: the patient identifier. Without "ccfid" the job uses MRN, then eMRN;
# name another column, such as "randid", if the study uses one.
ID <- "patient_id"

# Demo: what makes a row unique; one row per patient unless repeated measures
# add their visit time or date, for example KEY <- c(ID, "iv_echo").
KEY <- ID

# Optional, and needs no edit: NULL reads the cohort alone. To join one
# registered ancillary dataset (echoes, labs), name it in JOIN. The cohort
# above decides the patients, one row each; the joined records of other
# patients are dropped and counted in the data table.
#   JOIN_VARS: the cohort columns each joined row carries; NULL carries all,
#     and a column both datasets have stops, so list only those the job needs.
#   REDUCE: NULL keeps a row per joined record, keyed on that dataset's key;
#     list(rule = "first", by = "echo_date") keeps one row per patient ("last",
#     or "nearest" with to = a cohort date column). WHERE on a joined column
#     filters the records first, so "last" with WHERE echo_type == "TTE"
#     keeps each patient's last TTE. A tie stops: picking one record
#     silently would be a hidden choice; by = c("echo_date", "echo_seq")
#     breaks it. A job that counts or models
#     patients, one row each, needs REDUCE: NULL would count every record.
#   JOIN_KEY: overrides the joined dataset's registered key.
JOIN <- NULL
JOIN_VARS <- NULL
REDUCE <- NULL
JOIN_KEY <- NULL

# Demo: the variables to report, grouped. Each name is a section heading and
# becomes a row group in the table, in this order. These are the /* Demography */
# style banners from the SAS varlist; carry them across unchanged so the R table
# reads like the SAS one. Commented-out SAS blocks stay out.
# A fuller grouping to start from, the house summary-table categories with the
# SAS template's added where they differ. The names are CORR database columns, not
# one study's. Uncomment it in place of the GROUPS below, then delete the groups
# and rows your data does not have, since a name missing from the data stops the
# table. Race is race_grp; some studies spell it race_gp.
# GROUPS-EXAMPLE-BEGIN
# GROUPS <- list(
#   Demography = c("female", "age", "bsa", "bmi", "wt", "ht", "wtht", "race_bl", "race_wh", "race_ot", "race_grp"),
#   Symptoms = c("surgstat", "nyha_pr", "srgstat", "srg_ele", "srg_emg", "srg_emgs", "srg_urg", "srg_urem", "emgsrg"),
#   `AV hemodynamics` = c("avrgrg", "avrg_com", "avsten", "pavmngra", "pavpkgra", "pav_area"),
#   `Other valve pathology` = c("mvrgrg", "mvrg_com", "mvsten", "pvrgrg", "pvrgsev", "pvsten", "tvrgrg", "tvrg_com",
#                               "pmvmngra", "pmvpkgra", "tvsten"),
#   `LV function` = c("hx_mi", "plv_sfun", "lvef_pr", "pfs"),
#   `LV geometry` = c("plvidd", "plvisd", "plvedv", "plvedvol", "plvesv", "plvesvol", "plvedvi", "plvesvi"),
#   `LV mass` = c("prwt", "pivswt", "ppwt", "plvmass", "plvmassi"),
#   `Aorta diameter` = c("pmidaadm", "paosindm"),
#   `Cardiac comorbidity` = c("afib_pr", "chb_pr", "varr_pr", "hx_csurg", "hx_chf", "surg_num"),
#   `Non-Cardiac comorbidity` = c("hx_endo", "hx_pad", "hx_htn", "hx_dmtrt", "hx_iddm", "hx_niddm", "hx_copd", "hx_smoke",
#                                 "dial_pr", "hx_cva", "blrbn_pr", "creat_pr", "crcl_pr", "gfr_pr", "bun_pr", "hct_pr",
#                                 "chol_pr", "hdl_pr", "ldl_pr", "trig_pr", "meld_pr", "ptinr_pr"),
#   Procedure = c("avsize", "sp_cabg", "sp_av", "sp_mv", "sp_tv", "sp_avrpl", "sp_mvrpr", "sp_mvrpl", "sp_tvrpr",
#                 "sp_tvrpl", "sp_aotic", "sp_afib", "sp_asdpf", "sp_dscao", "sp_chd", "sp_anlre", "ita_any", "stsproc",
#                 "sp_pv", "sp_avrpr", "spc_tavr", "sp_lv", "sp_cend", "sp_sepmy", "sp_atrmy", "sp_tx", "sp_peric",
#                 "sp_tmr", "numcomp", "numcomp2", "ita_none", "ita_sin", "ita_bil", "ita_num"),
#   `Discharge medication` = c("dantico", "dccoum", "dcadp", "dcasa", "dcoanplt"),
#   Support = c("iv_aocc", "iv_cpb", "aoxclmp", "onpump", "circarr", "iabp", "iabpwhn", "iv_tca"),
#   `LA Dimensions` = c("pla_ge6", "pladia", "plavol", "plavoli", "plasarea", "pladarea"),
#   `Right Ventricular Function` = c("prvsp", "prvspnew", "ptv_rvel"),
#   Etiology = c("aet_rheu", "aet_degn", "aet_endo", "aet_cong", "aet_rgrg", "aet_nos", "avetiol", "met_isch", "met_degn",
#                "met_endo", "met_rgrg", "met_nos", "mvetiol", "tet_rheu", "tet_degn", "tet_rgrg", "tet_nos", "tvetiol"),
#   `Coronary Anatomy` = c("cad_sys", "vd0", "vd1", "vd2", "vd3", "lmt50", "lad50", "lad70", "lcx50", "lcx70", "rca50",
#                          "rca70", "lmt", "lad", "lcx", "rca"),
#   `STS Predicted Risk Scores` = c("sts14d", "sts6d", "stsdeep", "stsmm", "stsmort", "stsrenf", "stsreop", "stsstro",
#                                   "stsvent"),
#   `Incision Detail` = c("incision", "robot"),
#   `Intraoperative Management` = c("bldicry", "bldiffp", "bldiplt", "bldirbc", "bldiprod", "bldicryu", "bldiffpu",
#                                   "bldipltu", "bldirbcu"),
#   `Postoperative Management` = c("bldpcry", "bldpffp", "bldpplt", "bldprbc", "bldpprod", "bldpcryu", "bldpffpu",
#                                  "bldppltu", "bldprbcu"),
#   `Combined Blood Products` = c("bldtcry", "bldtffp", "bldtplt", "bldtrbc", "bldtprod", "trsf_all", "trsf_noc",
#                                 "bldtcryu", "bldtffpu", "bldtpltu", "bldtrbcu"),
#   `Postoperative Complications` = c("spu_asdv", "cotafib", "ciseptic", "cistdeep", "cnstrokp", "crenfail", "crendial",
#                                     "cpvntlng", "coprebld", "copregft", "coprenon", "copreoth", "coprevlv", "copreany",
#                                     "hdeath", "opmort", "co_stsmm", "los_lt6", "los_gt14"),
#   `Length of Stay` = c("los_hos", "los_op", "los_icu"),
#   Experience = c("iv_opyrs"),
#   `Time-related Outcomes` = c("dead", "iv_dead")
# )
# GROUPS-EXAMPLE-END
# MIGRATE-BEGIN: dc-tables-config
GROUPS <- list(
  Demography = c("age", "female", "race_grp", "bmi"),
  History    = c("hx_chf", "hx_dm", "nyha_pr"),
  Echo       = c("lvef", "plvmassi"),
  Laboratory = "creat_pr"
)
# Demo: NULL for the overall table. A column name reproduces the `%macro skip`
# by-group sections (by=): one column per observed level. Review byvalue=
# against the data before accepting the columns; COMPARE controls testing.
BY <- NULL
# All three NULL values use automatic classification for a new, unmigrated job.
# Migrated jobs declare every row explicitly; character(0) is an empty bucket.
CONTINUOUS <- NULL
BINARY <- NULL
CATEGORICAL <- NULL
COMPARE <- "none"             # Demo: choose whether to compare groups
CONTINUOUS_STAT <- "median"   # Demo: choose the continuous summary
PERCENTILES <- c(15, 85)       # Demo: choose the reported percentiles
ABBREVIATIONS <- character(0) # Demo: define abbreviations used in the table
WORD_FILE <- "dc-tables.docx"  # Demo: choose the Word filename within this set
MANUSCRIPT_LAYOUT <- "compare" # Demo: choose the Word table's layout
# MIGRATE-END: dc-tables-config
# The Word table is drawn in the manuscript style. MANUSCRIPT_LAYOUT, above,
# says what the table does: "compare" puts one n column beside the groups it
# compares; "describe" puts a count beside each group, for cohorts or repeated
# measures shown side by side. "describe" is also the layout that draws
# CONTINUOUS_STAT "both": "compare" has one statistic column per group.
# Demo: the Word table's caption, written in bold above it. A manuscript
# table must carry one, so the title is never typed into Word by hand.
MANUSCRIPT_CAPTION <- "Table 1. Patient characteristics"
# Demo: the shading of the Word table's section rows, one color "#RRGGBB".
# Journals differ here; "#CAEDFB" is the house default.
MANUSCRIPT_FILL <- "#CAEDFB"
# Demo: the Word table's page. "auto" turns it landscape when it is too wide
# for portrait, as a table with many groups is; "portrait" or "landscape"
# always wins, and a table too wide for that page has its columns narrowed.
TABLE_ORIENTATION <- "auto"
# Demo: TRUE leaves out a row whose every recorded value is the same, such as
# a finding every patient has by inclusion: the row says nothing, and a binary
# one has no event to count. The report names each row left out. FALSE keeps
# every row, and a constant binary row then stops the table.
DROP_CONSTANT <- TRUE
# Demo: the table's labels are tidied from the dataset's, which serve the
# analysis: TRUE strips a leading "Preoperative" and a coding such as "(Y/N)"
# or "(for analysis)", writes sentence case keeping the study's abbreviations,
# and turns kg/m2 into kg/m^2^. FALSE prints the labels as they are, or name
# the rules to keep, e.g. c("preoperative", "coding", "case", "units"). A
# label the rules get wrong belongs in table_labels.yml; see "Table" below.
TABLE_LABEL_RULES <- TRUE
# Demo: force a bucket where the data guess wrong, e.g. an ordinal score you
# want summarized as continuous: list(continuous = c("nyha_pr")). list() for none.
OVERRIDES <- list()
# Demo: continuous variables to show as mean ± SD, where the rest show
# CONTINUOUS_STAT: a manuscript table often wants age as a mean and length of
# stay as a median. Display only: every continuous variable is still tested
# with Wilcoxon (Kruskal-Wallis for three or more groups). character(0) for none.
MEAN_SD <- character(0)
# Demo: categorical variables whose levels are ordered, such as NYHA class.
# They are shown level by level like any other; only STDDIFF treats them
# differently, ranking them as %stddiff did with ORD1=. character(0) for none.
ORDINAL <- character(0)
# Demo: TRUE adds the standardized difference (%) %summarytable printed, from
# %stddiff, beside COMPARE's column. It needs BY with exactly two values, and
# COMPARE "pvalue" or "none": COMPARE's "smd" is gtsummary's generic
# difference, not %stddiff's, and the two disagree for skewed and ordinal rows.
STDDIFF <- FALSE
# Demo: with STDDIFF, the value of BY that is the treated group, such as
# "tavr". NULL when BY is coded 0/1, where 1 is treated.
GROUP_1 <- NULL
# Demo: FALSE drops the Variable column, the column name beside each label,
# from the report. The Word table never carries it, whatever this says.
SHOW_VARIABLE <- TRUE
# Demo: NULL skips the correlation variant (dc.tables.ods_<topic>.sas). To run
# it, name the numeric columns, the anchor to correlate them against (NULL for
# every pair), and an optional stratum:
#   list(vars = c("glu_pr", "creat_pr"), with = "a1c_pr", by = "a1c_grp")
CORR <- NULL

# Each figure is saved to descriptive/ as a PNG (for Word), and a PDF and a TIFF (for the publisher).
# SAVE_FIGURES <- FALSE saves none; FIGURES keeps only the figures whose names
# start with one of its entries, e.g. FIGURES <- c("hp-survival"). The names are the
# file names, listed for each template in the templates README.
SAVE_FIGURES <- TRUE
FIGURES <- NULL
```

## Data

Code

``` r
# The checksum of every dataset in manifest.yaml is checked before anything is
# read, so a result can name the data that produced it. It stops on a mismatch.
hvtiRutilities::verify_manifest(file.path(.root, "manifest.yaml"))
.cfg <- study_config(start = .root)
job_data <- hvtiRtemplates::read_job_data(.cfg, dataset = DATASET, analysis_set = ANALYSIS_SET,
                                          where = WHERE, id = ID, key = KEY, join = JOIN, join_vars = JOIN_VARS,
                                          reduce = REDUCE, join_key = JOIN_KEY)
d <- job_data$data
.provenance_data <- c(if (exists(".provenance_data")) .provenance_data else list(), list(job_data$provenance),
                      if (!is.null(job_data$provenance_join)) list(job_data$provenance_join))
knitr::kable(job_data$record, col.names = c("Data", ""))
```

| Data                |                                          |
|:--------------------|:-----------------------------------------|
| Source              | dataset `built` (built_20261028.parquet) |
| Rows read           | 800                                      |
| ID                  | `patient_id`                             |
| Identifiers dropped | none                                     |
| Rows kept           | 800 rows on 800 patients                 |

Table 1: The data this job read

Code

``` r
# unnumbered: its child chunk carries its own label and caption
if (!is.null(job_data$attrition)) {
  .fence <- strrep("`", 3)
  cat(knitr::knit_child(text = c(
    paste0(.fence, "{r}"), "#| label: tbl-data-attrition",
    paste0("#| tbl-cap: ", encodeString(paste0("Analysis set `", ANALYSIS_SET, "`: exclusions, in order"), quote = "\"")),
    "knitr::kable(job_data$attrition)", .fence
  ), envir = environment(), quiet = TRUE), sep = "\n")
}
```

Code

``` r
classify_buckets <- function(d, vars, overrides = list()) {
  vars <- unique(as.character(vars))
  unknown <- setdiff(vars, names(d))
  if (length(unknown)) stop("Unknown table variable(s): ", paste(unknown, collapse = ", "), call. = FALSE)
  allowed <- c("continuous", "binary", "categorical")
  if (!is.list(overrides)) {
    stop("overrides must be a list named continuous, binary, or categorical.", call. = FALSE)
  }
  override_names <- names(overrides)
  if (length(overrides) &&
        (is.null(override_names) || anyNA(override_names) || any(!nzchar(override_names)))) {
    stop("Every override bucket must be named continuous, binary, or categorical.", call. = FALSE)
  }
  if (anyDuplicated(override_names)) {
    stop("Override bucket names must be unique.", call. = FALSE)
  }
  if (length(setdiff(override_names, allowed))) {
    stop("overrides must be a list named continuous, binary, or categorical.", call. = FALSE)
  }
  forced <- unlist(overrides, use.names = FALSE)
  if (anyDuplicated(forced)) stop("A variable may appear in only one override bucket.", call. = FALSE)
  if (length(setdiff(forced, vars))) {
    stop("Override variable(s) are not in vars: ", paste(setdiff(forced, vars), collapse = ", "), call. = FALSE)
  }

  is_binary <- vapply(d[vars], function(x) {
    if (is.logical(x)) return(TRUE)
    values <- unique(stats::na.omit(x))
    if (is.numeric(x)) return(setequal(values, c(0, 1)))
    if (is.factor(x)) {
      return(nlevels(x) == 2L && setequal(toupper(levels(x)), c("NO", "YES")))
    }
    if (is.character(x)) {
      return(length(values) == 2L && setequal(toupper(values), c("NO", "YES")))
    }
    FALSE
  }, logical(1))
  is_continuous <- vapply(d[vars], function(x) {
    is.numeric(x) && length(unique(x[!is.na(x)])) > 6L
  }, logical(1))
  buckets <- list(
    continuous = vars[!is_binary & is_continuous],
    binary = vars[is_binary],
    categorical = vars[!is_binary & !is_continuous]
  )
  for (bucket in intersect(allowed, names(overrides))) {
    move <- as.character(overrides[[bucket]])
    buckets <- lapply(buckets, setdiff, y = move)
    buckets[[bucket]] <- unique(c(buckets[[bucket]], move))
  }
  buckets
}

# The standardized difference %summarytable printed, from %stddiff by way of
# hvtiRpropensity::ps_stddiff(), formatted as a percentage for hv_tbl_compare().
# The macro sent its mean +/- SD variables to %stddiff as Gaussian, and its
# other continuous and its ordinal variables as ranked; the buckets here follow
# it, so a skewed variable is not scored as though it were normal.
stddiff_values <- function(d, by, buckets, mean_sd = character(0), ordinal = character(0), group_1 = NULL) {
  if (is.null(by)) stop("STDDIFF compares two groups, so BY must name the group column.", call. = FALSE)
  seen <- unique(stats::na.omit(d[[by]]))
  if (length(seen) != 2L) {
    stop("STDDIFF needs exactly two values of ", by, "; the data hold ", length(seen), ".", call. = FALSE)
  }
  if (is.null(group_1) && !(is.logical(seen) || all(as.character(seen) %in% c("0", "1")))) {
    stop("STDDIFF needs GROUP_1 to name the treated value of ", by, ", one of: ",
         paste(sort(as.character(seen)), collapse = ", "), ".", call. = FALSE)
  }
  # A 0/1 group stored as text or a factor is the same group: 1 is treated,
  # as it is for a numeric one, which ps_stddiff() needs to be told.
  if (is.null(group_1) && !is.numeric(seen) && !is.logical(seen)) group_1 <- "1"
  if (!is.null(group_1) && !(as.character(group_1) %in% as.character(seen))) {
    stop("GROUP_1 must be one of the values of ", by, ": ",
         paste(sort(as.character(seen)), collapse = ", "), ".", call. = FALSE)
  }
  if (length(setdiff(mean_sd, buckets$continuous))) {
    stop("MEAN_SD names variable(s) that are not continuous: ",
         paste(setdiff(mean_sd, buckets$continuous), collapse = ", "), call. = FALSE)
  }
  if (length(setdiff(ordinal, buckets$categorical))) {
    stop("ORDINAL names variable(s) that are not categorical: ",
         paste(setdiff(ordinal, buckets$categorical), collapse = ", "), call. = FALSE)
  }
  # ps_stddiff() takes a binary column as 0/1 or logical; the table also
  # accepts Yes/No, so convert those, and only those, to logical first.
  for (v in buckets$binary) {
    if (is.character(d[[v]]) || is.factor(d[[v]])) d[[v]] <- toupper(as.character(d[[v]])) == "YES"
  }
  # %stddiff ranks an ordinal variable, so it needs the order: a factor's
  # levels give it, and text does not.
  for (v in intersect(ordinal, names(d))) {
    if (is.factor(d[[v]])) {
      d[[v]] <- as.integer(d[[v]])
    } else if (!is.numeric(d[[v]])) {
      stop("ORDINAL variable ", v, " must be numeric or a factor whose levels are in order.", call. = FALSE)
    }
  }
  none <- function(x) if (length(x)) x else NULL
  r <- hvtiRpropensity::ps_stddiff(
    d, treatment_col = by, treated_level = group_1,
    gaussian = none(intersect(buckets$continuous, mean_sd)),
    nong_ord = none(c(setdiff(buckets$continuous, mean_sd), intersect(buckets$categorical, ordinal))),
    binary = none(buckets$binary),
    categorical = none(setdiff(buckets$categorical, ordinal))
  )
  s <- r$tables$stddiff
  stats::setNames(sprintf("%.1f", 100 * s$stddiff), s$variable)
}
```

## Table

The table’s labels are its own, so the dataset’s labels, which the
analyses use, are never changed. Two files at the study root, shared by
every table job in the study, say what a rule cannot. `table_labels.yml`
gives a variable the label its table prints, as `labels_overrides.yml`
does, `nyha_pr: "NYHA class"` on a line, and wins over the rules.
`value_labels.yml` gives a coded column its level text,
`hvtiRutilities::apply_value_labels()`’s format, so NYHA 1 to 4 prints
as I to IV. A column whose data already carry value labels, such as a
haven labeled column, prints its level text without either file. Every
label changed, and every variable with no label, is listed under the
table.

Code

``` r
# unnumbered: relabels the copy of the data the table is drawn from
# A binary row prints one line, its label, counting the event (1, Yes or TRUE),
# so level text would print nowhere, and hv_tbl_summary() could not find the
# event among, say, Absent and Present. Binary rows therefore keep their codes:
# those BINARY or OVERRIDES name, and those the data make binary unless named
# categorical. Continuous rows named in CONTINUOUS or OVERRIDES keep theirs too:
# they are summarized as numbers.
.rows <- intersect(unlist(GROUPS, use.names = FALSE), names(d))
.binary_by_data <- .rows[vapply(d[.rows], function(x) {
  is.logical(x) || is.numeric(x) && all(x[!is.na(x)] %in% c(0, 1))
}, logical(1))]
.labeled <- hvtiRtemplates:::.table_labels(
  d, c(unlist(GROUPS, use.names = FALSE), BY), .root, rules = TABLE_LABEL_RULES,
  protect = c(unname(hvtiRutilities::study_abbreviations(.cfg)), names(ABBREVIATIONS)),
  keep_codes = c(CONTINUOUS, BINARY, OVERRIDES$continuous, OVERRIDES$binary,
                 setdiff(.binary_by_data, c(CATEGORICAL, OVERRIDES$categorical)))
)
d_table <- .labeled$data
# A BY given level text still names STDDIFF's treated group: GROUP_1 may be
# its code, and a 0/1 BY's 1 is treated, as it was before the text replaced it.
.by_levels <- .labeled$levels[[BY %||% ""]]
if (!is.null(.by_levels) && (!is.null(GROUP_1) || setequal(names(.by_levels), c("0", "1")))) {
  .treated <- if (is.null(GROUP_1)) "1" else as.character(GROUP_1)
  if (.treated %in% names(.by_levels)) GROUP_1 <- .by_levels[[.treated]]
}
```

Code

``` r
if (!is.logical(DROP_CONSTANT) || length(DROP_CONSTANT) != 1L || is.na(DROP_CONSTANT)) {
  stop("DROP_CONSTANT must be TRUE or FALSE.", call. = FALSE)
}
explicit <- list(continuous = CONTINUOUS, binary = BINARY, categorical = CATEGORICAL)
if (all(vapply(explicit, is.null, logical(1)))) {
  b <- classify_buckets(d_table, unlist(GROUPS, use.names = FALSE), OVERRIDES)
  CONTINUOUS <- b$continuous
  BINARY <- b$binary
  CATEGORICAL <- b$categorical
} else {
  if (any(vapply(explicit, is.null, logical(1))) || length(OVERRIDES)) {
    stop("Declare all three buckets and leave OVERRIDES empty for explicit classification.", call. = FALSE)
  }
  rows <- unlist(GROUPS, use.names = FALSE)
  classified <- unlist(explicit, use.names = FALSE)
  if (anyDuplicated(rows) || anyDuplicated(classified) || !setequal(rows, classified)) {
    stop("Every grouped row must appear in exactly one explicit bucket.", call. = FALSE)
  }
  invisible(classify_buckets(d_table, rows, explicit))
}
# A missing value is not a second value: a row is constant when every
# recorded value is the same. A row with nothing recorded is kept, since an
# empty row points at the data rather than at the cohort.
constant_rows <- character(0)
if (DROP_CONSTANT) {
  rows <- unlist(GROUPS, use.names = FALSE)
  constant_rows <- rows[vapply(d_table[rows], function(x) length(unique(x[!is.na(x)])) == 1L, logical(1))]
  GROUPS <- Filter(length, lapply(GROUPS, setdiff, y = constant_rows))
  if (!length(GROUPS)) stop("Every row has one value for every patient; there is no table to draw.", call. = FALSE)
  CONTINUOUS <- setdiff(CONTINUOUS, constant_rows)
  BINARY <- setdiff(BINARY, constant_rows)
  CATEGORICAL <- setdiff(CATEGORICAL, constant_rows)
  MEAN_SD <- setdiff(MEAN_SD, constant_rows)
  ORDINAL <- setdiff(ORDINAL, constant_rows)
}
tbl <- hvtiRtables::hv_tbl_summary(
  d_table, by = BY, groups = GROUPS, continuous = CONTINUOUS,
  binary = BINARY, categorical = CATEGORICAL, compare = COMPARE,
  percentiles = PERCENTILES, continuous_stat = CONTINUOUS_STAT,
  mean_sd = MEAN_SD, show_variable = SHOW_VARIABLE
)
if (!is.logical(STDDIFF) || length(STDDIFF) != 1L || is.na(STDDIFF)) {
  stop("STDDIFF must be TRUE or FALSE.", call. = FALSE)
}
if (STDDIFF) {
  if (COMPARE %in% c("smd", "both")) {
    stop("STDDIFF adds %stddiff's difference; set COMPARE to \"pvalue\" or \"none\", ",
         "since COMPARE's \"smd\" is a different number for the same thing.", call. = FALSE)
  }
  if (!requireNamespace("hvtiRpropensity", quietly = TRUE) ||
        utils::packageVersion("hvtiRpropensity") < "0.2.0") {
    stop("STDDIFF needs hvtiRpropensity >= 0.2.0 for ps_stddiff().", call. = FALSE)
  }
  buckets <- list(continuous = CONTINUOUS, binary = BINARY, categorical = CATEGORICAL)
  tbl <- hvtiRtables::hv_tbl_compare(tbl, stddiff_values(d_table, BY, buckets, MEAN_SD, ORDINAL, GROUP_1),
                                     label = "Std. Diff. (%)")
}
# The report's table, in the report style. hv_man_table_display() adds the
# header marks, notes and abbreviation key the Word table carries, from the
# saver's own code.
ft <- hvtiRtables::hv_man_table(tbl)
hvtiRtables::hv_man_table_display(ft, abbreviations = ABBREVIATIONS)
```

| Characteristic | Variable | No.\* | N = 800† |
|----|----|----|----|
| Demography |  |  |  |
| Age at operation (years) | age | 800 | 63 \[49, 75\] |
| Female | female | 800 | 299 (37) |
| Race | race_grp |  |  |
| Black |  | 800 | 111 (14) |
| Other |  | 800 | 58 (7.3) |
| White |  | 800 | 631 (79) |
| Body mass index (kg/m2) | bmi | 800 | 28 \[23, 32\] |
| History |  |  |  |
| History of heart failure | hx_chf | 800 | 243 (30) |
| Diabetes | hx_dm | 800 | 175 (22) |
| NYHA functional class | nyha_pr |  |  |
| 1 |  | 800 | 129 (16) |
| 2 |  | 800 | 360 (45) |
| 3 |  | 800 | 275 (34) |
| 4 |  | 800 | 36 (4.5) |
| Echo |  |  |  |
| LV ejection fraction (%) | lvef | 800 | 52 \[42, 62\] |
| LV mass index (g/m2) | plvmassi | 800 | 121 \[91, 152\] |
| Laboratory |  |  |  |
| Creatinine (mg/dL) | creat_pr | 725 | 1.0 \[0.75, 1.4\] |
| \* Number of non-missing values. |  |  |  |
| † No. (%) or Median \[15th, 85th percentiles\]. |  |  |  |

Table 2: Summary statistics for the study cohort

Code

``` r
# unnumbered: a note under the table, and only when DROP_CONSTANT left rows out
if (length(constant_rows)) {
  cat("Not shown, because every patient with a recorded value has the same one: ",
      paste0("`", constant_rows, "`", collapse = ", "),
      ". Set `DROP_CONSTANT <- FALSE` to show them.\n", sep = "")
}
```

Code

``` r
# unnumbered: its child chunk carries its own label and caption
if (nrow(.labeled$changes)) {
  .fence <- strrep("`", 3)
  cat(knitr::knit_child(text = c(
    paste0(.fence, "{r}"), "#| label: tbl-table-labels",
    "#| tbl-cap: \"The labels and levels this table prints in place of the dataset's, and why\"",
    "knitr::kable(.labeled$changes, col.names = c(\"Variable\", \"Dataset\", \"Table\", \"Rule\"))", .fence
  ), envir = environment(), quiet = TRUE), sep = "\n")
}
```

Code

``` r
knitr::kable(.labeled$changes, col.names = c("Variable", "Dataset", "Table", "Rule"))
```

| Variable | Dataset                 | Table                   | Rule  |
|:---------|:------------------------|:------------------------|:------|
| bmi      | Body mass index (kg/m2) | Body mass index (kg/m²) | units |
| plvmassi | LV mass index (g/m2)    | LV mass index (g/m²)    | units |

Table 3: The labels and levels this table prints in place of the
dataset’s, and why

Code

``` r
# unnumbered: writes the Word file; the table below shows what it holds
# The same summary, drawn for the manuscript. MANUSCRIPT_CAPTION is written into
# the .docx above the table; this report numbers its own tables. The tbl-word
# chunk below shows word_ft, so it cannot run without this chunk: if the Word
# table stops here, fix MANUSCRIPT_LAYOUT rather than skipping the chunk.
word_ft <- hvtiRtables::hv_man_table(
  tbl, style = hvtiRtables::hv_table_style("manuscript", fill = MANUSCRIPT_FILL),
  layout = MANUSCRIPT_LAYOUT
)
if (length(WORD_FILE) != 1L || is.na(WORD_FILE) ||
      !grepl("^[A-Za-z0-9_][A-Za-z0-9_.-]*[.]docx$", WORD_FILE)) {
  stop("WORD_FILE must be a plain .docx filename within this set.", call. = FALSE)
}
word_path <- file.path(study_dir("documents", .root), paste0(SUBJECT, "-", TYPE), WORD_FILE)
dir.create(dirname(word_path), recursive = TRUE, showWarnings = FALSE)
hvtiRtables::hv_man_table_save(word_ft, word_path, abbreviations = ABBREVIATIONS, caption = MANUSCRIPT_CAPTION,
                               orientation = TABLE_ORIENTATION)
# The file carries what wrote it, the job, the render and the package versions,
# as document properties (File > Info in Word), so a copy that is emailed on
# says which release built it without anyone opening this report.
hvtiRtemplates:::.stamp_docx(word_path, hvtiRtemplates:::.run_reconcile(.job$run), data = .provenance_data,
                             caption = MANUSCRIPT_CAPTION)
# The manuscript style merges its header and section rows, and nothing else.
check <- hvtiRtables::hv_check_docx(word_path, style = "manuscript")
if (nrow(check)) stop("Word output failed the CORR structural check", call. = FALSE)
```

Code

``` r
hvtiRtables::hv_man_table_display(word_ft, abbreviations = ABBREVIATIONS)
```

| Characteristic | n\* | All patients (N = 800)† |
|----|----|----|
| Demography |  |  |
| Age at operation (years) | 800 | 63 \[49, 75\] |
| Female | 800 | 299 (37) |
| Race | 800 |  |
| Black |  | 111 (14) |
| Other |  | 58 (7.3) |
| White |  | 631 (79) |
| Body mass index (kg/m2) | 800 | 28 \[23, 32\] |
| History |  |  |
| History of heart failure | 800 | 243 (30) |
| Diabetes | 800 | 175 (22) |
| NYHA functional class | 800 |  |
| 1 |  | 129 (16) |
| 2 |  | 360 (45) |
| 3 |  | 275 (34) |
| 4 |  | 36 (4.5) |
| Echo |  |  |
| LV ejection fraction (%) | 800 | 52 \[42, 62\] |
| LV mass index (g/m2) | 800 | 121 \[91, 152\] |
| Laboratory |  |  |
| Creatinine (mg/dL) | 725 | 1.0 \[0.75, 1.4\] |
| \*Patients with non-missing data. |  |  |
| †Values are No. (%) or median \[15th, 85th percentiles\]. |  |  |

Table 4: The table as saved to Word, in the manuscript style

## Correlations

Code

``` r
# unnumbered: each child chunk below carries its own label and caption
if (is.null(CORR)) {
  cat("Correlation variant not requested (`CORR <- NULL`).\n")
} else {
  ct <- hv_correlation_table(d, vars = CORR$vars, with = CORR$with)
  conf_level <- attr(ct, "conf_level")
  if (!is.null(CORR$by)) {
    st <- hv_correlation_table(d, vars = CORR$vars, with = CORR$with, by = CORR$by)
    ct[[CORR$by]] <- "Overall"
    ct <- rbind(ct[names(st)], st)
    attr(ct, "conf_level") <- conf_level
  }
  cm <- hv_correlation_matrix(d, vars = unique(c(CORR$with, CORR$vars)))
  fname <- "dc-tables-correlation-matrix.png"
  # Free size: a scatter-plot matrix, so a single 6 by 4 panel would leave each cell too small to read.
  save_figure(plot(cm) + theme_hv_manuscript(base_size = 12), sub("[.]png$", "", fname), width = 10, height = 10,
              kind = "descriptive", linked = TRUE)
  .fence <- strrep("`", 3)
  .caption <- sprintf("Spearman and Pearson, %d%% Fisher interval", round(100 * conf_level))
  cat(knitr::knit_child(text = c(
    paste0(.fence, "{r}"), "#| label: tbl-correlation", paste0("#| tbl-cap: ", encodeString(.caption, quote = "\"")),
    "knitr::kable(ct)", .fence, "",
    paste0(.fence, "{r}"), "#| label: fig-correlation-matrix",
    paste0("#| fig-cap: \"Scatter-plot matrix of the correlated variables. Each cell plots one variable against another, ",
           "each patient a small translucent black filled circle.\""),
    "knitr::include_graphics(file.path(paste0(SUBJECT, \"-\", TYPE), fname), error = FALSE)", .fence
  ), envir = environment(), quiet = TRUE), sep = "\n")
}
```

Correlation variant not requested (`CORR <- NULL`).

## About this run

| Group           | Item             | Value                    |
|:----------------|:-----------------|:-------------------------|
| Run             | Started          | 2026-10-28 09:17:47 EDT  |
|                 | Ended            | 2026-10-28 09:17:48 EDT  |
|                 | Duration         | 1 s                      |
|                 | Status           | final                    |
|                 | Rendered by      | gallery                  |
|                 | Host             | gallery                  |
| Job             | File             | dc.tables.cohort.eda.qmd |
|                 | Template         | dc.tables                |
|                 | Subject          | cohort                   |
|                 | Type             | eda                      |
|                 | hvtiRtemplates   | 1.5.3                    |
| Dataset `built` | Version file     | built_20261028.parquet   |
|                 | Version date     | 2026-10-28               |
|                 | Source file      | built.rds                |
|                 | Rows kept        | 800 rows on 800 patients |
|                 | WHERE            | none                     |
|                 | sha256           | b236a472f1f3             |
|                 | Manifest         | current                  |
| Reproducibility | renv             | not active               |
|                 | renv.lock sha256 | d09f96b6cd21             |
