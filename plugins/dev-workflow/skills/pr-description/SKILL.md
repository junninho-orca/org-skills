---
name: pr-description
description: Writes a pull request title and description from the actual diff against the base branch, following the org PR template. Use when opening a PR, when asked to "write a PR description", "summarize my changes for review", or when a PR body is empty or stale.
license: Apache-2.0
allowed-tools: Bash(git diff:*) Bash(git log:*) Bash(git status:*) Read
metadata:
  org.example.owner: platform-team
  org.example.review-tier: standard
---

# PR description

Generate a PR title and body that a reviewer can act on without opening every file.

## Steps

1. Determine the base branch: `git symbolic-ref --short refs/remotes/origin/HEAD` (fall back to `main`).
2. Read the change set:
   - `git diff --stat <base>...HEAD` for shape and size
   - `git log --oneline <base>..HEAD` for author intent
   - `git diff <base>...HEAD` for the substance — read it, don't skim the stat
3. Write the description using the template below.
4. Print it to the user. Do not push, and do not open or edit the PR unless the user asks.

## Template

```markdown
## What changed
<2-4 sentences: the behavior difference, not a file list>

## Why
<the problem being solved; link the issue if the branch name or commits reference one>

## Review notes
<the 1-3 places a reviewer should actually look, as file:line>

## Testing
<what was run, and what was not>
```

## Rules

- Describe behavior, not file names. "Retries now back off exponentially" beats "changed retry.go".
- If the diff contains a schema migration, a new dependency, or a config default change, call it out under **Review notes** — those are the parts reviewers miss.
- If the diff spans unrelated concerns, say so and suggest a split rather than writing one description that papers over it.
- Never invent test results. If you cannot tell what was run, write "Not verified" and say why.
- If the diff contains a credential — an API key, token, connection string, or private key — stop
  and tell the user instead of writing the description. A PR body is a bad place to first mention a
  leaked secret, and it will be indexed the moment the PR opens.
