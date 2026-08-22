#!/usr/bin/env python3
"""Build the estimates-library read/write graph across the SAS study template.

A write is `data est.<member>`; a read is `set` / `data=` / `inhaz=` on one.
The member name is the only thing joining a writer to a reader, and nothing in
SAS checks it at either end -- which is the finding, not the counts.

An unmatched read is usually NOT a defect: the corpus is a library of examples
drawn from many studies, so the counterpart commonly lives in a study this scan
cannot see. Prints JSON on stdout.
"""
import os, re, json, collections

ROOT = os.path.expanduser("~/Documents/template")
FOLDERS = ["datasets", "descriptive", "distributions", "analyses", "graphs", "documents"]

WRITE = re.compile(r"\bdata\s+est\.([A-Za-z0-9_]+)", re.I)
READ  = re.compile(r"(?:\bset\s+|\bdata\s*=\s*|\binhaz\s*=\s*|\bindata\s*=\s*)est\.([A-Za-z0-9_]+)", re.I)
LIBRARY = re.compile(r"\b(?:set|data\s*=)\s*library\.([A-Za-z0-9_]+)", re.I)
VARS = re.compile(r"%vars\b", re.I)
PREFIX = re.compile(r"^tp\.([A-Za-z0-9_]+?)\.", re.I)

jobs = {}
for folder in FOLDERS:
    tdir = os.path.join(ROOT, folder, "templates")
    if not os.path.isdir(tdir):
        continue
    for name in sorted(os.listdir(tdir)):
        p = os.path.join(tdir, name)
        if not os.path.isfile(p) or not name.lower().endswith(".sas"):
            continue
        try:
            txt = open(p, errors="replace").read()
        except OSError:
            continue
        # strip the SAS comment convention *....; lines? keep it simple: keep all.
        m = PREFIX.match(name)
        jobs[f"{folder}/{name}"] = {
            "folder": folder,
            "prefix": (m.group(1).lower() if m else None),
            "writes": sorted(set(w.lower() for w in WRITE.findall(txt))),
            "reads":  sorted(set(r.lower() for r in READ.findall(txt))),
            "library": sorted(set(l.lower() for l in LIBRARY.findall(txt))),
            "vars": bool(VARS.search(txt)),
        }

writers = collections.defaultdict(list)
readers = collections.defaultdict(list)
for job, d in jobs.items():
    for w in d["writes"]:
        writers[w].append(job)
    for r in d["reads"]:
        readers[r].append(job)

dangling = {m: v for m, v in readers.items() if m not in writers}
orphan   = {m: v for m, v in writers.items() if m not in readers}
linked   = {m: {"w": writers[m], "r": readers[m]} for m in writers if m in readers}

out = {
    "n_jobs": len(jobs),
    "n_with_prefix": sum(1 for d in jobs.values() if d["prefix"]),
    "prefix_counts": dict(sorted(collections.Counter(
        d["prefix"] for d in jobs.values() if d["prefix"]).items())),
    "folder_counts": dict(sorted(collections.Counter(
        d["folder"] for d in jobs.values()).items())),
    "n_read_built": sum(1 for d in jobs.values() if "built" in d["library"]),
    "n_vars": sum(1 for d in jobs.values() if d["vars"]),
    "n_members_written": len(writers),
    "n_members_read": len(readers),
    "n_linked": len(linked),
    "n_dangling": len(dangling),
    "n_orphan": len(orphan),
    "linked": linked,
    "dangling": dangling,
    "orphan": orphan,
    "jobs": jobs,
}
print(json.dumps(out, indent=1))
