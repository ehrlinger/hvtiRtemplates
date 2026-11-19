# Install every hvtiR family member at the floor DESCRIPTION declares for it
# (#566), over a library that already holds their main-branch versions.
#
# The family is every `Remotes:` entry written `ehrlinger/<pkg>` with no ref.
# A pinned remote (boostmtree, `name=repo@tag`) is already tested at its pin
# and is left alone. Each floor is the `(>= x.y.z)` bound in Imports or
# Suggests, installed from the tag `vx.y.z`, which every family bump carries
# (AGENTS.md, "Release ordering"). A floor released before that rule has no
# tag, and is installed from the commit listed in UNTAGGED below.
#
# Installs use `dependencies = FALSE`, so pak's one-ref-per-package rule never
# sees the floors next to the members' own unpinned Remotes. R CMD INSTALL
# still refuses a member whose own floor on a sibling the set does not meet,
# and that failure is a finding: this package's floors admit a combination no
# user can install.

untagged <- c(
  # hvtiRlifetables tags start at v0.1.3; 0.1.2 is the commit that set it.
  "hvtiRlifetables@0.1.2" = "5e1d3fd9b78f11b4ab94895affb404a57f3924bc"
)

desc <- read.dcf("DESCRIPTION")
field <- function(name) {
  x <- if (name %in% colnames(desc)) desc[1, name] else ""
  x <- trimws(strsplit(x, ",")[[1]])
  x[nzchar(x)]
}

remotes <- field("Remotes")
family <- sub("^ehrlinger/", "", grep("^ehrlinger/[A-Za-z0-9.]+$", remotes, value = TRUE))

deps <- c(field("Imports"), field("Suggests"))
pkg <- sub("\\s*\\(.*$", "", deps)
floor <- ifelse(grepl(">=", deps), sub(".*>=\\s*([0-9.]+).*", "\\1", deps), NA)
floors <- setNames(floor, pkg)[intersect(pkg, family)]

if (anyNA(floors)) {
  stop("No `>=` floor for family member(s): ", paste(names(floors)[is.na(floors)], collapse = ", "))
}

# Install the members other members import first, so R CMD INSTALL finds the
# floor version and not the main one when it test-loads each package.
db <- installed.packages()
uses <- tools::package_dependencies(names(floors), db = db, which = c("Depends", "Imports", "LinkingTo"))
order <- character()
while (length(order) < length(floors)) {
  ready <- setdiff(names(floors), order)
  ready <- ready[vapply(ready, function(p) all(intersect(uses[[p]], names(floors)) %in% order), logical(1))]
  if (!length(ready)) stop("Import cycle among family members: ", paste(setdiff(names(floors), order), collapse = ", "))
  order <- c(order, ready)
}

for (p in order) {
  key <- paste0(p, "@", floors[[p]])
  ref <- if (key %in% names(untagged)) untagged[[key]] else paste0("v", floors[[p]])
  message("::group::", p, " >= ", floors[[p]], " from ehrlinger/", p, "@", ref)
  remotes::install_github(paste0("ehrlinger/", p, "@", ref),
                          dependencies = FALSE, upgrade = "never",
                          build_vignettes = FALSE, force = TRUE, quiet = TRUE)
  message("::endgroup::")
}

got <- vapply(names(floors), function(p) as.character(packageVersion(p)), character(1))
cat("\nFamily floors installed:\n")
print(data.frame(floor = floors, installed = got))
bad <- got != floors
if (any(bad)) {
  stop("Installed version differs from the floor for: ", paste(names(floors)[bad], collapse = ", "),
       ". The tag or commit used does not carry that version.")
}
