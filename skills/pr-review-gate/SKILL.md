---
name: pr-review-gate
description: MANDATORY before opening any pull request, merging a branch, or when the user asks for PR checks, the review gate, or the four passes — runs four independent review passes (design/SOLID, standard code review, security, concurrency) on the full branch diff and resolves their findings. Invoke unasked when PR preparation begins.
---

# Pre-PR Review Gate

No PR is opened until FOUR review passes have run on the full branch diff and their
findings are resolved. Run them unasked — a review the user has to request is a process
failure, and by the time they ask, findings are usually too large to fix in the same PR.
The passes are independent: run them in parallel as subagents.

1. **Design / SOLID review** — the Uncle Bob (Robert C. Martin) lens: type-level single
   responsibility, ownership, state lifetimes, dependency direction, the
   `design-principles.md` thresholds, and the full design review lens (load the
   `design-review-lens` skill for the complete checklist: SOLID, Clean Architecture
   boundaries, GRASP, Clean Code hygiene, coupling laws). Explicit verdict on whether
   any type accumulated responsibilities over the branch.
2. **Standard code review** — correctness, project conventions, error handling, test
   coverage (use the code-reviewer agent where available).
3. **Security review** — adversarial pass over the diff: secrets/credentials in code or
   history, injection, unsafe file/archive/network handling (zip-slip, path traversal),
   authn/authz gaps, supply chain (dependency pins, mutable refs), sensitive data in
   logs, and location/EXIF metadata in committed media.
4. **Concurrency review** — a dedicated pass, because concurrency bugs are the class most
   frequently introduced during development and least visible in a general review: shared
   mutable state across threads / isolation domains; state assumed unchanged across a
   suspension or callback boundary (reentrancy, TOCTOU); one-shot completion primitives
   (continuations, promises) resolved exactly once, never leaked, never assumed
   cancellation-aware; task lifecycle (cancellation propagation and checks, orphaned
   background work, polling loops racing terminal state); ordering assumptions between
   async callbacks arriving from different queues/executors; every "trust me"
   thread-safety annotation justified by immutability or internal synchronization.
   Stack-specific rules files supply the concrete lens (e.g. `swift/concurrency.md`).

Findings are fixed before the PR opens, or listed explicitly to the user with a
recommendation — never silently dropped. The PR-prep report includes one verdict line per
pass.

## Diff drift after the passes

The four passes certify the diff they ran on, not the branch name. If the diff changes
materially after a pass has run — a fix for a finding, a changed approach, an extra
commit — the changed portion is re-reviewed before the PR opens: either a fresh run of
the affected passes or a focused delta review applying all four lenses to the new
commits. Reviewer-prescribed fixes are NOT exempt: implementing a prescription can
itself introduce a defect the prescription didn't anticipate (e.g. a remedy that hides
a symptom while leaving related state inconsistent), and only a review of the delta is
positioned to catch it.

## Composition with the design gate

Where the design gate is installed (`rules/workflow/design-gate.md`), its fresh-context
run is the hardened form of pass 1: run passes 2–4 first, then the gate last, so its
stamp certifies the final diff.
