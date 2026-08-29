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
- A scheduled **scanner health check** proving the scanner still detects malicious skills at all,
  kept off the PR path so it does not clutter every developer's checks
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

### Scanner health, off the PR path

A green scan proves the scanner found nothing in what changed. It does not prove the scanner can
still find *anything* — a bad pin or a silently degraded ruleset passes everything, with no visible
symptom.

[`scanner-health.yml`](.github/workflows/scanner-health.yml) closes that. It scans
[`tests/fixtures/known-bad/`](tests/fixtures/) — a plugin that reads as ordinary repository
maintenance while exfiltrating credentials and piping a remote script to `sudo bash` — and asserts
SkillSpector **fails** it.

It runs on a weekday schedule, and on any change to the scanner pin, the workflows, or the fixture.
It deliberately **does not run on ordinary PRs**: it validates the tool, not the change, so putting
it on every PR would show developers a check about a fake malicious plugin that has nothing to do
with their diff. Scanner health changes when the scanner changes, not when a skill does.

### Verified on every build, not asserted

This is real output from the `scanner-health` job, not a description of it. See the latest under
[Actions](https://github.com/junninho-orca/org-skills/actions/workflows/scanner-health.yml), or
download the `scanner-health` artifact from any run.

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

Fork it, then run the bootstrap script. It rewrites every placeholder that would otherwise
misbehave in a fork — most importantly [`CODEOWNERS`](CODEOWNERS), which names accounts that do not
exist in your org and would make required code-owner review impossible to satisfy, blocking every
PR with a confusing message.

```bash
./scripts/bootstrap.sh --org acme --repo skills          # preview, writes nothing
```

```bash
./scripts/bootstrap.sh --org acme --repo skills --apply --protect \
    --team platform --security-team appsec --email-domain acme.com \
    --model claude-sonnet-4-6
```

`--apply` writes the changes; `--protect` also applies branch protection and enables auto-merge;
`--model` declares your model's token budget so the scanner does not assume a 128k context and
silently truncate large skills. It is dry-run by default, and `--help` documents every flag. On a personal account with no teams,
pass your username for `--team` and `--security-team` and it writes `@username` instead of
`@org/team`.

Then, by hand:

1. **Replace the example plugins** under `plugins/` with your own, and update
   [`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json) to match.
2. **Optional: enable semantic analysis.** Static analysis is the default and needs no credentials.
   Adding an LLM catches description-vs-behavior mismatch, which pattern matching cannot. The
   workflow passes every SkillSpector provider's credentials through, so choosing one is a
   repository-settings change, not a workflow edit. Gemini, OpenAI, Anthropic, Azure, Bedrock
   (OIDC, no stored key), NVIDIA Build, and self-hosted Ollama are all supported. Matrix in
   [docs/skill-policy.md](docs/skill-policy.md).
3. **Keep [`tests/fixtures/known-bad/`](tests/fixtures/)** — it is what tells you the gate still
   works. Everything else here is replaceable; that is not.

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
