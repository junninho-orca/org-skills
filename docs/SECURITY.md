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
| Model credential scoped + rotatable | Actions secret, unreadable by fork PRs; or none at all via OIDC |
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

Static analysis is the default and needs no credentials. The optional LLM pass adds
description-vs-behavior mismatch detection, which pattern matching cannot do.

**Any** SkillSpector provider works — the workflow passes all of their credentials through, so
choosing one is a settings change, not a workflow edit. The full matrix of variable names is in
[skill-policy.md](skill-policy.md#semantic-analysis-optional).

The general shape, whichever provider you pick:

1. Set `SKILLSPECTOR_PROVIDER` as a repository **variable**.
2. Set that provider's credential as a repository **secret**, and its endpoint/model settings as
   **variables** (Settings → Secrets and variables → Actions — note the two tabs).
3. Leave every other provider's settings unset. They are ignored.

Leaving all of them unset is supported: the gate runs static-only.

Two options avoid holding a long-lived model key at all, worth considering before you store one:

- **`bedrock`** — set `SKILLSPECTOR_BEDROCK_ROLE_ARN` and the workflow assumes an OIDC-federated
  AWS role per run. No stored secret.
- **`ollama`**, or `openai_compatible` against a self-hosted endpoint — keeps skill source inside
  your network.

### Worked example: Gemini

What *this* repository uses, as one concrete instance of the above. Nothing here is required by the
gate.

| Kind | Name | Value |
|------|------|-------|
| Secret | `SKILLSPECTOR_COMPAT_API_KEY` | key from [Google AI Studio](https://aistudio.google.com/apikey) |
| Variable | `SKILLSPECTOR_PROVIDER` | `openai_compatible` |
| Variable | `SKILLSPECTOR_COMPAT_BASE_URL` | `https://generativelanguage.googleapis.com/v1beta/openai/` |
| Variable | `SKILLSPECTOR_MODEL` | `gemini-3.7-flash` — confirm the current id in AI Studio |

Gemini has no native SkillSpector provider; it is reached through its OpenAI-compatible endpoint.
`openai_compatible` reads `SKILLSPECTOR_COMPAT_*` and deliberately **not** `OPENAI_API_KEY` /
`OPENAI_BASE_URL`, so stray OpenAI settings cannot silently redirect it.

There is no default base URL in the workflow, by design. A baked-in one would send your skills to
that vendor whenever an adopter sets the provider but forgets the endpoint. Setting the key without
the URL fails the run with an explicit error rather than quietly dropping to static-only.

### Tradeoff of an API-key provider

An API key stored in GitHub is a long-lived credential, which the OIDC `bedrock` path avoids. For a
model API the blast radius is a quota rather than cloud access, which is why it is a reasonable
default — but rotate on a schedule and scope the key to its own project.

### Verify before touching CI

Run the fixture locally. Fastest way to confirm credentials, endpoint, and model id work together,
and it exercises the same path CI takes. Substitute your own provider's variables:

```bash
export SKILLSPECTOR_PROVIDER=openai_compatible
export SKILLSPECTOR_COMPAT_API_KEY='<your-key>'
export SKILLSPECTOR_COMPAT_BASE_URL='<your-endpoint>'
export SKILLSPECTOR_MODEL='<your-model>'
skillspector scan tests/fixtures/known-bad
echo "exit=$?"   # expect 1
```

`exit=1` means the whole chain works. A credentials error means the key or endpoint is wrong; a
model error means the model id is not valid for that endpoint.

### Optional: model token budgets

Each provider bundles a `model_registry.yaml` of context/output-token metadata. A model absent from
it falls back to conservative defaults — true for Gemini under `openai_compatible`. Point
`SKILLSPECTOR_MODEL_REGISTRY` at your own YAML to declare a larger context window if you hit
truncation on big skills.

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
