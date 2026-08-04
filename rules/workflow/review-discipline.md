---
description: Symmetric PR review protocol — invariant-first comments, one complete fix shape, thread protocol on majors, mutation-checked tests, device evidence before the PR
paths:
  - "**/*"
---

# Review discipline — symmetric, for author and reviewer alike

These rules apply in both directions: today's reviewer is tomorrow's author. They exist
because multi-round review dances are almost always caused by process, not by hard code —
each rule below is named after the failure it prevents.

## Reviewer side

- **State the invariant first, then the finding.** A comment that only describes a failure
  scenario invites a patch scoped to that scenario. Name the contract the code must hold
  ("OK acknowledges exactly what the advisor read"); the scenario is evidence, the
  invariant is the requirement. A fix satisfying the invariant closes every scenario;
  a fix satisfying the scenario spawns the next round.
- **Give ONE complete fix shape — never a minimal variant alongside it.** If a quick fix
  and a robust fix are both described, the minimal one gets taken, and the difference
  returns as next round's major. Signatures over prose where possible.
- **Self-verify every major-class claim before posting** — by direct read at the branch
  head, or by a minimal compile/run repro. A refuted major costs the author a round and
  the reviewer trust. Subagent findings are hypotheses until verified.
- **Concede errors on the record.** A wrong suggestion, once discovered, is corrected
  explicitly in the next review — never silently dropped.

## Author side

- **Reply in-thread before pushing a fix for a major**: restate the invariant you
  understood and the fix shape you intend. Minutes of async dialogue replace whole review
  rounds spent discovering a misunderstanding after the code exists.
- **Walk the blast radius of every fix before pushing**: enumerate every consumer of the
  state, lifecycle, or contract the fix touches, and check each one. Fixes pushed without
  this walk are how one round's fix becomes the next round's major.
- **Every new test must name its mutation**: which line, reverted, makes it fail. A test
  that fails under no reversion is noise that inflates the passing count — the reviewer
  will check, so check first. Watch for the classic vacuous shapes: happy-path-only,
  asserting a mock was called, expectations mirroring the implementation's own logic.
- **Device/hardware evidence belongs to the author, before the PR.** Behavior the
  simulator or CI cannot exercise (offline media, real transport drops, sensor paths) is
  verified on hardware before review, with the evidence in the PR body — never carried
  across rounds as a pending gate.

## Both sides

- Findings are resolved or explicitly acknowledged — never silently dropped.
- Anything resting on undocumented platform behavior in a load-bearing path is a design
  finding, not a style note: design it away or demonstrate it empirically.
