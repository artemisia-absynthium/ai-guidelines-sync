---
description: Android testing conventions — JUnit 4, Robolectric, MockK, Turbine for Flow assertions
globs:
  - "**/*.kt"
---

# Android Testing Conventions

## Test stack

| Layer | Library |
|-------|---------|
| Test runner | JUnit 4 |
| JVM Android simulation | Robolectric |
| Mocking | MockK |
| Flow / StateFlow assertions | Turbine |

Do not introduce JUnit 5, Mockito, or RxJava testing utilities — they are not part of the established stack.

## Robolectric SDK configuration

Robolectric lags behind the Android SDK. Configure each test class to run against a supported SDK explicitly rather than relying on the default:

```kotlin
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class MyViewModelTest {
    ...
}
```

Check the Robolectric release notes before bumping `minSdk` or `targetSdk` — there may be a gap between the project's target API level and the highest SDK Robolectric supports.

## Flow and StateFlow assertions

Use Turbine's `test { }` block to assert on `Flow` and `StateFlow` emissions. Never use `runBlocking { collect { } }` with manual cancellation — it is fragile and misses emissions.

```kotlin
@Test
fun `emits loading then success`() = runTest {
    viewModel.state.test {
        assertEquals(MyState.Loading, awaitItem())
        assertEquals(MyState.Success(expectedData), awaitItem())
        cancelAndIgnoreRemainingEvents()
    }
}
```

## Unit tests vs instrumentation tests

- Unit tests (`src/test/`) run on the JVM via Robolectric. They do not require a device.
- Instrumentation tests (`src/androidTest/`) run on a connected device or emulator. Use them only for tests that genuinely require the Android runtime (e.g. end-to-end database migration tests).

Prefer unit tests. Write instrumentation tests only when the behaviour cannot be covered by Robolectric.
