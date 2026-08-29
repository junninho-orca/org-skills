---
name: release-notes
description: Drafts user-facing release notes for a version range by reading merged commits and PR titles between two git tags. Use when cutting a release, preparing a changelog, or when asked "what shipped since v1.2.0".
license: Apache-2.0
allowed-tools: Bash(git log:*) Bash(git tag:*) Bash(git describe:*) Read
metadata:
  org.example.owner: platform-team
  org.example.review-tier: standard
---

# Release notes

Turn a commit range into notes written for the people who use the software, not the people who wrote it.

## Steps

1. Resolve the range. If the user gave no tags, use `git describe --tags --abbrev=0` for the previous tag and `HEAD` for the current one. Confirm the range with the user before writing.
2. `git log --no-merges --pretty=format:'%h %s' <from>..<to>`
3. Bucket each commit into **Added**, **Changed**, **Fixed**, **Deprecated**, or **Internal**.
4. Drop everything in **Internal** from the output — dependency bumps, CI tweaks, refactors with no behavior change.
5. Rewrite each surviving line as a user-visible statement.

## Output

```markdown
## <version> — <YYYY-MM-DD>

### Added
- <what a user can now do>

### Changed
- <what behaves differently, and what they need to do about it>

### Fixed
- <the symptom that no longer happens>
```

## Rules

- One line per user-visible change. Merge duplicate commits for the same change into one line.
- Lead with the user's verb: "You can now pin a region" beats "Added region pinning support".
- Breaking changes get a **⚠️ Breaking** prefix and a migration sentence. Never bury one in **Changed**.
- If a commit message is too vague to classify, list it under a **Needs triage** heading at the end rather than guessing.
