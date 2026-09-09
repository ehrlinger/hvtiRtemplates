#!/usr/bin/env python3
"""Macro component emitter. Dominator-based components, direct-edge majority.

Supersedes the ALLOCATION half of 2026-08-14-macro-allocation-scan.py, not its
parsing: the macro-library reader below is that script's, kept deliberately
identical so a difference in the output is a difference in the RULE and not in
how a %macro body was read.

Two things change:

1. The corpus. 2026-08-14 read ~/Documents/template (229 legacy `tp.*.sas`
   templates). This reads the STUDIES corpus, where jobs are named
   `<prefix>.<variable>[.<qualifier>].<ext>` and `tp.` is the legacy template
   marker. The template folder is a curated sample; the studies are the
   population, and "133 of 270 macros unreachable" is a fact about the sample.

2. The unit. 2026-08-14 allocated per FILE and let a dependency "travel with a
   dependent" unallocated. This allocates per COMPONENT, where a component is a
   subtree of the dominator tree rooted at ROOT's children. A helper reachable
   only through %plot is dominated by plot.sas and moves with it; a helper a job
   can reach directly, or reach by two independent paths, is its own component
   and is allocated on its own votes. That is what makes the hvtiRutilities sink
   an OUTPUT of the method rather than a curated exception list.

Usage:
    ./2026-09-09-macro-component-scan.py [--corpus PATH] [--out PATH] [--limit N]

--corpus defaults to the resolved qhsstudies mount. Pointing it at
~/Documents/template is a supported dry run: the prefix reader accepts both
naming conventions, so the emitter can be exercised while the share is
unmounted. The output records which corpus it read.
"""
import argparse, collections, glob, json, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import macro_library_files
# $MACROS first -- the same fileref SAS and the corpus use -- then the
# workstation default. See macro_library_files.macro_dir().
MACRO_DIR = macro_library_files.macro_dir()

# Distinct studies below which a corpus is a sample, not the population.
# The template dry run yields a handful; the studies corpus yields thousands.
# Set well below the real figure so a partial mount is still caught, and well
# above anything the template folder can produce.
MIN_POPULATION_STUDIES = 50

# ---------------------------------------------------------------- prefix owners
#
# NOT hvtiR's jobs.json. That catalog's `destination` is who owes the TEMPLATE
# JOB, and it reads "hvtiRtemplates" on 42 of its 55 rows -- voting macro
# ownership through it sends four fifths of the library to one package and
# returns a full, plausible allocation over a vote that never varied. What is
# needed here is the DOMAIN owner, which is this map, carried forward verbatim
# from 2026-08-14-macro-allocation-scan.py. Disagreement with the catalog's
# `replaced_by` is reported (see owner_map_vs_catalog) rather than resolved
# silently in either direction.
OWNER = {}
for _p in "bd vars dt".split():           OWNER[_p] = "hvtiRdatabuild"
for _p in "hp np lp dp fp cp gp mp".split(): OWNER[_p] = "hvtiPlotR"
for _p in "lm cm pm rm".split():          OWNER[_p] = "hvtiRpropensity"
for _p in "ac hz hs nd ce hm".split():    OWNER[_p] = "TemporalHazard"
for _p in "bh bl bc bn br bq".split():    OWNER[_p] = "hvtiRbootstrap"
OWNER["dc"] = "hvtiRtables"
OWNER["vars_base_only"] = "hvtiRdatabuild"

# hvtiR is the routing table, not a code home: it imports only cli/jsonlite/utils
# and nothing imports it, deliberately, so jobs() can load a destination package
# to validate a routing without suggesting its own dependents. A macro allocated
# into it would invert that. Enforced, not documented.
NEVER_A_DESTINATION = {"hvtiR"}

# Dependency edges that already exist, read from DESCRIPTION on 2026-09-09.
# Used only to label a required package edge as new or existing -- a component
# whose callers sit below it needs a NEW Imports edge, and that is the cost this
# allocation actually imposes on the family.
EXISTING_DEPS = {
    "hvtiRtemplates": {"hvtiRutilities", "hvtiRbootstrap"},
    "hvtiRdatabuild": {"hvtiRutilities"},
    "hvtiRlifetables": {"TemporalHazard"},
}
# CRAN packages cannot declare a dependency on a GitHub-only package: CRAN
# requires every dependency to resolve on CRAN/Bioconductor and does not accept
# Remotes:. So an edge OUT of one of these is not a dependency anyone can write,
# and is reported as a boundary violation rather than as a new edge.
CRAN_PACKAGES = {"TemporalHazard", "ggRandomForests", "ggBoostedTrees", "ggsankey"}

JOB_EXT = (".sas",)
JOB_FOLDERS = {"analyses", "datasets", "descriptive", "distributions",
               "documents", "graphs"}
PRUNE = {"estimates", "archive", ".git", "__pycache__", "output", "outputs"}

# ------------------------------------------------------------------- SAS reader
# Verbatim from 2026-08-14. Do not "improve": the per-%macro body split at
# bodies() is what stops a file that calls a helper it defines itself from
# linking to every other file defining that name (117 of 272 names are multiply
# defined, and a whole-file split invented a phcurv9 <-> usmatchd cycle).
strip = lambda s: re.sub(r'^\s*\*[^;]*;', ' ',
                         re.sub(r'/\*.*?\*/', ' ', s, flags=re.S), flags=re.M)
CALL = re.compile(r'%([A-Za-z_][A-Za-z0-9_]*)\s*[\(;]')
INC = re.compile(r'"[^"]*!MACROS/([^"]+?)"', re.I)
TOK = re.compile(r'%(macro)\s+([A-Za-z_][A-Za-z0-9_]*)|%(mend)\b', re.I)
KW = set("""macro mend if then else do end let put include inc global local sysfunc
eval str nrstr bquote nrbquote quote unquote upcase lowcase scan substr sysevalf
symdel symexist length index trim left right cmpres superq qsysfunc sysget syscall
return abort window display goto to by while until do_over""".split())
calls = lambda t: {n.lower() for n in CALL.findall(strip(t)) if n.lower() not in KW}


def bodies(txt):
    out, stack = [], []
    for m in TOK.finditer(txt):
        if m.group(1):
            stack.append((m.group(2).lower(), m.end()))
        elif stack:
            n, s = stack.pop()
            out.append((n, txt[s:m.start()]))
    return out + [(n, txt[s:]) for n, s in stack]


def read_library():
    # Denylist, NOT `*.sas`. This line read glob(f"{MACRO_DIR}/*.sas")
    # on the emitter's first run (2026-09-09) and inherited the
    # 2026-08-14 defect verbatim along with the reader: 176 files of
    # 310. `kaplan` -- the shared house survival primitive -- has no
    # `.sas` twin and was invisible to both. See
    # ../2026-09-09-macro-library-coverage-erratum.md.
    files = macro_library_files.source_files(MACRO_DIR)
    if not files:
        sys.exit(f"FATAL: no SAS source under {MACRO_DIR}")
    canon = {os.path.basename(f).lower(): os.path.basename(f) for f in files}
    fdefs, fcalls, fincs = {}, {}, {}
    for f in files:
        b = os.path.basename(f)
        t = open(f, errors="replace").read()
        fdefs[b], fcalls[b] = set(), set()
        for n, body in bodies(t):
            fdefs[b].add(n)
            fcalls[b] |= calls(body)
        fincs[b] = {canon[i.lower().strip()] for i in INC.findall(t)
                    if i.lower().strip() in canon}
    name2file = collections.defaultdict(set)
    for b, ns in fdefs.items():
        for n in ns:
            name2file[n].add(b)
    return files, canon, fdefs, fcalls, fincs, name2file


# -------------------------------------------------------------------- the walk
def resolve_corpus(explicit):
    if explicit:
        return os.path.expanduser(explicit)
    # The mount name changes across remounts (/Volumes/qhsstudies vs
    # -1); a hard-coded spelling fails as a bare "No such file or directory",
    # which reads as "the corpus is gone" rather than as a mount problem.
    try:
        out = subprocess.run(["mount"], capture_output=True, text=True).stdout
    except OSError:
        out = ""
    for line in out.splitlines():
        m = re.search(r'\son (/Volumes/[^ ]*qhs[^ ]*) ', line, re.I)
        if m:
            return m.group(1)
    # On the server the corpus is not a mount at all -- it is the local
    # tree the workstation sees THROUGH that mount. Checking it after the
    # mount scan keeps the workstation behaviour unchanged while letting the
    # staged copy run with no arguments, which is how the other scans on
    # /studies/general are run.
    if os.path.isdir("/studies"):
        return "/studies"
    sys.exit("FATAL: no corpus found and no --corpus given.\n"
             "       On a workstation: check `mount | grep -i qhs`.\n"
             "       On the server: /studies does not exist.\n"
             "       Pass --corpus ~/Documents/template for a dry run against\n"
             "       the legacy template folder.")


def job_prefix(basename):
    """<prefix>.<variable>...  in the corpus; tp.<prefix>.<variable>... legacy."""
    parts = basename.split(".")
    if len(parts) < 2:
        return None
    if parts[0].lower() == "tp":
        return parts[1].lower() if len(parts) > 2 else None
    return parts[0].lower()


def walk_jobs(root, limit):
    """os.scandir recursion, never find(1).

    find is unusable on this share at ANY depth -- every entry costs a network
    stat and a -maxdepth 4 run over one topic returned nothing in 250s. scandir
    is one directory read per directory, which is what ls does and is fast.
    """
    seen = 0
    stack = [(root, 0)]
    while stack:
        d, depth = stack.pop()
        if depth > 8:
            continue
        try:
            entries = list(os.scandir(d))
        except OSError:
            continue
        for e in entries:
            name = e.name
            if name.startswith(".") or name.lower() in PRUNE:
                continue
            try:
                is_dir = e.is_dir(follow_symlinks=False)
            except OSError:
                continue
            if is_dir:
                stack.append((e.path, depth + 1))
            elif name.lower().endswith(JOB_EXT):
                yield e.path, name
                seen += 1
                if limit and seen >= limit:
                    return
                if seen % 2000 == 0:
                    print(f"  ... {seen} job files", file=sys.stderr)


def study_id(path, root):
    """Stable id for a study, NEVER its name.

    The census provenance rule is counts only: no path, study name, filename
    stem or patient identifier leaves this script. A study is the directory
    above the taxonomy folder when there is one, else the file's directory.
    """
    d = os.path.dirname(path)
    if os.path.basename(d).lower() in JOB_FOLDERS:
        d = os.path.dirname(d)
    return hash(os.path.relpath(d, root)) & 0xFFFFFFFF


# --------------------------------------------------------------- the dominators
def dominators(succ, root):
    """Cooper-Harvey-Kennedy. Returns idom over nodes reachable from root."""
    order, seen = [], {root}
    stack = [(root, iter(succ.get(root, ())))]
    while stack:                                   # iterative postorder
        u, it = stack[-1]
        for v in it:
            if v not in seen:
                seen.add(v)
                stack.append((v, iter(succ.get(v, ()))))
                break
        else:
            order.append(stack.pop()[0])
    rpo = order[::-1]
    num = {n: i for i, n in enumerate(rpo)}
    preds = collections.defaultdict(set)
    for u in rpo:
        for v in succ.get(u, ()):
            if v in num:
                preds[v].add(u)
    idom = {root: root}

    def intersect(a, b):
        while a != b:
            while num[a] > num[b]:
                a = idom[a]
            while num[b] > num[a]:
                b = idom[b]
        return a

    changed = True
    while changed:
        changed = False
        for b in rpo:
            if b == root:
                continue
            new = None
            for p in preds[b]:
                if p in idom:
                    new = p if new is None else intersect(p, new)
            if new is not None and idom.get(b) != new:
                idom[b] = new
                changed = True
    return idom


def component_root(node, idom, root):
    """The child-of-ROOT that dominates this node -- the unit that moves."""
    seen = set()
    while idom.get(node) not in (root, None) and node not in seen:
        seen.add(node)
        node = idom[node]
    return node


# ---------------------------------------------------------------------- the run
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--corpus")
    # Which edges SEED the graph -- i.e. which make a macro file a component
    # root. Voting is unaffected: a root is always scored on both edge types.
    #
    # %inc is a LOAD, not a USE. A job that includes plot.sas plus its six
    # helpers but only ever writes %plot(...) states one intent and raises seven
    # ROOT edges, and every helper escapes its parent's dominance. Measured
    # 2026-09-09 on the template corpus: seed=both gives 95 components of which
    # 2 have more than one member -- the component rule is inert. So the default
    # is `call`: intent forms components, %inc still traverses them.
    ap.add_argument("--seed", choices=("call", "inc", "both"), default="call")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--out", default=os.path.join(HERE, "2026-09-09-macro-components.json"))
    a = ap.parse_args()

    files, canon, fdefs, fcalls, fincs, name2file = read_library()
    root_dir = resolve_corpus(a.corpus)
    if not os.path.isdir(root_dir):
        sys.exit(f"FATAL: corpus root {root_dir} is not a directory")
    print(f"library: {len(files)} files, {len(name2file)} names", file=sys.stderr)
    print(f"corpus:  {root_dir}", file=sys.stderr)

    # ---- direct job -> macro-file edges. Direct only: no transitive closure.
    call_sites = collections.Counter()                     # (file, pkg) -> n
    studies = collections.defaultdict(set)                 # (file, pkg) -> {study}
    inc_sites = collections.Counter()                      # (file, pkg) -> n
    ambiguous = 0
    n_jobs = n_attributed = 0
    # Per-prefix rollups. Prefix level ONLY: a corpus job filename carries a
    # clinical variable in its stem, so no basename is retained here.
    pre_jobs = collections.Counter()
    pre_studies = collections.defaultdict(set)
    pre_macros = collections.defaultdict(set)
    unknown_prefix = collections.Counter()
    outside_folder = 0
    for path, base in walk_jobs(root_dir, a.limit):
        n_jobs += 1
        if os.path.basename(os.path.dirname(path)).lower() not in JOB_FOLDERS:
            outside_folder += 1
        pre = job_prefix(base)
        pkg = OWNER.get(pre)
        if pkg is None:
            unknown_prefix[pre or "?"] += 1
            continue
        n_attributed += 1
        sid = study_id(path, root_dir)
        pre_jobs[pre] += 1
        pre_studies[pre].add(sid)
        try:
            txt = open(path, errors="replace").read()
        except OSError:
            continue
        for n in calls(txt):
            hits = name2file.get(n, ())
            if len(hits) > 1:
                ambiguous += 1
            for b in hits:
                call_sites[(b, pkg)] += 1
                studies[(b, pkg)].add(sid)
                pre_macros[pre].add(b)
        for i in INC.findall(txt):
            b = canon.get(i.lower().strip())
            if b:
                inc_sites[(b, pkg)] += 1
                studies[(b, pkg)].add(sid)
                pre_macros[pre].add(b)

    if n_jobs == 0:
        sys.exit(f"FATAL: walked {root_dir} and found no .sas job files. "
                 "An empty walk produces an allocation over nothing.")
    if n_attributed == 0:
        sys.exit(f"FATAL: {n_jobs} job files, none with a prefix in OWNER. "
                 f"Top unrecognised: {unknown_prefix.most_common(5)}")

    seed_src = {"call": list(call_sites),
                "inc": list(inc_sites),
                "both": list(call_sites) + list(inc_sites)}[a.seed]
    seeded = {b for (b, _p) in seed_src}
    if not seeded:
        sys.exit("FATAL: no macro file was reached by any job.")

    # ---- graph: ROOT -> seeded files, then direct file -> file edges
    ROOT = "\0ROOT"
    succ = collections.defaultdict(set)
    succ[ROOT] = set(seeded)
    for b in fdefs:
        out = set(fincs[b])
        for n in fcalls[b] - fdefs[b]:              # a call it does not define
            out |= name2file.get(n, set())
        succ[b] = {x for x in out if x != b}

    idom = dominators(succ, ROOT)
    comp = {b: component_root(b, idom, ROOT) for b in idom if b != ROOT}
    members = collections.defaultdict(list)
    for b, c in comp.items():
        members[c].append(b)

    # ---- allocate: direct-edge majority, on DISTINCT STUDIES.
    #
    # Studies, not call sites: one study that runs the same job forty times
    # would otherwise outvote forty studies that run it once. Call-site counts
    # are emitted beside the vote so the reader can see which carried it.
    #
    # By construction a non-root member of a component has NO direct job edge --
    # if a job called it directly it would have a ROOT edge and be its own
    # component root. So the component's votes are exactly its root's votes,
    # and nothing is being propagated from a dependent here.
    detail, alloc = {}, collections.defaultdict(list)
    for c, mem in members.items():
        votes = {p: len(s) for (b, p), s in studies.items() if b == c}
        total = sum(votes.values())
        top, top_n = (max(votes.items(), key=lambda kv: (kv[1], kv[0]))
                      if votes else (None, 0))
        if not votes:
            dest, tier = None, "unreached"
        elif top in NEVER_A_DESTINATION:
            dest, tier = None, "blocked-never-a-destination"
        elif top_n * 2 > total:
            dest, tier = top, "majority"
        else:
            dest, tier = "hvtiRutilities", "shared-no-majority"
        for b in mem:
            alloc[dest or ("_" + tier)].append(b)
            detail[b] = {
                "component": c, "is_component_root": b == c,
                "destination": dest, "tier": tier,
                "votes_studies": dict(sorted(votes.items(), key=lambda kv: -kv[1])),
                "n_studies": total,
                "majority_share": round(top_n / total, 3) if total else None,
                "direct_call_sites": {p: n for (x, p), n in call_sites.items() if x == c},
                "direct_inc_sites": {p: n for (x, p), n in inc_sites.items() if x == c},
                "macros": sorted(fdefs.get(b, ())),
                "n_component_members": len(mem),
            }
    for b in sorted(fdefs):
        if b not in detail:
            detail[b] = {"component": None, "is_component_root": False,
                         "destination": None, "tier": "library-only",
                         "votes_studies": {}, "n_studies": 0,
                         "macros": sorted(fdefs[b])}
            alloc["_library-only"].append(b)

    # ---- component -> component edges, and the package edges they imply
    cedge = collections.Counter()
    for b, outs in succ.items():
        if b == ROOT or b not in comp:
            continue
        for v in outs:
            if v in comp and comp[v] != comp[b]:
                cedge[(comp[b], comp[v])] += 1
    pkg_adj = collections.defaultdict(set)
    pkg_edges = collections.Counter()
    for (x, y), n in cedge.items():
        dx, dy = detail[x]["destination"], detail[y]["destination"]
        if dx and dy and dx != dy:
            pkg_adj[dx].add(dy)
            pkg_edges[(dx, dy)] += n

    def acyclic(g):
        colour = {}

        def walk(u):
            colour[u] = 1
            for v in g.get(u, ()):
                if colour.get(v) == 1:
                    return False
                if colour.get(v) is None and not walk(v):
                    return False
            colour[u] = 2
            return True
        return all(walk(u) for u in list(g) if colour.get(u) is None)

    edges = []
    for (dependent, dependency), n in sorted(pkg_edges.items(), key=lambda kv: -kv[1]):
        edges.append({
            "dependent": dependent, "dependency": dependency, "n_file_edges": n,
            "already_declared": dependency in EXISTING_DEPS.get(dependent, ()),
            # A CRAN package cannot declare this at all -- see CRAN_PACKAGES.
            "cran_boundary_violation": dependent in CRAN_PACKAGES,
        })

    # ---- the catalog: one row per prefix, joining WHERE THE TEMPLATE LANDS to
    # WHERE ITS MACROS LAND. These are two different questions with two
    # different authorities, and conflating them is the trap this scan started
    # from:
    #   template/job destination -> hvtiR's jobs.json `destination` (who owes
    #       the R job that replaces the SAS template)
    #   macro destination        -> this scan (who owns the domain primitive)
    # A row is backlog-ready when its job destination is known AND every macro
    # component it reaches has a destination.
    cat_path = os.environ.get("HVTI_JOBS") or os.path.expanduser(
        "~/Documents/GitHub/hvtiR/inst/extdata/jobs.json")
    catalog_rows, cat_by_prefix = [], {}
    try:
        for r in json.load(open(cat_path))["jobs"]:
            cat_by_prefix.setdefault(r["prefix"], r)
    except (OSError, KeyError, ValueError):
        cat_by_prefix = {}
    for pre in sorted(set(pre_jobs) | set(OWNER)):
        cat = cat_by_prefix.get(pre, {})
        comps, blocked_on, needs = {}, [], set()
        owner = OWNER.get(pre)
        for b in sorted(pre_macros.get(pre, ())):
            c = comp.get(b)
            if c is None:
                continue
            rec = detail[c]
            comps[c] = {"destination": rec["destination"], "tier": rec["tier"],
                        "n_members": rec.get("n_component_members", 1)}
            if rec["destination"] is None:
                blocked_on.append(c)
            elif owner and rec["destination"] != owner:
                needs.add(rec["destination"])
        cran_block = sorted(n for n in needs if owner in CRAN_PACKAGES)
        catalog_rows.append({
            "prefix": pre,
            "domain_owner": owner,
            "job_destination": cat.get("destination"),
            "job_disposition": cat.get("disposition"),
            "job_status": cat.get("status"),
            "folder": cat.get("folder"),
            "n_jobs": pre_jobs.get(pre, 0),
            "n_studies": len(pre_studies.get(pre, ())),
            "n_macro_components": len(comps),
            "macro_components": comps,
            "needs_dependency_on": sorted(needs),
            "cran_boundary_blocked_on": cran_block,
            "blocked_on_unallocated": sorted(blocked_on),
            "backlog_ready": bool(owner and cat.get("destination")
                                  and not blocked_on and not cran_block),
        })

    # ---- is the VOTE strong enough to be read as an allocation?
    #
    # A majority over one study is not a majority, it is one job's habit wearing
    # a percentage. The template dry run produces exactly this -- a full,
    # plausible by_destination table over a denominator of 1 -- which is the
    # shape of defect this package exists to refuse. So the denominator is
    # reported, and a thin one marks the allocation provisional in the file
    # itself rather than in a reader's memory of how it was run.
    denom = sorted(r["n_studies"] for r in detail.values()
                   if r["destination"] and r["is_component_root"])
    med = denom[len(denom) // 2] if denom else 0

    # "Is this the population?" is a question about what was READ, not about
    # what the path is called.
    #
    # This tested `"qhs" not in root_dir.lower()` until 2026-09-09 -- the
    # WORKSTATION mount name. On the server the same corpus is /studies, so
    # the first real run stamped itself "OTHER -- dry run, not the
    # population" after walking 215,708 job files across 1,000+ studies. The
    # heuristic failed at the one place the real run happens, which is the
    # only place it mattered.
    #
    # The structural difference is the study count. The template dry run is
    # one flat folder of 244 files and yields a handful of studies; the
    # population yields thousands. That is also the quantity the vote
    # actually rests on, so it is the honest thing to gate on.
    n_studies = len({sid for sids in pre_studies.values() for sid in sids})
    thin_corpus = n_studies < MIN_POPULATION_STUDIES
    provisional = (med < 3) or thin_corpus
    trust = {
        "allocation_provisional": provisional,
        "median_studies_per_allocated_component": med,
        "max_studies_per_allocated_component": denom[-1] if denom else 0,
        "n_components_voted_by_one_study": sum(1 for d in denom if d <= 1),
        "distinct_studies": n_studies,
        "population_threshold": MIN_POPULATION_STUDIES,
        "reason": ("read the machinery, not the allocation: "
                   + ("; ".join(filter(None, [
                       "median vote denominator < 3 studies" if med < 3 else "",
                       f"only {n_studies} distinct studies, below the "
                       f"{MIN_POPULATION_STUDIES} that separates the "
                       f"population from a dry run" if thin_corpus else "",
                   ]))) if provisional else "vote denominator is adequate"),
    }

    # ---- fail loud: an allocation whose vote never varied is the house defect
    dests = {r["destination"] for r in detail.values() if r["destination"]}
    if len(dests) < 2:
        sys.exit(f"FATAL: every allocated component resolved to {dests or 'nothing'}. "
                 "A vote that does not vary is not a measurement -- check the "
                 "OWNER map and the corpus prefix parse before trusting this.")

    # ---- does the OWNER map disagree with the catalog's replaced_by?
    disagree = []
    try:
        for r in json.load(open(cat_path))["jobs"]:
            named = {x.split("::")[0] for x in (r.get("replaced_by") or [])}
            mine = OWNER.get(r["prefix"])
            if named and mine and mine not in named:
                disagree.append({"prefix": r["prefix"], "owner_map": mine,
                                 "catalog_replaced_by": sorted(named)})
    except (OSError, KeyError, ValueError) as e:
        disagree = [{"error": f"catalog not read: {e}"}]

    res = {
        "_provenance": {
            "generated_by": os.path.basename(__file__),
            "corpus_root_kind": ("population" if not thin_corpus
                                 else "THIN -- dry run, not the population"),
            "rule": "dominator components; direct-edge majority on distinct studies",
            "seed_edges": a.seed,
            "identifiers": "counts only. No path, study name, filename stem or "
                           "patient identifier leaves this script.",
            "supersedes_allocation_in": "2026-08-14-macro-allocation.json",
        },
        "counts": {
            "macro_files": len(files), "macro_names": len(name2file),
            "job_files_walked": n_jobs, "job_files_attributed": n_attributed,
            "job_files_outside_known_folder": outside_folder,
            "macro_files_seeded": len(seeded),
            "macro_files_reached": len(comp),
            "macro_files_library_only": len(alloc["_library-only"]),
            "components": len(members),
            "components_multi_member": sum(1 for m in members.values() if len(m) > 1),
            "ambiguous_name_edges": ambiguous,
        },
        "by_destination": {k: sorted(v) for k, v in sorted(alloc.items())},
        "package_dependencies": {
            "acyclic": acyclic(pkg_adj),
            "n_new_edges": sum(1 for e in edges if not e["already_declared"]
                               and not e["cran_boundary_violation"]),
            "n_cran_boundary_violations": sum(1 for e in edges
                                              if e["cran_boundary_violation"]),
            "edges": edges,
        },
        "allocation_trust": trust,
        "catalog": catalog_rows,
        "catalog_counts": {
            "rows": len(catalog_rows),
            "backlog_ready": sum(1 for r in catalog_rows if r["backlog_ready"]),
            "no_domain_owner": sum(1 for r in catalog_rows if not r["domain_owner"]),
            "no_job_destination": sum(1 for r in catalog_rows if not r["job_destination"]),
            "blocked_on_unallocated": sum(1 for r in catalog_rows
                                          if r["blocked_on_unallocated"]),
            "cran_boundary_blocked": sum(1 for r in catalog_rows
                                         if r["cran_boundary_blocked_on"]),
        },
        "owner_map_vs_catalog": disagree,
        "unknown_prefixes": dict(unknown_prefix.most_common(30)),
        "files": detail,
    }
    json.dump(res, open(a.out, "w"), indent=2)
    print(json.dumps(res["counts"], indent=2))
    print("\nby destination:")
    for k, v in sorted(alloc.items()):
        print(f"  {len(v):>4}  {k}")
    print(f"\npackage graph acyclic: {res['package_dependencies']['acyclic']}"
          f"  new edges: {res['package_dependencies']['n_new_edges']}"
          f"  cran violations: {res['package_dependencies']['n_cran_boundary_violations']}")
    if trust["allocation_provisional"]:
        print(f"\n*** PROVISIONAL: {trust['reason']}. "
              f"median vote denominator = {trust['median_studies_per_allocated_component']} "
              f"study/studies. Do not quote by_destination as an allocation. ***")
    cc = res["catalog_counts"]
    print(f"\ncatalog: {cc['rows']} prefixes, {cc['backlog_ready']} backlog-ready, "
          f"{cc['no_domain_owner']} without a domain owner, "
          f"{cc['no_job_destination']} without a job destination, "
          f"{cc['cran_boundary_blocked']} CRAN-boundary blocked")
    print(f"\nwrote {a.out}")


if __name__ == "__main__":
    main()
