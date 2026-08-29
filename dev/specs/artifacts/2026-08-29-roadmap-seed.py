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
