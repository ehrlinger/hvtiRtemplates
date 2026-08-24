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


def sas_files(tdir):
    """Yield (dirpath, name) for every .sas file under tdir, archives excluded.

    Recursive on purpose. A flat listdir saw one level and missed 13 corpus
    files, 10 of them the current datasets/templates/transplant_mcs/ work, and
    it would have missed the next file dropped in a subdirectory just as
    quietly. Archives are skipped because they record history, not current
    flow -- the same rule, and the same relpath test, as
    2026-08-22-prefix-placement-scan.py. Two scans over one corpus must not
    disagree about what the corpus is.
    """
    for dirpath, dirnames, filenames in os.walk(tdir):
        if "archive" in os.path.relpath(dirpath, tdir).split(os.sep):
            continue
        for name in sorted(filenames):
            if name.lower().endswith(".sas"):
                yield dirpath, name


jobs = {}
for folder in FOLDERS:
    tdir = os.path.join(ROOT, folder, "templates")
    if not os.path.isdir(tdir):
        continue
    for dirpath, name in sas_files(tdir):
        p = os.path.join(dirpath, name)
        if not os.path.isfile(p):
            continue
        try:
            # Pinned, not left to the locale. Four corpus files carry non-ASCII
            # bytes in comment prose, and utf-8, cp1252 and ascii each decode
            # them differently -- the counts happen to survive that today
            # because the bytes sit away from any pattern, which is luck, not a
            # guarantee. CI now holds the diagrams to these numbers, so the
            # scan decodes the same way on every machine by construction.
            with open(p, encoding="utf-8", errors="replace") as fh:
                txt = fh.read()
        except OSError:
            continue
        # strip the SAS comment convention *....; lines? keep it simple: keep all.
        m = PREFIX.match(name)
        jobs[f"{folder}/{os.path.relpath(p, tdir)}"] = {
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

# A member is only a *handoff* when some reader is a different job from every
# writer. Most linked members are a job writing and re-reading its own dataset
# within one program, which couples nothing. The diagrams quote the handoff
# count, not the linked count, so it is computed here rather than by eye.
cross = {}
for m, v in linked.items():
    ws, rs = set(v["w"]), set(v["r"])
    other = sorted(rs - ws)
    if other:
        cross[m] = {"w": sorted(ws), "r": other}

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
    "n_cross_job": len(cross),
    "cross_job": cross,
    "n_dangling": len(dangling),
    "n_orphan": len(orphan),
    "linked": linked,
    "dangling": dangling,
    "orphan": orphan,
    "jobs": jobs,
}
print(json.dumps(out, indent=1))
