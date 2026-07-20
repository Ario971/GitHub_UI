# Changelog

All notable Branchline changes are recorded here. The project follows semantic versioning once a stable `1.0.0` release is reached.

## 0.9.0-beta - 2026-07-17

### Added

- Fail-closed repository health reporting and detached-HEAD guidance.
- Structured action phases, steps, partial-success state, and recovery guidance.
- Tracking repair, new-branch publication, and remote-only branch checkout.
- Lazy, searchable, paginated local and fetched-GitHub file browsers with safe previews.
- Separate local-scan and GitHub-fetch timestamps plus adaptive visible-page polling.
- Installation/version identity coordination through loopback-only `GET /api/about`.
- Playwright, axe accessibility checks, disposable failure-injection scenarios, and Windows CI.
- A bounded 32 MiB read-only query cache keyed by opaque repository revisions.
- Incremental action refresh scopes and an extended lightweight `GET /api/local-status` response.
- A complete beginner-oriented user guide covering installation, daily sync, branches, conflicts, recovery, troubleshooting, and use on another laptop.

### Changed

- Publish, Pull, merge, reset, switching, adoption, and recovery now re-check repository state immediately before mutation.
- Combined commit-and-publish preserves a successful commit when the push fails and reports the operation as partial success.
- Git timeouts terminate the complete child-process tree.
- Recovery references and transaction journals use collision-proof identifiers.
- The frontend and backend are divided into focused API, state, rendering, action, dialog, process, repository-state, and server helpers.
- Repository status is collected through one porcelain-v2 scan with optional Git locks disabled for background reads.
- UI polling now pauses while hidden, busy, or inside a dialog; loaded file tabs, focus, selection, scrolling, and commit text survive incremental refreshes.
- Large persistent blur effects and continuous status animations were removed while preserving Branchline's visual design.
- Runtime markers self-heal and include process start time so launcher reuse and STOP cannot confuse a recycled PID with Branchline.
- Windows CI invokes PowerShell tests with `-File` semantics so an intentionally captured native failure cannot falsely fail a successful test script.
- Repository-state parity tests now return an explicit successful process code after their intentional conflict fixture, matching Windows PowerShell 5.1 behavior on hosted runners.
- Local file browsing reuses the complete porcelain status snapshot for untracked paths instead of scanning the working tree twice.
- The branch panel now presents the standard team sequence before advanced local merging and guides a clean stale `main` through GitHub integration before branch creation.
- The interruptible local server accept interval was reduced without adding network polling, improving UI response latency while preserving low idle activity.

### Removed

- Obsolete legacy API actions, the empty Word document, and the encoded `start-source.b64` artifact.

This beta does not include automatic updates, code signing, an embedded editor, automatic PR merging, tags, or a GitHub Release.
