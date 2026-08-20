#!/usr/bin/env bash
#
# check-no-site-identifiers.sh — fail if an internal hostname, warehouse
# instance, or developer path has been committed.
#
# WHY: this repository is PUBLIC. Design specs and plans quote real
# infrastructure while the work is being figured out — the internal Posit
# Package Manager host reached `specs/` exactly that way. `specs/` is
# .Rbuildignore'd, so it never ships in the package and a testthat guard
# would never see it; the only place this can be caught is CI over the repo.
#
# Usage: tools/check-no-site-identifiers.sh
# Exit:  0 = clean, 1 = identifier found, 2 = not a git worktree.

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

scan() {  # $1 = extended regex; prints matches, returns 1 when none
    if [ "${ENGINE}" = "git" ]; then
        git grep -nIE "$1" -- ":!${SELF}" 2>/dev/null
    else
        grep -rnIE --exclude-dir=.git --exclude="$(basename "${SELF}")" "$1" . 2>/dev/null
    fi
}

PATTERNS=(
    'lri-[a-z0-9-]+\.lerner\.ccf\.org'   # internal CCF hosts (PPM, SAS, ...)
    '[a-z0-9-]+\.cchs\.net'              # internal CCF domain
    'ESQLPROD|ESQLPLDAG'                 # warehouse SQL Server instances
    '/home/ehrlinj|/Users/ehrlinj'       # developer home paths
)

status=0
for pat in "${PATTERNS[@]}"; do
    if hits="$(scan "${pat}")" && [ -n "${hits}" ]; then
        echo "FAIL: site identifier committed (/${pat}/):"
        echo "${hits}" | sed 's/^/    /'
        status=1
    fi
done

[ "${status}" -eq 0 ] && echo "PASS: no site identifiers in tracked files" \
    || echo $'\nUse a placeholder (e.g. <internal-ppm-host>). This repo is public.'
exit "${status}"
