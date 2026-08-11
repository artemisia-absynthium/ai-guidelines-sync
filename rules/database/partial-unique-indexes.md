---
paths:
  - "**/*.sql"
  - "**/[Mm]igrations/**"
  - "**/[Pp]ersistence/**"
  - "**/*[Ss]chema*"
  - "**/[Rr]epositor*/**"
---

# Partial Unique Indexes — Domain Transitions Are Writes Too

A partial unique index (`CREATE UNIQUE INDEX ... WHERE <predicate>`) constrains only the
rows inside its WHERE-domain. The obvious collision path — inserting a duplicate — is the
one everybody guards and tests. The one that ships broken is the **state transition**: an
`UPDATE` that changes a predicate column and thereby moves an existing row *into* the
domain, colliding with an occupant that was legally there all along.

Rationale: the transition collision is worse than the insert collision, not equivalent.
An insert failure happens at creation time, where retry-or-rename is natural. A
transition failure hits a row the user already owns, every retry hits the same occupant,
and unless some other actor removes the occupant the operation is permanently impossible
— a persistent, user-facing dead end that insert-focused tests never see.

The discipline, whenever a partial unique index exists:

1. **Audit every write that touches a predicate column** — not just inserts. Any
   `UPDATE` that can flip a row from outside the domain to inside it is a collision
   site.
2. **Absorb or merge occupants in the same transaction** that performs the transition.
   Fetch conflicting in-domain rows by the index's key and resolve them (merge, soft
   delete, re-key) before the transitioning write lands. Doing it in a separate
   transaction reintroduces the race the index exists to prevent.
3. **Match with equality at least as strong as the index's.** If application code
   normalizes more aggressively than SQL (e.g. Swift's full Unicode `lowercased()` vs
   SQLite's ASCII-only `LOWER()`), sweep with the application-side equality — it
   supersets what the index would reject, so nothing slips through.
4. **Test the transition with an occupant present.** A suite that only proves duplicate
   inserts are rejected has not tested the index. The failing shape is: occupant inside
   the domain, second row outside, transition the second row in, assert the write
   succeeds and the conflict was resolved.

```sql
-- One live active row per (owner, folded key)
CREATE UNIQUE INDEX item_uniqueActiveKey
ON item(ownerId, LOWER(TRIM(key)))
WHERE state = 'active' AND deletedAt IS NULL;
```

```
-- Collision site that is NOT an insert:
UPDATE item SET state = 'active' WHERE id = ?   -- re-enters the domain
```

Any code path issuing that update must, inside the same transaction, first resolve a
live `active` row with the same `(ownerId, folded key)` — or the update throws a
uniqueness violation, rolls back, and will do so again on every retry.
