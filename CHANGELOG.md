# Changelog

## [0.1.8] - 2026-02-09

### Added
- **Usage rules**: Added `usage-rules.md` for AI agent integration via the `usage_rules` package.

## [0.1.6] - 2026-02-09

### Changed
- **Simplified scoped alias resolution**: `datastar/3` now always delegates to `Phoenix.Router.scoped_alias/2`, matching Phoenix's own convention for controllers. Previously, single-segment vs multi-segment module names were special-cased; now all view modules are treated uniformly. Fully-qualified modules still work as before.

### Fixed
- `live?/1` now calls `Code.ensure_compiled!/1` before inspecting module attributes, preventing false negatives when the module hasn't been loaded yet.
- Removed stray "bump" entry from 0.1.5 changelog.
- Updated LICENSE copyright year to 2026.

## [0.1.5] - 2026-02-07

### Added
- **Built-in mount template**: The HTML wrapper (`DefaultHTML`) is now shipped inside the package. You no longer need to create a `DatastarHTML` module in your app — it works out of the box. To customize, configure `html_module` globally or per-route (see README).
- Installer no longer generates a `DatastarHTML` module — the built-in `DefaultHTML` is used by default.
- **Auto-injected initial signals**: Assigns set in `mount/3` are now automatically initialized as Datastar signals on the wrapper element. No more manually adding `data-signals={Jason.encode!(%{count: @count})}` in your `render/1` — just `assign(socket, :count, 0)` in `mount/3` and use `$count` in your template.
- `@initial_signals` assign is now available in custom HTML modules (see `DefaultHTML` docs).
- New tests for initial signal injection and internal assign filtering.

### Fixed
- `event_path` was leaking as a user signal — added it to `internal_assigns` filter list.

## [0.1.3] - 2026-02-04

### Added
- Stateless views can now handle events synchronously (no GenServer required).
- New `event/2` macro replaces `post/2` and `get/2` for triggering server events.
- `event_path` assign is now set for all views (live and stateless).
- CSRF token is now read from meta tag automatically (no signal setup required).

### Changed
- **Breaking**: Removed `datastar_events()` macro - all event routes are now per-page.
- **Breaking**: Replaced `post/2` and `get/2` macros with single `event/2` macro.
- **Breaking**: Event route path changed from `/path/event/:event` to `/path/_event/:event`.
- Simplified routing - `datastar/3` macro now generates event routes for all views.
- Installer no longer adds `datastar_events()` to router.

### Fixed
- Root path "/" now generates correct URLs (was creating double slashes like `//_event`).

### Removed
- Removed dead `:datastar_update` code path from SSE loop.
- Removed unnecessary `id` attribute from DatastarHTML wrapper (was only used by dead code).

## [0.1.2] - 2026-02-01

### Added
- Installer: adds `datastar/0` to my_app_web.ex

### Fixed
- conditional check to check if it should stablish a sse connection or not


## [0.1.1] - 2026-02-01

### Added
- Installer: Created mix installer (`mix phoenix_datastar.install`).
- Router: Added `PhoenixDatastar.Router` and "sse" option support.
- Config: Added option to remove debug annotations.
- Web: Added `:live_sse` to `_web` module.
- Layout: Added script tag generation for `<head>`.

### Fixed
- Signals: Fixed prepending of scope.
- Patches: Fix to ensure both patches and signals are sent correctly.
