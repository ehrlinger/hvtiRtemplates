# Template identity: the ordinal, and the width of a prefix

**Status.** Evidence complete, **both decisions open**. Nothing is renamed and
no code is changed. Raised by the maintainer on 2026-09-03: "ordinals are
still TBD and might not actually be necessary", and "we might want to increase
the template identifier lengths to 4 characters, especially for the new
formatting".

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
| files scaffolded from **our** templates, whole corpus | **16** (5 `set`, 11 `r_transitional`) |
| legacy SAS files carrying a known prefix | **423,269** |

**Only sixteen files anywhere would be orphaned by a prefix rename**, and every
job scaffolded from here on adds to that. The cost of this change only rises.

⚠️ **But the 423,269 are the real cost, in a different way.** They are not
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

1. **Are templates within a folder ordered?** If not, `MM` has no job and `NN`
   is redundant with the directory, so the ordinal can go entirely.
2. **If they are ordered, what orders them?** `MM`, or an explicit `order:`
   field in the ledger, which would be recomputable rather than permanent.
3. **Does the prefix rename carry a legacy alias map**, or does the census
   accept that renamed prefixes fall into the unknown bucket? The second is not
   viable: `dp` alone is 32,462 files.
4. **What happens to the nine shipped templates and the sixteen scaffolded
   jobs?** Sixteen is small enough to migrate by hand, and it is the smallest
   this number will ever be.
5. **`04.06` is retired and in the wild.** If ordinals go, the retirement
   register goes with them, and any study still holding `04.06-bh` holds a name
   nothing explains. That needs a sentence somewhere permanent.

## 8. Recommendation

**Take them in two steps, ordinal first, and only after question 1 is answered.**

The ordinal is cheap to remove, local to this package, and already
under-used at 9 of 53. The prefix rename is upstream, permanent, and needs a
legacy alias map that will outlive everyone; it should not ride along with a
smaller change.

Neither is urgent. Both get more expensive as templates ship, and the prefix
one gets more expensive with every job a study scaffolds, from sixteen today.
