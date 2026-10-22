# `sid` templates: design, 2026-10-22

**Status** Design, approved by section on 2026-10-22. Not implemented.
**Adds** two templates under the existing `sid` prefix, `sid-fit.qmd` and
`sid-clusters.qmd`. Both ship with ledger status `in-flight`.
**Starts from** the two SID clustering studies named in the ML family roadmap
(`2026-09-17-ml-family-roadmap-design.md` §5). The first is a biventricular
repair morphology notebook (four clusters, published). The second is a
morphology Quarto book: seven clusters, five of them reported as groups. Study
paths and identifiers stay out of this repository.

## 1. What the two studies do, and what this keeps

Both studies run one pipeline:

1. Drop rows with every clustering variable missing, then columns more than
   40% missing.
2. Run one `mice` pmm imputation (`m = 1`, `maxit = 50`).
3. Run `sidClustering(method = "sid", ntree = 5000)` on the completed data.
4. Run PAM on `sid$dist` for each K in a range (2 to 5, and 2 to 9), ignoring
   the hierarchical `sid$clustering`.
5. Assign letters that keep their identity as K grows, and draw a Sankey of
   the letters across K.
6. Choose K: PAM objective (elbow), average silhouette, gap statistic.
7. Profile each cluster at each K, and fit varPro with the cluster as outcome.

Stage 7 repeats once per K and makes up about 80% of each notebook. Its two
halves have homes now. **Profiling** is a `dc-tables` job that JOINs the cluster
assignments. **"Which variables separate the clusters"** is a `vp-fit` job with
the cluster as a classification outcome (`vp` landed in #382). So the `sid`
templates stop at the assignments. They hand those to later jobs as a
registered dataset (section 5), and the report points to both jobs.

### Three things the studies' code does that the templates do not

Each was found while reading the studies against randomForestSRC 3.9.0 and
`cluster` 2.1.8, and checked on `iris`:

- **`seed =` alone does not reproduce `sidClustering()`.** The default
  `reduce = TRUE` holdout-VIMP step draws from R's own generator. Two identical
  calls with `seed = 7` gave different distance matrices; `set.seed()` before
  each made them identical. Both studies call `set.seed(1024)` once at the top
  of the notebook, so their fits reproduce only when the chunks run in the same
  order. The template calls `set.seed(SEED)` inside the cached expression,
  directly before the fit.
- **`na.action = "na.impute"` errors when values are missing.** Both studies
  pass it ("arguments imply differing number of rows: 150, 147" on iris with
  three missing values). It only works for them because `mice` has already
  completed the data. The template imputes first, passes no `na.action`, and
  stops if a missing value reaches the fit.
- **The published assignments are not PAM on the SID dissimilarity.**
  `sid$dist` is a plain `matrix`, and `cluster::pam()` sets
  `diss = inherits(x, "dist")`. So `pam(sid$dist, k)`, the studies' assignment
  call, treats each patient's row of distances as a feature vector and
  clusters on Euclidean distances between rows. Their elbow and silhouette
  call `pam(as.dist(sid$dist), k)`, PAM on the dissimilarity itself, so the
  supplement metrics describe a slightly different clustering from the one
  reported. On iris the two disagree on one or two patients at each K. Their
  gap statistic, `clusGap(sid$dist, ...)`, also takes rows as features. The
  templates use **`pam(as.dist(D), k)` for everything** and drop the gap
  statistic, which needs a data matrix, not a dissimilarity (section 4). A
  study that has to reproduce a published assignment says so in its own job.

## 2. Taxonomy, ledger and naming

- **Taxonomy:** `sid` is already in `hvti_taxonomy()` (hvtiRutilities #127),
  folder `analyses`. Nothing changes there, so nothing crosses repositories.
- **Files:** `inst/templates/30_analyses/sid-fit.qmd` and
  `inst/templates/30_analyses/sid-clusters.qmd`. `template_list()` shows them
  as `sid.fit` and `sid.clusters`. The pair mirrors `rfs-fit`/`rfs-explain`
  and `vp-fit`/`vp-explain`. The SID forest is the slow step, while choosing K
  and pinning letters is cheap and gets repeated, so redoing the second should
  never touch the first.
- **The prefix becomes wholly qualified.** The one unqualified ledger row
  `(sid, NA)` is replaced by `(sid, fit)` and `(sid, clusters)`.
  `check-roadmap-counts.py` refuses a half-qualified prefix, so both changes
  land in one commit. The catalog grows by one row and no prefix:
  `test-template-catalog.R` moves from 68 rows to 69 and stays at 45 prefixes
  (counts on `origin/main` at `88cd7cd`; re-measure at implementation, since
  the `vt` work may land rows first).
- **`blocked_on: hvtiRforests#1` is cleared.** The SID helpers live in
  template chunks (section 6), so no package has to exist first. hvtiRforests#1
  gets a comment saying so: the helpers move there once `vt` needs shared
  method code too.
- **The two-study gate.** Both studies ran this pipeline, so the gate is
  cleared. Neither ran these exact jobs, though: the PAM input and the seeding
  differ (section 1). Both rows therefore ship `in-flight` and flip to `shipped`
  once a study renders the pair, the route `vp` and `bd` took.

## 3. `sid-fit.qmd`

Chunks, in order:

1. **`setup`**, the standard single chunk. It attaches randomForestSRC,
   `mice` and hvtiRutilities, checks their floors, and sets
   `options(rf.cores = 1L, mc.cores = 1L)`.
2. **`edit-study-choices`**, holding every `EDIT:` marker:
   - `DATASET`, `ANALYSIS_SET`, `WHERE`, `ID`, `KEY`, the standard read
     choices.
   - `VARS`: the clustering variables. These are what defines a cluster, so
     the narration says so. They are not candidate predictors, and an outcome
     never belongs here: that would cluster on the answer a later job asks
     about.
   - `MAX_MISSING <- 0.4`, `NTREE <- 5000`, `REDUCE <- TRUE`
     (sidClustering's holdout-VIMP variable reduction), `MICE_MAXIT <- 50`,
     `SEED <- 1024`.
3. **Cohort.** `read_job_data(one_row_per_patient = TRUE)`. The run stops if
   `VARS` names the ID or a column the data lack. Rows with every variable in
   `VARS` missing are dropped and counted.
4. **Missingness.** A table of the percent missing per variable. Variables
   above `MAX_MISSING` are dropped and listed by name. A factor with one level
   left is dropped and listed too.
5. **Impute.** One `mice(method = "pmm", m = 1, maxit = MICE_MAXIT,
   seed = SEED)`, cached with `cache_fit()`. The prose says that a single
   imputation ignores imputation uncertainty. That is acceptable for a
   distance used to form groups, but it means the cluster boundaries are
   conditional on one draw.
6. **Fit.** `cache_fit()` around `{ set.seed(SEED); sidClustering(d,
   method = "sid", ntree = NTREE, reduce = REDUCE, seed = -abs(SEED)) }`. No
   `na.action` is passed: a missing value at this point stops with a message,
   because section 1 shows that `na.impute` would fail here anyway.
7. **What the forest used.** The variables the reduce step kept, from the
   fit's `sid` element, beside those it dropped, and the dimension of `dist`.
8. **Save** one handoff, `estimates/<subject>-<type>/sid.rds`, with handoff
   lineage attached (including the data selection):
   `list(dist, kept, vars, dropped, reduced, settings)`. `kept` is a logical
   vector over the rows read, marking those clustered.
   - **It holds no patient identifier and no patient values.** `sid-clusters`
     rebuilds the IDs from the recorded selection, as every downstream job
     rebuilds its cohort. That keeps an MRN out of `estimates/` when a study's
     ID falls back to MRN.
   - Later profiling reads the built dataset through `JOIN`, so it describes
     observed values, not imputed ones.
   - The forest itself is not saved: it is large and nothing downstream reads
     it.
9. **`provenance`**, the standard closing chunk.

## 4. `sid-clusters.qmd`

It reads `sid.rds` and never calls `sidClustering(`. When no `sid-fit` has run
in its set, it stops with a message naming the missing file. It rebuilds the
fit's cohort from the handoff's recorded selection
(`.read_upstream_job_data()`, which checks the rows and their key hash), and
takes the IDs of the `kept` rows from it. Nothing in it is
random: PAM is deterministic given the dissimilarity, and so are the
silhouette and classical MDS. So it needs no seed.

1. **`setup`**: `cluster`, hvtiPlotR and hvtiRutilities.
2. **`edit-study-choices`**:
   - `K_RANGE <- 2:9`: the solutions assigned letters and drawn in the Sankey.
   - `K <- NULL`: the solution a study reports. A draft render with
     `K = NULL` shows the metrics and sizes, skips every section that needs K,
     and says why, so the first render is how an author chooses. A final
     render needs K. A K outside `K_RANGE` is an error.
   - `OVERRIDES <- list()`: pins letters, as
     `list(pm4 = c("1" = "B", "2" = "D"))`. The narration explains that PAM's
     cluster numbers are arbitrary, so overrides are a domain decision written
     down, not a fix.
   - `COLLAPSE <- NULL`: a letter-to-group map at K, such as
     `list(Z = c("C", "D", "E"))`.
   - `MIN_SIZE <- 20`, `K_METRICS_MAX <- 15`.
3. **`sid-helpers`**, a chunk of its own, so tests can call the helpers on
   hand-built inputs without a fit, as `vp-fit`'s `judge` chunk does:
   - `sid_align_labels(mat, overrides)`: the second study's
     `align_cluster_labels()`. The first column's clusters take letters
     largest first. At each later K, the largest child of each parent inherits
     the parent's letter by majority overlap, and its siblings take fresh
     letters. An override naming an unknown cluster id is an error, and so is
     running past 26 letters.
   - `sid_collapse(letters, map)`: unmapped letters keep their own letter. A
     letter in the map that does not occur at K is an error, and so is one
     mapped twice.
   - `sid_mds_signs(xy)`: flips each MDS axis so that the patient with the
     largest absolute coordinate on it is positive. The second study's map
     mirrored between renders because `cmdscale()` signs are arbitrary. This
     rule depends on neither the row order nor the render.
4. **PAM.** `pam(as.dist(D), k)` for k = 1 to `max(K_RANGE, K_METRICS_MAX)`,
   held in memory. At this size PAM is seconds, so it is not cached.
5. **Choosing K.** One faceted figure: the PAM objective normalized to its
   k = 1 value (the elbow), and the average silhouette for k ≥ 2. A table
   gives each k's values and marks the silhouette maximum. The elbow is read
   by eye, and the prose says so rather than inventing a rule for it. There is
   no gap statistic (section 1).
6. **Sizes.** Patients per letter at every K in `K_RANGE`, plus the smallest
   cluster at each K. A cluster smaller than `MIN_SIZE` at K raises a warning
   and a callout, since varPro and per-cluster tables later need enough
   patients.
7. **Sankey.** `hvtiPlotR::hv_sankey()` over `C<k>` for `K_RANGE`, plotted
   and saved through the package's figure standard.
8. **At K** (skipped when `K = NULL`):
   - per-cluster silhouette widths, as a sorted bar figure and a table of the
     average width and the share of negative widths per cluster. This shows a
     poorly separated cluster that the average silhouette hides;
   - a 2-D classical MDS map of `D` (`cmdscale(as.dist(D), k = 2)`, signs from
     `sid_mds_signs()`), coloured by letter.
   - When `COLLAPSE` is set, a `C<K>` × `G<K>` table showing the mapping.
9. **Reading the result.** Plain-language prose on what a SID cluster is (a
   region of the clustering variables, not a diagnosis), how stability across
   K reads off the Sankey, what the silhouette does and does not say, and
   where to go next: `dc-tables` to profile and `vp-fit` to explain.
10. **Save** (section 5), then **`provenance`**.

## 5. The handoff to later jobs

Later jobs read data through `read_job_data()`, which can JOIN a registered
ancillary dataset on the patient ID. So `sid-clusters` writes and registers
one:

- `datasets/<subject>-<type>-clusters.csv`: the ID, `C<k>` for each k in
  `K_RANGE` (letters, in Sankey order), and `G<K>` when `COLLAPSE` is set. It
  holds only the ID and letters, never a clustering variable, so the
  registered file adds no data the study did not already hold.
- On the first render, `hvtiRutilities::register_data(built = <that file>,
  dataset = "clusters_<subject>_<type>", role = "named", kind = "ancillary",
  key = ID)`. Dataset names must match `^[a-z][a-z0-9_]*$`, so subject and
  type are lowercased.
- On a later render, `register_data()` would stop: it registers a dataset
  only once. The job instead rewrites the file and runs
  `update_manifest(dataset = "clusters_<subject>_<type>")` from the study
  root. That records a new dated version (`_r2` on the same day), keeps the
  earlier ones, and leaves an unchanged file alone. A later job therefore
  reads the current assignments, and its manifest check passes.
- `estimates/<subject>-<type>/sid-clusters.rds`, with lineage: the PAM fits,
  the metrics table, the letter map per K (`pm<k>` id to letter), `K`,
  `OVERRIDES` and `COLLAPSE`.

A later job then sets `JOIN <- "clusters_<subject>_<type>"`.
**To be verified in the plan:** `read_job_data()` stops a
`one_row_per_patient = TRUE` job, such as `vp-fit`, on any JOIN without
`REDUCE`, even when the joined key is the ID itself. The plan proves that a
`dc-tables`-style read and a `vp-fit`-style read both consume the file, and
records the `REDUCE` value the second needs. If that value is awkward,
relaxing the rule for an ID-keyed join is a follow-up in `read_job_data()`,
not part of this work.

## 6. Where the code lives

The roadmap put PAM over K and label alignment in a new package,
hvtiRforests. That repository is still empty, and the helpers are about 100
lines. They therefore live in `sid-clusters`' `sid-helpers` chunk, where they
are tested, and move to hvtiRforests once `vt` needs shared method code too.
This is the choice `vp-fit` made for `vp_judge()`. ggRandomForests stays the
study-agnostic layer: no SID-specific code goes into it.

## 7. Testing

A new `tests/testthat/test-sid-templates.R` with a `helper-sid.R` beside it,
running the **installed** templates chunk by chunk through `rf_run()` and
`rf_env()` (`helper-rf.R`), as the `vp` tests do.

1. **Planted clusters are recovered.** A synthetic cohort of about 150 rows
   in three well-separated groups across four continuous variables and one
   factor, with a few values missing, fit at `NTREE = 50`, `REDUCE = FALSE`.
   At K = 3 the clusters match the planted groups:
   `randomForestSRC::sid.perf.metric()`'s normalized measure is below 0.2.
2. **The seed reproduces the fit, proven by mutation.** Two `sid-fit` runs
   with `REDUCE = TRUE` and the same `SEED` give identical `dist`. Remove the
   `set.seed()` from the fit chunk and confirm the test fails.
3. **`sid_align_labels()`** on hand-built matrices: lineage across K, an
   override applied, an unknown override id errors, the letter pool errors
   past 26, and relabelling PAM's cluster numbers within each column leaves
   the letters unchanged. No fit, so these run on CRAN too.
4. **`sid_collapse()`** and **`sid_mds_signs()`**: an unmapped letter is kept,
   an absent letter errors, a letter mapped twice errors; signs do not change
   under a row permutation or a sign flip of the input. No fit.
5. **The handoff.** `sid-clusters` reads `sid.rds`, has no `sidClustering(`
   in its source, and stops naming the file when no fit has run.
6. **The registered dataset.** After `sid-clusters` runs, the file exists,
   holds only the ID and letter columns, and is registered as ancillary with
   key ID. A second render with different `OVERRIDES` succeeds, and a read
   returns the new letters. A `read_job_data(join = ...)` read returns one cluster per patient,
   for both a long read and a `one_row_per_patient = TRUE` read (section 5).
7. **K.** `K = NULL` runs every chunk and skips the K sections with a note. A
   K outside `K_RANGE` errors.
8. **No MRN in any file under `estimates/`**, with the ID falling back to MRN
   on `rf_mrn_data()`. The clusters dataset in `datasets/` carries the
   study's ID by design, as the built dataset beside it does.

The catalog-wide tests cover the format block, the `SUBJECT`/`TYPE` lines, the
single `setup` chunk, no study identifiers, `EDIT:` markers only in `edit-`
chunks, package floors, provenance and lineage, with no new code.

**Gates outside `testthat`:**

- a `.lintr` **file** key for each template;
- `cluster` and `mice` added to `Suggests`, with floors at the installed
  versions the tests ran against;
- the ledger rows, with the roadmap tables regenerated by
  `python3 dev/specs/artifacts/roadmap_render.py`.

**CI cost.** Tests 1, 2, 5, 6, 7 and the MRN scan fit SID, so they carry
`skip_on_cran()`. That is about eight small fits at `NTREE = 50` on 150 rows.
Test 2 needs `REDUCE = TRUE` and is the slowest, and the plan times it. Under
`NOT_CRAN=true` the expected `SKIP 0` on macOS and Ubuntu and `SKIP 3` on
Windows do not change.

**Not tested:** whether SID clusters are clinically meaningful. That is a
claim for each study, and `in-flight` records that no study has yet run these
jobs.

## 8. Out of scope

- **Per-cluster profiling and per-cluster varPro.** These are `dc-tables` and
  `vp-fit` with the JOIN above. The report points to both.
- **The gap statistic**, and an option to reproduce the studies'
  `pam(matrix)` assignments (section 1).
- **UMAP** and other embeddings beyond the MDS map.
- **Moving the helpers to hvtiRforests** (section 6).
- **Relaxing `read_job_data()`'s REDUCE rule** for ID-keyed joins, if the
  plan's check shows it is needed (section 5).
- **`vt`.** It consumes clusters only as a post-hoc stratifier joined on the
  ID, which is exactly the registered dataset above, so the two designs share
  no other interface.
