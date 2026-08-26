# ScanGitRepos

## What it does
ScanGitRepos scans configured folder trees to find Git repositories and summarizes their status in one place. It helps keep many repos in sync without opening each one.

It shows whether each repo is clean or dirty and whether it is ahead or behind its upstream. Actions are run per repo when selected.

## Main features
- Scan multiple folder trees for Git repositories while pruning `.ignoredirectory` rules.
- Filter discovered repository names or relative paths with `*` and `?` patterns.
- Identify clean/dirty and ahead/behind status.
- Per-repo actions: pull, commit, push, fetch, rescan, and open folder. When TortoiseGit is installed, its Commit and Sync dialogs are also available.
- Bulk actions for all visible repos (Pull / Push).
- Settings are remembered between runs.
- Lightweight toolbar with inline scan + filter inputs.
- Status badges for branch/behind/ahead/dirty.
- Status filter shows counts for: Needs attention, All, Dirty, Behind, Detached, Clean.
- Repository rows appear during discovery; local status appears before any stale remote fetch completes.
- A validated repository inventory warm-starts repeat scans, while the refresh interval limits repeated fetches.

## Requirements
- Windows.
- Git installed and available on PATH.
- `sk4d.dll` beside `ScanGitRepos.exe`; Delphi deployment metadata copies the Win32 Skia runtime when deploying from the IDE.

## How to run
After a build, the executable is expected at `bin/ScanGitRepos.exe`. Start it by double-clicking the file or by running it from a command prompt.

## First-time setup
1. Start the app.
2. Edit Scan Paths and enter one root folder per line.
3. Enter a Search Filter if needed. The default `*` includes every discovered repository.
4. Start the scan.

## UI overview
- Top toolbar: Scan Paths, Search Filter, Scan/Cancel, Pull all, Push all, Settings.
- An animated scan indicator remains visible while repository discovery and status work continue.
- Results: a virtual two-line list with a bold relative path, then status badges and extra row spacing.
- Actions: Pull appears only when behind; Push/Commit appear only when dirty.
- Status filter shows counts and can show detached HEAD repos.
- Status bar shows the current phase or summary. Double-click to copy it.
- Use Show log to open the log drawer.

## Settings storage
Settings are saved alongside the executable in the `bin` directory.

## Accessibility
The UI uses screen-reader-friendly controls. Each field has a screen reader friendly label so it is announced clearly.

## Troubleshooting
### crash or invalid pointer operation
- The app re-raises scan exceptions so madExcept can capture a call stack.
- Open the crash report from madExcept and share the stack trace and module list.

### where to find logs
- Use the **Show log** button in the status bar to open the log drawer.
- The status bar shows the most recent scan phase or action summary.

### git not found
- Install Git for Windows and ensure `git.exe` is on PATH.
- Close and reopen the app after updating PATH.

### no repos found
- Confirm at least one configured scan path contains Git repos.
- Check that the wildcard filter is not too narrow.

### repo has no upstream configured
- Set an upstream on the current branch, for example:
  - `git push -u origin BRANCH`
  - `git branch --set-upstream-to origin/BRANCH`

### permissions / authentication issues
- Verify repository access rights.
- Refresh credentials (HTTPS) or SSH keys and agent (SSH).
