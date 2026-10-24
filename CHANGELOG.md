# Changelog

All notable user-visible changes to this project will be documented in this file.

## [Unreleased]

### Added
- Added Update Repo list here to the folder popup for one-off discovery without changing folder checkboxes or filters. (T-043)
- Added a persistent checkbox Folders pane with inherited selection, mixed states, background folder expansion, and restored layout. (T-040)
- Added live repository search and persistent folder-name/full-path exclusion globs, with a preview before Apply. Hidden repositories remain available when filters are cleared. (T-039)
- Startup now restores saved repositories and timestamped status in the background, including unavailable roots and Not analyzed entries. Cached or failed observations cannot authorize repository mutations. (T-038)
- Added an Unrelated history badge and status filter for repositories whose HEAD and upstream have no common ancestor. (T-037)
- Bulk-operation summaries now use coherent SVG glyphs for Copy and Close, and every application-owned Close button shares the same glyph. (T-036)
- Repository rows now retain separate last Pull and Push failure badges for the current session, with popup commands for the full diagnostics. (T-031)
- Repositories whose Git status cannot be read now remain visible with a Scan failed badge and filter, expose the full diagnostic from the popup, and recover on a later successful scan without losing current-session Pull/Push errors. (T-032)
- Added modal help beside Status Filter that explains every repository state and closes with Escape. (T-030)
- Pull all and Push all now show completed/total progress, live status text, and a compact transfer animation while they run. (T-029)
- Added an Ahead status filter with a live repository count. (T-024)
- Added a submodule warning badge when `HEAD` cannot fast-forward to `origin/main` (fallback `origin/master`) plus a popup action to realign that submodule.
- Repo popups now offer Rescan and, when TortoiseGit is installed, shortcuts to its Commit, Sync, and Log dialogs. (T-013, T-023)
- Added the same animated scanning indicator used by SkillSearch and distinct DPI-aware SVG icons for the main toolbar actions. (T-014)
- Search Filter now has keyboard access, inline syntax help, and a matched-versus-discovered repository count. (T-021)

### Changed
- Repository rows now announce the short display path and elapsed analysis age in minutes, hours, days, months, or years, without the absolute path or a cached tag. Ctrl+C copies the full path. The row popup offers Pull and Push when current repository state permits them. (T-044)
- The application and test runner now use FastMM5 with its default allocation strategy. (T-052)
- Split Scan into Update Repo list for discovery and Analyze Repos for the visible snapshot captured at invocation. Analyze this repo checks one selected repository through the same analyzer; filtering does not erase inventory or alter a running analysis scope. (T-041, T-042)
- Pull all and Push all now suppress per-repository error dialogs, collect failures, and show one bounded Copy/Close summary with one diagnostic line per failed repository. Individual Pull/Push failures remain immediate. (T-031)
- Status Filter now uses actionable Needs attention, Operation failed, Scan failed, Safe pull: clean and behind, Behind, not ahead, Diverged, Ahead, not behind, Dirty, Detached, No issues, and All states. (T-030, T-035)
- Scan and Pull/Push concurrency are now configured separately; bulk Git operations default to at most three concurrent workers. (T-028)
- Pull all and Push all now explicitly document and share the current visible repository scope, with balloon hints on both actions and both filters. (T-025)
- Virtual repository-row actions now show a mouse hover state, and `Ctrl+C` copies the selected repository's full path. (T-022)
- Search Filter now uses the Foundation extended syntax for required terms, alternatives, exclusions, quoted phrases, and wildcards. (T-021)
- Scan paths and `.ignoredirectory` rules are now edited together from the Scan Paths button; the separate Settings action was removed. (T-020)
- Application push buttons now use `TBitBtn`, and the SkillSearch scan animation is shown at its original prominent size. (T-019)
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
- Individual Pull and Push failures open their full diagnostic immediately.

### Fixed
- NVDA status-bar lookup now reads discovery and analysis status, including completion and error messages. (T-056)
- Folder popup discovery now dispatches the selected native menu command before clearing its target. (T-055)
- Folder keyboard popups now open for selected paths whose text extends beyond the visible pane. (T-054)
- Fixed folder-tree access violations and retained metadata during native window recreation, including recreation of a parent window. (T-050)
- Restored useful madExcept reports from command-line Release builds with current source-line symbols and an unattended local-report mode. (T-051)
- Repository accessibility point lookup now returns the row's full path, status, freshness, and full row bounds, including after scrolling and filtering. (T-044)
- Streaming discovery preserves the selected repository when filters change, and unchecked inaccessible folders no longer abort discovery in checked folders. (T-039, T-041)
- Disconnected histories no longer show misleading Ahead, Behind, Diverged, or no-fast-forward states, and Pull all excludes them. (T-037)
- The Ahead filter no longer includes repositories that are also behind; those repositories remain under Diverged. (T-035)
- Bulk Pull/Push summaries now prefer the actual fatal/error line over preceding fetch or submodule progress output. (T-034)
- Pull now supplies the remote default branch explicitly for detached submodules, allowing safe fast-forward updates without attaching HEAD; divergent histories still fail without moving HEAD. (T-033)
- Repository rows now stay sorted by displayed path as scan results stream in and filters change. (T-027)
- No-fast-forward warning badges and the realignment popup action now also appear for regular branches tracking `origin/main` or `origin/master`, not only submodules. (T-010)
- Repo cards now show only the path relative to the configured scan directory instead of repeating the scan-root segment. (T-009)
- Prevented Phase 3 scans from hanging on non-interactive git prompts. (T-003)
- Normalized paths and handled directory attributes safely during git write-access checks. (T-005)
- Released temp-file handles before deleting them during git write-access checks. (T-006)
- Hardened background thread shutdown and error reporting to avoid invalid pointer exceptions. (T-007)
- Fixed behind detection for repos tracking non-origin remotes by fetching and comparing against the upstream remote. (T-008)
