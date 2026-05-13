---
description: Jetpack Compose conventions — state management, lifecycle-aware collection, call formatting, UI state coverage
globs:
  - "**/*.kt"
---

# Jetpack Compose Conventions

## State management

Model UI state as a sealed interface, one per feature flow. Expose it from the ViewModel as `StateFlow`:

```kotlin
sealed interface MyFeatureState {
    data object Idle : MyFeatureState
    data object Loading : MyFeatureState
    data class Success(val data: MyData) : MyFeatureState
    data class Error(val message: String) : MyFeatureState
}

class MyFeatureViewModel : ViewModel() {
    private val _state = MutableStateFlow<MyFeatureState>(MyFeatureState.Idle)
    val state: StateFlow<MyFeatureState> = _state.asStateFlow()
}
```

Never use `LiveData` for state exposed to Compose UI.

## Lifecycle-aware collection

Always collect `StateFlow` and `Flow` in the UI layer with `collectAsStateWithLifecycle()`, never `collectAsState()`. The lifecycle-aware variant stops collecting when the UI is not visible, preventing unnecessary work and memory pressure.

```kotlin
// Correct
val state by viewModel.state.collectAsStateWithLifecycle()

// Wrong — leaks collection when composable is not visible
val state by viewModel.state.collectAsState()
```

`collectAsStateWithLifecycle` requires `androidx.lifecycle:lifecycle-runtime-compose`.

## Call formatting

Every Composable call with more than one argument uses one argument per line, with a trailing comma on the last argument:

```kotlin
// Correct
Text(
    text = "Hello",
    style = MaterialTheme.typography.bodyMedium,
    color = MaterialTheme.colorScheme.onSurface,
    maxLines = 2,
)

// Wrong — never collapse onto one line
Text(text = "Hello", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurface)
```

This applies to all Composable invocations, regardless of total line length.

## UI state coverage order

When building a screen that loads data or performs async work, implement states in this order:

1. **Error state** — what the user sees when the operation fails
2. **Empty state** — what the user sees when the result set is empty
3. **Loading state** — skeleton or progress indicator
4. **Success / happy path** — the populated content

Do not ship a screen where any of the first three states render nothing or crash. An unhandled `else` branch in a `when` on a sealed interface is a compile error waiting to happen — always handle every branch explicitly.
