# Security model

## Why this repo is a trust boundary

Installing this marketplace grants every listed plugin's skills to an agent running on an
engineer's machine, with that engineer's credentials. A merged PR here executes on every installed
machine on next update. Treat a change to `plugins/**` as you would a change to a shared base image.

## Controls

| Control | Where |
|---------|-------|
| Automated scan of every changed plugin | [`skill-scan.yml`](../.github/workflows/skill-scan.yml) |
| Fail-closed on scanner error | `Enforce policy` step, exit code `2` |
| Findings as SARIF in code scanning | `github/codeql-action/upload-sarif@v3` — **requires GHAS on a private repo**, see below |
| 90-day retained scan reports | `actions/upload-artifact@v4` — audit trail |
| Human approval before merge | [`CODEOWNERS`](../CODEOWNERS) + branch protection |
| Pinned scanner version | `SKILLSPECTOR_VERSION` — bump is security-reviewed |
| Least-privilege CI | top-level `permissions: {}`, per-job opt-in, `persist-credentials: false` |
| Model credential scoped + rotatable | Gemini key as an Actions secret; unreadable by fork PRs |
| Ephemeral scan environment | GitHub-hosted runners, fresh per job |

## Code scanning entitlement

SARIF upload is **non-fatal**. On a private repository, GitHub code scanning requires GitHub
Advanced Security; without it the API returns `403 Code scanning is not enabled` and the upload step
logs a failure but does not block the merge gate. That is deliberate — a missing reporting surface
is not a security failure, and the scan verdict, job summary, and 90-day artifact are unaffected.

To get findings into the Security tab, one of:

- move the repo to an org with GHAS licensing (the intended end state for an org marketplace),
- make the repository public — code scanning is free for public repos, or
- accept the artifact + job summary as the finding surface.

Until one is chosen, read findings from the run's job summary or download the
`skillspector-<plugin>` artifact.

## Fork PRs

Fork PRs run with a read-only token and cannot write security events, so SARIF upload is skipped.
The scan still runs and still blocks. Findings are in the job summary and artifact.

## Required branch protection on `main`

Auto-merge is only safe because these are enforced. Set them when standing up the repo:

- Require a pull request before merging, with **Require review from Code Owners**
- Require the **`Gate`** status check — and only that one. `Scan <plugin>` are matrix jobs whose
  names change with the plugin set; requiring them by name means a newly added plugin produces an
  unrequired check and merges ungated. `Gate` aggregates them under a stable name.
- Require branches to be up to date before merging
- Dismiss stale approvals on new commits
- Do not allow bypassing the above (including for admins)
- Enable **Allow auto-merge** at the repository level

## Semantic stage credentials

The optional LLM pass uses `SKILLSPECTOR_PROVIDER=openai_compatible` pointed at Gemini's
OpenAI-compatible endpoint.

**1. Get a Gemini API key** from [Google AI Studio](https://aistudio.google.com/apikey).

**2. Add it as a repository _secret_** (Settings → Secrets and variables → Actions → **Secrets**):

| Secret | Value |
|--------|-------|
| `SKILLSPECTOR_COMPAT_API_KEY` | your Gemini API key |

**3. Add these as repository _variables_** (same page, **Variables** tab — neither is sensitive):

| Variable | Value |
|----------|-------|
| `SKILLSPECTOR_COMPAT_BASE_URL` | `https://generativelanguage.googleapis.com/v1beta/openai/` (this is the default; only set it to override) |
| `SKILLSPECTOR_MODEL` | e.g. `gemini-3.7-flash` — confirm the current model id in AI Studio |

Leaving the secret unset is a supported state: the gate runs static-only.

### Local credentials

Copy [`.env.example`](../.env.example) to `.env` and fill in your key. `.env` is gitignored;
`.env.example` is the committed template.

**SkillSpector does not auto-load `.env`** — it has no `python-dotenv` dependency and reads the
process environment only. Export it yourself:

```bash
set -a; source .env; set +a
```

A `.env` that merely exists changes nothing, which fails quietly: the scan falls back to whatever
`SKILLSPECTOR_PROVIDER` defaults to (`nv_build`) and errors on a missing key, rather than telling
you the file was ignored.

### Verify before touching CI

Run the fixture locally. This is the fastest way to confirm the key, base URL, and model id all
work together, and it exercises the same path CI takes:

```bash
export SKILLSPECTOR_PROVIDER=openai_compatible
export SKILLSPECTOR_COMPAT_API_KEY='<your-gemini-key>'
export SKILLSPECTOR_COMPAT_BASE_URL='https://generativelanguage.googleapis.com/v1beta/openai/'
export SKILLSPECTOR_MODEL='gemini-3.7-flash'
skillspector scan tests/fixtures/known-bad
echo "exit=$?"   # expect 1
```

`exit=1` means the whole chain works. A credentials error means the key or base URL is wrong; a
model error means the model id is not valid for this endpoint.

### Tradeoff accepted

This is a long-lived API key stored in GitHub — the thing an OIDC-federated `bedrock` role would
have avoided. It is the cheaper path to running, and the blast radius is a Gemini quota rather than
cloud access. Rotate it on a schedule, and scope it to its own Google Cloud project. If the repo
later holds skills whose source should not leave the network, `ollama` or a self-hosted
`openai_compatible` endpoint removes the egress without changing the workflow shape.

### Optional: model token budgets

Each provider bundles a `model_registry.yaml` of context/output-token metadata. Gemini models are
not in the `openai_compatible` bundle, so SkillSpector falls back to conservative defaults. Point
`SKILLSPECTOR_MODEL_REGISTRY` at your own YAML to declare Gemini's larger context window if you hit
truncation on big skills.

## Reporting

Found a malicious or vulnerable skill that shipped? Do not open a public issue.
Mail security@example.com, or open a private security advisory on this repo.
