"""Package a gallery build for publishing.

    python3 dev/gallery/package.py <study root> <output folder>

Each rendered report is self-contained, so all 30 carry their own copy of the
same Quarto stylesheets and scripts (about 1.9 MB a report, 1.4 MB of it one
URL-encoded stylesheet with the icon font inside). This copies every report
listed in <study root>/gallery-build.csv to <output>/reports/<template>.html
and moves each large embedded file (a data: URI over 20 kB in a src or href
attribute, base64 or URL-encoded) to <output>/reports/assets/, named by its
MD5, so a file shared by every report is stored once. Figures move out too.
Nothing is re-rendered. Python, not R: URL-decoding the stylesheet in R
took minutes per report.
"""
import base64, csv, hashlib, os, re, shutil, sys, urllib.parse

EXT = {"text/css": "css", "application/javascript": "js", "text/javascript": "js",
       "image/png": "png", "image/svg+xml": "svg", "image/jpeg": "jpg",
       "font/woff2": "woff2", "font/woff": "woff", "application/font-woff": "woff"}
PATTERN = re.compile(r'(src|href)="data:([^;,"]+)((?:;[^;,"]+)*),([^"]+)"')


def package(root, out, min_bytes=20000):
    with open(os.path.join(root, "gallery-build.csv"), newline="") as fh:
        built = list(csv.DictReader(fh))
    failed = [row["template"] for row in built if row["report"] in ("", "NA")]
    if failed:
        sys.exit("The build has failed jobs: " + ", ".join(failed))
    reports = os.path.join(out, "reports")
    assets = os.path.join(reports, "assets")
    # The reports folder is this tool's alone: clear it, so a template or asset
    # dropped from the build does not survive into the next publish.
    shutil.rmtree(reports, ignore_errors=True)
    os.makedirs(assets)

    def extract(match):
        whole, attr, mime, params, payload = match.group(0), *match.groups()
        if len(whole) <= min_bytes or mime not in EXT:
            return whole
        data = base64.b64decode(payload) if ";base64" in params else urllib.parse.unquote_to_bytes(payload)
        name = hashlib.md5(data).hexdigest() + "." + EXT[mime]
        path = os.path.join(assets, name)
        if not os.path.exists(path):
            with open(path, "wb") as fh:
                fh.write(data)
        return f'{attr}="assets/{name}"'

    for row in built:
        with open(row["report"], encoding="utf-8") as fh:
            html = PATTERN.sub(extract, fh.read())
        with open(os.path.join(reports, row["template"] + ".html"), "w", encoding="utf-8") as fh:
            fh.write(html)
    sizes = [os.path.getsize(os.path.join(d, f)) for d, _, fs in os.walk(reports) for f in fs]
    print(f"{len(built)} reports, {len(os.listdir(assets))} shared assets, "
          f"{sum(sizes) / 1e6:.1f} MB in all, largest file {max(sizes) / 1e6:.1f} MB")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("Usage: python3 dev/gallery/package.py <study root> <output folder>")
    package(sys.argv[1], sys.argv[2])
