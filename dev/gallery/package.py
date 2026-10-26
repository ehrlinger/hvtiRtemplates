"""Package a gallery build for publishing.

    python3 dev/gallery/package.py <study root> <output folder>

Each rendered report is self-contained, so all 32 carry their own copy of the
same Quarto stylesheets and scripts (about 1.9 MB a report, 1.4 MB of it one
URL-encoded stylesheet with the icon font inside). This copies every report
listed in <study root>/gallery-build.csv to <output>/reports/<template>.html
and moves each large embedded file (a data: URI over 20 kB in a src or href
attribute, base64 or URL-encoded) to <output>/reports/assets/, named by its
MD5, so a file shared by every report is stored once. Figures move out too.
A template the catalog marks in-flight gets an "In flight" banner at the top
of its report, pointing at its spec and the issue tracker. It also copies the
gallery page, dev/gallery/index.html, to <output>/index.html, and writes each
template's run sheet, from <study root>/run-sheets.json, to
<output>/sheets/<template>.html, so the output folder is the whole site. Nothing is re-rendered. Python, not R: URL-decoding the stylesheet in R
took minutes per report.
"""
import base64, csv, hashlib, json, os, re, shutil, sys, urllib.parse
from html import escape as html_escape

EXT = {"text/css": "css", "application/javascript": "js", "text/javascript": "js",
       "image/png": "png", "image/svg+xml": "svg", "image/jpeg": "jpg",
       "font/woff2": "woff2", "font/woff": "woff", "application/font-woff": "woff"}
PATTERN = re.compile(r'(src|href)="data:([^;,"]+)((?:;[^;,"]+)*),([^"]+)"')
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GITHUB = "https://github.com/ehrlinger/hvtiRtemplates"


# The catalog's rows, keyed as the template files are named: "<prefix>" or
# "<prefix>-<qualifier>".
def catalog():
    data = json.load(open(os.path.join(REPO_ROOT, "inst", "extdata", "templates.json"), encoding="utf-8"))
    rows = data["templates"] if isinstance(data, dict) else data
    return {r["prefix"] if not r.get("qualifier") else f'{r["prefix"]}-{r["qualifier"]}': r for r in rows}


# Where a reader of an in-flight template sends what they find: its spec, and a
# new issue titled with the template's name.
def feedback_links(name, row):
    spec = f'{GITHUB}/blob/main/{row["spec"]}' if row.get("spec") else None
    issue = f'{GITHUB}/issues/new?title={urllib.parse.quote(name + ": ")}'
    return spec, issue


# The banner at the top of an in-flight report. Styled inline: the report is
# self-contained, and its own stylesheet knows nothing of the gallery.
def flight_banner(name, row):
    spec, issue = feedback_links(name, row)
    link = 'style="color:#9A5B06;font-weight:600"'
    parts = [f'<a {link} href="{spec}" target="_blank" rel="noopener">its spec</a>'] if spec else []
    parts.append(f'<a {link} href="{issue}" target="_blank" rel="noopener">an issue</a>')
    return ('<div class="gallery-in-flight" role="note" style="margin:0;padding:10px 20px;background:#FBF0DE;'
            'color:#5C3703;border-bottom:2px solid #9A5B06;font:15px/1.5 system-ui,sans-serif">'
            '<strong style="color:#9A5B06;text-transform:uppercase;letter-spacing:.05em">In flight</strong> '
            f'&mdash; <code>{name}</code> is released for review in a real study and not yet shipped, so it may still '
            'change. Help get it to shipped: read ' + " and open ".join(parts) + ' with what you find.</div>')


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
    rows = catalog()

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
        entry = rows.get(row["template"], {})
        if entry.get("status") == "in-flight":
            banner = flight_banner(row["template"], entry)
            html, n = re.subn(r"(<body[^>]*>)", lambda m: m.group(1) + banner, html, count=1)
            if n != 1:
                sys.exit(f"No <body> tag in {row['template']}'s report to put its in-flight banner after.")
        with open(os.path.join(reports, row["template"] + ".html"), "w", encoding="utf-8") as fh:
            fh.write(html)
    page = os.path.join(os.path.dirname(os.path.abspath(__file__)), "index.html")
    shutil.copyfile(page, os.path.join(out, "index.html"))
    sizes = [os.path.getsize(os.path.join(d, f)) for d, _, fs in os.walk(reports) for f in fs]
    print(f"{len(built)} reports, {len(os.listdir(assets))} shared assets, "
          f"{sum(sizes) / 1e6:.1f} MB in all, largest file {max(sizes) / 1e6:.1f} MB")


# ---- Run sheets ----------------------------------------------------------------
# Each template's run sheet, generated from the template by
# hvtiRtemplates:::.run_sheets() when gallery.R built the reports, published as a
# page of its own. The wording and its HTML come from R, where they are tested;
# this only wraps each sheet in a page that matches the gallery.
SHEET_PAGE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>{title} | run sheet</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500&family=IBM+Plex+Sans:wght@400;500;600&display=swap">
<style>
  :root {{ --ground: #F5F7F4; --panel: #FFFFFF; --ink: #1B2420; --muted: #5A6962; --rule: #D8DED9; --accent: #1D6C75;
          --accent-soft: #E3EFEF; --sans: "IBM Plex Sans", "Helvetica Neue", Arial, sans-serif;
          --mono: "IBM Plex Mono", ui-monospace, "SF Mono", Menlo, monospace; }}
  @media (prefers-color-scheme: dark) {{ :root:not([data-theme="light"]) {{ color-scheme: dark; --ground: #121816;
          --panel: #19201D; --ink: #E4EBE7; --muted: #9AA9A2; --rule: #2C3632; --accent: #6FB9C1; --accent-soft: #1C3033; }} }}
  :root[data-theme="dark"] {{ color-scheme: dark; --ground: #121816; --panel: #19201D; --ink: #E4EBE7; --muted: #9AA9A2;
          --rule: #2C3632; --accent: #6FB9C1; --accent-soft: #1C3033; }}
  body {{ background: var(--ground); color: var(--ink); font: 16px/1.6 var(--sans); margin: 0; padding: 32px 20px 48px; }}
  main {{ max-width: 74ch; margin: 0 auto; }}
  nav {{ font-size: 14px; margin-bottom: 20px; }}
  a {{ color: var(--accent); }}
  h1 {{ font-size: 28px; line-height: 1.25; margin: 0 0 4px; font-weight: 600; }}
  h1 + .kind {{ color: var(--muted); font: 500 12px/1.6 var(--mono); letter-spacing: .06em; text-transform: uppercase; margin: 0 0 24px; }}
  h2 {{ font-size: 19px; font-weight: 600; margin: 32px 0 8px; padding-top: 16px; border-top: 1px solid var(--rule); }}
  li {{ margin: 6px 0; }}
  li ul {{ margin: 4px 0; }}
  code {{ font: 0.88em/1.4 var(--mono); background: var(--accent-soft); padding: 1px 4px; border-radius: 3px; overflow-wrap: anywhere; }}
  footer {{ margin-top: 40px; padding-top: 12px; border-top: 1px solid var(--rule); color: var(--muted); font-size: 13px; }}
  @media (max-width: 520px) {{ body {{ padding: 20px 16px 40px; font-size: 15px; }} h1 {{ font-size: 23px; }} }}
</style>
</head>
<body>
<main>
<nav><a href="../index.html">&larr; The template gallery</a></nav>
{body}
<footer>Generated from the template by hvtiRtemplates, {stamp}. The template holds the details; this sheet is its outline.</footer>
</main>
</body>
</html>
"""


def write_sheets(root, out):
    path = os.path.join(root, "run-sheets.json")
    if not os.path.exists(path):
        sys.exit(f"No run sheets at {path}. Build the gallery with gallery.R, which writes them.")
    sheets = {s["name"]: s for s in json.load(open(path, encoding="utf-8"))}
    disk = [f[:-4] for d in os.listdir(os.path.join(REPO_ROOT, "inst", "templates"))
            if os.path.isdir(os.path.join(REPO_ROOT, "inst", "templates", d))
            for f in os.listdir(os.path.join(REPO_ROOT, "inst", "templates", d)) if f.endswith(".qmd")]
    missing = sorted(set(disk) - set(sheets))
    if missing:
        sys.exit("No run sheet for template(s): " + ", ".join(missing) + ". Rebuild the gallery with gallery.R.")
    folder = os.path.join(out, "sheets")
    shutil.rmtree(folder, ignore_errors=True)
    os.makedirs(folder)
    stamp = _build_stamp()
    for name, sheet in sheets.items():
        # The <h1> the sheet opens with stays; a line under it says what the page is.
        body = sheet["html"].replace("</h1>", '</h1>\n<p class="kind">Run sheet</p>', 1)
        with open(os.path.join(folder, name + ".html"), "w", encoding="utf-8") as fh:
            fh.write(SHEET_PAGE.format(title=html_escape(sheet["title"]), body=body, stamp=html_escape(stamp)))
    return set(sheets)


# ---- The gallery's data ------------------------------------------------------
# The table on the page is generated, not typed: each template's purpose from
# the catalog, the add_job() call that scaffolds it from its own SUBJECT and
# TYPE lines (as template_list() builds it), its table and figure counts from
# the numbered captions in its rendered report, and its render time from the
# build. Only the curated open issues and gallery notes are kept by hand, in
# dev/gallery/notes.json.
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


def gallery_data(root, out, sheets=frozenset()):
    by_name = catalog()
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
                "in_flight": cat.get("status") == "in-flight",
                "spec": feedback_links(name, cat)[0], "feedback": feedback_links(name, cat)[1],
                "call": _template_call(os.path.join(fdir, f), name),
                "tables": _caption_count(html, "Table"), "figures": _caption_count(html, "Figure"),
                "seconds": float(built[name]["seconds"]) if name in built else None,
                "report": bool(html), "sheet": name in sheets,
                "issues": note.get("issues", []), "note": note.get("note", ""),
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
    gallery_data(sys.argv[1], sys.argv[2], write_sheets(sys.argv[1], sys.argv[2]))
