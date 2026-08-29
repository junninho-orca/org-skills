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

## Keeping it honest

If a SkillSpector upgrade makes this fixture score ≤ 50, the selftest fails. That is working as
intended: investigate before bumping the pin, rather than weakening the fixture to go green.
