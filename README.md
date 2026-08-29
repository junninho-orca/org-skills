# org-skills

Org-managed Claude Code plugins and skills, with a supply-chain gate on the way in.

Anything merged here becomes installable by every engineer with this marketplace configured. So
nothing merges until [NVIDIA SkillSpector](https://github.com/NVIDIA/SkillSpector) has scanned it
and a code owner has approved it.

## Layout

```
.
├── .claude-plugin/
│   └── marketplace.json          # what the org can actually install
├── plugins/
│   ├── dev-workflow/             # Agent Plugins 1.0.0 package
│   │   ├── plugin.json
│   │   └── skills/
│   │       ├── pr-description/SKILL.md
│   │       └── release-notes/SKILL.md
│   └── incident-response/
│       ├── plugin.json
│       ├── mcp.json
│       └── skills/
│           ├── incident-timeline/SKILL.md
│           └── postmortem/SKILL.md
├── tests/fixtures/
│   └── known-bad/                # deliberately malicious - proves the gate blocks
├── .github/workflows/
│   └── skill-scan.yml            # scan -> SARIF -> gate -> auto-merge
├── docs/
│   ├── skill-policy.md           # thresholds, suppressions, what review still owns
│   ├── CONTRIBUTING.md
│   └── SECURITY.md
└── CODEOWNERS
```

Two specs are in play: [Agent Plugins 1.0.0](https://agent-plugins.org/specification) for the plugin
package, and [Agent Skills](https://agentskills.io/specification) for each `SKILL.md`.
`.claude-plugin/marketplace.json` is the Claude Code–specific layer that makes the repo installable.

## Install

```bash
/plugin marketplace add example-org/org-skills
```

Then `/plugin install dev-workflow@example-org`.

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
          arm auto-merge  ──►  still waits on CODEOWNERS + branch protection
```

Running alongside it, `gate-selftest` scans [`tests/fixtures/known-bad/`](tests/fixtures/) and
asserts SkillSpector exits **1**. If a malicious skill ever passes, the build fails loudly — that
inverted assertion is the only check that catches a scanner which has silently stopped detecting
anything. Auto-merge waits on it too.

Thresholds, suppression policy, and what the scanner does *not* cover are in
[docs/skill-policy.md](docs/skill-policy.md).

## Scan locally before you push

```bash
pipx install "skillspector @ git+https://github.com/NVIDIA/SkillSpector.git@v2.11.0"
skillspector scan plugins/dev-workflow --no-llm
```

## Before this repo goes live

Auto-merge is only safe with branch protection configured — required CODEOWNERS review, required
status checks, no admin bypass, and **Allow auto-merge** enabled on the repository. The full list is
in [docs/SECURITY.md](docs/SECURITY.md#required-branch-protection-on-main). Replace the
`example-org` / `example.com` placeholders in `CODEOWNERS`, the manifests, and `marketplace.json`
with your real org and teams.
