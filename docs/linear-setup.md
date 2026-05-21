# Linear Setup

Use this when a human already has:

- a Linear workspace
- an agent with Linear access
- permission to create documents and issues

## Agent Prompt

```text
Set up Four Eyes in Linear.

Use this repository as the source:
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

Keep everything brief, generic, and public-safe. Do not include company names, secrets, internal links, or real task history.
```

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

