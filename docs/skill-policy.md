# Skill admission policy

What has to be true before a plugin is installable by the org.

## The gate

Every PR touching `plugins/**` is scanned by [NVIDIA SkillSpector](https://github.com/NVIDIA/SkillSpector),
pinned to `v2.11.0` in [`skill-scan.yml`](../.github/workflows/skill-scan.yml). One scan per changed
plugin, so one bad plugin does not mask a clean one.

SkillSpector emits a 0–100 risk score. We adopt its default bands as the merge gate:

| Score | Severity | Recommendation | Exit | Our policy |
|-------|----------|----------------|------|------------|
| 0–20 | LOW | `SAFE` | 0 | Merge (auto-merge armed) |
| 21–50 | MEDIUM | `CAUTION` | 0 | Merge, findings visible in code scanning |
| 51–80 | HIGH | `DO_NOT_INSTALL` | 1 | **Blocked** |
| 81–100 | CRITICAL | `DO_NOT_INSTALL` | 1 | **Blocked** |
| — | — | scanner error | 2 | **Blocked** — we fail closed |

A scanner error blocks. An unscannable plugin is not a passing plugin.

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

`gate-selftest` closes that. It scans [`tests/fixtures/known-bad/`](../tests/fixtures/) — a skill
carrying textbook AST01/02/03/04/08 patterns — and asserts exit `1`. Exit `0` fails the build with
`GATE IS BROKEN`. Auto-merge depends on this job, so a broken gate stops merges outright.

The fixture lives outside `plugins/` on purpose: `discover` only globs `plugins/*`, and nothing
known-bad should ever be one edit away from a marketplace entry. Its findings are not uploaded as
SARIF — they are intentional and would pollute code scanning.

If a scanner upgrade makes the fixture score ≤ 50, the self-test fails. Investigate before bumping
the pin; do not weaken the fixture to go green.

## Semantic analysis (optional)

Static analysis is the default (`--no-llm`) and is fully deterministic. The optional LLM stage adds
what pattern matching cannot do: compare a skill's *stated* description against what its body
actually instructs, flag vague triggers, and filter false positives. The `known-bad` fixture is
built around exactly that gap — it advertises repo cleanup and does something else.

SkillSpector v2.11.0 registers twelve providers via `SKILLSPECTOR_PROVIDER` (the README lists only
seven — this table is from the source). `SKILLSPECTOR_MODEL` overrides any provider's default model.

| Provider | Credentials | Notes |
|----------|-------------|-------|
| `openai_compatible` | `SKILLSPECTOR_COMPAT_API_KEY` + `SKILLSPECTOR_COMPAT_BASE_URL` | **What this repo uses**, pointed at Gemini |
| `openai` | `OPENAI_API_KEY`, optional `OPENAI_BASE_URL` | api.openai.com |
| `anthropic` | `ANTHROPIC_API_KEY` | api.anthropic.com |
| `anthropic_proxy` | `ANTHROPIC_PROXY_API_KEY` + `ANTHROPIC_PROXY_ENDPOINT_URL` | Vertex-style raw-predict proxy |
| `bedrock` | AWS SigV4 (boto3 chain / `AWS_PROFILE`) | No static key if federated via OIDC |
| `azure_openai` | Azure OpenAI Service | |
| `nv_build` | `NVIDIA_INFERENCE_KEY` | build.nvidia.com |
| `ollama` | none | Local instance |
| `claude_cli` / `codex_cli` / `gemini_cli` | none | Local binary, uses your existing CLI auth |
| `antigravity_cli` | — | Registered but disabled; use `gemini_cli` |

> [!IMPORTANT]
> `SKILLSPECTOR_PROVIDER` defaults to **`nv_build`** when unset. If you run without `--no-llm` and
> forget to set the provider, it will try build.nvidia.com and fail on a missing
> `NVIDIA_INFERENCE_KEY` rather than doing what you meant. Always set it explicitly.

`openai_compatible` uses dedicated `SKILLSPECTOR_COMPAT_*` variable names on purpose — it does not
read `OPENAI_API_KEY` or `OPENAI_BASE_URL`, so stock OpenAI settings in your shell cannot silently
redirect it. Setting the wrong pair is the most likely first-run failure.

Setup: [SECURITY.md](SECURITY.md#semantic-stage-credentials).

The stage is enabled only when `SKILLSPECTOR_COMPAT_API_KEY` is non-empty. Fork PRs cannot read
repository secrets, so they run static-only and fall back rather than failing. **A missing semantic
pass must never mean a missing gate** — static analysis and the exit-code policy still block.

That fallback is a real coverage difference, not just a degraded log line: the
description-vs-behavior mismatch check does not run on fork PRs. Weigh that when deciding whether to
accept plugin contributions from forks at all.

Note the LLM stage is non-deterministic. It can move a risk score between runs on unchanged input,
so a re-run may flip a borderline result near the 50 boundary. The `gate-selftest` job deliberately
stays on `--no-llm` so the gate's own health check cannot flake.

## Suppressions

False positives are suppressed via a repo-root `.skillspector-baseline.yaml`, generated with
`skillspector baseline <path> --reason "<why>"`. Every entry needs a reason. The file is owned by
Security in CODEOWNERS — a suppression is a policy change, not a build fix.

## Running it yourself

```bash
pipx install "skillspector @ git+https://github.com/NVIDIA/SkillSpector.git@v2.11.0"
skillspector scan plugins/dev-workflow --no-llm
```
