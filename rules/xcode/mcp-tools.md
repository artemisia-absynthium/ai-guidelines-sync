---
description: Xcode MCP tool usage — file operations, directory listing, project structure
globs:
  - "**/*.swift"
  - "**/*.xcodeproj/**"
---

# Xcode MCP Tools

Prefer Xcode MCP tools over filesystem equivalents for all operations inside an Xcode project. They handle both synchronized folders (`PBXFileSystemSynchronizedRootGroup`) and legacy groups (`PBXGroup`) correctly, and avoid SourceKit false-positive diagnostics that fire when the filesystem `Read`/`Edit` tools touch Swift files.

## File operations

| Task | Use | Not |
|------|-----|-----|
| Read a source file | `mcp__xcode__XcodeRead` | `Read` |
| Edit a source file | `mcp__xcode__XcodeUpdate` | `Edit` |
| Create a new source file | `mcp__xcode__XcodeWrite` | `Write` |
| List directory contents | `mcp__xcode__XcodeLS` | `ls` / `Bash(ls)` |
| Create a new directory/group | `mcp__xcode__XcodeMakeDir` | `Bash(mkdir)` |

## Gotchas

- `mcp__xcode__XcodeMakeDir` requires `mcp__xcode__XcodeLS` to have been called first in the same session or it will fail with an error about unknown project structure.
- A project can mix synchronized folders and legacy groups. Do not assume everything is one or the other — check with `XcodeLS` or inspect `project.pbxproj` for `PBXFileSystemSynchronizedRootGroup` vs `PBXGroup`. `XcodeWrite` is safe for both; it adds to `project.pbxproj` only when the parent is a legacy group.
