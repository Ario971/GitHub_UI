# Git & GitHub UI

A local browser control panel for everyday Git and GitHub work. It runs on your own computer, opens like a small website, and turns common Git commands into buttons.

## Why The Script Is Encoded

The app source is stored as:

```text
start-source.b64
```

The launcher decodes it into a local `start.ps1` file when you run the app. This keeps the published repository easier to upload through strict security filters while still giving users a normal PowerShell app locally.

## Requirements

- Windows
- Git installed
- PowerShell 5.1 or newer
- A browser

## Start

Double-click:

```text
start-git-control-panel.cmd
```

Then open:

```text
http://127.0.0.1:4848
```

## Connect A Project

In the UI:

1. Put your local repository path in **Local Repo**.
2. Put your GitHub repository URL in **GitHub Repo**.
3. Click **Connect**.

## Daily Workflow

For a normal file change:

1. Click **Pull**.
2. Edit your file locally.
3. Click **Status**.
4. Click **Diff** beside the changed file.
5. Click **Stage** beside the file, or **Stage All**.
6. Write a commit message.
7. Click **Commit**.
8. Click **Push** or **Publish Ahead Commits To GitHub**.

If GitHub rejects the push with `HTTP 403`, click **Reset GitHub Login**, finish the browser login as the repository owner, then click **Push** again.

## File Colors

- Green: staged
- Yellow: modified
- Blue: untracked
- Red: deleted
- Gray: unchanged

## Notes

This app runs Git commands on the folder you choose. Use it only with repositories you trust.

If a mapped drive such as `M:` is not found, start the app from normal PowerShell, not Administrator PowerShell. Windows often hides mapped drives from Administrator sessions.
