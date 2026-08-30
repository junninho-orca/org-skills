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
4. Check it locally before pushing — CI runs both of these:
   ```bash
   skillspector scan plugins/<name> --no-llm
   ```
   ```bash
   agentskills validate plugins/<name>/skills/<skill>
   ```
   The validator comes from `pipx install skills-ref==0.1.1`. Note the distribution is named
   `skills-ref` but the command it installs is `agentskills`; upstream's README documents a
   `skills-ref` command that the published wheel does not provide.
5. Open a PR. CI scans each changed plugin and arms auto-merge if you pass. The required check is
   **`Gate`**; the per-plugin `Scan <name>` jobs feed it. Findings are in the job summary and the
   90-day `skillspector-<plugin>` artifact — and in the Security tab if the repo has opted into
   SARIF upload with `SKILLSPECTOR_UPLOAD_SARIF`, which is off by default.

## Writing skills that survive review

- **Scope `allowed-tools` to the narrowest thing that works.** `Bash(git diff:*)` — not `Bash`.
  Broad tool grants are an AST03 finding and will cost you a review round.
- **Write `allowed-tools` as a space-separated string.** `Bash(git diff:*) Bash(git log:*) Read`.
  Not a comma-separated string, and **not** a YAML sequence — neither inline (`[a, b]`) nor block
  (`- a`). That is not style preference; it is the only form every consumer accepts:

  | Form | Agent Skills spec | `skills-ref` model | Claude Code |
  |---|---|---|---|
  | Space-separated string | documented format | `Optional[str]` | accepted |
  | Comma-separated string | wrong delimiter | is a `str` | accepted |
  | YAML sequence | not a string | **not `Optional[str]`** | accepted |

  A sequence looks like the portable choice and is the opposite. It happens to survive
  `skills-ref validate` today only because the validator checks field *names* and never
  type-checks this field's value — that is a gap in enforcement, not a contract. Do not build on
  the absence of a check in a repo that exists to argue against exactly that.

  Two caveats worth knowing. The field is marked **experimental** in the spec and support varies
  between implementations, so treat it as a review artifact documenting intent as much as an
  enforced control — the gate and the reviewer are what actually hold. And note that a scope like
  `Bash(git diff:*)` contains a space *inside* the parentheses, while the spec's own example
  (`Bash(git:*) Bash(jq:*) Read`) does not. Claude Code parses the narrow form correctly and the
  reference implementation never splits the string at all, but a consumer that naively splits on
  whitespace would mis-read it. We keep the narrow form: a real reduction in privilege beats
  hypothetical portability.
- **Every grant must appear in the body, and every command in the body must be granted.** An
  unused grant is over-privilege; a command the body instructs but the frontmatter omits is a
  skill that breaks on first use. Both are review rounds.
- **Keep `SKILL.md` under 500 lines.** Push detail into `references/`; it loads on demand.
- **No network fetches of instructions.** A skill that curls a prompt at runtime is unreviewable,
  because what shipped is not what runs.
- **Say what not to do.** The rules that stop bad output are worth more than the steps.

## What a failure looks like

[`tests/fixtures/README.md`](../tests/fixtures/README.md) walks through a skill that will not merge:
a benign-sounding `description` over a body that exfiltrates credentials, pipes a remote script to
`sudo bash`, and grants itself bare `Bash`. It is the shortest description of what the gate looks
for.

Read the README, not the fixture. The fixture files deliberately carry no warning of their own — the
whole point is that they look like an ordinary plugin — so nothing in them will stop you if you
start copying. Never move that directory under `plugins/`.

## Versioning

Bump `version` in both `plugin.json` and the marketplace entry in the same PR. They are checked
against each other in review.
