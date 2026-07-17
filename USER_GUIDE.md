# Branchline User Guide

This guide is for people who want to use Git and GitHub without memorizing terminal commands.

Branchline runs only on your Windows computer. It shows your local project and the last GitHub version that Git has fetched. It never silently force-pushes, deletes a history, or overwrites unrelated work.

## 1. The simple idea

Think of your project as having two copies:

- **On this computer** is the folder on your laptop.
- **On GitHub** is the online copy.

The normal local-to-GitHub workflow is:

```text
Change files → Stage → Commit → Check GitHub → Publish
```

If GitHub contains something newer:

```text
Check GitHub → Pull or Integrate → Publish
```

### What the Git words mean

| Word | Simple meaning |
|---|---|
| Refresh local files | Look again at the files on this computer. It does not contact GitHub. |
| Stage | Choose a local change for the next saved package. |
| Commit | Save the staged changes in local Git history. It is not online yet. |
| Check GitHub / Fetch | Download information about new GitHub commits. It does not change your working files. |
| Pull | Bring newer GitHub commits into your local branch when a fast-forward is safe. |
| Integrate GitHub | Combine different local and GitHub commits with a normal merge. |
| Publish / Push | Send local commits to GitHub. |
| Branch | A separate line of work, such as a feature or experiment. |

## 2. Requirements

For normal use, the laptop needs:

- Windows 10 or Windows 11;
- Git for Windows;
- Windows PowerShell 5.1 or PowerShell 7;
- a current web browser.

Node.js, npm, and Playwright are only for developers running the test suite. Normal users do not need them.

## 3. Install Branchline on another laptop

### Option A: Download the ZIP

1. Open this repository on GitHub.
2. Click **Code**.
3. Click **Download ZIP**.
4. Extract the ZIP to a normal project-tools folder.
5. Open the extracted folder.
6. Double-click `RUN-BRANCHLINE.cmd`.

Do not run the application from inside the ZIP preview. Extract it first.

### Option B: Clone with Git

Open PowerShell in the folder where Branchline should live and run:

```powershell
git clone https://github.com/Ario971/GitHub_UI.git
cd GitHub_UI
```

Then double-click:

```text
RUN-BRANCHLINE.cmd
```

Branchline opens at:

```text
http://127.0.0.1:4848/
```

If Windows shows a security warning, confirm only when the files came from this repository and you trust them.

## 4. Stop Branchline safely

Double-click:

```text
STOP-BRANCHLINE.cmd
```

The stop file verifies the Branchline installation identity before terminating a process. It will not intentionally stop an unrelated application that happens to use another port.

## 5. Choose a local project

1. Enter the local folder path under **Choose a project folder**.
2. Click **Inspect folder**.
3. Branchline explains what kind of folder it found.

### If it is already a Git repository

Branchline opens it directly. Existing staged files, commits, branches, and Git history remain unchanged.

### If it is a normal folder containing your work

Choose **Make Git repository** only if you want to start new local Git history in that folder.

### If the normal folder is empty and GitHub already has a project

Enter the GitHub repository URL and choose **Clone GitHub here**. This is usually the easiest and safest way to create the local copy.

### If you want to remove Git from a folder but keep its files

Open **Local Git tools** and use **Detach Git, keep files**. Branchline moves the `.git` metadata into a timestamped backup rather than deleting the project files. Use **Restore Git history** to reverse it.

## 6. Connect the local project to GitHub

1. Inspect and open the local Git repository.
2. Enter a URL such as:

```text
https://github.com/owner/repository
```

3. Click **Connect GitHub origin**.
4. Confirm replacement if the repository already has a different origin.
5. Click **Check GitHub**.

The connection graphic shows the local branch and corresponding GitHub branch. A connection does not automatically copy or merge files; Branchline first compares both histories.

### Special first-connection cases

- **GitHub is empty:** commit local work, then use **Publish as a new GitHub branch** or **Publish** when offered.
- **Local Git has no commits but GitHub has work:** use **Bring GitHub here**. Branchline preserves existing local file contents and adopts GitHub as the history base.
- **Both sides have unrelated histories:** verify that the correct GitHub repository URL was selected. Branchline blocks automatic merging.

## 7. Set the commit identity

Git requires an author name and email before creating a commit.

1. Open **Commit identity**.
2. Enter the name that should appear in commits.
3. Enter the email connected to the GitHub account, or a GitHub no-reply email.
4. Save it.

Branchline stores this identity only in the selected repository. It does not silently change the global identity used by every project on the computer.

## 8. Send a local change to GitHub

Imagine that you edited `README.md`.

1. Open **On this computer**.
2. Click **Refresh local files** if the change is not visible yet.
3. Click **Diff** to review it.
   - Green lines were added.
   - Red lines were removed.
4. Click **Stage** beside the file.
5. Enter a short commit message, for example:

```text
Update installation guide
```

6. Click **Commit staged**.
7. Click **Check GitHub**.
8. If GitHub has no new commit, return to **On this computer** and click **Publish**.

You can use **Commit staged & publish** when Branchline confirms that both operations are currently safe. It does not stage unrelated files automatically.

## 9. Receive a GitHub change

1. Open **On GitHub**.
2. Click **Check GitHub**.
3. Review the incoming files and commits.
4. If Branchline shows that GitHub is simply ahead, click **Pull**.

Pull is not required when GitHub contains nothing new.

## 10. When local and GitHub both changed

Branchline may show:

```text
Local and GitHub both have new commits
```

Do this:

1. Commit or restore every remaining uncommitted local file.
2. Open **On GitHub**.
3. Click **Integrate GitHub**.
4. Confirm the normal merge.
5. Review the result.
6. Return to **On this computer**.
7. Click **Publish**.

In short:

```text
Open GitHub side → Integrate GitHub → Publish
```

Branchline preserves both histories. It does not force-push to solve divergence.

## 11. Resolve a conflict

A conflict means both histories changed the same part of a file and Git cannot choose the final text automatically.

1. Open the affected file using your normal editor.
2. Find the conflict markers:

```text
<<<<<<<
local text
=======
GitHub text
>>>>>>>
```

3. Edit the file so it contains the correct final text.
4. Remove the conflict-marker lines.
5. Save the file.
6. Return to Branchline and refresh local files.
7. Stage the resolved file.
8. Commit the resolution.
9. Publish.

If you do not want to continue the merge, use Branchline's confirmed **Abort operation** action.

## 12. Work with branches

### Create a branch

1. Enter a clear name, such as `feature/better-guide`.
2. Click **Create**.
3. Branchline creates the branch from the current commit and switches to it.

### Switch branches

1. Choose another local branch under **Switch branch**.
2. Click **Switch**.

Git blocks the switch if it would overwrite incompatible uncommitted files.

### Publish a new branch

If the local branch does not exist on GitHub, choose **Publish as a new GitHub branch**. This also sets the correct tracking relationship.

### Merge a feature into main

Choose the source and target explicitly:

```text
feature/better-guide → main
```

Branchline switches to the target and performs a normal merge. The working tree must be clean first.

## 13. Understand the two Project Changes tabs

### On this computer

Shows local files and local working changes. This is where Stage, Unstage, Commit, and Publish belong.

### On GitHub

Shows the last fetched GitHub snapshot. It is not a live network filesystem. Use **Check GitHub** to update it. This is where incoming commits, Pull, and Integrate belong.

Switching tabs does not itself change files or run a fetch.

## 14. Understand the command journal

Every action creates an entry in **Command journal**.

- A green completed status means the operation succeeded.
- A yellow partial status means one step succeeded and another needs attention. For example, the commit succeeded but the push failed.
- A red needs-attention status means Branchline stopped safely and shows the reason.

Select an entry to see its command, numbered steps, individual results, and final message. Click **Expand** for a larger view and **Copy** to copy the complete readable record.

## 15. Common situations

### Publish is disabled or waiting

Click Publish anyway. The guide explains the missing prerequisite. Common reasons are:

- changes are not committed;
- GitHub has a newer commit;
- local and GitHub both have unique commits;
- the branch has no matching GitHub branch;
- commit identity or GitHub authentication is missing;
- a merge conflict or another Git operation is active.

### A staged file is still there after restarting

This is normal. Git stores staging independently of Branchline. Enter a commit message and commit it; you do not need to remove and recreate the file.

### A new local file does not appear

Click **Refresh local files**. This scans the local repository immediately and does not contact GitHub.

### Check GitHub does not change local files

This is correct. Check GitHub is Fetch. Use Pull or Integrate afterward when incoming commits exist.

### Port 4848 is already used

Branchline reuses the matching installation or selects another safe port for an unrelated collision. Use `STOP-BRANCHLINE.cmd` to stop the matching installation. Do not terminate an unknown process merely because it uses a port.

### The page looks old after an update

Restart Branchline and press:

```text
Ctrl + F5
```

### Commit works but Publish fails

The commit remains safely stored locally. Read the selected output, fix authentication or incoming-history requirements, click **Check GitHub**, and retry Publish.

## 16. What moves to another laptop

Downloading this repository gives the other laptop the Branchline application.

It does not automatically transfer:

- your unrelated local project folders;
- GitHub credentials;
- the last selected repository path;
- runtime markers or command-journal entries.

Clone each project separately and authenticate GitHub on that laptop when publishing is required.

## 17. Safety reminders

- Use Branchline only with repositories you trust. Git repositories can contain hooks and special configuration.
- Read confirmation dialogs before restore, detach, reset, merge, or connection replacement.
- Do not manually delete `.git` when Branchline's recoverable detach action is available.
- Keep important work backed up independently of Git and GitHub.
- Branchline is a beta. Review diffs and selected output before publishing important work.

## 18. Developer tests

Developers can run:

```powershell
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\tests\run-tests.ps1
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\tests\stabilization-tests.ps1
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\tests\state-cache-tests.ps1
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\tests\performance-tests.ps1
npm ci
npx playwright install chromium
npm run test:syntax
npm run test:e2e
```

All Git workflow tests use disposable temporary repositories. Do not point automated tests at a real project.
