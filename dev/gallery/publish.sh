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
# slips through: the builder's home, username, and the macOS and Linux temp roots.
leak='/Users/|/home/|/private/tmp/|/private/var/|/var/folders/'
[ -n "${HOME:-}" ] && leak="$leak|$HOME"
user="${USER:-$(id -un)}"
# Between separators only: a bare match would refuse every gallery whose builder
# shares a name with a URL in it, as ehrlinger does with ehrlinger.github.io.
[ "${#user}" -ge 3 ] && leak="$leak|[/-]$user[/-]"
if hits="$(grep -rlE "$leak" "$site")"; then
  echo "Refusing to publish: these files name a local path or the user $user." >&2
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
