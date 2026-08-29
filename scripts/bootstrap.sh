#!/usr/bin/env bash
# Adapt this reference marketplace to your own org.
#
# Rewrites every placeholder that would otherwise silently misbehave in a fork -
# most importantly CODEOWNERS, which names an account that does not exist in
# your org and would make required code-owner review unsatisfiable.
#
# Dry-run by default. Nothing is written without --apply.
set -euo pipefail

ORG=""; REPO=""; TEAM=""; SEC_TEAM=""; DOMAIN=""; APPLY=0; PROTECT=0
MODEL=""; CTX=""; MAXOUT=""

usage() {
  cat <<'USAGE'
Usage: scripts/bootstrap.sh --org ORG --repo REPO [options]

Required:
  --org ORG              GitHub org or user that will own the fork
  --repo REPO            Repository name

Options:
  --team TEAM            Team owning plugins       (default: platform-team)
  --security-team TEAM   Team owning gate + policy (default: security)
  --email-domain DOMAIN  Replaces example.com in manifests
  --model ID             Model you will configure, e.g. claude-sonnet-4-6.
                         Replaces the token-budget registry entry, so the
                         scanner stops assuming a 128k context for your model.
  --context-length N     Context window for --model   (default 200000)
  --max-output N         Max output tokens for --model (default 8192)
  --apply                Write the changes (default: dry-run)
  --protect              Also apply branch protection and enable auto-merge
                         (needs gh auth, and the repo must already exist)
  -h, --help             Show this help

Examples:
  scripts/bootstrap.sh --org acme --repo skills                  # preview
  scripts/bootstrap.sh --org acme --repo skills --apply
  scripts/bootstrap.sh --org acme --repo skills --apply --protect \
      --team platform --security-team appsec --email-domain acme.com \
      --model claude-sonnet-4-6 --context-length 200000 --max-output 64000

For a personal account with no teams, pass --team and --security-team as your
username; the script will write @username instead of @org/team.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --org) ORG="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    --team) TEAM="$2"; shift 2 ;;
    --security-team) SEC_TEAM="$2"; shift 2 ;;
    --email-domain) DOMAIN="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --context-length) CTX="$2"; shift 2 ;;
    --max-output) MAXOUT="$2"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    --protect) PROTECT=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument '$1'" >&2; usage >&2; exit 2 ;;
  esac
done

[ -n "$ORG" ]  || { echo "error: --org is required" >&2; usage >&2; exit 2; }
[ -n "$REPO" ] || { echo "error: --repo is required" >&2; usage >&2; exit 2; }
[ -f .claude-plugin/marketplace.json ] || {
  echo "error: run this from the repository root" >&2; exit 2; }

TEAM="${TEAM:-platform-team}"
SEC_TEAM="${SEC_TEAM:-security}"
DOMAIN="${DOMAIN:-$ORG.com}"

# A personal account has no teams; @org/team would never resolve.
if [ "$TEAM" = "$ORG" ]; then OWNER="@$ORG"; else OWNER="@$ORG/$TEAM"; fi
if [ "$SEC_TEAM" = "$ORG" ]; then SEC_OWNER="@$ORG"; else SEC_OWNER="@$ORG/$SEC_TEAM"; fi

echo "org/repo     : $ORG/$REPO"
echo "plugin owner : $OWNER"
echo "gate owner   : $SEC_OWNER"
echo "email domain : $DOMAIN"
[ "$APPLY" -eq 1 ] && echo "mode         : APPLY" || echo "mode         : dry-run (pass --apply to write)"
echo

FILES=$(git ls-files '*.md' '*.json' '*.yml' CODEOWNERS 2>/dev/null \
        | grep -v '^tests/fixtures/' || true)

python3 - "$ORG" "$REPO" "$OWNER" "$SEC_OWNER" "$DOMAIN" "$APPLY" $FILES <<'PY'
import sys, pathlib, re
org, repo, owner, sec_owner, domain, apply_ = sys.argv[1:7]
apply_ = apply_ == "1"
files = sys.argv[7:]

subs = [
    (r"@junninho-orca/security",  sec_owner),
    (r"@example-org/security",    sec_owner),
    (r"@junninho-orca",           owner),
    (r"@example-org/[a-z-]+",     owner),
    (r"junninho-orca/org-skills", f"{org}/{repo}"),
    (r"example-org/org-skills",   f"{org}/{repo}"),
    (r"@example\.com",            f"@{domain}"),
]
# CODEOWNERS lines that must stay with the security owner.
sec_paths = ("/docs/skill-policy.md", "/.github/workflows/", "/CODEOWNERS",
             "/.skillspector-baseline.yaml", "/tests/fixtures/",
             "/.claude-plugin/marketplace.json")

total = 0
for f in files:
    p = pathlib.Path(f)
    if not p.exists(): continue
    orig = p.read_text(); t = orig
    for pat, rep in subs:
        t = re.sub(pat, rep, t)
    if p.name == "CODEOWNERS":
        out = []
        for line in t.splitlines():
            if line.startswith(sec_paths) and sec_owner not in line:
                line = re.sub(r"@\S+.*$", sec_owner, line)
            out.append(line)
        t = "\n".join(out) + "\n"
    if t != orig:
        n = sum(1 for a, b in zip(orig.splitlines(), t.splitlines()) if a != b)
        n = n or 1
        total += n
        print(f"  {f}  ({n} line{'s' if n != 1 else ''})")
        if apply_: p.write_text(t)

print()
print(f"{total} lines {'rewritten' if apply_ else 'would change'}")
if not apply_:
    print("Re-run with --apply to write them.")
PY

REG=.github/skillspector-model-registry.yaml
if [ -n "$MODEL" ]; then
  CTX="${CTX:-200000}"; MAXOUT="${MAXOUT:-8192}"
  echo
  echo "model registry: $MODEL (context $CTX, max output $MAXOUT)"
  if [ "$APPLY" -eq 1 ]; then
    cat > "$REG" <<REGEOF
# Token-budget metadata for models absent from SkillSpector's bundled registries.
#
# Without an entry here SkillSpector assumes a 128000-token context. That is not
# only noisy: under-declaring the window can truncate a large skill during
# semantic analysis, and the unanalysed tail is where something would hide.
#
# Verify these numbers against your provider's documentation. A wrong value is
# worse than no file at all.

models:
  $MODEL:
    context_length: $CTX
    max_output_tokens: $MAXOUT
REGEOF
    echo "  wrote $REG"
  else
    echo "  would rewrite $REG"
  fi
fi

if [ "$PROTECT" -eq 1 ]; then
  [ "$APPLY" -eq 1 ] || { echo; echo "error: --protect requires --apply" >&2; exit 2; }
  command -v gh >/dev/null || { echo "error: gh CLI not found" >&2; exit 2; }
  echo
  echo "Applying branch protection to $ORG/$REPO ..."
  gh api -X PUT "repos/$ORG/$REPO/branches/main/protection" --input - >/dev/null <<JSON
{
  "required_status_checks": { "strict": true, "contexts": ["Gate"] },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": true,
    "required_approving_review_count": 1,
    "require_last_push_approval": true
  },
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "block_creations": false,
  "required_conversation_resolution": true
}
JSON
  echo "  required check: Gate  |  code-owner review: required  |  force pushes: blocked"
  gh repo edit "$ORG/$REPO" --enable-auto-merge >/dev/null && echo "  auto-merge enabled"
  echo
  echo "NOTE: enforce_admins is false, so an admin can still bypass. Set it true"
  echo "      once you have a second maintainer - see docs/SECURITY.md."
fi

cat <<NEXT

Remaining steps this script cannot do for you:

  1. Replace the example plugins under plugins/ with your own, and update
     .claude-plugin/marketplace.json to match.
  2. Optional - enable semantic analysis. Any provider works; static analysis
     needs no credentials at all:
       gh variable set SKILLSPECTOR_PROVIDER --body <provider>
       gh variable set SKILLSPECTOR_MODEL    --body <model-id>
       gh secret   set <PROVIDER_CREDENTIAL>
     Full matrix: docs/skill-policy.md. If you configure a model, re-run this
     script with --model so its token budget is declared.
  3. plugins/incident-response/mcp.json points at https://mcp.example.com -
     an illustrative endpoint, left alone deliberately rather than rewritten
     to a host that would not resolve. Change it or drop the plugin.
  4. Keep tests/fixtures/known-bad/ - it is what proves the gate still works.

NEXT
