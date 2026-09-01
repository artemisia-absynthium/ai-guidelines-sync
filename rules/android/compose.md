---
paths:
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

The cross-stack rule (`rules/workflow/ui-state.md`) governs: error and empty states are implemented before the happy path, and a screen is not shippable without them. Compose-specific addition: never leave an unhandled `else` branch in a `when` on a sealed state interface — handle every branch explicitly so a new state is a compile error, not a blank screen.
