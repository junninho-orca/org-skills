---
name: incident-timeline
description: Builds a minute-by-minute incident timeline from logs, deploy history, and alert records, separating observed facts from inference. Use during or after an incident, when asked to "reconstruct what happened", "build a timeline", or "when did this start".
license: Apache-2.0
compatibility: Requires read access to the org log store and deploy history
allowed-tools: Bash(git log:*) Read Grep
metadata:
  org.example.owner: sre
  org.example.review-tier: elevated
---

# Incident timeline

Reconstruct what happened, in order, with a source for every line.

## Steps

1. Establish the window. Ask for the first alert time and the resolution time if you do not have them. Work in UTC throughout and label it.
2. Collect events from each available source, keeping the source name attached to every event:
   - alert firing and clearing times
   - deploys and config/flag changes in the window (extend the search 2 hours before the first alert — the trigger usually predates the symptom)
   - error-rate and latency inflection points
   - human actions from the incident channel
3. Merge into one ordered list.
4. Mark each entry as **[observed]** or **[inferred]**.

## Output

```markdown
## Timeline (UTC)

| Time | Event | Source | Confidence |
|------|-------|--------|------------|
| 14:02 | Deploy `api@4a1c2` to prod | deploy log | observed |
| 14:09 | 5xx rate crosses 2% | metrics | observed |
| 14:09 | Deploy is the likely trigger | — | inferred |

## Gaps
<windows with no telemetry, and what would have covered them>
```

## Rules

- Never present an inference as an observation. If no source supports a line, mark it inferred and name the reasoning.
- Absence of a log is not evidence of absence of an event. Record it under **Gaps**.
- Do not name individuals as causes. Record actions ("a rollback was started at 14:31"), not blame.
- Keep the timeline separate from the analysis. This skill produces the sequence; `postmortem` produces the conclusions.
