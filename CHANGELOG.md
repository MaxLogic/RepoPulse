# Changelog

All notable user-visible changes to this project will be documented in this file.

## [Unreleased]

### Added

### Changed
- Replaced the exclude-dirs field with an editor for `.ignoredirectory` rules. (T-001)
- Scanner cancellation now uses CancelToken and debug logging relies on the MaxLogic logger instead of a per-scan file. (T-002)
- Phase 3 now logs each repo as it starts. (T-004)

### Fixed
- Prevented Phase 3 scans from hanging on non-interactive git prompts. (T-003)
- Normalized paths and handled directory attributes safely during git write-access checks. (T-005)
- Released temp-file handles before deleting them during git write-access checks. (T-006)
- Hardened background thread shutdown and error reporting to avoid invalid pointer exceptions. (T-007)
- Fixed behind detection for repos tracking non-origin remotes by fetching and comparing against the upstream remote. (T-008)
