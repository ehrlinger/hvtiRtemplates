#!/usr/bin/env bash
# Publish a built template gallery for the pkgdown site.
#
#   bash dev/gallery/publish.sh [site folder]
#
# The site folder is what package.py wrote, pkgdown/assets/gallery by default.
# Its reports are about 25 MB, so they are not committed: this archives the
# folder and uploads it to the `gallery` release, replacing the archive there.
# The pkgdown workflow downloads it before building the site. The release is a
# prerelease, never marked latest, so it does not read as a package version.
set -euo pipefail
site="${1:-pkgdown/assets/gallery}"
[ -f "$site/index.html" ] && [ -f "$site/gallery-data.js" ] || {
  echo "No built gallery in $site; run gallery.R and package.py first." >&2; exit 1; }
# Nothing local goes up. A report that prints a path names the machine it was
# built on: on 2026-11-03 and again on 2026-11-06 sid-clusters printed the
# study's full path, and a build under a home-based scratch directory published
# the builder's username. Build in a temp directory, and let this refuse what
# slips through. A username leaks inside a path, so the check is on paths: home
# and temp roots, also in the dash-mangled form a scratch folder name takes
# (-Users-<name>-). Matching the bare username would refuse every gallery whose
# builder shares a name with a URL in it, as github.com/ehrlinger/ does.
leak='/Users/|/home/|-Users-|-home-|/tmp/|/var/tmp/|/private/tmp/|/private/var/|/var/folders/'
hits="$(grep -rlE "$leak" "$site" || true)"
# $HOME as fixed text: a directory name may hold regex syntax, such as [1].
if [ -n "${HOME:-}" ] && [ "$HOME" != "/" ]; then
  hits="$(printf '%s\n%s' "$hits" "$(grep -rlF "$HOME" "$site" || true)" | sed '/^$/d' | sort -u)"
fi
# Every report's run record names who rendered it. gallery.R sets both to
# "gallery"; a job re-rendered by hand outside it records the real user and
# host, as two did on 2026-11-06.
named="$(grep -rlE '"(user|host)":"' "$site" | while read -r f; do
  grep -oE '"(user|host)":"[^"]*"' "$f" | grep -qv ':"gallery"$' && echo "$f"; done || true)"
hits="$(printf '%s\n%s' "$hits" "$named" | sed '/^$/d' | sort -u)"
if [ -n "$hits" ]; then
  echo "Refusing to publish: these files name a local path, or a user or host other than gallery." >&2
  echo "$hits" | sed "s|^|  |" >&2
  echo "Rebuild in a temp directory, find what prints the path, and package again." >&2
  exit 1
fi
archive="$(mktemp -d)/gallery.tar.gz"
tar -czf "$archive" -C "$(dirname "$site")" "$(basename "$site")"
if ! gh release view gallery >/dev/null 2>&1; then
  gh release create gallery --prerelease --latest=false --title "Template gallery (site asset)" \
    --notes "The rendered template gallery for the pkgdown site. Not a package release: the pkgdown workflow downloads gallery.tar.gz from here. Rebuilt with dev/gallery/gallery.R, package.py and publish.sh."
fi
gh release upload gallery "$archive" --clobber
echo "Published $(du -h "$archive" | cut -f1) to the gallery release."
