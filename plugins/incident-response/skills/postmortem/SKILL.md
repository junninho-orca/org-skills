---
name: postmortem
description: Drafts a blameless postmortem in the org template from an incident timeline, including contributing factors and concrete action items with owners. Use after an incident is resolved, or when asked to "write the postmortem", "do an RCA", or "what are the follow-ups".
license: Apache-2.0
allowed-tools: Read Grep
metadata:
  org.example.owner: sre
  org.example.review-tier: elevated
---

# Postmortem

Write the document that stops the incident from recurring.

## Prerequisites

Start from a timeline. If none exists, run the `incident-timeline` skill first — a postmortem written from memory encodes the wrong cause.

## Template

```markdown
# <Incident title> — <date>

**Severity:** <SEV1-4>  **Duration:** <detection to resolution>  **Author:** <name>

## Impact
<who was affected, how many, for how long, in user-visible terms>

## Timeline
<link or inline the timeline>

## Contributing factors
<plural, always. List each factor and how it combined with the others.>

## What went well
<detection, tooling, or decisions that worked — these are worth protecting>

## Action items
| Action | Type | Owner | Due |
|--------|------|-------|-----|
| <specific change> | prevent / detect / mitigate | <team or person> | <date> |
```

## Rules

- **Contributing factors, not root cause.** Real incidents have several. If you have written exactly one, look again for what let it reach production.
- Blameless means describing the system that made the action reasonable. "The deploy tool showed a stale diff" — not "X deployed the wrong thing".
- Every action item must be a change someone can merge or configure. "Be more careful" and "improve monitoring" are not action items.
- Tag each action item **prevent**, **detect**, or **mitigate**. A postmortem with only *prevent* items has not reduced the next incident's duration.
- Leave the owner blank rather than assigning someone who has not agreed to it.
