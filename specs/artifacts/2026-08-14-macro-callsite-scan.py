import re,os,glob,json,collections
MD=os.path.expanduser("~/Documents/macro.library"); TR=os.path.expanduser("~/Documents/template")
PKG={}
for p in "bd vars dt".split():              PKG[p]="hvtiRdatasets"
for p in "hp np lp dp fp cp gp".split():    PKG[p]="hvtiPlotR"
for p in "lm cm pm rm".split():             PKG[p]="hvtiPropensityScores"
for p in "ac hz hs nd ce".split():          PKG[p]="temporal_hazard"
for p in "mm gm bh bl bc nm".split():       PKG[p]="UNASSIGNED-modeling"
for p in "dc lg cd hm rf rfsrc mp".split(): PKG[p]="UNASSIGNED-no-owner"
sc=lambda s:re.sub(r'^\s*\*[^;]*;',' ',re.sub(r'/\*.*?\*/',' ',s,flags=re.S),flags=re.M)
callre=re.compile(r'%([A-Za-z_][A-Za-z0-9_]*)\s*[\(;]'); defre=re.compile(r'^\s*%macro\s+([A-Za-z_][A-Za-z0-9_]*)',re.I|re.M)
incre=re.compile(r'"[^"]*!MACROS/([^"]+?)"',re.I)          # filename ref "!MACROS/<file>"
KW=set("macro mend if then else do end let put include inc global local sysfunc eval str nrstr bquote nrbquote quote unquote upcase lowcase scan substr sysevalf symdel symexist length index trim left right cmpres superq qsysfunc sysget syscall return abort window display goto to by while until do_over".split())
calls=lambda t:{n.lower() for n in callre.findall(sc(t)) if n.lower() not in KW}

fname_by_lower={os.path.basename(f).lower():os.path.basename(f) for f in glob.glob(f"{MD}/*.sas")}
defs=collections.defaultdict(set); file_defs=collections.defaultdict(set); mcalls=collections.defaultdict(set); file_incs=collections.defaultdict(set)
for f in glob.glob(f"{MD}/*.sas"):
    b=os.path.basename(f); t=open(f,errors="replace").read()
    ns=[m.lower() for m in defre.findall(t)]
    for n in ns: defs[n].add(b); file_defs[b].add(n)
    c=calls(t)
    for n in ns: mcalls[n]|=c
    for inc in incre.findall(t):
        r=fname_by_lower.get(inc.lower().strip())
        if r: file_incs[b].add(r)
lib=set(defs)

tpl={}; unknown=collections.Counter()
for f in glob.glob(f"{TR}/*/templates/*.sas"):
    b=os.path.basename(f); parts=b.split("."); pre=parts[1].lower() if len(parts)>2 else "?"
    pkg=PKG.get(pre)
    if pkg is None: unknown[pre]+=1; pkg=f"UNKNOWN:{pre}"
    t=open(f,errors="replace").read()
    incs={fname_by_lower[i.lower().strip()] for i in incre.findall(t) if i.lower().strip() in fname_by_lower}
    tpl[b]=(pkg, calls(t)&lib, incs)

reach=collections.defaultdict(set); via=collections.defaultdict(set)
for b,(pkg,cs,incs) in tpl.items():
    seed=set(cs)|{n for fl in incs for n in file_defs[fl]}
    for n in seed: via[n].add("name" if n in cs else "inc")
    stack=list(seed); seen=set()
    while stack:
        m=stack.pop()
        if m in seen: continue
        seen.add(m); reach[m].add(pkg)
        for n in mcalls.get(m,()):
            if n in lib and n not in seen: stack.append(n)
        for fl in file_incs.get(next(iter(defs[m]),""),()):
            for n in file_defs[fl]:
                if n not in seen: stack.append(n)
called=set(reach); dead=sorted(lib-called)
res={"counts":{"macro_files":len(fname_by_lower),"macro_names":len(lib),"templates":len(tpl),
"reachable":len(called),"dead":len(dead),
"single":sum(1 for n in called if len(reach[n])==1),"shared":sum(1 for n in called if len(reach[n])>1)},
"unknown_prefixes":dict(unknown),
"macros":{n:{"pkgs":sorted(reach[n]),"files":sorted(defs[n]),"via":sorted(via.get(n,[]))} for n in sorted(called)},
"dead":dead}
json.dump(res,open(os.path.join(os.path.dirname(os.path.abspath(__file__)),"2026-08-14-macro-callsite-evidence.json"),"w"),indent=2)
print(json.dumps(res["counts"],indent=2))
print("\nspot-checks:")
for n in ["summarytable","stddiff","usmatchd","kaplan","adjsurv","corrtable","stst able".replace(" ","")]:
    e=res["macros"].get(n); print(f"  {n:<14}", "DEAD" if not e else f"{','.join(e['pkgs'])}  via={','.join(e['via']) or 'transitive'}")
