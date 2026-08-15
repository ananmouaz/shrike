---
description: Forensic high-precision bug hunt on a diff, PR, branch, or file
---

Invoke the `deep-bug-hunter` skill and run a full bug hunt on: $ARGUMENTS

If no target was given, hunt the current working diff (uncommitted changes plus
commits not yet on the default branch).

Follow the skill's scope contract exactly: report only correctness bugs backed by
a concrete failure scenario. Zero findings is a valid, successful result.
