---
description: Swift concurrency — @MainActor, @Observable, async/await patterns
globs:
  - "**/*.swift"
---

# Swift Concurrency

## ViewModels and state

All ViewModels and state classes must be `@Observable @MainActor`:

```swift
@Observable
@MainActor
final class MyViewModel {
    ...
}
```

Never use `ObservableObject` / `@Published`.

## MainActor discipline

All work that reads or mutates `@Observable` state or touches the UI must run on `@MainActor`.
If you are on a background context and need to update state, hop explicitly:

```swift
await MainActor.run { self.isLoading = false }
// or
Task { @MainActor in self.isLoading = false }
```

## Async closures and capture lists

Async closures that capture `self` always use `[weak self]`:

```swift
Task { @MainActor [weak self] in
    guard let self else { return }
    self.result = await fetch()
}
```

Back-navigation and completion callbacks follow the same pattern.

## Structured concurrency

Prefer structured concurrency (`async let`, `withTaskGroup`) over unstructured `Task { }` where possible.
Only use `Task.detached` when you explicitly need to escape the current actor — justify it in a comment.
