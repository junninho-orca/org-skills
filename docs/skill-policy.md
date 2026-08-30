# Skill admission policy

What has to be true before a plugin is installable by the org.

## The gate

[`skill-scan.yml`](../.github/workflows/skill-scan.yml) runs on **every** pull request and scans
each plugin the PR changed with [NVIDIA SkillSpector](https://github.com/NVIDIA/SkillSpector),
pinned to `v2.11.0`. One scan per changed plugin, so one bad plugin does not mask a clean one.

It runs on every PR rather than filtering on `paths:` because `Gate` is a required check, and a
workflow skipped by path filtering never reports its checks — GitHub leaves them pending and the PR
cannot merge. A PR that changed no plugin is short-circuited inside the workflow instead: nothing to
scan, matrix skipped, `Gate` passes. See
[SECURITY.md](SECURITY.md#why-the-gate-workflow-has-no-path-filter).

The pins in `skill-scan.yml` and `scanner-health.yml` must match, and the `Scanner pin` step in
`discover` fails the build if they drift — otherwise the gate and its own health check would be
testing different scanners.

SkillSpector emits a 0–100 risk score. We adopt its default bands as the merge gate:

| Score | Severity | Recommendation | Exit | Our policy |
|-------|----------|----------------|------|------------|
| 0–20 | LOW | `SAFE` | 0 | Merge (auto-merge armed) |
| 21–50 | MEDIUM | `CAUTION` | 0 | Merge; findings reported, not blocking |
| 51–80 | HIGH | `DO_NOT_INSTALL` | 1 | **Blocked** |
| 81–100 | CRITICAL | `DO_NOT_INSTALL` | 1 | **Blocked** |
| — | — | scanner error | 2 | **Blocked** — we fail closed |

A scanner error blocks. An unscannable plugin is not a passing plugin.

## The format gate

Separate from the security gate, and it blocks too.

SkillSpector judges whether a skill is *dangerous*. It does not check that `SKILL.md` is
*well-formed*. Those are different failures with different symptoms: a skill whose frontmatter
`name` disagrees with its directory, or that carries a field the spec does not allow, scans
perfectly clean and then fails at install time on every machine that has the marketplace — or
worse, silently never loads, and nobody notices the capability is missing.

The `Validate skill format` job runs the Agent Skills spec's own reference implementation,
[`skills-ref`](https://github.com/agentskills/agentskills/tree/main/skills-ref), pinned to `0.1.1`,
over every skill in every changed plugin. Using upstream's validator rather than our own means
"valid" is defined by the spec, not by our reading of it.

| Exit | Meaning | Policy |
|------|---------|--------|
| 0 | Valid skill | Pass |
| 1 | Validation errors | **Blocked** |
| other | Could not validate (e.g. unreadable path) | **Blocked** — fail closed |

Only `0` and `1` are documented upstream; `2` shows up for a path it cannot read. Anything that is
not a clean `0` is treated as a failure to validate, which is not the same as a pass — the same
posture the scanner gets.

Two practical notes for anyone adopting this:

- The PyPI distribution is named `skills-ref`, but the console script it installs is **`agentskills`**.
  Upstream's README documents `skills-ref validate`, which does not exist in the published wheel.
- It is a `0.1.x` package, so the pin is exact rather than a range: a minor bump can legitimately
  change what counts as valid, and that is a decision to make deliberately rather than inherit.

A plugin with no `skills/` directory is reported as a notice, not an error — a plugin that ships
only MCP servers is legitimate.

## Auto-merge is not auto-approve

A passing scan arms GitHub auto-merge (`gh pr merge --auto`). It does not merge the PR by itself.
The PR still needs CODEOWNERS approval and every required check green, enforced by branch
protection. OWASP's [scanner integration guidance](https://owasp.org/www-project-agentic-skills-top-10/skill-scanner-integration)
deliberately stops short of endorsing merge-on-green, and a static scanner cannot judge whether a
skill should exist — only whether it looks dangerous. Human review covers the first question.

## What the scanner covers

SkillSpector ships 68 patterns across 17 categories and maps to the OWASP Agentic Skills Top 10 at
**AST01, AST02, AST03, AST04, AST08, AST09, AST10** — malicious instructions, prompt injection,
over-privileged patterns, code injection, supply-chain risk, and approval-workflow controls.

It does **not** cover AST05–AST07. Those stay with the reviewer:

- Does this skill need to exist, or does an existing one already cover it?
- Is `allowed-tools` the narrowest set that works?
- Does the described behavior match what the body actually instructs?

## Proving the gate still works

A green build proves the scanner found nothing in what changed. It does not prove the scanner is
still capable of finding anything. A bad pin, a broken install, or a silently degraded ruleset
passes everything — and every `PASS` in this repo becomes meaningless with no visible symptom.

[`scanner-health.yml`](../.github/workflows/scanner-health.yml) closes that. It scans
[`tests/fixtures/known-bad/`](../tests/fixtures/) — a plugin carrying AST01/02/03/04/08 behavior —
and asserts exit `1`. Exit `0` fails with `SCANNER IS NOT DETECTING`.

It runs on a weekday schedule and on any change to the scanner pin, the workflows, or the fixture —
**not** on ordinary PRs. It checks the tool, not the change, and a developer editing one skill
should not see a check about a fake malicious plugin. The trade: a scanner that degrades between
scheduled runs could pass a PR in the interim. Gating every PR on it would close that window at the
cost of a permanently confusing check on unrelated work, and of re-proving an invariant that only
moves when the scanner does. Bumping `SKILLSPECTOR_VERSION` triggers it, so the most likely cause of
degradation is covered synchronously.

The fixture lives outside `plugins/` on purpose: `discover` only globs `plugins/*`, and nothing
known-bad should ever be one edit away from a marketplace entry. Its findings are not uploaded as
SARIF — they are intentional and would pollute code scanning.

If a scanner upgrade makes the fixture score ≤ 50, the self-test fails. Investigate before bumping
the pin; do not weaken the fixture to go green.

The fixture carries no marker in scanned content — it reads as a plausible plugin, so detection has
to come from behavior. See
[tests/fixtures/README.md](../tests/fixtures/README.md#blind-by-construction). The health check runs
`--no-llm` for determinism: a check that can flake is not a health check.

## Semantic analysis (optional)

Static analysis is the default (`--no-llm`) and is fully deterministic. The optional LLM stage adds
what pattern matching cannot do: compare a skill's *stated* description against what its body
actually instructs, flag vague triggers, and filter false positives. The `known-bad` fixture is
built around exactly that gap — it advertises repo cleanup and does something else.

SkillSpector v2.11.0 registers twelve providers via `SKILLSPECTOR_PROVIDER`. The workflow passes
**every** provider's credentials through, so switching providers is a settings change — no workflow
edit. Set `SKILLSPECTOR_PROVIDER` as a repository variable, supply only that row's credentials, and
leave the rest unset.

Variable names below are those the v2.11.0 source actually reads. `SKILLSPECTOR_MODEL` overrides
any provider's default model.

| `SKILLSPECTOR_PROVIDER` | Secrets | Variables |
|---|---|---|
| `openai_compatible` *(default here — Gemini, Groq, Together, Mistral)* | `SKILLSPECTOR_COMPAT_API_KEY` | `SKILLSPECTOR_COMPAT_BASE_URL` |
| `openai` | `OPENAI_API_KEY` | `OPENAI_BASE_URL`, `OPENAI_PROJECT_ID` |
| `anthropic` | `ANTHROPIC_API_KEY` | `ANTHROPIC_BASE_URL` |
| `anthropic_proxy` | `ANTHROPIC_PROXY_API_KEY` | `ANTHROPIC_PROXY_ENDPOINT_URL` |
| `azure_openai` | `AZURE_OPENAI_API_KEY` | `AZURE_OPENAI_ENDPOINT`, `AZURE_OPENAI_DEPLOYMENT`, `AZURE_OPENAI_API_VERSION` |
| `bedrock` | *none — OIDC* | `SKILLSPECTOR_BEDROCK_ROLE_ARN`, `AWS_REGION` |
| `nv_build` | `NVIDIA_INFERENCE_KEY` | — |
| `ollama` | *none* | `OLLAMA_BASE_URL` (runner must reach it) |
| `claude_cli` / `codex_cli` / `gemini_cli` | *none* | local binary; not practical on a hosted runner |

`bedrock` is the only one with no stored secret: the workflow assumes an OIDC-federated role when
`SKILLSPECTOR_BEDROCK_ROLE_ARN` is set, and the step is inert otherwise. Prefer it if you would
rather not hold a long-lived model key. `ollama` or `openai_compatible` against a self-hosted
endpoint keeps skill source inside your network.

> [!IMPORTANT]
> `SKILLSPECTOR_PROVIDER` defaults to **`nv_build`** in SkillSpector itself when unset. This
> workflow defaults it to `openai_compatible` instead, so an unconfigured fork fails toward the
> documented path rather than an unexplained missing `NVIDIA_INFERENCE_KEY`.

`openai_compatible` uses dedicated `SKILLSPECTOR_COMPAT_*` names on purpose — it does not read
`OPENAI_API_KEY` or `OPENAI_BASE_URL`, so stock OpenAI settings cannot silently redirect it.

Setup: [SECURITY.md](SECURITY.md#semantic-stage-credentials).

The semantic pass is enabled when **any** provider credential is present. Fork PRs cannot read
repository secrets, so they run static-only. **A missing semantic pass must never mean a missing
gate** — static analysis and the exit-code policy still block.

That fallback is a real coverage difference: the description-vs-behavior mismatch check does not run
on fork PRs. Weigh that when deciding whether to accept plugin contributions from forks at all.

The LLM stage is non-deterministic and can move a risk score between runs on unchanged input, so a
re-run may flip a borderline result near the 50 boundary. The scanner health check deliberately stays on
`--no-llm` so the gate's own health check cannot flake.

For the same reason the gate takes its verdict and its human-readable report from a **single**
SkillSpector invocation. Running the scan twice — once for the report, once for SARIF — could show a
reviewer a `CAUTION` summary on a job that blocked at 52. The optional SARIF run is the only second
invocation, and its exit code is ignored.

## Suppressions

False positives are suppressed via a repo-root `.skillspector-baseline.yaml`, generated with
`skillspector baseline <path> --reason "<why>"`. Every entry needs a reason. The file is owned by
Security in CODEOWNERS — a suppression is a policy change, not a build fix.

## Running it yourself

```bash
pipx install "skillspector @ git+https://github.com/NVIDIA/SkillSpector.git@v2.11.0"
skillspector scan plugins/dev-workflow --no-llm
```
