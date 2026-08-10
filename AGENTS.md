# Agent Instructions

This file is for agents editing the version-controlled Four Eyes repo. Agents using the workflow on other repos should load policy from one recorded full commit SHA in this repository.

## Style

- Be brief, simple, and necessary.
- Include enough exact information for another human or AI to continue safely.
- Do not add narrative padding.

## Scope

- Keep this repository public-safe.
- Do not add company names, private issue links, account IDs, credentials, regulated personal data, customer data, or real operational logs.
- Use generic examples only.

## Editing

- Read existing docs before changing workflow language.
- Preserve the human-approved framing.
- Do not make the project sound like a fully autonomous agent framework.
- Update examples when the playbook or templates change materially.
- Update the selected pull request, GitHub parent issue, or temporary local coordination record when workflow state changes.
- Record the full workflow commit SHA in coordination records, reviewer packets, and verdicts.

## Verification

Before committing, run:

```bash
ruby -w -c scripts/check-docs.rb
ruby scripts/check-docs.rb --write-derived
ruby scripts/check-docs.rb --self-test
ruby scripts/check-docs.rb
git diff --check
```

The local bare `git diff --check` validates the uncommitted tree. CI deliberately validates the event's committed range instead.

Also run a public-safety scan for private company names, real issue links, account IDs, credentials, real logs, and sensitive identifiers before publishing.
