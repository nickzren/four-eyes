# Four Eyes

Human-approved multi-agent review workflow.

Four Eyes uses the four-eyes principle: high-stakes work should not proceed on one agent's judgment alone.

Four Eyes helps you use AI agents without pretending they are fully autonomous. Agents can plan, review, and execute, but a human approves risky actions.

Unlike role-heavy agent frameworks, Four Eyes asks AI reviewers to judge the same plan independently.

## Shape

- one orchestrator agent owns the plan and execution
- two reviewer agents give independent feedback
- one human approves risky actions
- one issue tracks gates, decisions, and verification

```mermaid
flowchart LR
    Plan["Local plan"] --> Issue["Issue tracker gate"]
    Issue --> R1["Reviewer 1"]
    Issue --> R2["Reviewer 2"]
    R1 --> Synth["Orchestrator synthesis"]
    R2 --> Synth
    Synth --> Decision{"Any blocker?"}
    Decision -->|Yes| Revise["Revise plan or ask human override"]
    Revise --> Issue
    Decision -->|No| Approve["Human approval"]
    Approve --> Execute["Execute approved slice"]
    Execute --> Verify["Verify"]
    Verify --> Close{"Done?"}
    Close -->|No| Wait["Waiting external eval"]
    Wait --> Verify
    Close -->|Yes| Done["Close issue"]
```

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

[Linear](https://linear.app/) works well as the issue tracker for Four Eyes.

Prerequisite: you already have a Linear workspace and your agent has Linear access.

Copy this into Codex, Claude Code, or another agent:

```text
Set up Four Eyes in Linear.

Source repo: https://github.com/nickzren/four-eyes

If the repo is not available locally, clone or read the source repo first. Then use:
- README.md
- docs/playbook.md
- docs/templates.md
- docs/linear-setup.md

Create or update Linear docs for the playbook and templates. Create a standing workflow-doc review issue. Keep it brief, public-safe, and generic. Do not add company names, secrets, internal links, or real task history. If repo or Linear access is missing, stop and say exactly what access is needed.
```

## Run Your First Review

```text
Use Four Eyes for this task.

Repo path: <repo path>
Plan path: <local plan path>
Issue tracker: <Linear/GitHub/Jira/etc.>

Act as orchestrator. Create or update one issue from the plan, set the gate to Review, and give me Reviewer 1 and Reviewer 2 prompts. Do not execute yet.
```

## Example Agent Mix

Current default:

- Orchestrator: Codex
- Reviewer 1: Codex
- Reviewer 2: Claude Code

These roles are not fixed. Use the strongest current agent for orchestration, and use independent reviewers that give useful disagreement.

## Source Of Truth

Use this repo as the version-controlled source.

If you maintain a Linear copy, update this repo and Linear in the same task. Do not let tracker docs become the only durable copy.

## License

MIT
