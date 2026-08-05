---
description: Uncle Bob's SOLID — type-level single-responsibility enforced at plan time and via an implementation tripwire, not discovered in post-hoc review
paths:
  - "**/*"
---

# Design Principles — Uncle Bob's SOLID From the Start

Apply Robert C. Martin's ("Uncle Bob") SOLID principles — above all the Single
Responsibility Principle in its original form: a type should have one reason to change,
one actor it answers to. Type-level design is enforced during planning and implementation,
not discovered in review.
A post-hoc design review that fails is a plan that failed earlier: by then the refactor is
too large to fold into the same change and gets postponed, and postponed refactors compound.

## At plan time

- For every type the plan touches, state which responsibilities it gains. A type gaining a
  responsibility outside the contract its name states ⇒ the plan includes the extraction as
  part of the same work item — never "as a follow-up".
- New state added to an existing type must name its lifetime (who resets it, when). Two
  different lifetimes living in one type is a split signal.

## While implementing — the tripwire

Stop and propose a split immediately (mid-task, not at review time) when a type being edited:

- exceeds ~300 lines, or
- exceeds ~15 stored properties, or
- holds state with two different lifetimes, or
- gains a responsibility its name doesn't cover.

Proposing the split is mandatory; deferring it is the user's call, never a silent default.
The rationale: god classes are never designed — they accrete through individually reasonable
increments, and only a per-increment check catches the accretion while the fix is still small.

## Tiebreak vs "no premature abstraction"

Rules like "don't introduce an abstraction until it has two users" govern protocols,
generics, and indirection layers. They do NOT apply to extracting concrete collaborator
types out of a growing class: owned concrete types with one implementation and no protocol
are the cure for a god class, not premature abstraction. When single-responsibility and
"simplest shape" pull in opposite directions at the type level, single-responsibility wins.

## Solutions are rooted in the literature

Every design problem is treated as an instance of a known problem until shown otherwise:
name the precedent — the design pattern, the algorithm, the data structure, the
architectural style, the concurrency primitive — and take its known solution, adapted,
stating what was adapted and why. A mechanism with no named precedent is presumed
invented, and invention requires justification: what was searched, and why nothing fits.
Novelty is a cost — an invented mechanism has no literature documenting its failure modes.

Calibration: the demand is the *mapping*, not the ceremony. "This is a plain loop / a
switch over a closed set — no precedent needed" is a valid mapping for trivial mechanism,
and forcing a Visitor where a switch is proportionate is the inverse failure (the YAGNI
guardrails govern the solution's weight). The rule bites on non-trivial mechanism — state
machines, caches, schedulers, synchronization, retry/backoff, parsers, distributed or
exactly-once semantics — anything with a named literature and documented failure modes.

## Complexity is stated at plan time

For every operation over a collection, stream, or query, the plan names the expected input
scale and the time/space complexity of the chosen approach. "n is small and bounded" is a
valid answer — but it must be *said*, with the bound, so the assumption is visible the day
the bound changes.

## Design review lens

The comprehensive review checklist (SOLID, Clean Architecture, GRASP, Clean Code,
coupling laws, guardrails) lives in the `design-review-lens` skill — invoke it for the
design pass of the PR gate or any standalone design review. This file keeps only what
must be active while planning and writing code.

## Invariant-first (companion rule)

Type-level design (this file) says who owns what; `invariant-first.md` says what must stay
true and who enforces it — properties before mechanisms, enforcement points named at plan
time, values epistemically typed, property tests before the mechanism. Both apply to every
plan; neither substitutes for the other.
