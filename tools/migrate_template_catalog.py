#!/usr/bin/env python3
"""Convert hvtiR v1.1.15's frozen jobs.json into the local template catalog.

Run from this repository with the tagged catalog path as the argument. The
checksum prevents an accidental conversion of an edited or later catalog.
"""
import hashlib
import json
import pathlib
import sys

SOURCE_SHA256 = "d637c4dcc7ec09a07acbe166a148701b08cb8bc7de1efa5c4041b932e777f668"
TARGET = pathlib.Path(__file__).resolve().parents[1] / "inst/extdata/templates.json"


def convert(source):
    content = pathlib.Path(source).read_bytes()
    if hashlib.sha256(content).hexdigest() != SOURCE_SHA256:
        raise SystemExit("Source must be the frozen hvtiR v1.1.15 jobs.json")
    original = json.loads(content)
    rows = []
    for row in original["jobs"]:
        if row["prefix"] in ("rf", "rfsrc"):
            continue
        row.pop("destination")
        row["uses"] = row.pop("replaced_by")
        if row["status"] is None:
            row["status"] = "queued"
        rows.append(row)
    assert len(rows) == 55
    assert len({row["prefix"] for row in rows}) == 44
    assert sum(row["status"] == "queued" for row in rows) >= 8
    return {"templates": rows, "options": original.get("options", [])}


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: migrate_template_catalog.py hvtiR-v1.1.15/inst/extdata/jobs.json")
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    TARGET.write_text(json.dumps(convert(sys.argv[1]), indent=2) + "\n")
