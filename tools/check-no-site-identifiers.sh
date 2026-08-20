#!/usr/bin/env bash
#
# check-no-site-identifiers.sh — fail if an internal hostname, warehouse
# instance, or developer path has been committed.
#
# WHY: this repository is PUBLIC. Design specs and plans quote real
# infrastructure while the work is being figured out — the internal Posit
# Package Manager host reached `specs/` exactly that way. `specs/` is
# .Rbuildignore'd, so it never ships in the package and a testthat guard would
# never see it; the only place this can be caught is CI over the repo.
#
# THIS FILE NAMES NOTHING INTERNAL, BY DESIGN. An earlier version listed the
# real SQL instance names and developer home paths as literal patterns —
# publishing, in a tracked file of a public repo, the very strings a history
# rewrite had just been run to remove. A guard must not be the leak. Every
# pattern below matches a CLASS, so it names nothing and also catches a host,
# account or instance nobody has enumerated.
#
# Kept in step with the guard in ehrlinger/hazard. That repo additionally
# checks its capture corpus structurally (`.meta` / `.lst` provenance fields);
# this repo has no such corpus, so the class patterns are the whole scan.
#
# Usage: tools/check-no-site-identifiers.sh
# Exit:  0 = clean
#        1 = an identifier was found
#        2 = environment/setup failure (cannot cd, no scan engine)
#        3 = the guard itself is disarmed (a pattern was rewritten away)

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

# Scan tracked files via `git grep` when git is usable, else fall back to a
# plain recursive grep over the worktree. Kept identical to the guard in
# ehrlinger/hazard, where a git-dependent version broke the Windows MSYS2 job:
# a check that cannot run somewhere is worse than useless. A CI checkout has no
# untracked files, so the two engines see the same set.
SELF="tools/check-no-site-identifiers.sh"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    ENGINE="git"
else
    ENGINE="grep"
    echo "note: git unavailable — scanning the worktree directly" >&2
fi

# Exit status is meaningful and must be preserved: grep returns 0 for
# "matched", 1 for "no match", and >1 for a real error (invalid regex,
# unreadable tree). Do NOT redirect stderr away here — the caller captures it,
# and an error that cannot be seen is an error that reads as "clean".
scan() {  # $1 = extended regex. 0 = matches, 1 = none, >1 = error
    if [ "${ENGINE}" = "git" ]; then
        git grep -nIE "$1" -- ":!${SELF}"
    else
        grep -rnIE --exclude-dir=.git --exclude="$(basename "${SELF}")" "$1" .
    fi
}

# Class patterns — each matches a category, never a specific site value.
#   1. any host under the organisation's INTERNAL domains. Deliberately not
#      bare `ccf.org`: public-facing addresses under that domain are legitimate
#      in citations. The leading class also excludes an `@`, so mail addresses
#      do not trip it.
#   2. warehouse SQL Server instances, by naming convention rather than name.
#   3. any developer home directory, POSIX or Windows — not one person's.
#      Verified against this tree: zero matches, so it costs no false positives
#      here (the sibling hazard repo cannot use this one — it carries ~71
#      legacy SAS logs full of a historic /home path).
PATTERNS=(
    '(^|[^@A-Za-z0-9._-])[a-z0-9-]+\.(lerner\.ccf\.org|cchs\.net)'
    'ESQL[A-Z0-9]{2,}'
    '(/home/|/Users/|\\Users\\)[a-z][A-Za-z0-9_.-]*'
)

# Public, citable URLs that may legitimately appear in docs and must not fail
# the scan. ERE has no negative lookahead, so allowlisting is a second pass
# over the hits rather than part of the pattern.
ALLOW='www\.lerner\.ccf\.org'

# Guard the guard. A `git filter-repo --replace-text` rewrite treats this file
# like any other and can rewrite a pattern into a placeholder — which happened
# on 2026-08-20, turning two of the four patterns here into '<redacted-*>'
# while the scan went on reporting PASS. Class patterns are far less exposed
# (they contain no site literal to replace), but the check costs nothing and
# the failure it prevents is silent.
for pat in "${PATTERNS[@]}"; do
    case "${pat}" in
        *'<redacted'*|*'<internal-'*|*'<path-to'*)
            echo "FATAL: pattern '${pat}' has been replaced by a redaction placeholder." >&2
            echo "       This scan cannot detect what it was written to detect." >&2
            echo "       Restore the class patterns (see git history) before relying on it." >&2
            exit 3
            ;;
    esac
done

status=0
errfile="$(mktemp)"
trap 'rm -f "${errfile}"' EXIT

for pat in "${PATTERNS[@]}"; do
    # This file necessarily describes what it guards — scan() excludes it.
    raw="$(scan "${pat}" 2>"${errfile}")"
    rc=$?
    case "${rc}" in
        0)
            hits="$(printf '%s\n' "${raw}" | grep -vE "${ALLOW}")" || hits=""
            if [ -n "${hits}" ]; then
                echo "FAIL: site identifier committed (/${pat}/):"
                echo "${hits}" | sed 's/^/    /'
                status=1
            fi
            ;;
        1)  ;;   # no matches — the good case
        *)
            # A scan that errored has NOT proved the tree clean. Treating this
            # like "no match" is how a guard silently stops guarding.
            echo "ERROR: scan failed for /${pat}/ (exit ${rc}) — tree NOT verified:"
            sed 's/^/    /' "${errfile}"
            status=1
            ;;
    esac
done

if [ "${status}" -eq 0 ]; then
    echo "PASS: no site identifiers in tracked files"
else
    echo $'\nUse a placeholder (e.g. <internal-ppm-host>). This repo is public.'
fi
exit "${status}"
