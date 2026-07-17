# Branchline Git Workbench 0.9.0-beta

Branchline is a local Windows control panel for everyday Git and GitHub work. It keeps the real PowerShell, HTML, CSS, and JavaScript source visible in the repository and turns common Git operations into a careful, readable workflow.

**New to Git?** Read the step-by-step [Branchline User Guide](USER_GUIDE.md). It explains installation, the first connection, Publish, Pull, Integrate, branches, recovery, and common problems in beginner-friendly language.

Quick start for normal use:

1. Install Git for Windows.
2. Download or clone this repository.
3. Double-click `RUN-BRANCHLINE.cmd`.
4. Choose a trusted project folder and click **Inspect folder**.
5. Follow the **Next safe action** card; blocked buttons open a guide explaining what is missing.

## What changed

This version replaces the encoded single-file application with plain source and adds:

- loopback-only networking (`127.0.0.1`);
- a random per-run API session token;
- a random per-install identity and versioned loopback coordination endpoint;
- strict Host, Origin, Fetch Metadata, and JSON checks;
- no CORS access;
- GitHub URL validation with credentials and custom protocols rejected;
- Git process timeouts and asynchronous output capture;
- fast-forward-only pulls and explicit origin pushes;
- explicit detection of empty, unpublished, missing, diverged, and unrelated remote histories;
- separate **On this computer** and **On GitHub** snapshot views;
- lazy file browsers with search, pagination, safe text/binary/large-file previews, and local/remote differences;
- repository-scoped commit author setup with clear preflight guidance;
- a safe **Bring GitHub here** path that adopts remote history while preserving files in an unborn local repository;
- a visual local-to-GitHub connection bridge with the active local and remote branches;
- context-matched sync controls: Publish in **On this computer**, and Check/Pull/Integrate in **On GitHub**;
- an explicit **Integrate GitHub** merge that preserves both histories when local and GitHub have unique commits;
- separate branch workflows for switching destinations and explicit `source → target` merges;
- upstream repair, separate new-GitHub-branch publication, and remote-only branch checkout;
- normal-folder inspection, GitHub cloning, and reversible Git detachment;
- exact file, branch, and full commit validation;
- confirmation and safety references for destructive actions;
- a separated, responsive, accessible UI;
- plain regression and security tests.

## Requirements

- Windows 10 or newer;
- Windows PowerShell 5.1 or PowerShell 7;
- Git for Windows;
- Git Credential Manager for the optional GitHub sign-in buttons;
- a current browser.

## Start

Double-click the clearly named launcher:

```text
RUN-BRANCHLINE.cmd
```

The application opens automatically at:

```text
http://127.0.0.1:4848/
```

Stop it with `Ctrl+C` in the Branchline PowerShell window. You can also
double-click `STOP-BRANCHLINE.cmd`; it verifies that port 4848 belongs to
Branchline before stopping anything.

You can also start it explicitly:

```powershell
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\start.ps1 -RepoPath "C:\Projects\my-repo"
```

## Safe first connection

1. Enter any project folder and choose **Inspect folder**.
2. For a normal folder, choose **Make Git repository**, or enter a GitHub URL and use **Clone GitHub here** when the folder is empty.
3. For an existing Git repository, enter a GitHub URL such as `https://github.com/owner/repository` and choose **Connect GitHub origin**.
4. Branchline inspects both histories before enabling Pull or Publish. If the local repository has no commits but GitHub already has work, use **Bring GitHub here**. It preserves existing local files, adds missing GitHub files, and clears staging for review.
5. Set the commit author name and email in **Commit identity**. These settings are stored only in the selected repository.
6. Use **On this computer** for local files, staging, and commits. Use **On GitHub** for the last fetched snapshot and incoming commits.

The tabs control what you are reviewing and which directional controls are shown, not Git safety. **On this computer** shows Publish. **On GitHub** shows Check GitHub and Pull/Integrate. The current branch, its ahead/behind relationship, and whether the working tree is clean still decide whether an action is safe.

**Check GitHub** runs fetch. It updates Git's remote-tracking snapshot and never edits local project files. The header's **Refresh view** only re-reads local state and the already-fetched snapshot; it does not contact GitHub.

Branchline does not silently initialize folders, rename branches, combine unrelated histories, or replace an origin. Folder setup and remote setup are separate confirmed actions.

## Daily workflow

1. Open **On GitHub** and choose **Check GitHub** to refresh the remote snapshot.
2. If GitHub is ahead and the local working tree is clean, choose **Pull**.
3. Open **On this computer**, inspect changes with **Diff**, then stage and commit them.
4. If both local and GitHub now contain unique commits, finish or restore every uncommitted file, open **On GitHub**, and choose **Integrate GitHub**. This creates a normal merge and never force-pushes.
5. Return to **On this computer** and choose **Publish** when the branch is ahead and no longer behind.

Staging is saved by Git, not by the browser. If Branchline is closed and reopened, staged files remain marked **Ready to commit**. Enter a commit message and use **Commit staged**, or **Commit staged & publish** to complete both remaining steps without re-staging or moving the file. Unstaged files are not included by that combined action.

Use **Refresh local files** inside **Project changes** to re-scan the working folder, staging area, and local commits immediately. It never contacts GitHub. While the page is visible and idle, Branchline uses only the lightweight local-status endpoint and adapts between 15, 30, and 60 seconds. Hidden pages, open dialogs, and active actions do not poll. **Check GitHub** remains the separate network action and the UI shows local-scan and GitHub-fetch times independently.

Branchline caches read-only identity, branch, history, snapshot, and file-index data in memory. The cache is bounded to 32 MiB and is invalidated by opaque repository revisions; every mutating Git action still performs a fresh, uncached safety preflight. If incremental state becomes unreadable, the last display is marked stale and changing controls are blocked until a successful retry.

**Publish**, **Pull**, and **Integrate GitHub** remain clickable when the repository is not ready. Instead of silently doing an unsafe operation, they open a synchronization guide showing completed steps, the exact blocker, and the next place to continue. For example, a diverged clean branch shows: local work committed → integrate incoming GitHub commits → publish the integrated branch.

The combined **Commit staged & publish** action asks before creating and publishing the commit. It never stages unrelated unstaged changes.

## Branch workflow

- **Switch branch** lists only other local branches as destinations. Compatible uncommitted changes may travel with the switch; Git refuses the switch instead of overwriting files when they cannot be applied safely.
- **Merge branches** has separate source and target selectors, so `feature → main` is unambiguous. Branchline requires a clean working tree, switches to the chosen target, then creates a normal merge commit from the source.
- **GitHub-only branches** can be checked out as a new local tracking branch when the working tree is clean.
- **Repair branch tracking** is a confirmed pointer-only repair when the current branch should track `origin/<same-name>`. If that GitHub branch does not exist, Branchline offers the separate **Publish as a new GitHub branch** action.
- If a merge conflicts, Branchline remains on the target branch, shows the conflicted files, and offers the existing safe abort action.

## Recovery behavior

- File restore requires a confirmation and accepts only an exact repository file.
- Branch deletion applies only to local, non-current, non-default branches and uses Git's safe `-d` mode.
- Pulls use fetch plus fast-forward-only merge.
- Diverged histories require a clean working tree and explicit confirmation before **Integrate GitHub** creates a normal merge. If files conflict, Git pauses for resolution and Branchline keeps its safe abort option available.
- **Bring GitHub here** is limited to local repositories with no commits; it never overwrites existing local file contents.
- Hard reset creates a collision-proof reference under `refs/branchline/backups/` before changing `HEAD`.
- Git commands stop after a safety timeout rather than hanging indefinitely on hidden prompts.
- **Detach Git, keep files** moves a standard `.git` directory to a timestamped `.branchline-git-backup-*` folder. **Restore Git history** reverses that operation.

## Local state

The last selected repository path is stored at:

```text
%LOCALAPPDATA%\GitControlPanel\config.json
```

Installation identity and the currently active port are stored in the ignored local `.runtime` folder. `/api/about` exposes only the application ID, version, protocol version, and installation ID; it never returns repository paths or session tokens.

No credentials, tokens, diffs, commit messages, or command output are stored there. GitHub credentials remain managed by Git Credential Manager.

## Tests

Run:

```powershell
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\tests\run-tests.ps1
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\tests\stabilization-tests.ps1
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\tests\performance-tests.ps1
npm ci
npx playwright install chromium
npm run test:syntax
npm run test:e2e
```

The PowerShell and browser suites create disposable repositories under the system temporary folder and remove them after completion. Node and Playwright are development-only; users running Branchline do not need them.

## Trust model

Git can execute repository hooks, configured filters, credential helpers, SSH commands, and other local extensions. Use Branchline only with repositories you trust. The web interface is locally protected, but it cannot make an untrusted Git repository safe to execute.

## License

MIT
