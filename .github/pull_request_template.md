## What this rule covers

<!-- One sentence: the pattern, constraint, or convention being captured. -->

## Automated checks

Filled by the `lift-to-shared-rules` skill based on its analysis of the existing rules:

- [ ] No duplication found across existing rules
- [ ] No contradiction found across existing rules
- [ ] No merge opportunity identified (or: content merged into an existing file instead)

## Author checklist

Attested by the contributor (human or Claude):

- [ ] Frontmatter matches the category: `paths:` scoped to the category's file types for stack categories; a one-line `description:` and no `paths:` for `workflow/` (unscoped, so it survives compaction)
- [ ] Applies to any project in this category — no internal file paths, type names, or org-specific references
- [ ] Not a restatement of Apple/framework documentation — captures a non-obvious constraint, gotcha, or decision
- [ ] Non-obvious constraints include a short rationale (the *why*, not just the *what*)
- [ ] Complex patterns include a code example
