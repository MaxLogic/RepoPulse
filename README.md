# RepoPulse

## What it does
RepoPulse keeps an inventory of Git repositories and their last analyzed status. Update the repository list when folders change, then analyze the repositories currently shown in the list.

It shows whether each repo is clean or dirty and whether it is ahead or behind its upstream. Actions are run per repo when selected.

## Main features
- **Update Repo list** discovers repositories under checked folders without running Git status or fetching. **Analyze Repos** checks the visible repository snapshot captured when the command starts, including matching rows below the scroll position.
- Filter known repositories immediately with the Search Filter and Status Filter. Exclusions match repository folder names or full paths and keep hidden repositories cached.
- Identify clean/dirty and ahead/behind status, while distinguishing repositories whose local and upstream histories have no common ancestor.
- Per-repo actions: pull, commit, push, fetch, Analyze this repo, and open folder. Drawn row actions highlight on hover, and `Ctrl+C` copies the selected repository path. Failed Pull, Push, and status-scan diagnostics remain available from the popup while their badges are present. When TortoiseGit is installed, its Commit, Sync, and Log dialogs are also available.
- Bulk Pull/Push actions target only repositories visible after search, status, folder selection, and exclusions are applied. They show completed/total progress, use a separate concurrency limit that defaults to 3, and collect failures into one bounded summary instead of interrupting the run.
- Settings are remembered between runs.
- A persistent Folders pane supports inherited checkboxes, excluded children, and explicitly re-included descendants.
- Status badges for branch, behind, ahead, unrelated history, dirty, and failed operations or scans. A repository whose Git status cannot be read remains visible under Needs attention and Scan failed; a later successful scan clears only the scan error.
- Status Filter shows counts for Needs attention, Operation failed, Scan failed, Unrelated history, Safe pull: clean and behind, Behind, not ahead, Diverged, Ahead, not behind, Dirty, Detached, No issues, and All. Its adjacent `?` button explains each state.
- Startup restores known repositories and saved statuses without discovery or Git commands. New rows show Not analyzed; saved observations show their UTC analysis time, age, and cached state.
- During analysis, local status appears before any stale remote fetch completes. Fetch TTL is independent of the time of the local observation.

## Requirements
- Windows.
- Git installed and available on PATH.
- `sk4d.dll` beside `ScanGitRepos.exe`; Delphi deployment metadata copies the Win32 Skia runtime when deploying from the IDE.

## How to run
After a build, the executable is expected at `bin/ScanGitRepos.exe`. Start it by double-clicking the file or by running it from a command prompt.

## First-time setup
1. Open the Folders pane and check the folders to include. Existing scan paths migrate on the first launch with the new folder settings.
2. Choose **Update Repo list**. Discovery retains repository identities even when the current filters hide them.
3. Adjust Search Filter, Status Filter, and Exclusions to show the repositories to analyze.
4. Choose **Analyze Repos**. Changes to filters or checkboxes during the job affect the display, while the captured work list stays unchanged.

## UI overview
- Top toolbar: Search Filter, Status Filter, Exclusions, Update Repo list/Cancel, Analyze Repos, Pull all, Push all, and Settings.
- Folders: arrows navigate and expand; Space changes inclusion. A mixed parent has child exceptions. Changing a parent clears its descendant exceptions. Expanding or selecting a folder does not start repository work.
- The Folders splitter width, expanded branches, and check rules survive restart. Known disconnected folders remain available in the tree.
- The folder popup's **Update Repo list here** discovers the pointed-to folder, or the selected folder for a keyboard popup. It leaves checkboxes and filters unchanged, so discovered repositories can remain hidden until the view includes them.
- Settings retains depth and **Traversal options** for `.ignoredirectory` rules. These control discovery; Exclusions controls visibility.
- Results use a virtual two-line list with a relative path and status badges. The repository popup offers **Analyze this repo** independently of batch analysis.
- Cached or failed observations cannot authorize Pull/Push/Commit. Analyze the repository successfully before using those actions.
- Status and log drawers report progress, completion, cancellation, and errors. Double-click the status bar to copy its text. NVDA desktop users can press NVDA+End to read the current status without moving focus.

## Inventory and saved status
Discovery streams provisional rows and commits membership only after successful completion. Cancellation, inaccessible directories, candidate limits, and save failures discard provisional additions. Existing identities are retained conservatively when traversal cannot prove absence; discovery never deletes folders or repositories on disk.

Filtering never removes cached identities. Analysis updates observations without replacing inventory membership. A failed analysis retains the last successful observation and timestamp with the new error; a failed remote fetch is reported separately from a successful local observation. Completed analysis results are flushed on cancellation and normal shutdown. Cache writes replace the previous file atomically; an unreadable or unsupported cache is reported and preserved.

## Live filters and exclusions
Type in Search Filter to update rows and counts without starting a scan. Search keeps its existing syntax: spaces combine terms, `|` separates alternatives, `!` excludes a term, quotes preserve spaces, and `*`/`?` are wildcards. An empty search includes every known repository allowed by the other filters.

Open **Exclusions** to enter one pattern per line. Patterns match both the repository folder name and its full path, ignoring case and accepting either slash direction. `*` matches any sequence, including path separators; `?` matches one character. Blank lines are ignored; other characters and spaces are literal. For example, `*-workspace` hides workspace folders, and `*\_obselete\*` hides that folder and repositories below it. These are visibility rules, separate from traversal ignores.

The preview includes all matching known repositories, even those hidden by another filter. Apply updates the list; removing an exclusion restores cached rows. **Clear filters** resets search, exclusions, and the status filter. Search, exclusions, and status selection are restored on the next launch.

## Settings storage
Settings are saved alongside the executable in the `bin` directory.

Repository-analysis threads and Pull/Push threads are configured separately. The Pull/Push limit defaults to 3 so bulk Git work does not saturate the machine.

## Accessibility
Use Alt+F for Search Filter and Alt+D for Folders. Space changes a folder checkbox; arrows navigate without changing inclusion. Menu or Shift+F10 opens the focused folder or repository popup. Ctrl+C copies the selected repository path. Repository accessibility text includes the full path, status, and saved observation time.

## Troubleshooting
### crash or invalid pointer operation
- Check Show log for a reported repository-operation error. madExcept saves crash reports locally as `bugreport.txt` beside the executable; retain the exception and source-line callstack for diagnosis.
- For unattended verification, set `MAXLOGIC_MADEXCEPT_AI=1` before launching either Debug or Release. This opts into a fresh, trimmed local report and exit code 207 without a crash dialog. Reports are not sent automatically.
- Build through the supplied DAK wrappers so the madExcept patch step runs. Release builds generate a fresh detailed map; keep the matching executable and map together for diagnosis.
- The application and test runner use FastMM5 from `F:\projects\3rdParty\FastMM5\FastMM5\FastMM5.pas`. The test runner records memory diagnostics in `FastMM5-errors.log` in its working directory instead of showing shutdown dialogs.

### where to find logs
- Use the **Show log** button in the status bar to open the log drawer.
- The status bar shows the most recent scan phase or action summary.

### git not found
- Install Git for Windows and ensure `git.exe` is on PATH.
- Close and reopen the app after updating PATH.

### no repos found
- Check a folder containing Git repositories and run Update Repo list.
- Check folder selection and the search, status, and exclusion filters. Clear filters restores search/status/exclusions; folder inclusion remains under the Folders checkboxes.

### repo has no upstream configured
- Set an upstream on the current branch, for example:
  - `git push -u origin BRANCH`
  - `git branch --set-upstream-to origin/BRANCH`

### permissions / authentication issues
- Verify repository access rights.
- Refresh credentials (HTTPS) or SSH keys and agent (SSH).
