---
description: Invariant-first implementation — properties over observables before mechanisms, named enforcement points, epistemically typed values, and property tests written before the mechanism
paths:
  - "**/*"
---

# Invariant-first implementation

Applies to any state machine, cache, display contract, sync protocol, retry/recovery logic, or
lifecycle — anything whose correctness is a property over time, not a single call's return value.
In stateful code, review-blocking defects cluster at the invariant level — not in API use,
concurrency, or security, the classes reviews already hunt — and the root cause is
pattern-matching a plausible mechanism instead of deriving it from the property it must maintain.
Only process forces derivation.

## At plan time — the design must be so thorough implementation cannot go wrong

- Invariants are stated as quantified properties over OBSERVABLES ("no served entry is ever staler
  than its TTL", "the shown total never exceeds the verified total, except visibly marked") —
  never as mechanisms ("the timer clears the entry", "the flag resets at teardown"). A mechanism
  is proposed only after the property it serves is written; if the property can't be written, the
  requirement isn't understood yet.
- Every invariant of the form "X stays consistent with Y" names its ENFORCEMENT POINT: the code
  location where Y changes. Unnameable ⇒ the invariant is unowned ⇒ the plan is not approvable.
  Reactive enforcement (checked where the value is consumed) requires an explicit justification of
  the window between the change and the check.
- Epistemic typing: two values of the same language type carrying different trust — measured
  truth, estimate, derived-for-display — get DISTINCT NAMES at plan time. Every comparison,
  `max()`, or assignment that mixes kinds states which kinds it mixes. Truth-only operations
  (diagnostics, recovery, control decisions, wire payloads) never take a display or estimate value.
- Universal quantifiers ("never", "always", "exactly once", "all surfaces") require a per-path or
  per-consumer walk in the plan — or the qualifier that survives one. An unqualified claim is a
  promise to every future reader.
- Design-note review precedes implementation: review the note + plan in a fresh context (the same
  fresh-context reviewer the design gate uses — see `design-gate.md`) BEFORE writing code.
  Findings cost sentences there; the same findings post-diff cost review rounds.

## TDD — the property test precedes the mechanism

- Contract-shaped behavior gets its PROPERTY TEST first: enumerate the event alphabet (every
  mutation the state can receive), write the property over event sequences, watch it fail, then
  build the mechanism until it passes. Unit tests of the mechanism come after and cover its edges.
- Every fixture value is load-bearing: a fixture that satisfies assertions vacuously (a zero that
  short-circuits the arithmetic, two values equal by accident) is a lying test. State why each
  magic value sits where it does relative to the property's boundary.
- Naming each test's mutation is `review-discipline.md`'s author rule — under TDD it applies at
  authoring time, before the test counts as coverage, not as a pre-push retrofit.

## Tiebreak

When this rule and delivery pressure conflict, the invariant work IS the schedule: plan-time
sentences skipped return as full review rounds, with interest.
