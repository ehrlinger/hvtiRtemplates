#!/usr/bin/env python3
"""Compare three claims about where each prefix lives.

The folder a file actually sits in, the prefix table in the study template's
README, and `hvti_taxonomy()`. Prints JSON on stdout; nothing is decided here.

Reads ~/Documents/template directly, and must: this package deliberately holds
no copy of the SAS corpus, so there is nothing in-repo to scan.
"""
import os, re, json, collections

TPL  = os.path.expanduser("~/Documents/template")
# The repository root, derived from this script's own location rather than
# hardcoded: the scan is committed here, so it must run from any clone.
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), os.pardir, os.pardir))
FOLDERS = ["datasets", "descriptive", "distributions", "analyses", "graphs", "documents"]

# --- A. where files ACTUALLY are (all extensions, not just .sas) -------------
actual = collections.defaultdict(collections.Counter)
NAME = re.compile(r"^tp\.([A-Za-z0-9_]+?)\.", re.I)
for folder in FOLDERS:
    tdir = os.path.join(TPL, folder, "templates")
    if not os.path.isdir(tdir):
        continue
    for dirpath, dirnames, filenames in os.walk(tdir):
        # skip archives: they record history, not current placement
        if "archive" in os.path.relpath(dirpath, tdir).split(os.sep):
            continue
        for name in filenames:
            m = NAME.match(name)
            if m:
                actual[m.group(1).lower()][folder] += 1

# --- B. the study README table ----------------------------------------------
readme = {}
txt = open(os.path.join(TPL, "README.md"), errors="replace").read()
for line in txt.splitlines():
    m = re.match(r"^\|\s*`([a-z]+)`(?:\s*/\s*`([a-z]+)`)?\s*\|.*\|\s*`([a-z]+)/`\s*\|", line)
    if m:
        readme[m.group(1)] = m.group(3)
        if m.group(2):
            readme[m.group(2)] = m.group(3)

# --- C. hvti_taxonomy() ------------------------------------------------------
tax, taxorder = {}, []
src = open(os.path.join(REPO, "R", "taxonomy.R"), errors="replace").read()
for m in re.finditer(r'c\(\s*(?:"([a-z]+)"|NA_character_)\s*,\s*"([^"]+)"\s*,\s*"([a-z]+)"\s*,\s*"([^"]+)"',
                     src):
    pfx, nm, folder, desc = m.group(1), m.group(2), m.group(3), m.group(4)
    key = pfx if pfx else "(none)"
    if pfx == "prefix" and folder == "folder":
        continue
    tax[key] = folder
    taxorder.append({"prefix": pfx, "name": nm, "folder": folder, "desc": desc})

rows = []
for r in taxorder:
    p = r["prefix"]
    a = dict(actual.get(p, {})) if p else {}
    rows.append({
        "prefix": p, "name": r["name"], "desc": r["desc"],
        "tax": r["folder"],
        "readme": readme.get(p),
        "actual": a,
        "n_files": sum(a.values()),
        "actual_main": (max(a, key=a.get) if a else None),
    })

def scattered(r):
    return len(r["actual"]) > 1

def verdict(r):
    if not r["prefix"]:            return "artifact-kind"
    if r["n_files"] == 0:          return "absent"
    claims = {r["tax"], r["actual_main"]} | ({r["readme"]} if r["readme"] else set())
    if len(claims) == 1:           return "agree"
    return "disagree"

for r in rows:
    r["verdict"] = verdict(r)
    r["scattered"] = scattered(r)

# prefixes that exist in the corpus but not in the taxonomy at all
known = {r["prefix"] for r in rows if r["prefix"]}
extra = {p: dict(c) for p, c in actual.items() if p not in known}

print(json.dumps({"rows": rows, "extra": extra,
                  "n_rows": len(rows),
                  "counts": collections.Counter(r["verdict"] for r in rows)}, indent=1, default=str))
