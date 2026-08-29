# Contributing a plugin or skill

## Layout

Plugins follow the [Agent Plugins 1.0.0](https://agent-plugins.org/specification) spec:

```
plugins/<plugin-name>/
├── plugin.json          # required
├── mcp.json             # optional, MCP servers
└── skills/
    └── <skill-name>/
        └── SKILL.md     # required per skill
```

`SKILL.md` follows the [Agent Skills spec](https://agentskills.io/specification). The frontmatter
`name` must match its directory name, and `description` must say **what it does and when to use it** —
that sentence is the only thing loaded at startup, so it is what decides whether the skill ever fires.

## Adding a plugin

1. Create `plugins/<name>/` with `plugin.json` and at least one skill.
2. Add an entry to [`.claude-plugin/marketplace.json`](../.claude-plugin/marketplace.json). This is
   the step that actually ships it — a plugin directory with no marketplace entry installs for nobody.
3. Add a CODEOWNERS line for the new directory naming the owning team.
4. Scan locally before pushing:
   ```bash
   skillspector scan plugins/<name> --no-llm
   ```
5. Open a PR. CI scans, uploads SARIF, and arms auto-merge if you pass.

## Writing skills that survive review

- **Scope `allowed-tools` to the narrowest thing that works.** `Bash(git diff:*)` — not `Bash`.
  Broad tool grants are an AST03 finding and will cost you a review round.
- **Keep `SKILL.md` under 500 lines.** Push detail into `references/`; it loads on demand.
- **No network fetches of instructions.** A skill that curls a prompt at runtime is unreviewable,
  because what shipped is not what runs.
- **Say what not to do.** The rules that stop bad output are worth more than the steps.

## What a failure looks like

[`tests/fixtures/known-bad/`](../tests/fixtures/) is a worked example of a skill that will not
merge — a benign-sounding `description` over a body that exfiltrates credentials, pipes a remote
script to `sudo bash`, and grants itself bare `Bash`. Read it once before writing your first skill;
it is the shortest description of what the gate is looking for.

Do not copy from it, and do not move it under `plugins/`.

## Versioning

Bump `version` in both `plugin.json` and the marketplace entry in the same PR. They are checked
against each other in review.
