# Changelog

All notable user-visible changes to this project will be documented in this file.

## [Unreleased]

### Added
- Added a submodule warning badge when `HEAD` cannot fast-forward to `origin/main` (fallback `origin/master`) plus a popup action to realign that submodule.
- Repo popups now offer Rescan and, when TortoiseGit is installed, shortcuts to its Commit and Sync dialogs. (T-013)
- Added the same animated scanning indicator used by SkillSearch and distinct DPI-aware SVG icons for the main toolbar actions. (T-014)

### Changed
- Repository discovery now streams waiting rows immediately, skips the redundant sequential Git root-resolution phase, publishes local status before stale fetches, and logs phase/cache/UI-queue timings. (T-018)
- Scans now warm-start from a validated, settings-specific repository inventory; canceled or failed discovery keeps the last good inventory, and a missing fetch TTL defaults to one hour. (T-017)
- Scan UI updates now run in count- and time-bounded batches, coalesce pending progress updates, and ignore results from older scan generations. (T-016)
- Repository results now use a virtual, two-line list with a bold path, status badges, row actions, and stable filtering/selection instead of one VCL control tree per repository. (T-015)
- Scan is now the leftmost toolbar action. Application-owned modal dialogs consistently close on Escape. (T-014)
- Repository discovery now scans every configured path, prunes `.ignoredirectory` rules, and applies a wildcard filter that defaults to `*`. Existing single-path settings migrate automatically. (T-011)
- Pulling or pushing a displayed submodule now also refreshes its displayed parent repository. (T-012)
- Replaced the exclude-dirs field with an editor for `.ignoredirectory` rules. (T-001)
- Scanner cancellation now uses CancelToken and debug logging relies on the MaxLogic logger instead of a per-scan file. (T-002)
- Phase 3 now logs each repo as it starts. (T-004)
- Pull failures caused by conflicts or non-fast-forward states now trigger a warning dialog in addition to the action log entry.

### Fixed
- No-fast-forward warning badges and the realignment popup action now also appear for regular branches tracking `origin/main` or `origin/master`, not only submodules. (T-010)
- Repo cards now show only the path relative to the configured scan directory instead of repeating the scan-root segment. (T-009)
- Prevented Phase 3 scans from hanging on non-interactive git prompts. (T-003)
- Normalized paths and handled directory attributes safely during git write-access checks. (T-005)
- Released temp-file handles before deleting them during git write-access checks. (T-006)
- Hardened background thread shutdown and error reporting to avoid invalid pointer exceptions. (T-007)
- Fixed behind detection for repos tracking non-origin remotes by fetching and comparing against the upstream remote. (T-008)
