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

## What this fixture does not test

It carries safety markers a real attack would not: a `known-bad` directory name, a `plugin.json`
description saying it is a fixture, and an in-file comment. Those keep it safe to hold in a public
repository, and they also tell a reader what it is.

So this is a valid test of the **static** engine — YARA rules and pattern matchers do not read
intent — but it is **not a blind test of the semantic stage**, which would see those markers and
could score them rather than the behavior.

That is one reason `gate-selftest` runs `--no-llm`, alongside keeping the check deterministic. A
fixture cannot be both clearly labelled for safety and blind for evaluation; this repo chooses
labelled, and confines the assertion to the engine the labels cannot influence.

Step headings previously named the OWASP category inline (`## Step 1 ... (AST08: credential
access)`). That went further than a safety marker — it named the rule that should fire — so it now
lives in the table above instead. Removing it did not change the score.

## Keeping it honest

If a SkillSpector upgrade makes this fixture score ≤ 50, the selftest fails. That is working as
intended: investigate before bumping the pin, rather than weakening the fixture to go green.
