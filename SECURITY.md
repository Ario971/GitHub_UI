# Security policy

## Supported version

Security fixes currently target the latest `0.9.x` beta only.

## Reporting a vulnerability

Please report a vulnerability privately through GitHub Security Advisories for this repository. Do not include credentials, private repository content, session tokens, or personal filesystem paths in a public issue.

Include the Branchline version, Windows and Git versions, a minimal reproduction using a disposable repository, and the security impact. A maintainer should acknowledge a complete report within seven days.

## Local trust boundary

Branchline binds only to `127.0.0.1`, requires a random session token for repository APIs, rejects cross-origin API use, and exposes only installation metadata at `/api/about`. The browser UI does not store GitHub credentials.

Git itself can run repository hooks, filters, credential helpers, SSH commands, and other configured programs. Branchline must therefore be used only with repositories the user trusts. File preview rejects traversal and reparse-point escapes, treats output as text, and never makes an untrusted repository safe to execute.
