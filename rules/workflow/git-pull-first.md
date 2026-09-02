---
description: On a shared branch (main/develop), fetch + fast-forward before the first edit when the last fetch is older than an hour — never on solo feature branches, never on every commit
paths:
  - "**/*"
---

# Pull First — on shared branches, when stale

Before the first edit of a task **on a shared branch** — the git-flow mainline branches, read
from `git config --get-regexp '^gitflow\.branch'` (typically `main`/`master` and `develop`) —
bring it up to date when the last fetch is older than about an hour:

```sh
[ -z "$(find .git/FETCH_HEAD -mmin -60 2>/dev/null)" ] && git fetch origin <base> && git merge --ff-only FETCH_HEAD
```

`merge --ff-only FETCH_HEAD` works on a dirty tree when the incoming files are disjoint;
`git pull --ff-only` refuses under `pull.rebase` when the tree is dirty, so prefer the explicit form.

Scope, deliberately narrow:

- **Shared branches only.** A solo `feature/`, `bugfix/`, `release/` or `hotfix/` branch has no
  one else committing to it; its base is refreshed by an explicit rebase when the author chooses,
  not by an ambient pull.
- **Staleness-gated, not per-commit.** Fetching before every commit in a session that started
  current is noise. The gate is the age of the last fetch, not the age of the head commit — a head
  can be legitimately days old on a quiet branch while a fetch minutes ago proved it current.

Rationale: on a shared branch, a stale base means edits against files someone else has already
changed, conflicts found at commit time instead of at the start, and pointers written to content
that has already moved. All of those are cheaper to find before the first edit than after the last.
