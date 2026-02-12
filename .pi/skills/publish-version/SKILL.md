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

### 3. Update README.md

Edit `README.md` — update the version in the dependency snippet under "Manual Installation" to match. The line looks like:

```elixir
{:phoenix_datastar, "~> X.Y.Z"}
```

Replace the version with the new one (keep the `~>` prefix).

### 4. Update CHANGELOG.md

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

### 5. Generate Docs

```bash
mix docs
```

Verify it succeeds without errors.

### 6. Commit

```bash
git add -A
git commit -m "v<VERSION>"
```

### 7. Tag

```bash
git tag v<VERSION>
```

### 8. Push

```bash
git push && git push --tags
```

### 9. Publish to Hex

**Do not run `mix hex.publish` yourself.** It requires an interactive password prompt that cannot be handled by the agent.

Instead, ask the user to run the following command in a separate terminal:

```bash
mix hex.publish --yes
```

Then wait for the user to confirm that the publish completed successfully before proceeding to step 10.

### 10. Verify

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
