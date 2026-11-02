* The "Adopt an existing study" and "Start a new study" tutorials now open with `hvtiR::setup()`, and the
  README points to the family's Start here page. "Adopt an existing study" no longer has you run
  `organize_templates.sh` or `renv::init()`, and warns before the call that adopting deletes every `tp.*` file by name, edited or not.
  "Start a new study" no longer says `study-setup` reads Study Tracker: the identity is typed, and only
  `study-setup --verify` reads it.
