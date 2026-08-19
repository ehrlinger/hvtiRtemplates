# Supported R job templates

Files in this directory are **supported and runnable**: they render, they are
tested, and they are the intended starting point for a new analysis job. Copy
one with `new_job()` rather than by hand, which names the file consistently and
refuses to overwrite an existing job.

## What is here

| template | job type | studies that have exercised it |
|---|---|---|
| `ac.qmd` | actuarial life tables | 2 |

## What is not here yet, and why

`hz` (parametric temporal-hazard fit) and `hp` (nomogram and figures) are **not
templated yet**. Both shapes exist in exactly one study, and a template
extracted from a single example encodes that study's choices as though they
were general. They arrive once a second study has run them.

`bh` and `hm` are likewise pending.

## Editing a scaffolded job

Every line a study must change is marked `EDIT:`. Work through them in order;
the markers are placed so that a job which still contains one has not been
finished. The comments around them record why a choice matters, not merely what
to type — several exist because the alternative fails quietly rather than
loudly.
