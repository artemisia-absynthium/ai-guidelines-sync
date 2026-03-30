---
description: Swift code style — Logger, file headers, import grouping, naming, access control, SwiftLint
globs:
  - "**/*.swift"
---

# Swift Code Style

## Logging

Never use `print()` in production code. Use `Logger` from `OSLog` everywhere:

```swift
private let logger = Logger(
    subsystem: NSString(#fileID).pathComponents.first ?? "",
    category: NSString(#fileID).lastPathComponent
)
```

## File header

Every Swift file starts with:

```swift
//
//  FileName.swift
//  TargetName
//
//  Copyright © <year> <org>. All rights reserved.
//
```

## Imports

Order: system/Apple frameworks first, then internal modules, then local.

```swift
import RealityKit
import SwiftUI

import MyModule
import MyOtherModule
```

No blank line within a group; one blank line between groups.

## Naming and structure

- State types: `*State`. Views: `*View`. Entities: `*Entity`.
- `final class` for state types not intended for subclassing.
- `// MARK: -` sections: `Properties`, `Initializer`, `Helper Functions`, etc.
- Access control: `private` for implementation details; expose only what callers need.
  Types used across modules are `public`.

## Deletion

When removing code, delete it. Never comment it out.

## SwiftLint — enforced rules

| Rule | Action |
|------|--------|
| `force_unwrapping` | Use `guard let` / `if let` — never `!` |
| `implicit_return` | Add explicit `return` where required |
| `multiline_arguments` | Each argument on its own line when breaking |
| `multiline_parameters` | Each parameter on its own line when breaking |

Run `swiftlint <TargetName>` before submitting any Swift change.
