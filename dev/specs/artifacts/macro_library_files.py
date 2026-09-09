"""Which files in ~/Documents/macro.library are SAS source.

Shared by 2026-08-14-macro-allocation-scan.py and
2026-09-09-macro-component-scan.py so the two cannot drift apart on the
question of what the library IS. Both previously globbed `*.sas` and read
176 of the top level's 281 files; see
../2026-09-09-macro-library-coverage-erratum.md.

Discovery is a DENYLIST, not a `*.sas` allowlist, for two reasons measured
on 2026-09-09:

1. 105 top-level files carry no extension at all. 58 of them define macros
   (`kaplan` among them, which has no `.sas` twin anywhere), 8 are PROC
   MATRIX programs, and 38 are CMS/MVS job decks -- call sites, whose
   absence reports live macros as unreachable.
2. The library uses dots as WORD SEPARATORS, not as extension markers:
   `bl_ord.perc.ci.sas`, `std_coef.05012015.sas`, `deciles.hazard`,
   `lm.cprobs`. The token after the last dot is usually part of the name,
   so an extension allowlist encodes a convention the corpus never held.

The rule is a port of `hvtiRutilities:::.sas_source_files()` and its
`.NON_SOURCE_RE`, which shipped 2026-08-14 for this exact failure. Keep the
two in step: if one changes, change both, or the R and Python answers to
"what is the library" diverge silently.

Scope is the TOP LEVEL ONLY. The nine subdirectories -- `archive/`,
`tests/`, `macros_to_test/`, `repeat_test/` and the rest -- hold a further
79 `.sas` files and are deliberately out of scope. They are not the library
corpus, and including them would change what "library-only" MEANS rather
than correct it. `excluded_dirs()` reports them so the exclusion is visible
in the artifacts rather than silently absent.
"""
import os
import re

# Suffixes that never hold SAS source: logs, listings, documents, binary data
# sets, and numbered RCS backups (`kaplan.~1.1.1.1.~`). A trailing `~` is
# allowed on each so `run.log~` is recorded as non-source rather than as an
# editor backup, which would be true but misleading evidence.
NON_SOURCE_RE = re.compile(
    r"\.(log|lst|txt|doc|docx|pdf|ps|cgm|emf|wmf|png|jpg|gif|"
    r"sas7bdat|sas7bcat|bak|save|asv|xls|xlsx|csv|rtf|zip)~?$"
    r"|\.~[0-9.]+~$",
    re.I,
)


def source_files(macro_dir):
    """Top-level SAS source files in `macro_dir`, sorted, full paths.

    Anything surviving the denylist is handed to the caller's %macro reader.
    A file that turns out not to be SAS contributes no definitions and no
    calls, which is the same outcome as skipping it -- but it is skipped
    with its name in the artifact rather than in silence.
    """
    out = []
    for name in os.listdir(macro_dir):
        path = os.path.join(macro_dir, name)
        if os.path.isdir(path):
            continue
        if name.startswith("."):
            continue
        if NON_SOURCE_RE.search(name):
            continue
        out.append(path)
    return sorted(out)


def excluded_dirs(macro_dir):
    """`{name: n_source_files}` for immediate subdirectories, recursively
    counted. Reported, never scanned -- see the module docstring.

    Dot-directories are infrastructure of this clone, not corpus: `.git`'s
    loose objects carry no extension and so match no non-source suffix,
    which would report them as excluded SAS source.
    """
    out = {}
    for name in sorted(os.listdir(macro_dir)):
        path = os.path.join(macro_dir, name)
        if not os.path.isdir(path) or name.startswith("."):
            continue
        n = 0
        for root, dirs, files in os.walk(path):
            dirs[:] = [d for d in dirs if not d.startswith(".")]
            n += sum(1 for f in files
                     if not f.startswith(".") and not NON_SOURCE_RE.search(f))
        out[name] = n
    return out


if __name__ == "__main__":
    d = os.path.expanduser("~/Documents/macro.library")
    fs = source_files(d)
    ext = sum(1 for f in fs if f.lower().endswith(".sas"))
    print(f"{len(fs)} source files ({ext} .sas, {len(fs) - ext} other)")
    print("excluded dirs:", excluded_dirs(d))
