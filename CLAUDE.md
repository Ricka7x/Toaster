# Toaster

Small dependency-free Swift package (macOS and iOS): the state machine behind a toast pill
(show, auto-dismiss, loading to success or error). It has no view; each host app (Sortic, Peggo,
Boomark, Snapback) draws its own toast in its own design system.

The shared workflow is in `~/.claude/CLAUDE.md`. Codebase memory project id:
`Users-ricka7x-Projects-Toaster`. This is a library, so it has no HANDOFF.md or FEATURES.md; the
README is the feature list.

- Keep it dependency-free and view-free. Anything visual belongs in the host app.
- Public API changes affect every host app: search them before changing a signature.
- Tests: `swift test`. Versions start at 0.1.0 and are tagged on release.
- Two test files have uncommitted edits (`ToastManagerTests.swift`); look before committing.
- No em dashes, no co-author line. Commit only when asked.
