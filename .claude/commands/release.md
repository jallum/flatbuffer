Release a new version of flatbuffer.

Argument: `$ARGUMENTS` — the bump type (`major`, `minor`, or `patch`) or an explicit version (e.g., `0.5.0`). Default to `patch` if omitted.

## Preflight

1. Verify you are on the `main` branch. If not, switch to it.
2. Verify the working tree is clean (`git status`). Abort if there are uncommitted changes.
3. Pull the latest changes from origin.
4. Read the current version from `mix.exs` (the `version:` field in `project/0`).
5. Calculate the new version based on the argument.
6. Verify the tag `X.Y.Z` does not already exist. Abort if it does.

## Changelog

1. Run `git log <latest-tag>..HEAD --oneline` to see all changes since the last release.
2. Read `CHANGELOG.md` to understand the existing format and tone. If the file doesn't exist yet, create it with a `# Changelog` header.
3. For each significant change, read the relevant code and diff to understand what actually changed. Commits may include ticket IDs (e.g., `fb-r3l`) — use `bw show <id>` to get additional context about the change.
4. Draft a new entry at the top (after the `# Changelog` header) using the format:

```
## X.Y.Z — YYYY-MM-DD

- Concise, user-facing summary of each important change
```

Guidelines for changelog entries:

- Describe _what changed_ from a user's perspective, not implementation details.
- Group related commits into a single bullet.
- Skip trivial changes (typo fixes, CI tweaks, dependency bumps) unless they're the only changes.
- **For new/changed/removed APIs, modules, or configuration:** write a short explanation that includes the rationale (why the change was made), the benefit to the user, and where helpful, a code snippet. These are the most visible changes — a bare bullet isn't enough.
- Match the tone and level of detail in existing entries.

5. **Present the draft changelog to the user for review.** Do not proceed until they approve or ask for edits. The changelog is user-facing and should be reviewed before it's committed.

## Version bump

1. Update `mix.exs`:
   - Update the `version:` field to the new version string.
   - Review hex package metadata (`description:`, `package:` links, the `files:` list) for accuracy. Update if links are stale, descriptions are outdated, or files were added/renamed.
2. Update `README.md`:
   - Update version references (e.g., `~> 0.4` → `~> 0.5`) for minor/major bumps, if any exist.
   - Update user-facing documentation if changes affect it (new modules, changed APIs, removed features). Skip if changes are internal.

## Verify

1. Run `mix format` to ensure formatting is consistent.
2. Run `mix compile --warnings-as-errors` to verify the build succeeds.
3. Run `mix test` to verify tests pass. If tests fail, stop and fix before continuing.
4. Run `mix docs` to verify doc generation succeeds. If it crashes (e.g., non-UTF8 bytes in `@doc` strings), fix the issue before continuing. Common fix: use `~S"""` sigils for docs containing escape sequences like `\xff`.
5. Verify the package tarball: run `mix hex.build -o <tmpdir>/pkg.tar`, extract it, and list `contents.tar.gz`. It must contain the `.xrl`/`.yrl` grammars and no generated `.erl` (see fb-r3l — the published 0.4.1 shipped stale generated parser output), and nothing outside `lib/`, the grammars, `mix.exs`, `README.md`, and `LICENSE.txt`.

## Ship

1. Commit all changes: `Bump version to X.Y.Z`
2. Tag: `git tag -a X.Y.Z -m "X.Y.Z"`
3. Push: `git push && git push --tags`
4. **Ask the user** if they want to publish to Hex. If yes, tell them to run `mix hex.publish` interactively (it requires a password prompt that can't run non-interactively).
