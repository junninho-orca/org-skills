# org-skills

A working reference for running an **org-managed Claude Code plugin marketplace with a security
gate on the way in**. Fork it, or read it and build your own.

The problem it solves: installing a marketplace grants every listed skill to an agent running on an
engineer's machine, with that engineer's credentials. A merged PR here executes on every installed
machine on the next update. That makes this repo a supply-chain boundary, so nothing merges until
[NVIDIA SkillSpector](https://github.com/NVIDIA/SkillSpector) has scanned it and a code owner has
approved it.

Research behind the tooling: **26.1% of published skills contain vulnerabilities and 5.2% show
likely malicious intent.** An org marketplace without a gate inherits that rate.

## What this demonstrates

- Packaging skills to the vendor-neutral [Agent Plugins 1.0.0](https://agent-plugins.org/specification)
  spec, with a Claude Code [`marketplace.json`](.claude-plugin/marketplace.json) layered on top
- A CI gate that scans every changed plugin and **blocks on risk score > 50**
- **Failing closed** — a scanner error blocks too; an unscannable plugin is not a passing plugin
- Findings as SARIF 2.1.0 in the GitHub Security tab, one category per plugin
- A **gate self-test** that proves the scanner still detects malicious skills at all
- Auto-merge that arms on a pass but still waits on human review

## Try it

```bash
/plugin marketplace add junninho-orca/org-skills
```

```bash
/plugin install dev-workflow@org-skills
```

Ships two example plugins: `dev-workflow` (PR descriptions, release notes) and `incident-response`
(incident timelines, blameless postmortems).

## The gate

```
PR touches plugins/**
        |
        v
  discover changed plugins  ──►  one scan job per plugin
                                      |
                    ┌─────────────────┼─────────────────┐
                    v                 v                 v
              exit 0 (≤50)      exit 1 (>50)      exit 2 (error)
                 PASS           DO_NOT_INSTALL      fail closed
                    |                 |                 |
                    v                 └────── BLOCKED ──┘
          SARIF ─► code scanning
                    |
                    v
             Gate (required check)
                    |
                    v
          arm auto-merge  ──►  still waits on CODEOWNERS + branch protection
```

Running alongside, `gate-selftest` scans [`tests/fixtures/known-bad/`](tests/fixtures/) — a skill
carrying textbook prompt-injection, credential-exfiltration, and privilege-escalation patterns — and
asserts SkillSpector **fails** it. A green build proves the scanner found nothing in what changed.
Only the inverted assertion proves it can still find anything at all. A bad pin or a silently
degraded ruleset passes everything, with no visible symptom, and every `PASS` here becomes
meaningless. Auto-merge depends on it.

### Verified on every build, not asserted

This is real output from the `gate-selftest` job, not a description of it. Every push to `main`
regenerates it — see the latest under
[Actions](https://github.com/junninho-orca/org-skills/actions/workflows/skill-scan.yml), or download
the `gate-selftest` artifact from any run.

```
# SkillSpector Security Report
**Source:** tests/fixtures/known-bad

| Metric         | Value           |
|----------------|-----------------|
| Score          | 100/100         |
| Severity       | CRITICAL        |
| Recommendation | DO NOT INSTALL  |

## Issues (19)
### 🔴 HIGH: P1   Instruction Override          skills/repo-doctor/SKILL.md:32   confidence 80%
### 🔴 HIGH: YR1  YARA agent_skill_destructive_autonomous_actions
### 🔴 HIGH: YR4  YARA agent_skill_prompt_injection_hidden_instructions
### 🔴 HIGH: TM1  Credential Access             ×5
### 🔴 HIGH: PE3  Sudo/Root Execution           ×4
### 🔴 HIGH: SC2  External Script Fetching      ×2
### 🔴 HIGH: TM2  External Transmission
### 🟡 MED:  PE2  Chaining Abuse                ×2
### 🟡 MED:  E1   Tool Parameter Abuse          ×2
```

Exit code `1` — the gate blocks. In the same run, `dev-workflow` and `incident-response` both
return `SAFE`.

All 19 findings come from **static analysis alone**, with every semantic analyzer skipped for a
missing API key. The LLM stage is an enhancement here, not a dependency: the gate holds without
credentials of any kind.

## Layout

```
.
├── .claude-plugin/marketplace.json   # what the org can install
├── plugins/
│   ├── dev-workflow/                 # Agent Plugins 1.0.0 package
│   │   ├── plugin.json
│   │   └── skills/<name>/SKILL.md
│   └── incident-response/            # + mcp.json for an MCP server
├── tests/fixtures/known-bad/         # deliberately malicious; proves the gate blocks
├── .github/workflows/skill-scan.yml  # scan → SARIF → Gate → auto-merge
├── docs/
│   ├── skill-policy.md               # thresholds, providers, suppressions
│   ├── CONTRIBUTING.md               # how to add a plugin
│   └── SECURITY.md                   # trust model, branch protection, credentials
└── CODEOWNERS
```

Two specs are in play: [Agent Plugins 1.0.0](https://agent-plugins.org/specification) for the
package, and [Agent Skills](https://agentskills.io/specification) for each `SKILL.md`.

## Adopting this for your own org

1. **Fork**, then replace the `example.com` placeholders in `plugins/*/plugin.json` and
   `.claude-plugin/marketplace.json`.
2. **Point [`CODEOWNERS`](CODEOWNERS) at real teams.** Under a personal account there are no teams,
   so the copy here names a single owner — which is a placeholder, not a control. Security-owned
   paths need a second, different pair of eyes.
3. **Configure branch protection** on `main`. Auto-merge is only safe because of it. Require a PR,
   require code-owner review, and require the **`Gate`** check.
   Full list in [docs/SECURITY.md](docs/SECURITY.md#required-branch-protection-on-main).
4. **Optional: enable semantic analysis.** Static analysis is the default and needs no credentials.
   Adding an LLM catches description-vs-behavior mismatch, which pattern matching cannot.
   The workflow passes every SkillSpector provider's credentials through, so choosing one is a
   repository-settings change, not a workflow edit — set `SKILLSPECTOR_PROVIDER` and that
   provider's secrets. Gemini, OpenAI, Anthropic, Azure, Bedrock (OIDC, no stored key), NVIDIA
   Build, and self-hosted Ollama are all supported. Matrix in
   [docs/skill-policy.md](docs/skill-policy.md).
5. **Replace the example plugins** with your own. Keep `tests/fixtures/known-bad/` — it is what
   tells you the gate still works.

> [!IMPORTANT]
> Require the **`Gate`** check, never the individual `Scan <plugin>` checks. Those are matrix jobs
> whose names change with the plugin set, so requiring them by name means a newly added plugin
> produces an unrequired check and merges ungated. `Gate` has a stable name and covers all of them.

## What the gate does not cover

SkillSpector maps to OWASP Agentic Skills Top 10 **AST01–04, AST08–10**. AST05–07 stay with the
reviewer, and the [PR template](.github/pull_request_template.md) asks for them explicitly:

- Does this skill need to exist, or does an existing one already cover it?
- Is `allowed-tools` the narrowest set that works?
- Does the description match what the body actually instructs?

## License

[Apache-2.0](LICENSE). The example skills and workflow are yours to copy.
