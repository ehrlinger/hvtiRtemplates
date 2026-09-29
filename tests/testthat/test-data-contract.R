# Every template takes its data the same way:
# dev/specs/2026-09-29-template-data-contract-design.md. Families not yet
# converted are listed here; each family's conversion removes its names, and
# the list is empty when the work is done.
pending_contract_families <- setdiff(template_list()$name, c("dc-general", "dc-gfup", "dc-tables", "dp-eda", "dp-gfup", "dp-trends"))

template_chunk <- function(src, label) {
  at <- match(paste0("#| label: ", label), src)
  if (is.na(at)) return(NULL)
  end <- at + match("```", src[-seq_len(at)])
  src[(at + 1L):(end - 1L)]
}

# Downstream templates take the selection their upstream job recorded: WHERE,
# ID and KEY default to NULL ("take the upstream value") and their data chunk
# checks it with .read_upstream_job_data(). hm, hp and hs also read data; the explain jobs and the bootstrap
# reports read a saved forest or bag, so they have no DATASET or ANALYSIS_SET.
downstream_templates <- c("hm", "hp", "hs", "rfs-explain", "rfc-explain", "rfr-explain",
                          "bl", "br", "bc", "bh")
reads_data <- function(name) !name %in% c("rfs-explain", "rfc-explain", "rfr-explain", "bl", "br", "bc", "bh")

expected_defaults <- function(name) {
  if (name %in% downstream_templates) {
    out <- c(WHERE = "WHERE <- NULL", ID = "ID <- NULL", KEY = "KEY <- NULL")
    # hm, hp and hs read data themselves, but take DATASET and ANALYSIS_SET
    # from upstream too, same as WHERE, ID and KEY.
    if (reads_data(name)) out <- c(DATASET = "DATASET <- NULL", ANALYSIS_SET = "ANALYSIS_SET <- NULL", out)
  } else {
    out <- c(WHERE = "WHERE <- NULL", ID = 'ID <- "ccfid"', KEY = "KEY <- ID")
    if (reads_data(name)) out <- c(DATASET = 'DATASET <- "study"', ANALYSIS_SET = "ANALYSIS_SET <- NULL", out)
  }
  # hm, hp and hs also take their time-to-event settings from upstream.
  if (name %in% c("hm", "hp", "hs")) out <- c(out, TIME = "TIME <- NULL", EVENT = "EVENT <- NULL")
  out
}

test_that("every converted template has the shared settings and a conforming data chunk", {
  tl <- template_list()
  # Guard against testthat treating this test as "empty" (and so skipped) while
  # pending_contract_families still names every template and the loop below
  # runs zero times.
  expect_gt(nrow(tl), 0L)
  todo <- setdiff(tl$name, pending_contract_families)
  for (i in match(todo, tl$name)) {
    name <- tl$name[[i]]
    src <- readLines(tl$file[[i]], warn = FALSE)
    choices <- template_chunk(src, "edit-study-choices")
    expect_false(is.null(choices), info = name)
    defaults <- expected_defaults(name)
    for (setting in names(defaults)) {
      expect_true(any(trimws(sub("#.*$", "", choices)) == defaults[[setting]]), info = paste(name, setting))
    }
    setup <- template_chunk(src, "setup")
    expect_true(any(grepl("hvtiRtemplates:::.find_study_root(", setup, fixed = TRUE)), info = paste(name, "setup"))
    data <- template_chunk(src, "data")
    expect_false(is.null(data), info = name)
    # Downstream templates that read data call .read_upstream_job_data() only:
    # DATASET and ANALYSIS_SET come from upstream, so read_job_data() itself
    # is never called directly in their data chunk.
    if (reads_data(name) && !name %in% downstream_templates) {
      expect_true(any(grepl("hvtiRtemplates::read_job_data(", data, fixed = TRUE)), info = name)
    }
    if (name %in% downstream_templates) {
      expect_true(any(grepl(".read_upstream_job_data(", data, fixed = TRUE)), info = name)
    }
  }
})

test_that("no converted template uses a retired name for the shared vocabulary", {
  tl <- template_list()
  # Same "empty test" guard as above.
  expect_gt(nrow(tl), 0L)
  retired <- c("^STATUS\\s*<-", "^KEY_COLS\\s*<-", '"iu_dead"', '"idead"', '^ID\\s*<-\\s*"id"')
  for (i in match(setdiff(tl$name, pending_contract_families), tl$name)) {
    src <- readLines(tl$file[[i]], warn = FALSE)
    for (pattern in retired) expect_false(any(grepl(pattern, src)), info = paste(tl$name[[i]], pattern))
  }
})

test_that("the pending and downstream lists name only real templates", {
  expect_true(all(pending_contract_families %in% template_list()$name))
  expect_true(all(downstream_templates %in% template_list()$name))
})
