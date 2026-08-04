---
description: Deterministic design gate — plan-time design note, fresh-context Uncle Bob review before any PR, diff-hash stamp, human-only override
paths:
  - "**/*"
---

# Design gate — no verdict, no PR

A PreToolUse hook (synced to `.claude/hooks/synced/design-gate.sh`) blocks PR-opening
commands — `gh pr create`, `gh pr ready`, and their `gh api`/REST/GraphQL equivalents —
unless a valid gate stamp exists: PASS verdict, diff-hash matching the branch head, and
local HEAD pushed — so push the branch BEFORE opening the PR (`gh pr create`'s own
auto-push offer arrives too late; the gate denies first). This is deterministic: the gate cannot be skipped by forgetting it.
This rule documents the protocol the hook enforces.

**Relationship to the pr-review-gate**: the gate's fresh-context run IS pass 1
(design/SOLID) of `pr-review-gate.md`, hardened — independent context, fixed prompt,
mechanical enforcement. Run passes 2–4 (code, security, concurrency) first, resolve their
findings, then run this gate last so its stamp certifies the final diff.

**Residual window (stated, not solved locally)**: a hook cannot be atomic with the command
it guards, and pushes after the PR exists are ungated — the local gate certifies the PR's
opening state. The unconditional layer is a server-side required check.

## The design note — written at plan time, committed on the branch

Every feature branch carries `Docs/design/<branch-slug>.md` (or the project's documented
equivalent), written when the plan is made — NOT reverse-engineered from the finished diff.
Required sections:

- **Types & responsibilities** — each type the work adds/touches, one responsibility each
- **State ownership & lifetimes** — who owns each piece of state, who resets it, when
- **Invariants** — each contract the feature must hold, one sentence each
- **Undecidables** — anything resting on undocumented platform behavior or verifiable only
  on hardware, with how it will be demonstrated

A note that describes what the code does instead of what constraints drove it is a
post-hoc note; the gate reviewer is instructed to flag the difference.

## The gate run

Before opening a PR, run `.claude/hooks/synced/design-gate-run.sh`. It launches a
fresh-context reviewer (`claude -p`, read-only tools) with a fixed adversarial prompt —
the full Uncle Bob / design-review lens, a blast-radius walk of every consumer of changed
state, a mutation-check of every new test, and design-note conformance. The authoring
session never grades its own homework: the reviewer's context contains none of the
authoring momentum, and the prompt is a synced file the session cannot rewrite.

PASS writes a stamp keyed to the hash of the branch diff — any commit after the review
invalidates it. FAIL prints findings; fix them and re-run. Findings are resolved or
explicitly listed to the user with a recommendation — never argued away in-session.

## PR body report lines (all mandatory)

```
Invariants: <one line per contract, or reference to the design note section>
Blast radius: <consumers of changed state/lifecycles walked, or "none — additive">
Undecidables: <each one + its evidence (device run, repro), or "none">
Tests: <each new test names the line whose reversion fails it>
Gate: PASS @ <diff-hash short> | OVERRIDE by <human> because <reason>
```

## Override — human-only, audit-visible

`DESIGN_GATE_OVERRIDE=1` lets the PR through and is recorded in the PR body. Setting it is
a decision reserved to the human: Claude never sets, exports, suggests, or scripts it.
An override without the human's explicit instruction in the conversation is a hard
violation.

## Hook integrity

The synced hooks and the settings entries that wire them are protected by a companion
deny-hook, and `.claude/hooks/synced/` is sync-managed like `rules/synced/`. Claude never
edits, disables, or works around these hooks; a hook that seems broken is diagnosed and
reported, not bypassed. For hard local immutability, hook files can be root-owned
(documented in the README — optional, requires sudo once).
