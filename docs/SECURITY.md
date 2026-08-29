# Security model

## Why this repo is a trust boundary

Installing this marketplace grants every listed plugin's skills to an agent running on an
engineer's machine, with that engineer's credentials. A merged PR here executes on every installed
machine on the next update. Treat a change under `plugins/` as you would a change to a shared base
image.

## Controls

| Control | Where |
|---------|-------|
| Every changed plugin scanned before merge | [`skill-scan.yml`](../.github/workflows/skill-scan.yml) |
| Scheduled proof the scanner still detects | [`scanner-health.yml`](../.github/workflows/scanner-health.yml) |
| Fail closed on scanner error | `Enforce policy` step — exit `2` blocks |
| Human approval before merge | [`CODEOWNERS`](../CODEOWNERS) + branch protection |
| Pinned scanner version | `SKILLSPECTOR_VERSION`, identical in both workflows |
| Actions pinned by commit SHA | A moved tag would run arbitrary code beside the model key |
| Least-privilege CI | top-level `permissions: {}`, per-job opt-in, `persist-credentials: false` |
| Ephemeral scan environment | GitHub-hosted runners, fresh per job |
| 90-day retained reports | `actions/upload-artifact` — audit trail |
| Findings as SARIF | `github/codeql-action/upload-sarif` — see [entitlement](#code-scanning-entitlement) |

## Required branch protection on `main`

Auto-merge is only safe because these are enforced. `scripts/bootstrap.sh --protect` applies them;
set them by hand if you prefer.

- Require a pull request before merging, with **Require review from Code Owners**
- Require the **`Gate`** status check — **and only that one**. `Scan <plugin>` are matrix jobs whose
  names change with the plugin set, so requiring them by name means a newly added plugin produces
  an unrequired check and merges ungated. `Gate` aggregates them under a stable name.
  Do not require `Scanner health`: it does not run on ordinary PRs, and a required check that never
  reports blocks every PR forever.
- Require branches to be up to date before merging
- Dismiss stale approvals on new commits
- Enable **Allow auto-merge** at the repository level

### On `enforce_admins`

The bootstrap sets it **false**, because with one maintainer a required approval you cannot give
yourself locks you out of your own repository. That is a starting position, not the destination:
while it is false, the review requirement constrains outside contributors but not you. Set it true
as soon as a second maintainer exists.

The same caveat applies to CODEOWNERS. A single owner approving their own security policy is not a
control — point the security-owned paths at a different team than the plugin paths as soon as you
have one.

## Semantic analysis (optional)

Static analysis is the default and needs no credentials. The optional LLM pass adds
description-vs-behavior mismatch detection, which pattern matching cannot do.

**Any** SkillSpector provider works: the workflow passes all of their credentials through, so
choosing one is a settings change rather than a workflow edit. The variable names for each are in
[skill-policy.md](skill-policy.md#semantic-analysis-optional).

1. Set `SKILLSPECTOR_PROVIDER` as a repository **variable**.
2. Set that provider's credential as a repository **secret**, and its endpoint and model settings as
   **variables** (Settings → Secrets and variables → Actions — note the two tabs).
3. Leave every other provider's settings unset. They are ignored.

Leaving all of them unset is supported: the gate runs static-only.

Two options avoid holding a long-lived model key at all:

- **`bedrock`** — set `SKILLSPECTOR_BEDROCK_ROLE_ARN` and the workflow assumes an OIDC-federated AWS
  role per run. No stored secret.
- **`ollama`**, or `openai_compatible` against a self-hosted endpoint — keeps skill source inside
  your network.

Otherwise you are storing a long-lived API key in GitHub. For a model API the blast radius is a
quota rather than cloud access, which makes it a reasonable default — rotate it on a schedule and
scope it to its own project.

### Declare your model's token budget

Each provider bundles a `model_registry.yaml` of context and output-token metadata. A model absent
from it falls back to a conservative **128000**-token context. `openai_compatible` targets arbitrary
endpoints and so bundles almost nothing.

This is not just log noise. Under-declaring the window can truncate a large skill during semantic
analysis, and in a security scanner the unanalysed tail is exactly where something would hide. The
scan still returns a verdict, so the coverage gap is silent.

[`.github/skillspector-model-registry.yaml`](../.github/skillspector-model-registry.yaml) declares
the limits, and the workflow points `SKILLSPECTOR_MODEL_REGISTRY` at it. `scripts/bootstrap.sh
--model` writes an entry for your model. Verify the numbers against your provider's documentation —
a wrong value there is worse than no file at all.

### Worked example: Gemini

What *this* repository happens to use. Nothing here is required by the gate.

| Kind | Name | Value |
|------|------|-------|
| Secret | `SKILLSPECTOR_COMPAT_API_KEY` | key from [Google AI Studio](https://aistudio.google.com/apikey) |
| Variable | `SKILLSPECTOR_PROVIDER` | `openai_compatible` |
| Variable | `SKILLSPECTOR_COMPAT_BASE_URL` | `https://generativelanguage.googleapis.com/v1beta/openai/` |
| Variable | `SKILLSPECTOR_MODEL` | `gemini-3.7-flash` |

Gemini has no native SkillSpector provider; it is reached through its OpenAI-compatible endpoint.
`openai_compatible` reads `SKILLSPECTOR_COMPAT_*` and deliberately **not** `OPENAI_API_KEY` /
`OPENAI_BASE_URL`, so stray OpenAI settings in the environment cannot silently redirect it.

The workflow sets no default base URL, by design: a baked-in one would send your skills to that
vendor whenever an adopter sets the provider but forgets the endpoint. Setting the key without the
URL fails the run with an explicit error rather than quietly dropping to static-only.

## Running a scan locally

SkillSpector reads the **process environment** only — it has no `python-dotenv` dependency, so a
`.env` file is never loaded. This repo ships no `.env.example` for that reason: a template for a
mechanism the tool ignores invites you to create a file, watch it do nothing, and get an error about
a missing key that never mentions the file.

Static-only needs no credentials at all:

```bash
skillspector scan plugins/dev-workflow --no-llm
```

To confirm a provider works end to end, scan the fixture — it exercises the same path CI takes and
must exit `1`:

```bash
export SKILLSPECTOR_PROVIDER='<provider>'
export SKILLSPECTOR_COMPAT_API_KEY='<key>'      # provider-specific; see the matrix
export SKILLSPECTOR_COMPAT_BASE_URL='<endpoint>'
export SKILLSPECTOR_MODEL='<model-id>'
skillspector scan tests/fixtures/known-bad
echo "exit=$?"   # expect 1
```

A credentials error means the key or endpoint is wrong; a model error means the model id is not
valid for that endpoint. If you keep credentials in a local file anyway, `.env` and `.env.*` are
gitignored — load it with `set -a; source .env; set +a` first.

## Code scanning entitlement

SARIF upload is **non-fatal**. On a private repository GitHub code scanning requires GitHub Advanced
Security; without it the API returns `403 Code scanning is not enabled`, and the upload step logs a
failure without blocking the gate. That is deliberate — a missing reporting surface is not a
security failure, and the verdict, job summary, and retained artifact are unaffected.

The consequence worth knowing: **a green run does not prove SARIF uploaded.** To get findings into
the Security tab, either move the repo to an org with GHAS, or make it public (code scanning is free
for public repos). Otherwise read findings from the job summary or the `skillspector-<plugin>`
artifact.

## Fork PRs

Fork PRs run with a read-only token. They cannot read repository secrets and cannot write security
events, so they scan static-only and skip the SARIF upload. The gate still runs and still blocks.

That is a real coverage difference, not just a degraded log line: the description-vs-behavior
mismatch check does not run on fork PRs. Weigh it when deciding whether to accept plugin
contributions from forks at all.

## Reporting

Found a malicious or vulnerable skill that shipped? Do not open a public issue. Open a private
security advisory on this repository.
