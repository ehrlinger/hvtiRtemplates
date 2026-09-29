#!/usr/bin/env bash
# Fail on British spellings in what this package ships and in the docs that
# describe it. The package writes US English; a template copied into a study
# carries its spelling with it, so a slip here spreads.
#
# Usage: tools/check-us-spelling.sh   (from the repository root)
#
# Dated design records under dev/specs/ are left as written, except the six
# living documents listed in PATHS below.

set -u

# "analyses" is a valid US plural, so only analyse/analysed/analysing are caught.
# programme is matched whole so "programmer" passes.
WORDS='colour|behaviour|favour|honour|labour|neighbour|analys(e|ed|ing)\b'
WORDS+='|(organi|summari|optimi|recogni|normali|standardi|visuali|initiali|prioriti|minimi|maximi'
WORDS+='|characteri|parameteri|categori|customi|emphasi|reali|utili|finali|seriali|randomi)s(e|ed|es|ing|ation|ations)\b'
WORDS+='|centre|metre|licence|catalogue|artefact|\bgrey|modell(ing|ed)|labell(ing|ed)|travell(ing|ed)'
WORDS+='|\bfulfil\b|\benrol\b|judgement|programmes?\b|whilst|amongst'

PATHS=(
  R tests inst man vignettes README.md NEWS.md DESCRIPTION AGENTS.md CLAUDE.md dev/demo
  dev/specs/2026-09-25-eda-composite-design.md
  dev/specs/2026-09-25-release-eda-complete-plan.md
  dev/specs/2026-09-23-new-study-guide-design.md
  dev/specs/2026-09-23-new-study-guide-plan.md
  dev/specs/2026-08-29-template-conversion-roadmap.md
  dev/specs/2026-09-17-ml-family-roadmap-design.md
)

# Allowlist: tokens stripped from a line before it is checked. Keep it short;
# each entry is a name this package does not own.
#   COLOURS           the pre-rename setting, named by the guard that stops an old
#                     study-choices chunk, its test, and NEWS. Upper case only, so
#                     prose "colours" is still caught.
#   `[[`, "colour"    ggplot_build() names its data column colour; a test reads it.
#   aria-labelledby   the HTML attribute, in the new-study vignette's SVG.
#   haven_labelled, labelled::   the labelled package's class and namespace.
ALLOW='COLOURS|`\[\[`, "colour"|aria-labelledby|haven_labelled|\blabelled::'

hits=$(grep -rniIE "$WORDS" "${PATHS[@]}" 2>/dev/null |
  perl -ne 'my ($loc, $text) = /^([^:]+:\d+:)(.*)$/s or next; $text =~ s/'"$ALLOW"'//g;
    # The release plan records 2.7.18, which named the scale scale_colour_hv().
    $text =~ s/scale_colour_hv//g if $loc =~ m{^dev/specs/2026-09-25-release-eda-complete-plan[.]md:}; print "$loc$text" if $text =~ /'"$WORDS"'/i')

if [ -n "$hits" ]; then
  echo "British spellings found (use US spelling, or allowlist a name this package does not own):"
  echo "$hits"
  exit 1
fi
echo "US spelling: no British spellings found."
