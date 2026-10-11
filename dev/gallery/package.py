"""Package a gallery build for publishing.

    python3 dev/gallery/package.py <study root> <output folder>

Each rendered report is self-contained, so all 32 carry their own copy of the
same Quarto stylesheets and scripts (about 1.9 MB a report, 1.4 MB of it one
URL-encoded stylesheet with the icon font inside). This copies every report
listed in <study root>/gallery-build.csv to <output>/reports/<template>.html
and moves each large embedded file (a data: URI over 20 kB in a src or href
attribute, base64 or URL-encoded) to <output>/reports/assets/, named by its
MD5, so a file shared by every report is stored once. Figures move out too.
It also copies the gallery page, dev/gallery/index.html, to <output>/index.html,
so the output folder is the whole site. Nothing is re-rendered. Python, not R: URL-decoding the stylesheet in R
took minutes per report.
"""
import base64, csv, hashlib, json, os, re, shutil, sys, urllib.parse

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
    page = os.path.join(os.path.dirname(os.path.abspath(__file__)), "index.html")
    shutil.copyfile(page, os.path.join(out, "index.html"))
    sizes = [os.path.getsize(os.path.join(d, f)) for d, _, fs in os.walk(reports) for f in fs]
    print(f"{len(built)} reports, {len(os.listdir(assets))} shared assets, "
          f"{sum(sizes) / 1e6:.1f} MB in all, largest file {max(sizes) / 1e6:.1f} MB")


# ---- The gallery's data ------------------------------------------------------
# The table on the page is generated, not typed: each template's purpose from
# the catalog, the add_job() call that scaffolds it from its own SUBJECT and
# TYPE lines (as template_list() builds it), its table and figure counts from
# the numbered captions in its rendered report, and its render time from the
# build. Only the curated open issues and gallery notes are kept by hand, in
# dev/gallery/notes.json.
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FIELD = re.compile(r"^[A-Za-z0-9_]+$")


def _template_call(path, name):
    def value(marker):
        lines = [l for l in open(path, encoding="utf-8") if re.match(marker + r"\s+<- ", l)]
        if len(lines) != 1:
            return None
        m = re.match(marker + r"""\s+<-\s+(["'])([^"']*)\1\s*(#.*)?$""", lines[0].rstrip("\n"))
        return m.group(2) if m and FIELD.match(m.group(2)) else None
    subject, type_ = value("SUBJECT"), value("TYPE")
    if subject is None or type_ is None:
        return None
    # template_list()$call shows a qualified template as "dc.trends".
    return f'add_job("{name.replace("-", ".", 1)}", subject = "{subject}", type = "{type_}")'


def _first_sentence(text):
    m = re.match(r"(.+?[.!?])(\s|$)", text or "")
    return m.group(1) if m else (text or "")


# Quarto writes "Table" and its number with a non-breaking space between them,
# as the character or as &nbsp;, so match any space. Each number is counted
# once, however often a cross-reference repeats it.
def _caption_count(html, kind):
    return len(set(re.findall(kind + r"(?:\s|&nbsp;)(\d+):", html)))


def _build_stamp():
    version = re.search(r"^Version:\s*(\S+)", open(os.path.join(REPO_ROOT, "DESCRIPTION"), encoding="utf-8").read(), re.M)
    import datetime
    return f"{version.group(1) if version else ''} · built {datetime.date.today().isoformat()}"


def gallery_data(root, out):
    catalog = json.load(open(os.path.join(REPO_ROOT, "inst", "extdata", "templates.json"), encoding="utf-8"))
    rows = catalog["templates"] if isinstance(catalog, dict) else catalog
    by_name = {}
    for r in rows:
        name = r["prefix"] if not r.get("qualifier") else f'{r["prefix"]}-{r["qualifier"]}'
        by_name[name] = r
    notes = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "notes.json"), encoding="utf-8"))
    with open(os.path.join(root, "gallery-build.csv"), newline="") as fh:
        built = {row["template"]: row for row in csv.DictReader(fh)}
    data = []
    for folder in sorted(os.listdir(os.path.join(REPO_ROOT, "inst", "templates"))):
        fdir = os.path.join(REPO_ROOT, "inst", "templates", folder)
        if not os.path.isdir(fdir):
            continue
        for f in sorted(os.listdir(fdir)):
            if not f.endswith(".qmd"):
                continue
            name = f[:-4]
            cat = by_name.get(name, {})
            report = os.path.join(out, "reports", name + ".html")
            html = open(report, encoding="utf-8").read() if os.path.exists(report) else ""
            note = notes.get(name, {})
            data.append({
                "name": name, "folder": folder,
                "title": cat.get("name", name),
                "use": _first_sentence(cat.get("description", "")),
                "deprecated_by": cat.get("deprecated_by"),
                "call": _template_call(os.path.join(fdir, f), name),
                "tables": _caption_count(html, "Table"), "figures": _caption_count(html, "Figure"),
                "seconds": float(built[name]["seconds"]) if name in built else None,
                "report": bool(html), "issues": note.get("issues", []), "note": note.get("note", ""),
            })
    with open(os.path.join(out, "gallery-data.js"), "w", encoding="utf-8") as fh:
        fh.write("// Generated by dev/gallery/package.py; do not edit by hand.\n")
        fh.write("window.GALLERY = " + json.dumps(data, indent=1, ensure_ascii=False) + ";\n")
        fh.write("window.GALLERY_BUILT = " + json.dumps(_build_stamp()) + ";\n")
    return data


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("Usage: python3 dev/gallery/package.py <study root> <output folder>")
    package(sys.argv[1], sys.argv[2])
    gallery_data(sys.argv[1], sys.argv[2])
