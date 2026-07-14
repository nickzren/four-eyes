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
- docs/linear-setup.md

Create:
- a project or workspace area named Four Eyes
- a Default Workflow document from the README.md Default Workflow section
- a Playbook document from docs/playbook.md
- a Templates document from docs/templates.md
- an Issue Tracker Setup document from docs/issue-tracker-setup.md
- a Linear Setup document from docs/linear-setup.md
- one standing issue for future workflow-doc reviews

If custom workflow states are available, use:
- Backlog
- Todo
- In Progress
- Review
- Approval
- Blocked
- Waiting External Eval
- Done

If custom states are not available, use labels:
- gate:review
- gate:approval
- waiting:external-eval
- state:applied-awaiting-verification
- blocked:<reason>

Make phase branch mode with implementation-first flow the default high-throughput path. Make review transport default to `pr` when the repo has a remote and CI or branch protection, otherwise `manual-relay`. Make post-merge branch cleanup default to `yes` and abandoned branch cleanup default to `ask`. Make the Codex-led default use the named isolated Reviewer 1 subagent `reviewer1`, reused across phases and review rounds for the same parent workflow. The orchestrator launches only internal Reviewer 1 and never launches an external reviewer. The human relays every external prompt, including every Reviewer 2 prompt. Require a fresh external Reviewer 2 session for the parent workflow unless the human explicitly chooses otherwise. Require each task issue and verdict to record the current review round, exact transport-specific artifact identity, and workflow revision. Until document markers exist, use the full pushed repo commit SHA in the latest successful sync note on the standing workflow-doc review issue as the authoritative workflow revision. Hold orchestrator-carried verdicts until all expected slots have returned or have a terminal record, then post them verbatim before synthesis. If the task input is not clear enough to execute safely, have the orchestrator write a temporary local executable plan, have reviewers confirm it when it defines the work, keep it uncommitted, and remove it after closeout.

Keep everything brief, generic, and public-safe. Do not include company names, secrets, internal links, or real task history. If repo or Linear access is missing, stop and say exactly what access is needed.
```

## Sync Rule

Treat this repo as the source of truth.

Runtime docs:
- Four Eyes Default Workflow
- Four Eyes Playbook
- Four Eyes Templates
- Four Eyes Issue Tracker Setup

Maintainer doc:
- Four Eyes Linear Setup

When updating the workflow:

1. Update this repo.
2. Commit the repo change.
3. Push the repo change.
4. Sync the matching Linear documents from the pushed commit by default unless the human explicitly asks for a repo-only change.
5. Record the full pushed repo commit SHA in a successful sync note on the standing workflow-doc review issue. Until document-level revision markers exist, the latest such note is the authoritative workflow revision.

If Linear is edited first, backport the change into this repo before treating it as durable.

## Standing Review Issue

Title:

```text
Review: Four Eyes workflow docs
```

Description:

```text
Use this issue for reviews of the Four Eyes default workflow, playbook, templates, issue tracker setup, and Linear setup.

Source docs:
- Default Workflow
- Playbook
- Templates
- Issue Tracker Setup
- Linear Setup

Boundary:
- Workflow-doc review only
- Brief, simple, necessary comments
- No private task history or sensitive data

Latest successful sync note:
- Workflow revision: <full pushed repo commit SHA>
```
