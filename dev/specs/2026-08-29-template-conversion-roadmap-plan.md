# Template Conversion Roadmap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the ledger, renderer and two CI guards that hold the template
conversion roadmap honest, and generate the roadmap document from them.

**Architecture:** A hand-maintained JSON ledger is the map; the roadmap
document's tables are generated from it; two guards in two languages check the
agreement — Python for anything the filesystem can answer, testthat for
anything needing `hvti_taxonomy()`. This is the
`2026-08-14-macro-allocation.json` + `check-spec-counts.py` pattern already
established here.

**Tech Stack:** Python 3 (stdlib only — `json`, `os`, `re`, `sys`), R with
testthat edition 3, GitHub Actions.

**Design spec:** `dev/specs/2026-08-29-template-conversion-roadmap-design.md`.
Read it before starting. This plan implements §4 (ledger), §5 (guards) and the
roadmap document; it implements **no template**.

## Global Constraints

- **Never push to `main`.** Branch, open a PR against `main` (not stacked, or
  Copilot review never fires), let the maintainer merge.
- **Everything here lives under `dev/`, which is `.Rbuildignore`d** (`^dev$`),
  except `tests/testthat/test-roadmap.R`. Nothing in `dev/` reaches
  `R CMD check`.
- **No new package dependency.** The Python guards are stdlib-only; the
  testthat guard uses only what `DESCRIPTION` already declares.
- **Roxygen here is Rd markup, not markdown** — irrelevant to this plan, which
  adds no roxygen, but do not "fix" any you pass.
- **Lines are 135 characters** in R (`.lintr`), not 80. Python follows the
  existing artifact scripts' informal ~88.
- **`testthat` edition 3.** Review any snapshot diff rather than accepting it.
- **Versions are straight three digits.** This plan adds no exported function
  and no user-visible behaviour, so it takes **one patch bump** at the end
  (Task 4), with `DESCRIPTION` `Version` + `Date` and a matching `NEWS.md`
  entry under a plain `# hvtiRtemplates X.Y.Z` heading — **no `Version:` line**
  in `NEWS.md`.
- **The ledger is the map. The document's tables are a copy.** Never hand-edit
  a generated table; edit the ledger and re-render.

## File Structure

| file | responsibility |
|---|---|
| `dev/specs/artifacts/2026-08-29-template-roadmap.json` | **the map** — one record per prefix plus an intake array |
| `dev/specs/artifacts/2026-08-29-roadmap-seed.py` | one-time seeder; kept so the map regenerates rather than being trusted |
| `dev/specs/artifacts/roadmap_render.py` | regenerates the document's tables from the map |
| `dev/specs/artifacts/check-roadmap-counts.py` | CI guard: filesystem agreement + doc/render agreement |
| `dev/specs/2026-08-29-template-conversion-roadmap.md` | the roadmap; prose hand-written, tables generated between markers |
| `tests/testthat/test-roadmap.R` | CI guard: ledger vocabulary vs `hvti_taxonomy()` |
| `.github/workflows/spec-counts.yaml` | gains one `run:` step |

---

### Task 1: The ledger and its filesystem guard

**Files:**
- Create: `dev/specs/artifacts/check-roadmap-counts.py`
- Create: `dev/specs/artifacts/2026-08-29-roadmap-seed.py`
- Create: `dev/specs/artifacts/2026-08-29-template-roadmap.json` (generated)
- Modify: `.github/workflows/spec-counts.yaml`

**Interfaces:**
- Consumes: `2026-08-29-job-census-summary.json` (fields `known[].prefix`,
  `.distinct_studies`, `.r_studies_deflated`, `.r_jobs`);
  `2026-08-22-job-flow.json` (field `cross_job`); `inst/templates/**.qmd`.
- Produces: `2026-08-29-template-roadmap.json` with top-level keys
  `_provenance` (object), `prefixes` (array), `intake` (array). Each prefix
  record has exactly these keys: `prefix`, `name`, `folder`, `family`, `kind`,
  `status`, `ordinal`, `batch`, `sas_breadth`, `r_exemplars`, `r_jobs`,
  `upstream`, `downstream`, `workflows`, `blocked_on`, `spec`, `note`.
  Task 2's renderer and Task 3's testthat guard both read this shape.

- [ ] **Step 1: Write the failing guard**

Create `dev/specs/artifacts/check-roadmap-counts.py`:

```python
#!/usr/bin/env python3
"""Fail if the roadmap ledger disagrees with the templates on disk.

The ledger (`2026-08-29-template-roadmap.json`) is authoritative for status,
family and batch; `inst/templates/` is authoritative for what actually ships.
This checks they agree, in both directions -- a ledger row claiming a template
that is absent is a lie, and a template no row claims is a template nobody
scheduled.

Deliberately does NOT read `hvti_taxonomy()`. That needs R, and this runs in a
Python step. The vocabulary check lives in `tests/testthat/test-roadmap.R`,
where R is already present. Splitting them keeps each guard in the language
that already has what it needs.

Exit 0 = agree. Exit 1 = drift, with every mismatch listed.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LEDGER = os.path.join(HERE, "2026-08-29-template-roadmap.json")
REPO = os.path.join(HERE, os.pardir, os.pardir, os.pardir)
TEMPLATES = os.path.join(REPO, "inst", "templates")

# The ordinal's major field is the taxonomy folder's position, and the two must
# agree or a template sorts into the wrong run order. Taken from the order of
# `hvti_taxonomy()`'s folder column, which is stable and is itself asserted in
# tests/testthat/test-taxonomy.R.
FOLDER_ORDINAL = {
    "datasets": "01",
    "descriptive": "02",
    "distributions": "03",
    "analyses": "04",
    "estimates": "05",
    "graphs": "06",
    "documents": "07",
}

STATUSES = {"shipped", "revisit", "in-flight", "queued", "intake", "out-of-scope"}
KINDS = {"job", "meta"}
FIELDS = ["prefix", "name", "folder", "family", "kind", "status", "ordinal",
          "batch", "sas_breadth", "r_exemplars", "r_jobs", "upstream",
          "downstream", "workflows", "blocked_on", "spec", "note"]

# A row in one of these states asserts a template exists on disk. Every other
# state asserts it does not. `revisit` counts as shipped: the file is there and
# incomplete, which is a different claim from absent.
ON_DISK = {"shipped", "revisit", "in-flight"}


def check_schema(rows):
    bad = []
    for i, r in enumerate(rows):
        where = r.get("prefix") or f"row {i}"
        missing = [f for f in FIELDS if f not in r]
        extra = [k for k in r if k not in FIELDS]
        if missing:
            bad.append(f"`{where}` is missing field(s): {', '.join(missing)}")
        if extra:
            bad.append(f"`{where}` has unknown field(s): {', '.join(extra)}")
        if r.get("status") not in STATUSES:
            bad.append(f"`{where}` has status {r.get('status')!r}, "
                       f"not one of {sorted(STATUSES)}")
        if r.get("kind") not in KINDS:
            bad.append(f"`{where}` has kind {r.get('kind')!r}, "
                       f"not one of {sorted(KINDS)}")
        # A measured zero and an unmeasured field must stay distinguishable:
        # nine prefixes genuinely have no R job, and reading that as "not yet
        # counted" would send someone to re-run a census that already answered.
        if r.get("r_exemplars") is not None and not isinstance(r["r_exemplars"], int):
            bad.append(f"`{where}` has non-integer r_exemplars "
                       f"{r['r_exemplars']!r}; use null for unmeasured")
    return bad


def check_ordinals(rows):
    bad = []
    seen = {}
    for r in rows:
        ordinal, folder, prefix = r.get("ordinal"), r.get("folder"), r.get("prefix")
        if ordinal is None:
            if r.get("status") in ON_DISK:
                bad.append(f"`{prefix}` is {r['status']} but has no ordinal")
            continue
        if not re.fullmatch(r"\d{2}[.]\d{2}", ordinal):
            bad.append(f"`{prefix}` has ordinal {ordinal!r}, not zero-padded NN.MM")
            continue
        major = ordinal.split(".")[0]
        want = FOLDER_ORDINAL.get(folder)
        if want is None:
            bad.append(f"`{prefix}` has unknown folder {folder!r}")
        elif major != want:
            bad.append(f"`{prefix}` is in {folder} (ordinal {want}) "
                       f"but its ordinal starts {major}")
        if ordinal in seen:
            bad.append(f"ordinal {ordinal} is used by both "
                       f"`{seen[ordinal]}` and `{prefix}`")
        else:
            seen[ordinal] = prefix
    return bad


def check_disk(rows):
    bad = []
    claimed = {}
    for r in rows:
        if r.get("status") not in ON_DISK or not r.get("ordinal"):
            continue
        rel = os.path.join(r["folder"], f"{r['ordinal']}-{r['prefix']}.qmd")
        claimed[rel] = r["prefix"]
        if not os.path.isfile(os.path.join(TEMPLATES, rel)):
            bad.append(f"`{r['prefix']}` is {r['status']} but "
                       f"inst/templates/{rel} does not exist")

    on_disk = []
    for root, _dirs, files in os.walk(TEMPLATES):
        for f in files:
            if f.endswith(".qmd"):
                rel = os.path.relpath(os.path.join(root, f), TEMPLATES)
                on_disk.append(rel)
    for rel in sorted(on_disk):
        if rel not in claimed:
            bad.append(f"inst/templates/{rel} exists but no ledger row claims it")
    return bad


def main():
    # Encodings are pinned, as in the sibling checks: this runs on a CI runner
    # whose locale is not ours to choose, and the ledger carries em dashes an
    # ascii default would refuse outright.
    with open(LEDGER, encoding="utf-8") as fh:
        d = json.load(fh)
    rows = d["prefixes"]

    bad = check_schema(rows) + check_ordinals(rows) + check_disk(rows)
    if bad:
        print("Roadmap ledger disagrees with the templates on disk:\n", file=sys.stderr)
        for b in bad:
            print(f"  - {b}", file=sys.stderr)
        print("\nThe ledger is the map. Fix the ledger, or ship the template it\n"
              "claims; do not delete the row to make the check pass.", file=sys.stderr)
        return 1

    shipped = sum(1 for r in rows if r["status"] in ON_DISK)
    print(f"Ledger agrees with disk: {len(rows)} prefixes, {shipped} on disk.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 2: Run it to verify it fails**

```bash
python3 dev/specs/artifacts/check-roadmap-counts.py
```

Expected: `FileNotFoundError` naming `2026-08-29-template-roadmap.json`. The
ledger does not exist yet — that is the failure this step is proving.

- [ ] **Step 3: Write the seeder**

Create `dev/specs/artifacts/2026-08-29-roadmap-seed.py`:

```python
#!/usr/bin/env python3
"""Seed the roadmap ledger from the taxonomy, the census and the job flow.

Kept rather than run-and-discarded, for the reason the macro-allocation scan is
kept: a 42-row table assembled by hand from three sources is wrong in ways
nobody can see, and a regenerable map can be checked against its sources.

RUN LOCALLY, NOT IN CI. It shells to Rscript for `hvti_taxonomy()` and reads
`~/Documents/template` for the SAS template counts; neither exists on a runner.
`check-roadmap-counts.py` is what CI can honestly enforce.

After the first run the ledger is HAND-MAINTAINED. Re-running overwrites
`status`, `batch` and `note`, which are decisions, not measurements -- so it
refuses to overwrite unless given --force.
"""
import collections
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "2026-08-29-template-roadmap.json")
CENSUS = os.path.join(HERE, "2026-08-29-job-census-summary.json")
FLOW = os.path.join(HERE, "2026-08-22-job-flow.json")
LIBRARY = os.path.expanduser("~/Documents/template")

# Family assignment is a DECISION from the design spec (section 3), not data.
# It lives here rather than being inferred, because inferring it from the
# taxonomy folder would put every analyses/ prefix in one bucket and lose the
# bootstrap / models / ML distinction the batching depends on.
FAMILY = {
    "bd": "datasets", "vars": "datasets", "dt": "datasets",
    "dc": "descriptive", "lg": "descriptive", "rg": "descriptive",
    "ac": "distributions", "hz": "distributions", "cd": "distributions",
    "nd": "distributions",
    "hm": "hazard-chain", "hs": "hazard-chain",
    "bh": "bootstrap", "bl": "bootstrap", "bc": "bootstrap",
    "bn": "bootstrap", "bq": "bootstrap", "br": "bootstrap",
    "mm": "models", "gm": "models", "lm": "models", "nm": "models",
    "rm": "models", "cm": "models", "ls": "models", "pm": "models",
    "rf": "machine-learning", "rfsrc": "machine-learning",
    "rfs": "machine-learning", "rfc": "machine-learning",
    "nb": "machine-learning",
    "hp": "plots", "mp": "plots", "lp": "plots", "np": "plots",
    "dp": "plots", "fp": "plots", "gp": "plots", "cp": "plots",
    "ce": "plots", "rp": "plots",
    "ar": "documents",
}

# Shipped and in-flight templates, with the ordinals already on disk.
KNOWN_STATUS = {
    "ac": ("shipped", "03.01"), "hz": ("shipped", "03.02"),
    "hm": ("shipped", "04.01"), "hp": ("revisit", "06.01"),
    "bh": ("in-flight", "04.06"),
}

# Demoted to umbrella rows by design spec section 3.4.
OUT_OF_SCOPE = {"rf", "rfsrc"}

# Batches 0-2 are decided; everything later is provisional and carries the
# family's provisional position, which the spec's section 7 states as such.
BATCH = {"bh": 0, "hs": 1,
         "bl": 2, "bc": 2, "bn": 2, "bq": 2, "br": 2}
PROVISIONAL_BATCH = {"plots": 3, "descriptive": 4, "machine-learning": 5,
                     "models": 6, "distributions": 7, "datasets": 8,
                     "documents": 9}

# Cross-cutting workflows, design spec section 3.5. Only the two the corpus
# actually evidences; inventing more would be speculative.
WORKFLOWS = {
    "hazard-chain": ["ac", "hz", "hm", "hs", "hp"],
    "propensity-matching": ["lm", "bd", "lp", "rp", "dc", "pm", "rm", "cm",
                            "bl", "hp"],
}

BLOCKED = {"bd": "hvtiRdatabuild", "vars": "hvtiRdatabuild",
           "dt": "hvtiRdatabuild"}


def taxonomy():
    """prefix -> (name, folder), read from hvtiRutilities via Rscript."""
    code = ('tx <- hvtiRutilities::hvti_taxonomy(); '
            'tx <- tx[!is.na(tx$prefix), c("prefix", "name", "folder")]; '
            'cat(jsonlite::toJSON(tx))')
    out = subprocess.run(["Rscript", "-e", code], capture_output=True,
                         text=True, check=True).stdout
    return {r["prefix"]: (r["name"], r["folder"]) for r in json.loads(out)}


def sas_template_counts():
    """prefix -> number of tp.<prefix>.*.sas files in the library."""
    n = collections.Counter()
    if not os.path.isdir(LIBRARY):
        print(f"!! {LIBRARY} absent; sas_templates left at 0", file=sys.stderr)
        return n
    for root, _dirs, files in os.walk(LIBRARY):
        for f in files:
            m = re.match(r"^tp[.]([A-Za-z0-9]+)[.].*[.]sas$", f)
            if m:
                n[m.group(1)] += 1
    return n


def flow_edges():
    """prefix -> (upstream set, downstream set), from the cross-job handoffs."""
    with open(FLOW, encoding="utf-8") as fh:
        cross = json.load(fh)["cross_job"]
    up = collections.defaultdict(set)
    down = collections.defaultdict(set)

    def pfx(path):
        m = re.match(r"^tp[.]([A-Za-z0-9]+)[.]", os.path.basename(path))
        return m.group(1) if m else None

    for edge in cross.values():
        writers = {p for p in map(pfx, edge.get("w", [])) if p}
        readers = {p for p in map(pfx, edge.get("r", [])) if p}
        for w in writers:
            down[w] |= readers - {w}
        for r in readers:
            up[r] |= writers - {r}
    return up, down


def main():
    if os.path.exists(OUT) and "--force" not in sys.argv:
        print(f"{OUT} exists. It is hand-maintained after seeding; re-running\n"
              "would overwrite status, batch and note, which are decisions.\n"
              "Pass --force if you really mean to reseed.", file=sys.stderr)
        return 1

    tax = taxonomy()
    with open(CENSUS, encoding="utf-8") as fh:
        census = {r["prefix"]: r for r in json.load(fh)["known"]}
    sas = sas_template_counts()
    up, down = flow_edges()

    rows = []
    for prefix, (name, folder) in sorted(tax.items()):
        family = FAMILY.get(prefix, "unassigned")
        status, ordinal = KNOWN_STATUS.get(prefix, (None, None))
        if status is None:
            status = "out-of-scope" if prefix in OUT_OF_SCOPE else "queued"
        c = census.get(prefix, {})
        rows.append({
            "prefix": prefix,
            "name": name,
            "folder": folder,
            "family": family,
            "kind": "job",
            "status": status,
            "ordinal": ordinal,
            "batch": BATCH.get(prefix, PROVISIONAL_BATCH.get(family)),
            "sas_breadth": c.get("distinct_studies"),
            "r_exemplars": c.get("r_studies_deflated"),
            "r_jobs": c.get("r_jobs"),
            "upstream": sorted(up.get(prefix, ())),
            "downstream": sorted(down.get(prefix, ())),
            "workflows": sorted(w for w, ps in WORKFLOWS.items() if prefix in ps),
            "blocked_on": BLOCKED.get(prefix),
            "spec": None,
            "note": None,
        })

    # Proposed prefixes are NOT yet in hvti_taxonomy(). They carry status
    # "intake" so tests/testthat/test-roadmap.R exempts them from the
    # vocabulary check until the hvtiRutilities PR lands.
    for prefix, name in (("rfr", "Random forest regression"),
                         ("sid", "Random forest clustering (sidClustering)"),
                         ("vt", "Virtual twins")):
        rows.append({
            "prefix": prefix, "name": name, "folder": "analyses",
            "family": "machine-learning", "kind": "job", "status": "intake",
            "ordinal": None, "batch": PROVISIONAL_BATCH["machine-learning"],
            "sas_breadth": None, "r_exemplars": None, "r_jobs": None,
            "upstream": [], "downstream": [], "workflows": [],
            "blocked_on": "hvtiRutilities#taxonomy", "spec": None,
            "note": "proposed prefix; blocks on the taxonomy PR",
        })

    doc = {
        "_provenance": {
            "seeded_by": "2026-08-29-roadmap-seed.py, run locally 2026-08-29",
            "design": "dev/specs/2026-08-29-template-conversion-roadmap-design.md",
            "sources": {
                "prefix/name/folder": "hvtiRutilities::hvti_taxonomy()",
                "sas_breadth,r_exemplars,r_jobs": "2026-08-29-job-census-summary.json",
                "upstream/downstream": "2026-08-22-job-flow.json cross_job edges",
            },
            "hand_maintained_after_seeding": ["status", "batch", "note", "spec",
                                              "ordinal"],
            "r_exemplars_note": ("the DEFLATED count -- a stem replicated across "
                                 "studies inflates the raw figure, severely for ar "
                                 "(395 -> 89). Never quote the undeflated number."),
            "batch_note": ("batches 0-2 are decided; 3 and later are PROVISIONAL "
                           "and carry the family's provisional position."),
        },
        "prefixes": rows,
        "intake": [],
    }
    with open(OUT, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, indent=2)
        fh.write("\n")
    print(f"seeded {len(rows)} prefixes -> {os.path.basename(OUT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Seed the ledger and run the guard**

```bash
python3 dev/specs/artifacts/2026-08-29-roadmap-seed.py && python3 dev/specs/artifacts/check-roadmap-counts.py
```

Expected: `seeded 45 prefixes -> 2026-08-29-template-roadmap.json`, then one
of two outcomes, depending on your base branch.

45 = 42 taxonomy prefixes + the three proposed (`rfr`, `sid`, `vt`).

⚠️ **`bh` is the branch-dependent one.** `inst/templates/analyses/04.06-bh.qmd`
lives on `feat/8-bh-template` and is **not on `main`**. So:

- **Branched off `feat/8-bh-template`:** `45 prefixes, 5 on disk` — `ac`, `hz`,
  `hm`, `hp` (`revisit`) and `bh` (`in-flight`). Nothing to change.
- **Branched off `main` (the likely case):** the guard exits 1 with
  `` `bh` is in-flight but inst/templates/analyses/04.06-bh.qmd does not exist ``.
  That is the guard working. Edit the ledger to set `bh`'s `status` to
  `"queued"` and its `ordinal` to `null`, re-run, and expect
  `45 prefixes, 4 on disk`. Say so in the commit message.

**Do not weaken the guard or delete the `bh` row to get past this.** Whichever
branch you are on, the check is telling the truth about that branch.

- [ ] **Step 5: Prove the guard actually catches drift**

```bash
python3 - <<'EOF'
import json
p = "dev/specs/artifacts/2026-08-29-template-roadmap.json"
d = json.load(open(p, encoding="utf-8"))
for r in d["prefixes"]:
    if r["prefix"] == "hs":
        r["status"], r["ordinal"] = "shipped", "04.02"
json.dump(d, open(p, "w", encoding="utf-8"), indent=2)
EOF
python3 dev/specs/artifacts/check-roadmap-counts.py; echo "exit=$?"
```

Expected: exit 1, with
`- \`hs\` is shipped but inst/templates/analyses/04.02-hs.qmd does not exist`.

Then restore:

```bash
python3 dev/specs/artifacts/2026-08-29-roadmap-seed.py --force && python3 dev/specs/artifacts/check-roadmap-counts.py
```

Expected: exit 0 again. A guard never run against a failure is a guard nobody
knows works.

- [ ] **Step 6: Wire it into CI**

In `.github/workflows/spec-counts.yaml`, after the
`Job flow diagrams agree with the generated maps` step, add:

```yaml
      - name: Roadmap ledger agrees with the templates on disk
        run: python3 dev/specs/artifacts/check-roadmap-counts.py
```

The workflow's existing `paths:` filters already cover `dev/specs/**`, so no
trigger change is needed. Note the header comment's warning: the path filters
and the `run:` paths must move together with any move of `dev/specs/`.

- [ ] **Step 7: Commit**

```bash
git add dev/specs/artifacts/check-roadmap-counts.py dev/specs/artifacts/2026-08-29-roadmap-seed.py dev/specs/artifacts/2026-08-29-template-roadmap.json .github/workflows/spec-counts.yaml
git commit -m "feat(roadmap): seed the conversion ledger and guard it against disk"
```

---

### Task 2: The renderer and the roadmap document

**Files:**
- Create: `dev/specs/artifacts/roadmap_render.py`
- Create: `dev/specs/2026-08-29-template-conversion-roadmap.md`
- Modify: `dev/specs/artifacts/check-roadmap-counts.py`

**Interfaces:**
- Consumes: `2026-08-29-template-roadmap.json` from Task 1, exactly the record
  shape listed there.
- Produces: `roadmap_render.py` exposing `render(rows) -> str` and
  `splice(text, body) -> str`, both imported by `check-roadmap-counts.py`.
  The document carries the markers `<!-- BEGIN GENERATED -->` and
  `<!-- END GENERATED -->`; everything between them is generated.

- [ ] **Step 1: Write the renderer**

Create `dev/specs/artifacts/roadmap_render.py`.

⚠️ **Underscore, not hyphen — unlike every sibling script here.** Task 2 Step 4
imports this module from `check-roadmap-counts.py`, and a hyphenated filename
is not an importable Python module name. The siblings are hyphenated because
nothing imports them.

```python
#!/usr/bin/env python3
"""Generate the roadmap document's tables from the ledger.

Two views of the same 45 rows. The family view is how the work is BATCHED; the
workflow view is what a study can actually RUN end to end. Family batching
amortises the design spec across a family, but it delivers a cross-cutting
workflow piecemeal -- propensity matching spans eight prefixes across five
batches -- so the second view exists to make that visible early rather than at
batch eight.

Writes between `<!-- BEGIN GENERATED -->` and `<!-- END GENERATED -->` in
`2026-08-29-template-conversion-roadmap.md`. Everything outside those markers is
hand-written prose and is never touched.

Run with --check to print the rendered body without writing (used by
check-roadmap-counts.py).
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LEDGER = os.path.join(HERE, "2026-08-29-template-roadmap.json")
DOC = os.path.join(HERE, os.pardir,
                   "2026-08-29-template-conversion-roadmap.md")

BEGIN = "<!-- BEGIN GENERATED -->"
END = "<!-- END GENERATED -->"

FAMILY_ORDER = ["hazard-chain", "bootstrap", "plots", "descriptive",
                "machine-learning", "models", "distributions", "datasets",
                "documents", "unassigned"]

STATUS_MARK = {"shipped": "shipped", "revisit": "**revisit**",
               "in-flight": "*in flight*", "queued": "queued",
               "intake": "*intake*", "out-of-scope": "~~umbrella~~"}


def _num(v):
    """A measured zero and an unmeasured field must not render the same."""
    return "—" if v is None else str(v)


def render(rows):
    out = [BEGIN, "",
           "> Generated from `artifacts/2026-08-29-template-roadmap.json` by",
           "> `artifacts/roadmap_render.py`. Do not hand-edit these tables —",
           "> edit the ledger and re-render. CI checks the agreement.", ""]

    live = [r for r in rows if r["status"] != "out-of-scope"]
    on_disk = [r for r in live if r["status"] in ("shipped", "revisit", "in-flight")]
    out += [f"**{len(live)} prefixes in scope**, of which {len(on_disk)} have a "
            f"template on disk. {len(rows) - len(live)} demoted to umbrella rows.",
            ""]

    out += ["## By family", ""]
    for fam in FAMILY_ORDER:
        fam_rows = [r for r in rows if r["family"] == fam]
        if not fam_rows:
            continue
        batches = sorted({r["batch"] for r in fam_rows if r["batch"] is not None})
        label = f"batch {batches[0]}" if len(batches) == 1 else \
                f"batches {batches[0]}–{batches[-1]}" if batches else "unscheduled"
        out += [f"### {fam} ({label})", "",
                "| prefix | status | ordinal | breadth | R exemplars | blocked on |",
                "|---|---|---|---|---|---|"]
        for r in sorted(fam_rows, key=lambda r: (r["batch"] is None,
                                                 r["batch"] or 0, r["prefix"])):
            out.append(f"| `{r['prefix']}` | {STATUS_MARK[r['status']]} | "
                       f"{r['ordinal'] or '—'} | {_num(r['sas_breadth'])} | "
                       f"{_num(r['r_exemplars'])} | {r['blocked_on'] or '—'} |")
        out.append("")

    out += ["## By workflow", "",
            "A workflow is complete when every prefix in it is on disk.", ""]
    wf = {}
    for r in rows:
        for w in r["workflows"]:
            wf.setdefault(w, []).append(r)
    for name in sorted(wf):
        members = sorted(wf[name], key=lambda r: r["prefix"])
        done = [r for r in members
                if r["status"] in ("shipped", "revisit", "in-flight")]
        short = [r["prefix"] for r in members if r not in done]
        out += [f"### {name} — {len(done)}/{len(members)}", "",
                "Members: " + ", ".join(f"`{r['prefix']}`" for r in members),
                "",
                ("**Complete.**" if not short else
                 "Outstanding: " + ", ".join(f"`{p}`" for p in short) + "."),
                ""]

    out.append(END)
    return "\n".join(out)


def splice(text, body):
    i, j = text.index(BEGIN), text.index(END) + len(END)
    return text[:i] + body + text[j:]


def main():
    with open(LEDGER, encoding="utf-8") as fh:
        rows = json.load(fh)["prefixes"]
    body = render(rows)
    if "--check" in sys.argv:
        print(body)
        return 0
    with open(DOC, encoding="utf-8") as fh:
        text = fh.read()
    with open(DOC, "w", encoding="utf-8") as fh:
        fh.write(splice(text, body))
    print(f"rendered {len(rows)} prefixes into "
          f"{os.path.basename(os.path.normpath(DOC))}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 2: Write the roadmap document's prose shell**

Create `dev/specs/2026-08-29-template-conversion-roadmap.md`:

```markdown
# Template conversion roadmap

**Date:** 2026-08-29
**Status:** live — this document tracks work in progress
**Design:** `2026-08-29-template-conversion-roadmap-design.md`, which argues
every decision recorded here. Read it before changing anything.

The taxonomy names 42 analysis prefixes and three more are proposed. Four
templates ship. This is the queue for the rest, and the ledger behind it is
`artifacts/2026-08-29-template-roadmap.json`.

## How to read this

**One template per prefix.** Variants become `EDIT:` markers inside the file,
not separate templates.

**Batched by family.** One design spec per family, then one implementation PR
per prefix off it. Batches 0 to 2 are decided; **3 and later are provisional**
and will be reordered as evidence arrives.

**Two counts, measuring different things.** *Breadth* counts studies using that
job type across every extension and is SAS-dominated — it measures how much a
template is worth. *R exemplars* counts studies with an R job of that type — it
measures how much precedent there is to extract from. A prefix can be wide and
precedent-free; `bd` is 1,134 and 15. Never conflate them.

**An em dash means unmeasured, not zero.** Nine prefixes have a measured zero R
exemplars, which is a finding, not a gap.

## Changing this document

Do not hand-edit the generated tables. Edit
`artifacts/2026-08-29-template-roadmap.json`, then:

```sh
python3 dev/specs/artifacts/roadmap_render.py
```

`check-roadmap-counts.py` fails the PR if the two disagree, or if a `shipped`
row has no template on disk.

<!-- BEGIN GENERATED -->
<!-- END GENERATED -->

## What is not tracked here

The **study-level assembly** — a bookdown report combining the templates a
study ran, for handoff to researchers — has no taxonomy prefix yet and so has
no row. It is a `new-prefix` intake item blocked on an `hvti_taxonomy()` PR in
`hvtiRutilities`, and it is the only genuinely terminal unit in the roadmap.
`ar` is **not** that thing: it writes up one analysis, named
`ar.<method>.<endpoint>`.
```

- [ ] **Step 3: Render, and check the document changed**

```bash
python3 dev/specs/artifacts/roadmap_render.py && grep -c "^| \`" dev/specs/2026-08-29-template-conversion-roadmap.md
```

Expected: `rendered 45 prefixes into 2026-08-29-template-conversion-roadmap.md`,
then a count of `45` table rows.

- [ ] **Step 4: Extend the guard to check doc against render**

In `check-roadmap-counts.py`, add below the existing imports:

```python
sys.path.insert(0, HERE)
import roadmap_render  # noqa: E402  (path set immediately above)

DOC = os.path.join(HERE, os.pardir, "2026-08-29-template-conversion-roadmap.md")
```

Then add this function and call it from `main()`:

```python
def check_doc(rows):
    """The document's tables must be exactly what the ledger renders."""
    with open(DOC, encoding="utf-8") as fh:
        text = fh.read()
    want = roadmap_render.render(rows)
    i, j = text.find(roadmap_render.BEGIN), text.find(roadmap_render.END)
    if i < 0 or j < 0:
        return ["the roadmap document has lost its BEGIN/END GENERATED markers"]
    have = text[i:j + len(roadmap_render.END)]
    if have != want:
        return ["the roadmap document's tables are not what the ledger renders; "
                "run `python3 dev/specs/artifacts/roadmap_render.py`"]
    return []
```

In `main()`, change the `bad = ...` line to:

```python
    bad = check_schema(rows) + check_ordinals(rows) + check_disk(rows) + check_doc(rows)
```

- [ ] **Step 5: Prove the doc check catches drift**

```bash
printf '\n| `zz` | queued | — | 1 | 1 | — |\n' >> dev/specs/2026-08-29-template-conversion-roadmap.md
python3 dev/specs/artifacts/check-roadmap-counts.py; echo "exit=$?"
```

Expected: exit 0 — the line landed **outside** the markers, which is
hand-written prose the guard correctly ignores. Remove it, then edit a number
*inside* the markers instead:

```bash
git checkout dev/specs/2026-08-29-template-conversion-roadmap.md
python3 dev/specs/artifacts/roadmap_render.py
sed -i '' '0,/| `ac` |/s/| `ac` | shipped |/| `ac` | queued |/' dev/specs/2026-08-29-template-conversion-roadmap.md
python3 dev/specs/artifacts/check-roadmap-counts.py; echo "exit=$?"
```

Expected: exit 1, reporting the tables are not what the ledger renders. Then
`python3 dev/specs/artifacts/roadmap_render.py` restores it and the guard
returns 0.

- [ ] **Step 6: Commit**

```bash
git add dev/specs/artifacts/roadmap_render.py dev/specs/artifacts/check-roadmap-counts.py dev/specs/2026-08-29-template-conversion-roadmap.md
git commit -m "feat(roadmap): generate the roadmap document from the ledger"
```

---

### Task 3: The testthat vocabulary guard

**Files:**
- Create: `tests/testthat/test-roadmap.R`

**Interfaces:**
- Consumes: `2026-08-29-template-roadmap.json`'s `prefixes[].prefix` and
  `.status`, and `hvti_taxonomy()`'s `prefix` column.
- Produces: nothing other tasks consume.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-roadmap.R`:

```r
# The roadmap ledger's vocabulary must match the taxonomy's.
#
# This lives in R rather than beside the other roadmap guards in Python for one
# reason: it needs `hvti_taxonomy()`, and R is where that already is. The
# Python guard checks everything the filesystem can answer on its own; this
# checks the one thing it cannot.
#
# `dev/` is .Rbuildignore'd, so the ledger is ABSENT from a built package and
# from `R CMD check` on the tarball. Without the skip below, every check of a
# built package would fail on a missing file that is deliberately missing.

ledger_path <- function() {
  # testthat runs with the working directory at tests/testthat/, so the repo
  # root is three levels up. `testthat::test_path()` is not used: it resolves
  # inside tests/testthat/, and the ledger is deliberately outside the package.
  file.path("..", "..", "dev", "specs", "artifacts",
            "2026-08-29-template-roadmap.json")
}

test_that("every taxonomy prefix has a roadmap row", {
  skip_if_not(file.exists(ledger_path()), "roadmap ledger not present")
  skip_if_not_installed("jsonlite")

  ledger <- jsonlite::fromJSON(ledger_path(), simplifyDataFrame = FALSE)
  rows <- ledger$prefixes
  in_ledger <- vapply(rows, function(r) r$prefix, character(1))
  tx <- stats::na.omit(hvti_taxonomy()$prefix)

  # Direction one: nothing the taxonomy names may be unscheduled. A prefix
  # added upstream in hvtiRutilities fails here until the roadmap accounts for
  # it, which is the whole point -- otherwise it arrives silently and nobody
  # decides which family it belongs to.
  expect_setequal(intersect(tx, in_ledger), as.character(tx))
})

test_that("every roadmap row is a taxonomy prefix, unless it is intake", {
  skip_if_not(file.exists(ledger_path()), "roadmap ledger not present")
  skip_if_not_installed("jsonlite")

  ledger <- jsonlite::fromJSON(ledger_path(), simplifyDataFrame = FALSE)
  rows <- ledger$prefixes
  tx <- as.character(stats::na.omit(hvti_taxonomy()$prefix))

  # Direction two, with one exemption. `rfr`, `sid` and `vt` are PROPOSED and
  # deliberately not in the taxonomy yet -- they block on a PR to
  # hvtiRutilities. They carry status "intake" to say so. Any other row naming
  # a prefix the taxonomy does not have is a typo or a stale row, and fails.
  live <- Filter(function(r) !identical(r$status, "intake"), rows)
  live_prefixes <- vapply(live, function(r) r$prefix, character(1))
  expect_true(all(live_prefixes %in% tx),
              label = paste("ledger rows not in the taxonomy:",
                            paste(setdiff(live_prefixes, tx), collapse = ", ")))
})

test_that("an intake row names what it blocks on", {
  skip_if_not(file.exists(ledger_path()), "roadmap ledger not present")
  skip_if_not_installed("jsonlite")

  ledger <- jsonlite::fromJSON(ledger_path(), simplifyDataFrame = FALSE)
  intake <- Filter(function(r) identical(r$status, "intake"), ledger$prefixes)

  # An intake row without a blocker is indistinguishable from a forgotten one.
  # The blocker is what tells a reader why it is not scheduled.
  for (r in intake) {
    expect_true(!is.null(r$blocked_on) && nzchar(r$blocked_on),
                label = paste("intake row", r$prefix, "has no blocked_on"))
  }
})
```

- [ ] **Step 2: Run it to verify it passes with the ledger present**

```bash
Rscript -e 'devtools::test(filter = "roadmap")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 3 ]`. If it reports `SKIP 3`, the
ledger path is wrong — check the working directory assumption in
`ledger_path()` rather than deleting the skip.

- [ ] **Step 3: Prove the test catches a missing row**

```bash
python3 - <<'EOF'
import json
p = "dev/specs/artifacts/2026-08-29-template-roadmap.json"
d = json.load(open(p, encoding="utf-8"))
d["prefixes"] = [r for r in d["prefixes"] if r["prefix"] != "bq"]
json.dump(d, open(p, "w", encoding="utf-8"), indent=2)
EOF
Rscript -e 'devtools::test(filter = "roadmap")'
```

Expected: FAIL on "every taxonomy prefix has a roadmap row". Then restore:

```bash
python3 dev/specs/artifacts/2026-08-29-roadmap-seed.py --force
python3 dev/specs/artifacts/roadmap_render.py
Rscript -e 'devtools::test(filter = "roadmap")'
```

Expected: PASS 3.

- [ ] **Step 4: Run the whole suite**

```bash
Rscript -e 'devtools::test()'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 93 ]` — the 90 that passed before
this plan, plus 3.

- [ ] **Step 5: Commit**

```bash
git add tests/testthat/test-roadmap.R dev/specs/artifacts/2026-08-29-template-roadmap.json
git commit -m "test(roadmap): assert the ledger's vocabulary matches the taxonomy"
```

---

### Task 4: Full gate, version bump and PR

**Files:**
- Modify: `DESCRIPTION` (lines 4 and its `Date`)
- Modify: `NEWS.md`
- Modify: `dev/specs/2026-08-29-template-conversion-roadmap-design.md`

**Interfaces:**
- Consumes: everything from Tasks 1 to 3.
- Produces: a PR against `main`.

- [ ] **Step 1: Run every guard**

```bash
python3 dev/specs/artifacts/check-spec-counts.py && python3 dev/specs/artifacts/check-flow-counts.py && python3 dev/specs/artifacts/check-roadmap-counts.py
```

Expected: three success lines, exit 0.

- [ ] **Step 2: Run lint and the full check**

```bash
Rscript -e 'lintr::lint_package()'
```

Expected: no output. `dev/` is not package source so nothing there is linted;
`tests/testthat/test-roadmap.R` is, and must be clean at 135 characters.

```bash
Rscript -e 'devtools::check()'
```

Expected: `0 errors | 0 warnings | 0 notes`. If a note names
`tests/testthat/test-roadmap.R`, fix the test — do not add a `.Rbuildignore`
entry, which would stop the test running on a built package entirely.

- [ ] **Step 3: Mark the design spec implemented**

In `dev/specs/2026-08-29-template-conversion-roadmap-design.md`, change the
header line:

```markdown
**Status:** designed, not started
```

to:

```markdown
**Status:** implemented 2026-08-29 — the ledger, renderer and both guards are
in place. The roadmap itself is `2026-08-29-template-conversion-roadmap.md`.
```

- [ ] **Step 4: Bump the version**

In `DESCRIPTION`, raise the patch digit (`1.0.9` → `1.0.10`) and set `Date` to
today. **Patch only** — the minor digit is the maintainer's decision, and this
adds no export.

In `NEWS.md`, add at the top, under a plain heading and with **no `Version:`
line**:

```markdown
# hvtiRtemplates 1.0.10

* Added the template conversion roadmap: a ledger of all 42 taxonomy prefixes
  plus three proposed ones, the roadmap document generated from it, and two CI
  guards that fail when the two disagree or when a row claims a template that
  is not on disk. Design and reasoning in
  `dev/specs/2026-08-29-template-conversion-roadmap-design.md`.
```

⚠️ If PR #44 (the SAS licence date correction) merged first and already took
`1.0.10`, use `1.0.11`. Check `git log origin/main -1 -- DESCRIPTION` before
choosing.

- [ ] **Step 5: Commit and open the PR**

```bash
git add DESCRIPTION NEWS.md dev/specs/2026-08-29-template-conversion-roadmap-design.md
git commit -m "chore: bump to 1.0.10 for the conversion roadmap"
git checkout -b feat/template-conversion-roadmap   # if not already on it
git push -u origin feat/template-conversion-roadmap
```

Then open the PR **against `main`**:

```bash
gh pr create --base main \
  --title "feat: the template conversion roadmap and its guards" \
  --body "Implements dev/specs/2026-08-29-template-conversion-roadmap-design.md.

Adds the ledger (45 prefixes: 42 taxonomy + rfr/sid/vt proposed), the renderer
that generates the roadmap document from it, and two CI guards -- Python for
what the filesystem can answer, testthat for what needs hvti_taxonomy().

No template, no export, no user-visible behaviour. Patch bump only.

Checks: devtools::check() 0/0/0; devtools::test() 93 pass; all three
dev/specs guards green."
```

⚠️ Do not stack this on another branch. The `protect main` ruleset fires
Copilot review only for a PR opened against `main`, and retargeting after a
parent merges does **not** re-trigger it.

- [ ] **Step 6: Verify the PR carries only this work**

```bash
gh api repos/ehrlinger/hvtiRtemplates/compare/main...feat/template-conversion-roadmap --jq '{ahead:.ahead_by, files:[.files[].filename]}'
```

Expected: only the files this plan names. If unrelated commits appear, you
branched off the wrong base — rebase with
`git rebase --onto origin/main <the-wrong-base-sha> feat/template-conversion-roadmap`
rather than opening the PR anyway.

---

## Self-review notes

**Spec coverage.** §4 ledger → Task 1. §5 Python guards 1–3 → Tasks 1 and 2.
§5 testthat guard 4 → Task 3. §3.5 workflow overlay → Task 2's renderer. The
roadmap document → Task 2.

**Deliberately not implemented here**, and each has its own future work: §6's
intake records (the `intake` array is seeded empty; source 1's library triage
is a separate piece of work), §3.4's `hvti_taxonomy()` PR for `rfr`/`sid`/`vt`
in `hvtiRutilities`, and every family design spec. This plan builds the
machinery, not the queue's contents.

**Known sharp edge.** `check-roadmap-counts.py` imports `roadmap_render`, so
the renderer is underscore-named while every sibling script here is hyphenated.
Task 2 Step 1 states that up front rather than leaving it to be discovered when
the import fails.
