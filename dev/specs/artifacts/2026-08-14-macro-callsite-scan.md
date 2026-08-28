# Macro call-site scan - evidence

Generated 2026-08-14T16:39Z. Sources: `~/Documents/macro.library`
(180 files) and `~/Documents/template/*/templates` (229 `tp.*.sas`,
archives excluded). This is **evidence only** - no allocation is decided here.

## Method

Three edge types, all followed transitively:

1. **Named invocation** - `%name(` / `%name;` in a template, matched against `%macro name`
   definitions in the library.
2. **File include** - `filename ref "!MACROS/<file>.sas"` + `%inc ref`. This is the dominant
   edge: **200 of 229 templates use it**. A name-only scan misses it and reports
   most of the library as dead.
3. **Macro to macro** - both of the above, found inside library files.

Each template is attributed to a destination package by its `tp.<prefix>` per the
canonicalization map; that package then propagates to every macro the template can reach.

## Counts

| | |
|---|---|
| Macro files | 180 |
| Macro names defined | 270 |
| Templates scanned | 229 |
| Reachable from some template | **137** |
| Unreachable | **133** |
| Reaches exactly one package | 64 |
| Reaches two or more | 73 |

## Validation

Three independent checks that the method produces correct answers:

| Macro | Scan says | Known truth |
|---|---|---|
| `summarytable` | `dc` prefix (unassigned) | the macro `hvtiRtables` just ported - confirms the `dc` gap |
| `usmatchd` | `temporal_hazard` | matches the `hvtiRlifetables` handoff, which calls it a TemporalHazard wrapper |
| `kaplan` | 4 packages, shared | house survival primitive, plausibly shared |

## Caveat that changes how to read this

**Transitive reach inflates sharing.** Of the 73 macros reaching 2+ packages, large blocks
carry *identical* package fingerprints because they are helpers of one widely-called parent
(`%plot`, `%decompos`). They are not independently shared; they are parts of one component.
Allocate on **direct** edges and move a component as a unit - do not treat every helper of a
shared parent as separately shared.

## Unassigned and unknown prefixes

The map does not cover these. Templates exist for all of them:

- `bn` - 10 template(s)
- `imputsub` - 2 template(s)
- `ls` - 2 template(s)
- `br` - 2 template(s)
- `rg` - 2 template(s)
- `rp` - 2 template(s)
- `plots` - 2 template(s)
- `mult_imput_mcmc` - 1 template(s)
- `stxxxx_ccfpull` - 1 template(s)
- `stxxx_snapshotpull` - 1 template(s)
- `vars_base_only` - 1 template(s)
- `bd_sgroups` - 1 template(s)
- `mult_imput` - 1 template(s)
- `stxxxx_dwpull` - 1 template(s)
- `echo_readin` - 1 template(s)
- `bq` - 1 template(s)
- `test` - 1 template(s)
- `import` - 1 template(s)
- `export` - 1 template(s)

Plus the map's own `UNASSIGNED` groups: `dc lg cd hm rf rfsrc mp` (no owner) and
`mm gm bh bl bc nm` (modeling, owner undetermined).

## Macros reaching exactly one package (64)

Candidates for that package under a one-package-means-owner rule.


### UNASSIGNED-modeling (3)

`hazboot`, `hazbtcp`, `logitlasso`

### UNASSIGNED-no-owner (40)

`callfreq`, `cdfs1`, `combo`, `congytab`, `congytab82`, `contab`, `contab82`, `desc_tab`, `edt`, `edt1`, `edt2`, `edt3`, `edt3a`, `edt4`, `freq`, `freq1`, `freq_tab`, `freq_tab82`, `frgy_tab`, `frgy_tab82`, `haz_to_mi`, `lrtrend`, `mi_to_haz`, `mw_var`, `mxpredc`, `newlist`, `reorder`, `reorder2`, `reorder3`, `reorder4`, `sans`, `std_cof`, `std_dif`, `stddiffci`, `stdz`, `summarytable`, `trunc`, `tx`, `var_sdif`, `vexist`

### UNKNOWN:bn (2)

`bnmnr`, `bnmnr_gr`

### UNKNOWN:bq (1)

`bootqr`

### UNKNOWN:ls (4)

`expdobsdplot`, `getref`, `stsratiopval`, `ststable`

### UNKNOWN:rp (1)

`linregm`

### hvtiPlotR (1)

`lgt_nom`

### hvtiRdatasets (4)

`gmatch`, `greedy`, `max1`, `repeatxt`

### temporal_hazard (8)

`botregwt`, `cifcp`, `cind_haz`, `greenwod`, `hazplot`, `nelsont`, `sample`, `usmatchd`


## Macros reaching two or more packages (73)

Shared by the proposed rule - but read the transitive caveat first.

| macro | packages | via |
|---|---|---|
| `_by` | UNASSIGNED-modeling, UNASSIGNED-no-owner, UNKNOWN:ls, UNKNOWN:rp, UNKNOWN:vars_base_only, hvtiPlotR, hvtiRdatasets, temporal_hazard | inc |
| `_id` | UNASSIGNED-modeling, UNASSIGNED-no-owner, UNKNOWN:ls, UNKNOWN:rp, UNKNOWN:vars_base_only, hvtiPlotR, hvtiRdatasets, temporal_hazard | inc |
| `_label` | UNASSIGNED-modeling, UNASSIGNED-no-owner, UNKNOWN:ls, UNKNOWN:rp, UNKNOWN:vars_base_only, hvtiPlotR, hvtiRdatasets, temporal_hazard | inc |
| `_plot` | UNASSIGNED-modeling, UNASSIGNED-no-owner, UNKNOWN:ls, UNKNOWN:rp, UNKNOWN:vars_base_only, hvtiPlotR, hvtiRdatasets, temporal_hazard | inc |
| `_scan_` | UNASSIGNED-modeling, UNASSIGNED-no-owner, UNKNOWN:ls, UNKNOWN:rp, UNKNOWN:vars_base_only, hvtiPlotR, hvtiRdatasets, temporal_hazard | inc |
| `_uscan_` | UNASSIGNED-modeling, UNASSIGNED-no-owner, UNKNOWN:ls, UNKNOWN:rp, UNKNOWN:vars_base_only, hvtiPlotR, hvtiRdatasets, temporal_hazard | inc |
| `adj_symb` | UNASSIGNED-modeling, UNASSIGNED-no-owner, UNKNOWN:ls, UNKNOWN:rp, UNKNOWN:vars_base_only, hvtiPlotR, hvtiRdatasets, temporal_hazard | inc |
| `axis` | UNASSIGNED-modeling, UNASSIGNED-no-owner, UNKNOWN:ls, UNKNOWN:rp, UNKNOWN:vars_base_only, hvtiPlotR, hvtiRdatasets, temporal_hazard | inc |
| `axisspec` | hvtiRdatasets, temporal_hazard | transitive |
| `bld_anno` | UNASSIGNED-modeling, UNASSIGNED-no-owner, UNKNOWN:ls, UNKNOWN:rp, UNKNOWN:vars_base_only, hvtiPlotR, hvtiRdatasets, temporal_hazard | inc |
| `bldano_c` | UNASSIGNED-no-owner, UNKNOWN:rp, hvtiPlotR, temporal_hazard | inc |
| `bnprev` | UNASSIGNED-modeling, UNKNOWN:bn | name |
| `bootreg` | UNASSIGNED-modeling, UNKNOWN:br | name |
| `bootsens` | UNASSIGNED-modeling, UNASSIGNED-no-owner | transitive |
| `bounds` | UNASSIGNED-modeling, UNASSIGNED-no-owner, UNKNOWN:ls, UNKNOWN:rp, UNKNOWN:vars_base_only, hvtiPlotR, hvtiRdatasets, temporal_hazard | inc |
| `bounds1` | UNASSIGNED-no-owner, UNKNOWN:rp, hvtiPlotR, temporal_hazard | inc |
| `break` | UNASSIGNED-modeling, UNKNOWN:bn, hvtiPlotR | inc |
| `cluster` | UNASSIGNED-modeling, UNKNOWN:br | name |
| `connect` | UNASSIGNED-modeling, UNASSIGNED-no-owner, UNKNOWN:ls, UNKNOWN:rp, UNKNOWN:vars_base_only, hvtiPlotR, hvtiRdatasets, temporal_hazard | inc |
| `dcom` | UNASSIGNED-modeling, UNKNOWN:bn, hvtiPlotR | transitive |
| `dcom1` | UNASSIGNED-modeling, UNKNOWN:bn, hvtiPlotR | inc |
| `dcom2` | UNASSIGNED-modeling, UNKNOWN:bn, hvtiPlotR | inc |
| `decompos` | UNASSIGNED-modeling, UNKNOWN:bn, hvtiPlotR, temporal_hazard | inc, name |
| `dij` | UNASSIGNED-modeling, UNASSIGNED-no-owner, hvtiRdatasets | transitive |
| `dist` | hvtiRdatasets, temporal_hazard | name |
| `doit` | hvtiRdatasets, temporal_hazard | transitive |
| `dummy` | UNASSIGNED-modeling, UNASSIGNED-no-owner, UNKNOWN:ls, UNKNOWN:rp, UNKNOWN:vars_base_only, hvtiPlotR, hvtiRdatasets, temporal_hazard | inc |
| `errm1` | hvtiRdatasets, temporal_hazard | transitive |
| `f` | UNASSIGNED-modeling, UNKNOWN:bn, hvtiPlotR | inc |
| `g` | UNASSIGNED-modeling, UNKNOWN:bn, hvtiPlotR | inc |
| `goption` | UNASSIGNED-modeling, UNASSIGNED-no-owner, UNKNOWN:ls, UNKNOWN:rp, UNKNOWN:vars_base_only, hvtiPlotR, hvtiRdatasets, temporal_hazard | inc |
| `greedmtch` | UNASSIGNED-modeling, UNASSIGNED-no-owner | transitive |
| `initcc` | UNASSIGNED-modeling, UNASSIGNED-no-owner | transitive |
| `inv` | UNASSIGNED-modeling, UNASSIGNED-no-owner, UNKNOWN:vars_base_only, hvtiRdatasets | name |
| `kaplan` | UNASSIGNED-modeling, UNASSIGNED-no-owner, hvtiPlotR, temporal_hazard | name |
| `labl_pos` | UNASSIGNED-modeling, UNASSIGNED-no-owner, UNKNOWN:ls, UNKNOWN:rp, UNKNOWN:vars_base_only, hvtiPlotR, hvtiRdatasets, temporal_hazard | inc |
| `lbls` | UNASSIGNED-modeling, UNASSIGNED-no-owner, hvtiRdatasets | transitive |
| `lgrpargs` | hvtiRdatasets, temporal_hazard | transitive |
| `lmakespl` | hvtiRdatasets, temporal_hazard | transitive |
| `ln` | UNKNOWN:vars_base_only, hvtiRdatasets | name |
| `logistc` | UNASSIGNED-modeling, UNKNOWN:bn, hvtiPlotR | name |
| `lstep8` | hvtiRdatasets, temporal_hazard | transitive |
| `match` | UNASSIGNED-modeling, UNASSIGNED-no-owner | transitive |
| `mknowinout` | hvtiRdatasets, temporal_hazard | transitive |
| `mrg` | UNASSIGNED-modeling, UNKNOWN:bn, hvtiPlotR | inc, name |
| `mrg0` | UNASSIGNED-modeling, UNKNOWN:bn | name |
| `mrg1` | UNASSIGNED-modeling, UNKNOWN:bn | name |
| `mrg2` | UNASSIGNED-modeling, UNKNOWN:bn | name |
| `mrg3` | UNASSIGNED-modeling, UNKNOWN:bn | name |
| `nelsonl` | UNASSIGNED-modeling, UNASSIGNED-no-owner, hvtiPlotR, hvtiRdatasets, temporal_hazard | name |
| `numargs` | hvtiRdatasets, temporal_hazard | transitive |
| `numobs` | hvtiRdatasets, temporal_hazard | inc |
| `ord_ci` | UNASSIGNED-modeling, UNKNOWN:bn, hvtiPlotR | name |
| `plot` | UNASSIGNED-modeling, UNASSIGNED-no-owner, UNKNOWN:ls, UNKNOWN:rp, UNKNOWN:vars_base_only, hvtiPlotR, hvtiRdatasets, temporal_hazard | inc, name |
| `probest` | UNASSIGNED-modeling, UNKNOWN:bn, hvtiPlotR | inc |
| `psplerr` | hvtiRdatasets, temporal_hazard | transitive |
| `pstep8` | hvtiRdatasets, temporal_hazard | transitive |
| `repeat` | UNASSIGNED-modeling, UNASSIGNED-no-owner, hvtiPlotR, hvtiRdatasets, temporal_hazard | name |
| `sens` | UNASSIGNED-modeling, UNASSIGNED-no-owner | transitive |
| `set_size` | UNASSIGNED-modeling, UNASSIGNED-no-owner, UNKNOWN:ls, UNKNOWN:rp, UNKNOWN:vars_base_only, hvtiPlotR, hvtiRdatasets, temporal_hazard | inc |
| `skip` | UNASSIGNED-modeling, UNASSIGNED-no-owner | inc |
| `skkip` | UNASSIGNED-modeling, UNKNOWN:br, temporal_hazard | inc |
| `sortcc` | UNASSIGNED-modeling, UNASSIGNED-no-owner | transitive |
| `stddiff` | UNASSIGNED-modeling, UNASSIGNED-no-owner | transitive |
| `sumboot` | UNASSIGNED-modeling, UNKNOWN:bq, UNKNOWN:br, temporal_hazard | name |
| `token` | UNASSIGNED-modeling, UNASSIGNED-no-owner, UNKNOWN:ls, UNKNOWN:rp, UNKNOWN:vars_base_only, hvtiPlotR, hvtiRdatasets, temporal_hazard | inc |
| `trends` | UNASSIGNED-modeling, UNASSIGNED-no-owner, UNKNOWN:vars_base_only, hvtiRdatasets | transitive |
| `varindat` | hvtiRdatasets, temporal_hazard | transitive |
| `vbles` | UNASSIGNED-modeling, UNASSIGNED-no-owner, hvtiRdatasets | transitive |
| `vls1` | hvtiRdatasets, temporal_hazard | transitive |
| `vls1i` | hvtiRdatasets, temporal_hazard | transitive |
| `vls1p` | hvtiRdatasets, temporal_hazard | transitive |
| `vmatch` | hvtiRdatasets, temporal_hazard | transitive |


## Unreachable from any template (133)

Not called by name and not `%inc`-ed by any template, directly or transitively. Corpus-only
under the proposed rule - but confirm against study code before discarding: this scan sees
templates, not the study programs copied from them.

`adjsurv`, `appdel`, `append`, `apploop`, `appnd`, `areakey`, `areakey_b`, `baseinfo`, `baseout`, `bl_delci`, `bl_gen`, `blord`, `brier`, `compcif`, `compcp`, `debug`, `distcomp`, `distincp`, `doit2`, `dydx`, `ex`, `findit`, `form01`, `formtf`, `getbc`, `hello`, `hlmrsq`, `ice`, `indexc`, `init`, `inline`, `iterate`, `jpmatchd`, `kap_tvc`, `lgtphcurv9`, `lmmodel1`, `lmmodel2`, `loadredcapdata`, `loop`, `max2`, `merge`, `mixcorr`, `mixed`, `model`, `myquant`, `nelson2`, `nelsonb`, `nelsong`, `nlin`, `nlinmix`, `np_ice`, `numder`, `optimal`, `ord_ci1`, `ord_ci2`, `plots`, `pseudoder`, `rep`, `rocplot`, `sgpie`, `std_cof2`, `std_df4g`, `stspred`, `uprep`, `uslife`, `usmtch08`, `vescode`, `vls2`, `vls2i`, `vls2p`, `whatever`, `xbug`, `xbugdo`, `xbylist`, `xchkdata`, `xchkdef`, `xchkdefv`, `xchkdsn`, `xchkech`, `xchkend`, `xchkeq`, `xchkerr`, `xchkint`, `xchkkey`, `xchklist`, `xchkmiss`, `xchkname`, `xchknum`, `xchkone`, `xchkuint`, `xchkvar`, `xconcat`, `xdelete`, `xdo_by`, `xdo_obs`, `xdsinfo`, `xecho`, `xend_by`, `xend_obs`, `xeq`, `xerrmisc`, `xerrset`, `xfloat`, `xice`, `xinit`, `xlag`, `xlagfq`, `xlagfqi`, `xlagfqr`, `xlagi`, `xlagr`, `xls2sas`, `xmacinc`, `xmain`, `xmerge`, `xname`, `xnobs`, `xnoisy`, `xnotes`, `xnvar`, `xput`, `xquiet`, `xrepstr`, `xreptok`, `xscan`, `xsubstr`, `xterm`, `xverify`, `xvfreq`, `xvlist`, `xvweight`, `xxbug`, `zuk`

