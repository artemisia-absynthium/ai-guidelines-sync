---
description: Kotlin/Android code style — no force non-null, Result<T> at boundaries, companion object constants
globs:
  - "**/*.kt"
---

# Kotlin / Android Code Style

## No force non-null assertion

Never use the `!!` operator in production code. It is a crash waiting to happen.

```kotlin
// Wrong
val name = user!!.name

// Correct — handle the null explicitly
val name = user?.name ?: return
val name = user?.name ?: throw IllegalStateException("User must be set before accessing name")
val name = requireNotNull(user) { "User must be set" }.name
```

The `!!` operator is only acceptable inside `if (BuildConfig.DEBUG)` blocks or test code.

## Result<T> at service and repository boundaries

Every method that can fail — network call, file I/O, external SDK call — returns `Result<T>`. No custom exception types cross layer boundaries.

```kotlin
// Correct
suspend fun fetchProduct(id: String): Result<Product> = runCatching {
    api.getProduct(id)
}

// Wrong — lets exceptions leak across layers
suspend fun fetchProduct(id: String): Product = api.getProduct(id)
```

Callers use `onSuccess` / `onFailure` / `fold` — they never catch exceptions from a method that already returns `Result<T>`.

## Constants in companion objects

Configuration values — timeouts, model names, endpoint paths, quality thresholds, buffer sizes — are named constants. They belong in the `companion object` of the class that owns the behaviour, not in a shared `AppConstants` or `Constants` object.

```kotlin
// Correct
class ImageUploader {
    companion object {
        private const val JPEG_QUALITY = 85
        private const val MAX_DIMENSION_PX = 1024
    }
}

// Wrong — a shared constants file that accumulates unrelated values
object AppConstants {
    const val JPEG_QUALITY = 85
    const val MAX_DIMENSION_PX = 1024
}
```

Before adding a new constant, grep for existing companion object constants in the class that will use it. Reuse what exists.
