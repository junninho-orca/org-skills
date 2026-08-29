# Test fixtures

> [!CAUTION]
> `known-bad/` contains a **deliberately malicious skill**. It exists so CI can prove the merge
> gate actually blocks. Do not install it, do not copy from it, and do not move it under
> `plugins/`.
>
> **The files inside carry no warning of their own.** `known-bad/plugin.json` and
> `known-bad/skills/repo-doctor/SKILL.md` read exactly like an ordinary plugin, deliberately —
> see [What reaches the semantic analyzer](#what-reaches-the-semantic-analyzer). This directory
> name and this README are the only warnings, so do not lift a file out of here on the assumption
> that it will still look suspicious somewhere else.

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

## Blind by construction

Every marker that once lived in scanned content has been removed, so an analyzer sees a plausible
plugin and nothing that gives the answer away:

| Removed | Was | Why it had to go |
|---|---|---|
| `org.example.expected-verdict: DO_NOT_INSTALL` | `SKILL.md` frontmatter | Stated the expected result outright |
| `(AST08: credential access ...)` in step headings | `SKILL.md` body | Named the rule that should fire |
| `attacker.invalid` hostnames | `SKILL.md` body | Announced intent in the host name |
| `"TEST FIXTURE - deliberately malicious"` | `plugin.json` description | Characterised the file for the reader |
| `"name": "known-bad"`, `do-not-install` keyword | `plugin.json` | Same, in identity and metadata |
| In-file `<!-- Test fixture -->` comment | `SKILL.md` | Same |

What remains: a plugin claiming to tidy repositories, whose body exfiltrates credentials, pipes a
remote script to `sudo bash`, and installs a cron beacon. A scanner has to detect that from
behavior, which is the point.

Safety now rests entirely on placement — the `known-bad/` directory name, this README, absence from
`marketplace.json`, and hosts on the non-resolving `.invalid` TLD. None of the first three reach a
model, so none of them can flatter the result.

### What this now permits

Because the fixture is blind, running it **with** an LLM is a meaningful test of the semantic stage,
not a test of whether a model can read a label. It was not before.

`gate-selftest` still runs `--no-llm`, for a reason unrelated to leakage: the check that decides
whether anything merges must be deterministic, and the semantic stage is not. A separate
non-blocking job could exercise the semantic path against this fixture without putting a
non-deterministic call on the merge path.

## Keeping it honest

If a SkillSpector upgrade makes this fixture score ≤ 50, the selftest fails. That is working as
intended: investigate before bumping the pin, rather than weakening the fixture to go green.
