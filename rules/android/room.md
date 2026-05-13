---
description: Room database conventions — Flow<T> from DAOs, KSP, explicit migrations, schema export
globs:
  - "**/*.kt"
---

# Room Database Conventions

## DAOs return Flow<T>

DAO methods that return live data must return `Flow<T>`. Never use `LiveData` or a one-shot plain return type for queries that should react to database changes.

```kotlin
// Correct
@Dao
interface ProductDao {
    @Query("SELECT * FROM products ORDER BY created_at DESC")
    fun getAll(): Flow<List<Product>>
}

// Wrong — returns a snapshot, not a reactive stream
@Dao
interface ProductDao {
    @Query("SELECT * FROM products ORDER BY created_at DESC")
    suspend fun getAll(): List<Product>
}
```

One-shot operations (insert, update, delete) use `suspend fun`. Queries that the UI observes use `Flow`.

## KSP, not kapt

Use KSP for Room annotation processing. Do not add or use kapt.

```kotlin
// build.gradle.kts
plugins {
    id("com.google.devtools.ksp")
}

dependencies {
    ksp("androidx.room:room-compiler:<version>")
}
```

## Explicit migrations

Every database version bump requires an explicit `Migration` object. Never use `fallbackToDestructiveMigration()` in production builds — it silently deletes all user data.

```kotlin
val MIGRATION_1_2 = object : Migration(1, 2) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL("ALTER TABLE products ADD COLUMN description TEXT")
    }
}

Room.databaseBuilder(context, AppDatabase::class.java, "app.db")
    .addMigrations(MIGRATION_1_2)
    .build()
```

## Schema export

Configure `room.schemaLocation` in the build file and commit the exported JSON files to source control. Schema history is the migration audit trail.

```kotlin
// build.gradle.kts — inside android > defaultConfig
ksp {
    arg("room.schemaLocation", "$projectDir/schemas")
}
```

Add `app/schemas/` to version control. Never add it to `.gitignore`.
