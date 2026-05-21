# Linear Setup

Use this when a human already has:

- a Linear workspace
- an agent with Linear access
- permission to create documents and issues

## Agent Prompt

```text
Set up Four Eyes in Linear.

Source repo: https://github.com/nickzren/four-eyes

If the repo is not available locally, clone or read the source repo first. Then use it as the source:
- README.md
- docs/playbook.md
- docs/templates.md
- docs/issue-tracker-setup.md

Create:
- a project or workspace area named Four Eyes
- a Playbook document from docs/playbook.md
- a Templates document from docs/templates.md
- one standing issue for future workflow-doc reviews

If custom workflow states are available, use:
- Backlog
- Todo
- In Progress
- Review
- Approval
- Waiting External Eval
- Done

If custom states are not available, use labels:
- gate:review
- gate:approval
- waiting:external-eval
- state:applied-awaiting-verification
- blocked:<reason>

Keep everything brief, generic, and public-safe. Do not include company names, secrets, internal links, or real task history. If repo or Linear access is missing, stop and say exactly what access is needed.
```

## Sync Rule

Treat this repo as the source of truth.

When updating the workflow:

1. Update this repo.
2. Commit the repo change.
3. Sync the matching Linear documents.
4. Record the repo commit SHA in the Linear review issue or sync note.

If Linear is edited first, backport the change into this repo before treating it as durable.

## Standing Review Issue

Title:

```text
Review: Four Eyes workflow docs
```

Description:

```text
Use this issue for reviews of the Four Eyes playbook and templates.

Source docs:
- Playbook
- Templates

Boundary:
- Workflow-doc review only
- Brief, simple, necessary comments
- No private task history or sensitive data
```
