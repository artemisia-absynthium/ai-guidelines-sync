---
description: Playwright — test execution vs visual verification
globs:
  - "**/*.spec.ts"
  - "**/*.spec.js"
  - "**/*.spec.tsx"
  - "**/*.test.ts"
  - "**/*.test.js"
  - "playwright.config.*"
---

# Playwright

- For running tests and checking pass/fail: use bash (`npx playwright test`).
- For verifying visual rendering (layout, images, proportions): use Playwright MCP with vision.
