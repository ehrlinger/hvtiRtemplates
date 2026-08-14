#!/usr/bin/env python3
"""Macro allocation scan. Ownership from named calls; %inc for reachability;
the FILE is the unit of allocation. See specs/2026-08-14-macro-allocation-design.md."""
import re, os, glob, json, collections

MACRO_DIR = os.path.expanduser("~/Documents/macro.library")
TPL_ROOT  = os.path.expanduser("~/Documents/template")
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   "2026-08-14-macro-allocation.json")

OWNER = {}
for p in "bd vars dt".split():           OWNER[p] = "hvtiRdatasets"
for p in "hp np lp dp fp cp gp".split(): OWNER[p] = "hvtiPlotR"
for p in "lm cm pm rm".split():          OWNER[p] = "hvtiPropensityScores"
for p in "ac hz hs nd ce".split():       OWNER[p] = "temporal_hazard"
OWNER["dc"] = "hvtiRtables"

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
for f in sorted(glob.glob(f"{TPL_ROOT}/*/templates/*.sas")):
    tpl_n += 1
    key  = os.path.relpath(f, TPL_ROOT)                       # FIX 2: full path
    pre  = os.path.basename(f).split(".")[1].lower() if os.path.basename(f).count(".") > 1 else "?"
    if pre not in OWNER: unknown[pre] += 1
    for n in calls(open(f, errors="replace").read()):
        for b in name2file.get(n, ()): seed[b].add(pre)

# ---- dependencies: NOT independently allocated; they travel with a dependent.
# Ownership deliberately does not propagate - inheriting owners from several
# dependents makes every shared dependency look like a utility, which is how an
# earlier draft mis-assigned usmatchd.sas away from temporal_hazard.
owners = {b: set(v) for b, v in seed.items()}
deps = collections.defaultdict(set)          # file -> seeded files that need it
for b in list(owners):
    stack = list(fincs[b] | {x for n in fcalls[b] for x in name2file.get(n, ())})
    seen = set()
    while stack:
        nb = stack.pop()
        if nb in seen or nb == b: continue
        seen.add(nb)
        if nb not in owners: deps[nb].add(b)
        stack += list(fincs[nb] | {x for n in fcalls[nb] for x in name2file.get(n, ())})

alloc = collections.defaultdict(list); blocked = collections.Counter(); detail = {}
for b in sorted(fdefs):
    pres = owners.get(b, set())
    known = {OWNER[p] for p in pres if p in OWNER}
    unk   = sorted(p for p in pres if p not in OWNER)
    if   not pres and b in deps:  dest = None; tier = "travels-with-dependent"
    elif not pres:                dest = None; tier = "corpus-only"
    elif unk and not known:       dest = None; tier = "blocked"
    elif len(known) == 1 and not unk: dest = next(iter(known)); tier = "single-owner"
    elif len(known) > 1:          dest = "hvtiRutilities"; tier = "shared"
    else:                         dest = None; tier = "blocked"
    if tier == "blocked":
        for p in unk: blocked[p] += 1
    alloc[dest or ("_" + tier)].append(b)
    detail[b] = {"destination": dest, "tier": tier,
                 "prefixes": sorted(pres), "unowned_prefixes": unk,
                 "macros": sorted(fdefs[b]), "seeded": b in seed,
                 "needed_by": sorted(deps.get(b, ()))}
res = {"counts": {"macro_files": len(files), "macro_names": len(name2file),
                  "templates": tpl_n,
                  "allocated": sum(len(v) for k, v in alloc.items() if not k.startswith("_")),
                  "blocked": len(alloc["_blocked"]),
                  "travels_with_dependent": len(alloc["_travels-with-dependent"]),
                  "corpus_only": len(alloc["_corpus-only"])},
       "by_destination": {k: sorted(v) for k, v in sorted(alloc.items())},
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
