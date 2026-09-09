"""Which files in the macro library are SAS source, and where the library is.

Shared by 2026-08-14-macro-allocation-scan.py and
2026-09-09-macro-component-scan.py so the two cannot drift apart on the
question of what the library IS. Both previously globbed `*.sas` and read
176 of the top level's 310 source files; see
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
163 source files under this same rule, and are deliberately out of scope.
(79 of those end in `.sas`; quoting that figure was the extension
assumption again, one directory down.) They are not the library
corpus, and including them would change what "library-only" MEANS rather
than correct it. `excluded_dirs()` reports them so the exclusion is visible
in the artifacts rather than silently absent.
"""
import os
import re
import sys

# Default for a workstation checkout. The server sets $MACROS.
DEFAULT_MACRO_DIR = "~/Documents/macro.library"


def macro_dir():
    """Where the macro library is, `$MACROS` first.

    `MACROS` is not an invented name: it is the SAS fileref the corpus
    itself uses, and the one this scan's own `%inc` reader parses out of
    `filename ref "!MACROS/<file>.sas"`. So a job, a SAS session and this
    scan all resolve the library through the same variable, and a server
    that has already set it for SAS needs no second setting for us.

    Falls back to the workstation path so a local run still works with
    nothing exported. A `$MACROS` that is set but does not exist is a hard
    error rather than a fallback: silently reading a different library than
    the operator asked for is the failure this whole module exists to stop.
    """
    env = os.environ.get("MACROS")
    if env:
        path = os.path.expanduser(os.path.expandvars(env))
        # A trailing separator is the normal shape of this value in the wild
        # -- the server exports it that way -- and it reads fine: listdir()
        # accepts it and os.path.join() tolerates the doubled separator. The
        # case that does NOT read is a SAS fileref CONCATENATION, "(a b)",
        # which names several directories at once and is not a path at all.
        #
        # The check LISTS the directory rather than asking os.path.isdir(),
        # which answers a different question: isdir() is true of a directory
        # this process cannot open, and the failure then surfaces from the
        # first source_files() call as a bare PermissionError traceback
        # instead of the message below. On a share with its own auth that is
        # the likely failure, not a typo in the path.
        try:
            os.listdir(path)
        except OSError as exc:
            sys.exit(
                f"FATAL: $MACROS is set to {env!r}, which is not a readable "
                f"directory.\n"
                f"       Resolved to: {path}\n"
                f"       {type(exc).__name__}: {exc.strerror or exc}\n"
                f"       Unset it to fall back to {DEFAULT_MACRO_DIR}, or "
                f"point it at the library root."
            )
        return path
    return os.path.expanduser(DEFAULT_MACRO_DIR)

# Suffixes that never hold SAS source: logs, listings, documents, binary data
# sets, and numbered RCS backups (`kaplan.~1.1.1.1.~`). A trailing `~` is
# allowed on each so `run.log~` is recorded as non-source rather than as an
# editor backup, which would be true but misleading evidence.
# A filename ending in `~` is an editor backup, whatever precedes it. This
# clause is separate from the suffix list on purpose: that list allows a
# trailing `~` on the suffixes it NAMES (`run.log~`), which is a different
# rule and does not catch `plot.sas~`.
#
# Found 2026-09-09 by the first server run. The workstation copy of the
# library carries no backups, so the gap was invisible locally and appeared
# only against the real library -- 25 of them, counted as source. The shipped
# R rule shares this gap and does not suffer from it, because sas_triage()
# runs a rule ladder AFTER discovery that drops editor backups with recorded
# evidence. This port kept the denylist and dropped the ladder, so nothing
# else was going to catch them.
EDITOR_BACKUP_RE = re.compile(r"~$")

NON_SOURCE_RE = re.compile(
    r"\.(log|lst|txt|doc|docx|pdf|ps|cgm|emf|wmf|png|jpg|gif|"
    r"sas7bdat|sas7bcat|bak|save|asv|xls|xlsx|csv|rtf|zip)~?$"
    r"|\.~[0-9.]+~$",
    re.I,
)


def describe_dir(path):
    """A form of `path` safe to write into a tracked artifact.

    This repository is PUBLIC and `tools/check-no-site-identifiers.sh` fails
    the build on a committed developer home path. Reporting the scoping
    basis beside a count is right, but the resolved path is the one part of
    that basis nobody outside needs and CI will not accept: on a
    workstation it is literally `/Users/<name>/...`.

    So $HOME contracts to `~`, and anything still matching the guard's
    class pattern degrades to its basename. What survives is what the
    reader actually needs -- which library, reached how -- without the
    account name.
    """
    home = os.path.expanduser("~")
    if path == home or path.startswith(home + os.sep):
        return "~" + path[len(home):]
    if re.search(r"(/home/|/Users/|\\Users\\)[^/\\]+[/\\]", path):
        return os.path.basename(path.rstrip("/\\"))
    return path


def source_files(macro_dir):
    """Top-level SAS source files in `macro_dir`, sorted, full paths.

    Anything surviving the denylist is handed to the caller's %macro reader.
    A file that turns out not to be SAS contributes no definitions and no
    calls, which is the same outcome as skipping it -- but it is skipped
    with its name in the artifact rather than in silence.

    A DUPLICATE is deliberately not dropped. `Copy of dist.sas` is real
    macro source that happens to be a second copy, and this corpus is full
    of per-study and per-year variants; taking their union and exposing the
    differences as arguments is the house rule. Filtering one out here would
    settle that question in the wrong place. It is a variant to reconcile,
    not noise to remove.
    """
    out = []
    for name in os.listdir(macro_dir):
        path = os.path.join(macro_dir, name)
        if os.path.isdir(path):
            continue
        if name.startswith("."):
            continue
        if NON_SOURCE_RE.search(name) or EDITOR_BACKUP_RE.search(name):
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
                     if not f.startswith(".")
                     and not NON_SOURCE_RE.search(f)
                     and not EDITOR_BACKUP_RE.search(f))
        out[name] = n
    return out


if __name__ == "__main__":
    d = macro_dir()
    print("library:", d)
    fs = source_files(d)
    ext = sum(1 for f in fs if f.lower().endswith(".sas"))
    print(f"{len(fs)} source files ({ext} .sas, {len(fs) - ext} other)")
    print("excluded dirs:", excluded_dirs(d))
