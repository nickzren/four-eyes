# Agent Instructions

This file is for agents editing the version-controlled Four Eyes repo. Agents using the workflow on other repos should follow the synced Linear workflow docs.

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
- When workflow docs are committed and pushed, sync the matching Linear docs by default unless the human explicitly asks for a repo-only change.
- Record the pushed repo commit SHA in the Linear review issue or sync note after syncing.

## Verification

Before committing, run:

```bash
git diff --check
```

Also run a public-safety scan for private company names, real issue links, account IDs, credentials, real logs, and sensitive identifiers before publishing.
