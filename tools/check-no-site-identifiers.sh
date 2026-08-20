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
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "not a git worktree — nothing to check" >&2; exit 2; }

PATTERNS=(
    'lri-[a-z0-9-]+\.lerner\.ccf\.org'   # internal CCF hosts (PPM, SAS, ...)
    '[a-z0-9-]+\.cchs\.net'              # internal CCF domain
    'ESQLPROD|ESQLPLDAG'                 # warehouse SQL Server instances
    '/home/ehrlinj|/Users/ehrlinj'       # developer home paths
)

status=0
for pat in "${PATTERNS[@]}"; do
    if hits="$(git grep -nIE "${pat}" -- ':!tools/check-no-site-identifiers.sh' 2>/dev/null)" \
       && [ -n "${hits}" ]; then
        echo "FAIL: site identifier committed (/${pat}/):"
        echo "${hits}" | sed 's/^/    /'
        status=1
    fi
done

[ "${status}" -eq 0 ] && echo "PASS: no site identifiers in tracked files" \
    || echo $'\nUse a placeholder (e.g. <internal-ppm-host>). This repo is public.'
exit "${status}"
