# Template identity: the ordinal, and the width of a prefix

**Status.** ⭐ **DECIDED 2026-09-03. The ordinal goes away entirely.**

- **Folders carry the digits**, in taxonomy order with taxonomy spellings:
  `00_datasets`, `10_descriptive`, `20_distributions`, `30_analyses`,
  `40_graphs`, `50_documents`, `90_estimates`.
- **`NN` moves into the folder name**, where it is the thing rather than a
  duplicate of it.
- **`MM` is dropped. Templates within a folder are NOT ordered** (maintainer,
  2026-09-03), so nothing replaces it, because nothing needed it. Section 7
  question 1 is answered: `MM` was asserting an order that does not exist.
- **Prefix width is deferred**, not rejected. It is upstream, permanent, and
  needs the legacy alias map of section 5; it should not ride along.

A template becomes `<folder>/<prefix>[-<qualifier>].qmd` and a job becomes
`<endpoint>-<type>-<prefix>[-<qualifier>].qmd`. `retired_ordinals` and the
never-reissue rule go with the ordinal, and `04.06` becomes a historical note
rather than a live constraint.

Implementation is a separate change; this note is the reasoning. Evidence
sections below stand as written.

**Provenance.** Raised by the maintainer on 2026-09-03: "ordinals are still TBD
and might not actually be necessary", and "we might want to increase the
template identifier lengths to 4 characters, especially for the new
formatting"; then "I'm actually leaning toward folders by digits", and "no
ordering within folders, drop MM".

⚠️ **No STUDY path, study name or patient identifier** appears here. Counts
only, from the 2026-08-27 catalogue.

## 1. What a template name currently holds

```
inst/templates/analyses/04.05-bh.qmd
               ^^^^^^^^ ^^ ^^ ^^
               folder   NN MM prefix
```

Four fields, and the `qualifier` added in 1.0.21 makes five:
`<folder>/<NN.MM>-<prefix>[-<qualifier>].qmd`.

## 2. `NN` is redundant, provably

`NN` is the taxonomy folder's position, and the folder is already the
directory the file sits in. `04.05-bh.qmd` lives in `analyses/`, and `04` **is**
`analyses`. The mapping is a constant in two places, `FOLDER_ORDINAL` in
`check-roadmap-counts.py` and the row order of `hvti_taxonomy()`, and CI exists
to check the two agree.

**That redundancy has already cost a rename.** `bh` shipped as `04.06` because
it was 6th in `analyses`. `hvtiRutilities` `aeb20f2` moved `hs` out to
`graphs`, correctly, and every analyses prefix below it shifted up one. `bh`
became 5th while the filename stayed at `04.06`. The identity was positional
**across a repository boundary**, so a correctness fix in the upstream
vocabulary silently invalidated a downstream filename. `bh` was renumbered to
`04.05` in 1.0.15, and `04.06` is now permanently retired.

## 3. What `MM` buys, and what it costs

`MM` is assigned from the next free minor in a folder and never recomputed. The
stated purpose is that a flat folder sorts into run order past nine entries.

Against that:

| cost | measure |
|---|---|
| `ordinal` handling in `check-roadmap-counts.py` | 40 mentions |
| the retirement register | `retired_ordinals`, 1 entry, permanent |
| rows that actually have one | **9 of 53** |
| the reason twelve more were not assigned on 2026-09-03 | assigning them would burn twelve keys on templates that may never exist |

That last row is the argument in miniature. A key that is expensive to issue,
impossible to reissue, and absent from 44 of 53 rows is not carrying much.

⚠️ **The counter-argument to weigh:** run order. If a folder's templates are
meant to be run in sequence, something has to say so, and alphabetical order of
`<prefix>-<qualifier>` does not. Nobody has yet stated that templates within a
folder ARE ordered; the ordinal asserts it. **Settle that first** — if they are
not ordered, `MM` is answering a question nobody asked.

## 4. Prefix width: what the vocabulary actually looks like

The prefix is **already variable-width**, not fixed at two:

| width | count | examples |
|---|---|---|
| 2 | 38 | `dp`, `dc`, `hz`, `hm` |
| 3 | 2 | `rfc`, `rfs` |
| 4 | 1 | `vars` |
| 5 | 1 | `rfsrc` |

So a four-character rule is not a widening of a fixed field; it is a **rewrite
of 41 of 42 entries in a shared vocabulary**.

**Why it is worth considering.** With the qualifier in place, a name reads
`dp-trends`: the half a study author can act on is `trends`, and `dp` is a
lookup. `dplt-trends` or similar would make the whole name self-describing.

## 5. The blast radius, measured

This is the number that decides when, if not whether.

| what | count |
|---|---|
| files in a template-era naming convention, whole corpus | **27** `.qmd` across **6 studies** |
| of those, the `r_transitional` shape that predates `new_job()` | **22** |
| of those, the current `set` shape | **5** |
| legacy SAS files carrying a known prefix | **423,269** |

⚠️ **Corrected 2026-09-03.** An earlier draft said sixteen, counting only rows
whose prefix is in the taxonomy; the honest figure is 27. It also called them
"scaffolded from our templates", which 22 of them were not: `r_transitional` is
the hand-written convention that predates `new_job()`.

⭐ **And the maintainer's account is that nobody has used the templates yet, the
work is still being specced.** So the template-side migration cost of renaming
a folder, a prefix or the ordinal is **effectively nil right now**, and every
number in this table is the largest it will be before real use begins. That
argues for deciding sooner rather than later, and it is the opposite of the
caution the earlier draft implied.

⚠️ **The 423,269 are a SEPARATE cost, and template usage has no bearing on
it.** They are not
renamed and do not need to be: they are pre-existing SAS jobs that keep their
own names. They are, however, **classified by this vocabulary**. Rename `dp` to
`dplt` and 32,462 `dp` files stop matching a known prefix unless
`hvti_taxonomy()` carries a **legacy alias map** from the old SAS prefix to the
new template prefix, permanently. That map, not the renaming, is what the
change actually costs, and it lives upstream where every consumer sees it.

## 6. Reach

A prefix change is not local to this package. `hvti_taxonomy()` lives in
`hvtiRutilities` and is re-exported here, so the vocabulary is shared by every
repository that consumes it, and the census that classifies 2.24M corpus rows
reads it. An ordinal change is local to template filenames, this ledger and its
checker.

**They are different sizes and should probably be decided separately, even
though they are one subject.**

## 7. What has to be settled

1. ✅ **Are templates within a folder ordered?** **No** (maintainer,
   2026-09-03). `MM` has no job, `NN` is redundant with the directory, and the
   ordinal goes entirely.
2. ✅ **If they are ordered, what orders them?** Moot, per 1.
3. **Does the prefix rename carry a legacy alias map**, or does the census
   accept that renamed prefixes fall into the unknown bucket? The second is not
   viable: `dp` alone is 32,462 files.
4. **What happens to the nine shipped templates?** They are renamed, and the
   three template folders become numbered. Section 5 measures the job side at
   27 files that nobody is using, so there is nothing else to migrate.
5. ⚠️ **`04.06` is retired and in the wild, and this is the one loose end.**
   The retirement register goes with the ordinal, so a study still holding
   `04.06-bh` would hold a name nothing explains. It needs a permanent
   sentence in `AGENTS.md` recording that ordinals existed, what they looked
   like, and when they were dropped, so an old filename stays readable.

## 8. The folder-digit proposal, and it is the better answer

Raised by the maintainer later the same day: put the digits on the **folder**.

```
00_datasets  10_descriptives  20_distributions  30_analysis
40_documents 50_graphs        60_estimates
```

**This is the right shape, and for a reason section 2 already established.**
`NN` is redundant in a filename because the directory already says it. Move it
to the directory and it stops being a duplicate and becomes the thing itself.
The filename then needs no ordinal at all, and `<prefix>-<qualifier>.qmd` is
the whole identity.

⭐ **The decade gaps fix the defect that caused the `bh` renumber.** `bh` was
renumbered because inserting `hs` shifted every folder position below it.
Under `00 / 10 / 20`, a new folder goes in at `25` and shifts nothing. The
scheme is insertable, which positional numbering never was.

### Resolved 2026-09-03: taxonomy names, taxonomy order, estimates at 90

The maintainer settled both discrepancies: **use the taxonomy names**, keep the
current order, and **push `estimates` to 90** because it is a different beast.

```
00_datasets   10_descriptive   20_distributions   30_analyses
40_graphs     50_documents                        90_estimates
```

⭐ **`estimates` at 90 is well founded by this session's own measurement.** It
is the one folder that holds no jobs: its contents are `.sas7bdat`, `.rda`,
`.RData` and `.ssd01`, model output rather than programs. Reading it as a job
folder is exactly what made `hzdead` (395 studies) and `deade`/`deadl` look
like analyses when they are saved estimates. Numbering it apart from the job
folders states that in the layout instead of leaving it to be rediscovered.

The gap from 50 to 90 is deliberate room, on the same principle as the
decades.

### What the original list would have changed, kept for the record

| proposed | taxonomy and corpus | corpus files |
|---|---|---|
| `10_descriptives` | **`descriptive`**, singular | 54,510 |
| `30_analysis` | **`analyses`**, plural | 119,582 |

And the tail is reordered. The taxonomy is `estimates` 05, `graphs` 06,
`documents` 07; the proposal is `documents` 40, `graphs` 50, `estimates` 60.

⚠️ **These are not cosmetic.** `new_job()` writes into the folder name inside
a real study, so a job landing in `descriptives/` while that study's other
jobs sit in `descriptive/` splits the estate. Renaming is possible, but it is
a **corpus-wide vocabulary change**, not a package-local one, and it needs the
same legacy alias treatment section 5 describes for prefixes: 54,510 and
119,582 existing files sit under the current spellings.

Both are superseded by the resolution above: the taxonomy spellings stand, so
neither rename happens and neither alias is needed.

### What it left, and how that closed

The folder digits replace `NN`, which left `MM` and section 7 question 1.
**Answered the same day: templates within a folder are not ordered.** So `MM`
is dropped outright rather than replaced. It had been asserting a sequence
nobody had claimed existed, and the cost of that assertion was a permanent
retirement register, 40 mentions in the checker, and a rename.

## 9. Recommendation

**Take the folder digits, then the ordinal, then the prefix, in that order.**
The folder digits are the cleanest of the three: they solve `NN` and the
insertion problem together, they keep the taxonomy spellings so no alias is
needed, and section 8's naming question is now settled.

⭐ **And do it while nobody is using the templates.** Section 5 measures 27
files in a template-era convention, 22 of them predating `new_job()`, against
a maintainer's account that the templates have not been used at all. Every one
of the three changes is cheapest today and never gets cheaper.

The ordinal is cheap to remove, local to this package, and already
under-used at 9 of 53. The prefix rename is upstream, permanent, and needs a
legacy alias map that will outlive everyone; it should not ride along with a
smaller change.

Neither is urgent. Both get more expensive as templates ship, and the prefix
one gets more expensive with every job a study scaffolds, from sixteen today.
