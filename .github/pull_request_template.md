## What this adds or changes

<!-- The capability, in a sentence. -->

## Plugin(s) touched

<!-- e.g. plugins/dev-workflow -->

## Reviewer checklist

The scanner covers AST01–04, AST08–10. These are the parts it cannot judge:

- [ ] `allowed-tools` is the narrowest set that works (no bare `Bash`)
- [ ] The `description` matches what the body actually instructs the agent to do
- [ ] No skill fetches instructions over the network at runtime
- [ ] `plugin.json` `version` and the `.claude-plugin/marketplace.json` entry agree
- [ ] Marketplace entry added/updated if this ships a new plugin
- [ ] CODEOWNERS names an owning team for any new directory

## Scan

<!-- Leave blank; CI fills Security -> Code scanning. Note any baseline suppression + reason here. -->
