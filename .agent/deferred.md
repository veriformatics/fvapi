# Deferred

- vflab has no copy off the machine. → restic to an append-only server on the controller + an encrypted cloud copy once `/srv/data` holds library data; acceptance = a restore of a test file from each copy onto a fresh path, compared with `cmp`.
