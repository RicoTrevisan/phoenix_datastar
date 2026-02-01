# Changelog

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
