# Four Eyes

Human-approved multi-agent review workflow.

Four Eyes helps you use AI agents without pretending they are fully autonomous. Agents can plan, review, and execute, but a human approves risky actions.

## Shape

- one orchestrator agent owns the plan and execution
- two reviewer agents give independent feedback
- one human approves risky actions
- one issue tracks gates, decisions, and verification

## Use It For

- production changes
- infrastructure or cloud changes
- security fixes
- data cleanup
- migrations
- complex debugging
- multi-repo work

Skip it for one-line fixes, tiny docs, and simple queue/admin work.

## Start

- [Playbook](docs/playbook.md)
- [Templates](docs/templates.md)
- [Linear setup](docs/linear-setup.md)
- [Issue tracker setup](docs/issue-tracker-setup.md)
- [Examples](examples/)

## Linear Quick Setup

Prerequisite: you already have a Linear workspace and your agent has Linear access.

Copy this into Codex, Claude Code, or another agent:

```text
Set up Four Eyes in Linear.

Use the files in this repo:
- docs/playbook.md
- docs/templates.md
- docs/linear-setup.md

Create or update Linear docs for the playbook and templates. Create a standing workflow-doc review issue. Keep it brief, public-safe, and generic. Do not add company names, secrets, internal links, or real task history.
```

## Source Of Truth

Use this repo as the version-controlled source.

If you maintain a Linear copy, update this repo and Linear in the same task. Do not let tracker docs become the only durable copy.

## License

MIT
