# Changelog

## [0.2.0] - 2026-02-04

### Added
- Stateless views can now handle events synchronously (no GenServer required)
- New `event/2` macro replaces `post/2` and `get/2` for triggering server events
- `event_path` assign is now set for all views (live and stateless)
- CSRF token is now read from meta tag automatically (no signal setup required)

### Changed
- **Breaking**: Removed `datastar_events()` macro - all event routes are now per-page
- **Breaking**: Replaced `post/2` and `get/2` macros with single `event/2` macro
- **Breaking**: Event route path changed from `/path/event/:event` to `/path/_event/:event`
- Simplified routing - `datastar/3` macro now generates event routes for all views
- Installer no longer adds `datastar_events()` to router

### Fixed
- Root path "/" now generates correct URLs (was creating double slashes like `//_event`)

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
