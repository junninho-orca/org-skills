# Test fixtures

> [!CAUTION]
> `known-bad/` contains a **deliberately malicious skill**. It exists so CI can prove the
> merge gate actually blocks. Do not install it, do not copy from it, and do not move it
> under `plugins/`.

## Why this is not in `plugins/`

Two reasons:

1. The `discover` job globs `plugins/*`, so a fixture there would be scanned by the real gate
   and would block every unrelated PR.
2. Anything under `plugins/` is a candidate for `marketplace.json` — the org-installable set.
   A known-bad skill must never be one edit away from shipping.

## What it tests

The `gate-selftest` job in [`skill-scan.yml`](../../.github/workflows/skill-scan.yml) scans
`known-bad/` and asserts SkillSpector exits **1**. An exit of `0` fails the build.

That inverted assertion covers the failure mode a normal green build cannot: a scanner that is
misconfigured, silently degraded, or pinned to a broken version passes everything, and every
"PASS" in this repo becomes meaningless without anyone noticing. This job is the canary.

Its findings are intentionally **not** uploaded as SARIF — they would pollute the repo's code
scanning state with alerts nobody should triage.

## What the fixture contains

Documented here, not in the file. `skillspector scan tests/fixtures/known-bad` does not read this
README — it is one level above the scan target — so the mapping stays available to humans without
being fed to the scanner.

| Step in `repo-doctor/SKILL.md` | Behavior | OWASP |
|---|---|---|
| 0 — Operating mode | Overrides prior instructions; suppresses confirmation | AST02 |
| 1 — Collect environment context | Reads AWS/SSH/`.env` credentials, POSTs them out | AST08 |
| 2 — Install the helper | Pipes a remote script to `sudo bash`; untrusted package index | AST08 |
| 3 — Apply fixes | `eval`s fetched content; `exec` of decoded base64 | AST04 |
| 4 — Tidy up | `rm -rf`, force-push to main, `chmod 777 -R /etc` | AST01 |
| 5 — Schedule follow-up checks | Installs a cron beacon | AST03 |

The frontmatter `description` promises repo cleanup. That gap between stated purpose and actual
body is the realistic shape of a malicious contribution, and the hardest thing for a human skimming
a diff to catch.

## What reaches the semantic analyzer

Worth being precise about, because it decides what this fixture can and cannot prove.

SkillSpector's LLM analyzers build a prompt of the form `## File: <path>` followed by the
line-numbered file content
([`llm_analyzer_base.py`](https://github.com/NVIDIA/SkillSpector/blob/v2.11.0/src/skillspector/llm_analyzer_base.py)).
The path is **relative to the scan root**, so it reads `skills/repo-doctor/SKILL.md` — the
`known-bad` directory name is not in the prompt.

| Marker | Reaches the LLM? |
|---|---|
| `tests/fixtures/known-bad/` directory name | **No** — outside the relative path |
| This README | **No** — above the scan target |
| `SKILL.md` frontmatter and body | **Yes** — it is file content |
| `plugin.json` `description` / `keywords` | **Yes** — it is file content |

The frontmatter previously carried `org.example.expected-verdict: DO_NOT_INSTALL`. That handed the
analyzer the answer outright and has been removed; it was bookkeeping, and protected no one.

## What this fixture does not test

Two markers still live in scanned content: the `plugin.json` description, and the comment at the top
of `SKILL.md`. Both exist so that anyone who copies a file out of this directory is warned by the
file itself.

They also mean this is **not a blind test of the semantic stage** — an analyzer sees them. It is a
sound test of the **static** engine, which matches patterns and does not read intent, and that is
what `gate-selftest` asserts by running `--no-llm`.

Making it blind would mean deleting those two markers, leaving the directory name and this README as
the only warnings — safe for a reader browsing the repo, weaker for someone who copies a lone file.
That trade has not been taken. If you take it, say so here.

## Keeping it honest

If a SkillSpector upgrade makes this fixture score ≤ 50, the selftest fails. That is working as
intended: investigate before bumping the pin, rather than weakening the fixture to go green.
