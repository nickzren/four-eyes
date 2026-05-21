# Agent Instructions

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
- If asked to update an operational Linear copy of this workflow, update this repo and Linear in the same task.
- Record the repo commit SHA in the Linear review issue or sync note after syncing.

## Verification

Before committing, run:

```bash
git diff --check
```

Also run a public-safety scan for private company names, real issue links, account IDs, credentials, real logs, and sensitive identifiers before publishing.
