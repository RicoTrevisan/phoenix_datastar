---
name: publish-version
description: Publish a new version of the phoenix_datastar hex package. Handles version bump, changelog, docs, git tag, and hex publish. Use when releasing a new version.
---

# Publish Version

Publishes a new version of `phoenix_datastar` to Hex. Follow every step in order.

## Prerequisites

- All changes for the release must already be committed (except version/changelog updates).
- The user will provide the new version number and changelog contents, or confirm auto-detected values.

## Steps

### 1. Confirm Release Details

Ask the user:
- **What version?** (current is in `@version` in `mix.exs`)
- **What changed?** (review `git log` since last tag to suggest changelog entries)

### 2. Update Version

Edit `mix.exs` — update the `@version` module attribute to the new version string.

### 3. Update CHANGELOG.md

Add a new section at the top of the changelog (below the `# Changelog` header) with the format:

```markdown
## [X.Y.Z] - YYYY-MM-DD

### Added
- ...

### Changed
- ...

### Fixed
- ...
```

Use today's date. Only include sections (Added/Changed/Fixed/Removed) that apply.

### 4. Generate Docs

```bash
mix docs
```

Verify it succeeds without errors.

### 5. Commit

```bash
git add -A
git commit -m "v<VERSION>"
```

### 6. Tag

```bash
git tag v<VERSION>
```

### 7. Push

```bash
git push && git push --tags
```

### 8. Publish to Hex

```bash
mix hex.publish
```

This will prompt for confirmation and a password — let the user handle the interactive prompts. Do NOT pass `--yes` or try to automate the confirmation.

### 9. Verify

After publish completes, confirm success:

```bash
mix hex.info phoenix_datastar
```

## Rollback

If something goes wrong after tagging but before/during publish:

```bash
git tag -d v<VERSION>
git push origin :refs/tags/v<VERSION>
```

Then fix the issue and re-run from step 2.
