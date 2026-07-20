# Contributing

Branchline's normal runtime must remain dependency-free: Windows, Git for Windows, Windows PowerShell 5.1 or newer, and a current browser are the only user requirements. Node packages are development-only.

## Development workflow

1. Create a focused branch from `main`.
2. Keep Git operations non-interactive and preserve the loopback/session-token boundary.
3. Use disposable repositories for every test. Never point automated tests at a real project.
4. Run:

```powershell
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\tests\run-tests.ps1
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\tests\stabilization-tests.ps1
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\tests\performance-tests.ps1
npm ci
npx playwright install chromium
npm run test:syntax
npm run test:e2e
```

5. Update `CHANGELOG.md` for user-visible behavior.
6. Open a draft pull request and wait for the Windows checks to pass.

## Safety requirements

- A failed status, branch, index, ref, or tracking read must block mutation.
- Pull is fast-forward-only; divergence requires an explicit normal merge.
- Do not add force-push, silent branch renaming, hidden initialization, or implicit unrelated-history merging.
- Every destructive recovery operation needs confirmation and a recoverable reference or transaction journal.
- New web assets must be added to the fixed server allowlist; dynamic filesystem serving is not allowed.
- Repository file content must be rendered with `textContent`, bounded in size, and protected from traversal and reparse-point escape.
