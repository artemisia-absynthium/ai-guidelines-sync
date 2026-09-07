---
description: Planning and execution discipline for non-trivial, multi-step work
---

# Planning & Execution Discipline

## Plans are durable artifacts, not conversation state

A plan for any multi-step task must live in a durable file (e.g. `~/.claude/plans/<name>.md`), not solely in the conversation. Long conversations are summarized on context compaction, and a plan held only in chat history is the first thing lost. Re-read the plan file at the start of each work session; update it in place as decisions land.

## Divergence is a re-plan trigger

Any unplanned event (see `terminology.md`) is a divergence. The next output is a diagnosis and a *proposed* change, never the change itself. The change must be **path-independent**: plan and code end up as they would have been designed had the requirement been known from the start — the simplest structure that satisfies everything now known, with the change placed where the design says it belongs, not where it is cheapest to bolt on. If the plan absorbs it that way, amend it in place; if not, remake the plan with the change designed in. A patch a reader could identify as "added later" — extra branches where a model should have changed, a step bolted beside the one it contradicts — is a Frankenstein, and every later step inherits the seam. Off-plan fixes must never silently accumulate; a trail of reactive "fix X" commits with no plan update is the signature of this rule being violated.

## Specify wire contracts before approving the plan

A plan that produces a wire artifact — file format, archive/zip layout, on-disk or remote naming, serialization, encoding — is not approvable until that contract is specified exactly. "Authored as part of this work" is not a spec: every unspecified byte or name becomes a bug the moment the artifact is generated, uploaded, fetched, and parsed end-to-end.

## Integration-test the first vertical slice

Exercise the real end-to-end round-trip on the first vertical slice, not after all sections are built. A green unit-test suite is not integration evidence — it proves the pieces, not the seams. The seams (naming, formats, transport) are where deferred contracts fail.

## Re-ground after a model switch

On a model switch mid-task, re-read the plan and the diff-so-far and reconcile before writing new code. The previous model's implicit context does not transfer; only the durable plan does — which is the other reason the plan must be a file, and must carry every contract the next model needs.
