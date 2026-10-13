# Extracted from test-lg.R:350

# prequel ----------------------------------------------------------------------
lg_two_variables <- c(
  "VARIABLES <- data.frame(",
  "  name = c(\"age\", \"nyha\"),",
  "  kind = c(\"continuous\", \"ordinal\"),",
  "  chosen = c(\"log\", \"raw\")",
  ")"
)

# test -------------------------------------------------------------------------
skip_on_cran()
skip_if_not_installed("ggplot2")
skip_if_not_installed("quarto")
skip_if_not(quarto::quarto_available())
d <- lg_data()
windows <- list(none = character(), window = "INTERVAL <- c(0.25, 5)")
for (window in names(windows)) {
    s <- lg_fixture(windows[[window]], variables = c(
      "VARIABLES <- data.frame(",
      "  name = c(\"age\", \"nyha\"),",
      "  kind = c(\"continuous\", \"ordinal\"),",
      "  chosen = c(\"log\", \"raw\")",
      ")"
    ))
    quarto::quarto_render(s$job, execute_dir = dirname(s$job), quiet = TRUE)
    html <- paste(readLines(sub("[.]qmd$", ".html", s$job), warn = FALSE), collapse = "\n")
    # Two figures and two tables, one of each for each covariate, numbered; the interval table only with INTERVAL.
    ids <- function(prefix) {
      found <- regmatches(html, gregexpr(paste0("id=\"", prefix, "-lg-[a-z-]+\""), html))[[1L]]
      sort(unique(sub("^id=\"(.*)\"$", "\\1", found)))
    }
    expect_identical(ids("fig"), c("fig-lg-age", "fig-lg-nyha"), info = window)
    expect_identical(ids("tbl"), sort(c("tbl-lg-age", "tbl-lg-nyha", "tbl-lg-scales", "tbl-lg-variables",
                                        if (window == "window") "tbl-lg-interval")), info = window)
    graphs <- file.path(hvtiRutilities::study_dir("graphs", s$root), "dead-calibration")
    expect_setequal(list.files(graphs), c("lg-age.png", "lg-age.pdf", "lg-nyha.png", "lg-nyha.pdf"))
    # The choices are saved with the right terms, and the report prints the line to copy.
    saved <- readRDS(file.path(hvtiRutilities::study_dir("estimates", s$root), "dead-calibration", "lg-scales.rds"))
    expect_identical(saved$term, c("log(age)", "nyha"), info = window)
    plain <- gsub("<[^>]+>", "", html)
    expect_match(plain, "PREDICTORS &lt;- c(&quot;log(age)&quot;, &quot;nyha&quot;)", fixed = TRUE)
    # No patient identifier, raw or digested, appears in the report. Embedded images and fonts are base64
    # data URIs, whose text can spell any short digit run by chance, so they are dropped before the scan,
    # and an identifier counts only as a whole token. The provenance JSON is not a data URI, so it is scanned.
    text <- gsub("data:[A-Za-z0-9.+/-]+(;[^,\"')]*)?,[^\"') ]*", "", html, perl = TRUE)
    key <- hvtiRtemplates:::.study_id_key(s$root)
    for (id in c(as.character(d$ccfid), hvtiRtemplates:::.id_digest(d$ccfid, key))) {
      at <- regexpr(paste0("(?<![A-Za-z0-9])", id, "(?![A-Za-z0-9])"), text, perl = TRUE)[[1L]]
      # On a hit, show the text around it, so a CI failure says where it came from.
      expect_false(at > 0L, info = if (at > 0L) substring(text, max(1L, at - 120L), at + 120L) else id)
    }
    # The provenance names the data read, the choices and the window, never a patient.
    payload <- hvtiRtemplates:::.extract_provenance(html, managed = TRUE)
    expect_length(payload$data, 1L)
    expect_identical(payload$lg$event, "dead")
    expect_identical(payload$lg$link, "hazard")
    expect_identical(payload$lg$time, "iv_dead")
    expect_identical(vapply(payload$lg$variables, function(v) v$name, ""), c("age", "nyha"))
    expect_identical(vapply(payload$lg$variables, function(v) v$chosen, ""), c("log", "raw"))
    if (window == "window") {
      kept <- d$iv_dead >= 0.25
      expect_identical(unlist(payload$lg$interval), c(start = 0.25, end = 5, left_out = sum(!kept), kept = sum(kept),
                                                      censored = sum(kept & d$iv_dead > 5)))
      expect_identical(payload$lg$patients, sum(kept))
    } else {
      expect_null(payload$lg$interval)
      expect_identical(payload$lg$patients, nrow(d))
    }
  }
