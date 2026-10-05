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

- Read the README before changing workflow language.
- Preserve the human-approved framing.
- Do not make the project sound like a fully autonomous agent framework.
- Keep the policy short. Prefer removing or merging a rule over adding one.

## Verification

Before committing, run:

```bash
git diff --check
```

CI also checks whitespace on the committed range and that relative Markdown links resolve.

Also run a public-safety scan for private company names, real issue links, account IDs, credentials, real logs, and sensitive identifiers before publishing.
