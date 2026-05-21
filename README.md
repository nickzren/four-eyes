# Four Eyes

Four Eyes is a practical workflow for using AI agents with independent review, explicit gates, and human approval.

It is not a fully autonomous agent framework. The core rule is simple:

> Agents can draft, review, and execute, but a human owns approval for risky actions.

## Why This Exists

AI agents are useful, but one agent working end to end can miss context, over-trust its own plan, or drift past the requested scope. Four Eyes adds a lightweight review structure:

- one orchestrator agent owns the plan and execution
- two reviewer agents provide independent judgment
- a human approves risky actions
- an issue tracker records gates, decisions, and verification

## When To Use It

Use Four Eyes for work that is important enough to need an explicit review gate:

- production changes
- infrastructure or cloud changes
- security remediation
- data cleanup
- migrations
- complex debugging
- multi-repo changes
- any action that is costly, destructive, or hard to reverse

Skip it for trivial work:

- one-line fixes
- small doc edits
- queue triage
- simple issue tracker admin
- tasks the human explicitly wants handled directly

## Workflow Summary

1. Create a local executable plan when the task needs one.
2. Create or update one issue tracker item from that plan.
3. Ask two reviewers to review independently before reading each other.
4. The orchestrator synthesizes feedback and updates the plan if needed.
5. A human approves execution when required.
6. The orchestrator executes only the approved slice.
7. The issue closes only after verification, or moves to a waiting state.

## Repository Contents

- [Playbook](docs/playbook.md)
- [Templates](docs/templates.md)
- [Issue tracker setup](docs/issue-tracker-setup.md)
- [Examples](examples/)

## Principles

- Be brief, simple, and necessary.
- Review against the task, not against unrelated improvement ideas.
- Keep sensitive data out of public issues, commits, and summaries.
- Prefer narrow verification over broad noisy checks.
- Treat any reviewer block as a real gate until resolved or overridden by the human.

## License

MIT

