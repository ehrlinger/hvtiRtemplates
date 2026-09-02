#!/usr/bin/env python3
"""Macro allocation scan. Ownership from named calls; %inc for reachability;
the FILE is the unit of allocation. See dev/specs/2026-08-14-macro-allocation-design.md."""
import re, os, glob, json, collections

MACRO_DIR = os.path.expanduser("~/Documents/macro.library")
TPL_ROOT  = os.path.expanduser("~/Documents/template")
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   "2026-08-14-macro-allocation.json")

OWNER = {}
for p in "bd vars dt".split():           OWNER[p] = "hvtiRdatabuild"
for p in "hp np lp dp fp cp gp".split(): OWNER[p] = "hvtiPlotR"
for p in "lm cm pm rm".split():          OWNER[p] = "hvtiRpropensity"
for p in "ac hz hs nd ce".split():       OWNER[p] = "TemporalHazard"
OWNER["dc"] = "hvtiRtables"
# Tier A - prefixes the map omitted from families it already assigns.
# hm: the template README defines it as the hazard model built on the HZ fit,
#     and hz/hs already go to TemporalHazard.
# mp: mixed-model plot; every other *p plot prefix is already hvtiPlotR.
# vars_base_only: a variant of vars, already mapped to hvtiRdatabuild.
OWNER["hm"] = "TemporalHazard"
OWNER["mp"] = "hvtiPlotR"
OWNER["vars_base_only"] = "hvtiRdatabuild"

# The bootstrap model-building family. One owner rather than a split by model
# type (bh -> TemporalHazard, bl -> hvtiRpropensity), because the prefixes
# are entangled: bootstrap.clusters.sas is reached from bh, bl and br, so a
# split would push it into hvtiRutilities as tier-2 "shared" -- a resampling
# engine separated from every model it serves. Splitting also buys little: bh
# alone unblocks 7 files, any other single prefix one or zero.
#
# NOTE bootstrap.summary.sas lands in hvtiRutilities REGARDLESS of this
# decision, and correctly: its prefixes are ac, bh, bl, bq, br, and ac is
# actuarial (TemporalHazard). It is shared beyond the bootstrap family, so
# tier 2 applies on its own merits. Do not read its placement as evidence
# against one-owner -- bootstrap.clusters.sas is the file this decision saved.
# bc is included though no template currently reaches it.
# mm/gm/nm are NOT included -- they are model families, not bootstrap, and
# remain owner-undetermined in the canonicalization spec.
for _p in ("bh", "bl", "bc", "bn", "br", "bq"):
    OWNER[_p] = "hvtiRbootstrap"

# Explicit file-level overrides, for destinations a human decides on grounds the
# call graph cannot see. Each carries a reason and is reported as tier
# "override" so it never looks like a derived result. Keep this list short: an
# override is an admission the rule does not cover a case, not a way to edit the
# map by hand.
FILE_OVERRIDE = {
    b: ("hvtiRlifetables",
        "replaced, not ported: hvtiRlifetables was scaffolded 2026-08-13 to "
        "reimplement %usmatchd in R and vendors this file in data-raw/sas. "
        "Prefix ownership sends it to TemporalHazard because hs templates "
        "name it, but the port has a different destination.")
    for b in ("usmatchd.sas", "usmatchd84.sas", "usmatchd10172003.sas",
              "usmtch08.sas", "uslife.sas")
}

strip = lambda s: re.sub(r'^\s*\*[^;]*;', ' ',
                        re.sub(r'/\*.*?\*/', ' ', s, flags=re.S), flags=re.M)
CALL = re.compile(r'%([A-Za-z_][A-Za-z0-9_]*)\s*[\(;]')
INC  = re.compile(r'"[^"]*!MACROS/([^"]+?)"', re.I)
TOK  = re.compile(r'%(macro)\s+([A-Za-z_][A-Za-z0-9_]*)|%(mend)\b', re.I)
KW = set("""macro mend if then else do end let put include inc global local sysfunc
eval str nrstr bquote nrbquote quote unquote upcase lowcase scan substr sysevalf
symdel symexist length index trim left right cmpres superq qsysfunc sysget syscall
return abort window display goto to by while until do_over""".split())
calls = lambda t: {n.lower() for n in CALL.findall(strip(t)) if n.lower() not in KW}

# A call resolves to a definition in the SAME file when one exists. Without
# this, a file calling a helper it defines itself (phcurv9.sas calls %numobs,
# which it defines) links to every other file defining that name. 117 of 272
# names are multiply defined, and this invented a phcurv9 <-> usmatchd cycle
# that does not exist in the source.
def bodies(txt):                      # FIX 3: per-%macro body, not per-file
    out, stack = [], []
    for m in TOK.finditer(txt):
        if m.group(1): stack.append((m.group(2).lower(), m.end()))
        elif stack:
            n, s = stack.pop(); out.append((n, txt[s:m.start()]))
    return out + [(n, txt[s:]) for n, s in stack]

files = sorted(glob.glob(f"{MACRO_DIR}/*.sas"))
canon = {os.path.basename(f).lower(): os.path.basename(f) for f in files}
fdefs, fcalls, fincs, bodycalls = {}, {}, {}, collections.defaultdict(set)
for f in files:
    b = os.path.basename(f); t = open(f, errors="replace").read()
    fdefs[b] = set(); fcalls[b] = set()
    for n, body in bodies(t):
        fdefs[b].add(n); c = calls(body)
        bodycalls[(b, n)] = c; fcalls[b] |= c
    fincs[b] = {canon[i.lower().strip()] for i in INC.findall(t)
                if i.lower().strip() in canon}
name2file = collections.defaultdict(set)      # FIX 4: keep ALL defining files
for b, ns in fdefs.items():
    for n in ns: name2file[n].add(b)

# ---- seeds: a template NAMING a macro states intent about that macro's file
seed = collections.defaultdict(set); tpl_n = 0; unknown = collections.Counter()
# recursive=True with **. The one-level glob missed 13 of the 244 template
# .sas files: ten under datasets/templates/transplant_mcs/ and three under an
# archive/ subdirectory. A scan that silently sees 95% of its input reports a
# confident allocation over an incomplete call graph.
for f in sorted(glob.glob(f"{TPL_ROOT}/*/templates/**/*.sas", recursive=True)):
    tpl_n += 1
    key  = os.path.relpath(f, TPL_ROOT)                       # FIX 2: full path
    pre  = os.path.basename(f).split(".")[1].lower() if os.path.basename(f).count(".") > 1 else "?"
    if pre not in OWNER: unknown[pre] += 1
    for n in calls(open(f, errors="replace").read()):
        for b in name2file.get(n, ()): seed[b].add(pre)

# ---- dependencies: NOT independently allocated; they travel with a dependent.
# Ownership deliberately does not propagate - inheriting owners from several
# dependents makes every shared dependency look like a utility, which is how an
# earlier draft mis-assigned usmatchd.sas away from TemporalHazard.
owners = {b: set(v) for b, v in seed.items()}
deps = collections.defaultdict(set)          # file -> seeded files that need it
for b in list(owners):
    stack = list(fincs[b] | {x for n in fcalls[b] - fdefs[b]
                             for x in name2file.get(n, ())})
    seen = set()
    while stack:
        nb = stack.pop()
        if nb in seen or nb == b: continue
        seen.add(nb)
        deps[nb].add(b)          # record for ALL files, seeded or not: a seeded
                                 # file can still be a dependency of another
                                 # package's file, and a port needs to see that
        stack += list(fincs[nb] | {x for n in fcalls[nb] - fdefs[nb]
                                   for x in name2file.get(n, ())})

alloc = collections.defaultdict(list); blocked = collections.Counter(); detail = {}
for b in sorted(fdefs):
    pres = owners.get(b, set())
    known = {OWNER[p] for p in pres if p in OWNER}
    unk   = sorted(p for p in pres if p not in OWNER)
    if   b in FILE_OVERRIDE:      dest, why = FILE_OVERRIDE[b]; tier = "override"
    elif not pres and b in deps:  dest = None; tier = "travels-with-dependent"
    elif not pres:                dest = None; tier = "corpus-only"
    elif unk and not known:       dest = None; tier = "blocked"
    elif len(known) == 1 and not unk: dest = next(iter(known)); tier = "single-owner"
    elif len(known) > 1:          dest = "hvtiRutilities"; tier = "shared"
    else:                         dest = None; tier = "blocked"
    if tier == "blocked":
        for p in unk: blocked[p] += 1
    alloc[dest or ("_" + tier)].append(b)
    detail[b] = {"destination": dest, "tier": tier,
                 **({"override_reason": why} if tier == "override" else {}),
                 "prefixes": sorted(pres), "unowned_prefixes": unk,
                 "macros": sorted(fdefs[b]), "seeded": b in seed,
                 "needed_by": sorted(deps.get(b, ()))}
# ---- cross-package dependency graph, EMITTED rather than left to a reader
# to count. The design note carried "19 file-level dependencies span 3 package
# pairs" from 2026-08-14 until 2026-09-02. It was right when written and went
# stale the same day, at 77734a9, which introduced hvtiRbootstrap and added 24
# edges across 2 more pairs without touching the sentence. Nothing caught it
# for nineteen days, because every other number in that document is anchored
# to this map and this one was prose. So the map now states it.
#
# An edge is one (dependent file, dependency file) pair whose two files are
# allocated to DIFFERENT packages. Files in _blocked, _corpus-only and
# _travels-with-dependent have no package, so they raise no edge.
xdep = collections.Counter()
for _b, _rec in detail.items():
    _src = _rec["destination"]
    for _dep in _rec["needed_by"]:
        _dst = detail.get(_dep, {}).get("destination")
        if _src and _dst and _src != _dst:
            xdep[(_dst, _src)] += 1          # dependent package -> dependency

# Acyclic is a claim the note makes, so it is checked rather than asserted.
# A spurious phcurv9 <-> usmatchd cycle was reported once already, at 8ad414c,
# and that one was between two FILES. So both graphs are checked: a package
# graph can be acyclic while the file graph under it is not, and reporting a
# single flag from the package graph alone would let exactly the historical
# failure pass. Raised by Copilot on #73.
def _acyclic(g):
    colour = {}
    def walk(u):
        colour[u] = 1
        for v in g.get(u, ()):
            if colour.get(v) == 1: return False
            if colour.get(v) is None and not walk(v): return False
        colour[u] = 2
        return True
    return all(walk(u) for u in list(g) if colour.get(u) is None)

_pkg_adj = collections.defaultdict(set)
for (_a, _b2) in xdep: _pkg_adj[_a].add(_b2)

# Every file-to-file edge, not only the cross-package ones: a cycle inside one
# package is still a cycle, and is what a porter would hit first.
_file_adj = collections.defaultdict(set)
for _b, _rec in detail.items():
    for _dep in _rec["needed_by"]:
        _file_adj[_dep].add(_b)

res = {"counts": {"macro_files": len(files), "macro_names": len(name2file),
                  "templates": tpl_n,
                  "allocated": sum(len(v) for k, v in alloc.items() if not k.startswith("_")),
                  "blocked": len(alloc["_blocked"]),
                  "travels_with_dependent": len(alloc["_travels-with-dependent"]),
                  "corpus_only": len(alloc["_corpus-only"])},
       "by_destination": {k: sorted(v) for k, v in sorted(alloc.items())},
       "cross_package_dependencies": {
           "n_dependencies": sum(xdep.values()),
           "n_package_pairs": len(xdep),
           "acyclic_packages": _acyclic(_pkg_adj),
           "acyclic_files": _acyclic(_file_adj),
           "edges": [{"dependent": a, "dependency": b2, "n": n}
                     for (a, b2), n in sorted(xdep.items(),
                                              key=lambda kv: (-kv[1], kv[0]))],
       },
       "blocked_by_prefix": dict(blocked.most_common()),
       "unknown_prefixes": dict(unknown.most_common()),
       "files": detail}
json.dump(res, open(OUT, "w"), indent=2)
print(json.dumps(res["counts"], indent=2))
print("\nby destination:")
for k, v in sorted(alloc.items()):
    if not k.startswith("_"): print(f"  {len(v):>4}  {k}")
print("\nground truths:")
for p in ["summarytable.sas", "usmatchd.sas", "plot.sas", "stddiff.sas"]:
    print(f"  {p:<20} -> {detail.get(p,{}).get('destination')}  ({detail.get(p,{}).get('tier')})")
