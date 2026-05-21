# Four Eyes Playbook

Use this workflow when a task is important enough to need independent agent judgment before execution, apply, deploy, merge, or another hard-to-reverse action.

## Communication Rule

Every agent message, issue, comment, review, synthesis, approval request, and closeout should be brief, simple, and necessary.

Include enough exact information for another human or AI to continue safely:

- repo or path
- plan path
- scope
- acceptance criteria
- current gate
- blockers
- commands
- approvals
- verification

Do not add narrative padding, duplicate old context, raw logs, secrets, or sensitive identifiers.

## Roles

### Orchestrator

Usually the primary agent session.

Responsibilities:

- create or update the local executable plan when needed
- create or update the issue tracker item from the plan
- decide whether the plan stays one issue or splits into execution-slice issues
- identify acceptance criteria, non-goals, and current git status before editing
- check existing implementation patterns before adding new ones
- keep sensitive data out of issues, commits, and broad summaries
- synthesize Reviewer 1 and Reviewer 2 feedback
- resolve blockers or ask the human for an explicit override
- execute only after the review gate is clear
- post verification, commit summary, and remaining risks
- after every issue or gate update, tell the human the current gate and exact next action

### Reviewer 1

Usually a separate agent session.

Responsibilities:

- review independently before reading other reviewer comments or orchestrator synthesis comments
- when prompted with a current-work issue reference, treat it as a review request: read the issue, review the current diff and verification evidence, and post the review as a comment on the same linked issue, even if the formal Reviewer Prompt template was not sent
- review against the linked local plan file, current repo state, current implementation diff and verification evidence if present, issue body, and orchestrator-provided plan/update content
- if the local plan file is not accessible, review against sanitized plan content in the issue and state that limitation
- check acceptance criteria, correctness, scope, safety, missing tests, and operational risks
- avoid unrelated suggestions unless severe
- post findings with the required header

### Reviewer 2

Usually a different model or agent family from Reviewer 1.

Responsibilities are the same as Reviewer 1.

### Human Approver

The human owns the final approval for risky actions:

- destructive changes
- costly actions
- production deploys
- cloud mutations
- data changes
- merge or publish decisions
- any action the plan marks as approval-gated

## Required Reviewer Header

Reviewer 1:

```text
Reviewer slot: 1
Agent/session: <agent name>
Read other reviews first: no
```

Reviewer 2:

```text
Reviewer slot: 2
Agent/session: <agent name>
Read other reviews first: no
```

## Plan-First Rule

For non-trivial repo, infrastructure, cloud, security, deploy, cleanup, migration, debugging, or operational work, create a local executable plan before creating or expanding issue tracker items.

The plan should state:

- goal
- acceptance criteria
- scope and non-goals
- source-of-truth repo or path
- proposed execution slices
- review gates
- approval gates
- commands or runbook steps
- verification steps
- rollback or stop conditions
- sensitive-data boundaries

A local plan file is not required for simple issue admin, queue triage, one-line fixes, tiny doc edits, or tasks the human explicitly wants handled directly.

## Local Plan Storage

Use the least durable place that still supports the work:

- repo-local temporary plan when agents need it next to code
- `/tmp/...` for ephemeral evidence, raw command output, sensitive metadata, or large generated artifacts
- committed docs only when the human explicitly wants the plan or runbook to become durable repo documentation

Repo-local temporary plans should stay uncommitted unless the human says otherwise. Remove or refresh stale plan files after the slice is complete.

If reviewers cannot access the local plan file, the orchestrator must include enough sanitized plan content in the issue for review to proceed safely.

## Issue Rule

The issue tracker is the orchestration and gate record. It should summarize and gate the local plan, not replace it.

Use one issue when the plan is one execution slice.

Use a parent issue plus child slice issues only when the local plan has independent execution gates, different repos, different owners, or separate approvals.

Do not create separate reviewer child issues by default. Reviewer identity belongs in the comment body.

### Multi-Slice Plans

When a finalized local plan contains multiple execution slices:

- create the parent issue and all ready child slice issues upfront
- record the intended execution order in the parent issue
- assign each ready child slice the Review gate
- keep unready slices Todo or Blocked when they need external decisions, missing evidence, or unresolved ownership
- reviewers review every ready slice and post feedback on each issue
- the orchestrator owns sequencing and may execute only the next approved slice
- post-execution review on each slice still applies before commit, push, apply, deploy, merge, or closeout
- if the parent plan changes materially, update affected slice issues in the same change under the Plan Drift Rule

Key distinction: create and review broadly; execute narrowly.

## Standard Task Flow

1. Orchestrator creates a local executable plan when required.
2. Orchestrator creates one issue or decomposes the plan into slice issues.
3. Orchestrator adds the plan path, sanitized summary, acceptance criteria, boundaries, expected files or resources, current gate, and review request. Current gate: Review.
4. Human sends the same issue link and task prompt to Reviewer 1 and Reviewer 2. Current gate: Review.
5. Reviewers post comments independently on the same issue. Current gate: Review.
6. Orchestrator synthesizes both reviews. Current gate: Approval if aligned, Review if material changes need re-review, or Blocked if blockers remain.
7. Orchestrator updates code or plan if needed. Current gate: Review if material changes need re-review.
8. If changes are material, repeat review on the updated slice.
9. Human approves execution, apply, deploy, or merge when needed. Current gate: Approval until approved.
10. Orchestrator executes the approved slice and posts verification. If execution creates material code, doc, config, infra, data, or plan changes, Current gate: Review.
11. Reviewers review the implementation diff and verification evidence on the same issue before commit, push, apply, deploy, merge, or closeout approval.
12. Orchestrator synthesizes implementation reviews. Current gate: Approval if aligned, Review if material changes need re-review, or Blocked if blockers remain.
13. Orchestrator commits only the intended tracked changes when the human approves the commit or when the approved workflow explicitly calls for it.
14. Orchestrator closes the issue only after verification, or moves it to an explicit waiting state.

If execution is read-only and creates no material diff, the orchestrator may move directly to Waiting External Eval, Approval, or Done according to the approved workflow and verification state.

## Orchestrator Next-Action Rule

After creating or updating an issue, changing a gate, posting a synthesis, requesting approval, or closing out work, the orchestrator must end its user-facing response with:

- issue ID or link
- current gate
- why that gate is set
- exact next human action
- what the orchestrator will do after that action
- what remains out of scope or forbidden

When the current gate is Approval, include an exact approval phrase the human can send, such as:

```text
Approved: execute <ISSUE-ID> <slice name> only.
```

Adapt the approval verb to the action, such as execute, merge, push, apply, deploy, close, or archive.

If execution is still forbidden, say that plainly.

## Implementation Discipline

Before editing:

- read the issue, local plan, linked spec, and relevant existing files
- identify acceptance criteria and non-goals
- inspect current git status so unrelated work is not disturbed
- check current implementation patterns before adding new ones

While editing:

- implement only the stated acceptance criteria
- do not change unrelated files
- do not refactor opportunistically
- preserve existing behavior unless the plan explicitly changes it
- follow existing code style, architecture, naming, and UI conventions
- add or update tests when the change affects logic, data flow, permissions, integrations, or user-visible behavior

Before review, commit, PR, deploy, or apply:

- run the narrowest useful verification command for the files or resources touched
- if a broad check is known to have unrelated failures, say that plainly and include the targeted checks that passed
- review the diff for unrelated changes
- confirm the next gate is correctly recorded in the issue

## Post-Execution Review Rule

Every material change created during execution must be reviewed before commit, push, apply, deploy, merge, or closeout.

Material changes include:

- code changes
- tests
- docs or runbooks
- CI/CD, infrastructure, or configuration
- database migrations or data changes
- local executable plans when their scope, gates, commands, verification, or safety boundaries changed

After material execution changes, the orchestrator must:

- update the issue Current gate to Review
- identify the exact files, resources, or diff to review
- include verification already run
- tell reviewers to post feedback on the same issue
- keep commit, push, apply, deploy, merge, and closeout out of scope until reviews are synthesized and the human approves the next gated action

Reviewers must review the current implementation diff and verification evidence, not only the original plan.

If the approved action itself is apply, deploy, or another external mutation and creates no reviewable local diff, post verification and move to Waiting External Eval or Done according to the approved workflow.

## Gate State

The current gate must be visible in the issue tracker, not only buried in comments.

Recommended states:

- Backlog: idea not started
- Todo: local plan exists or task is ready to prepare
- In Progress: orchestrator actively working
- Review: waiting for Reviewer 1 or Reviewer 2
- Approval: reviewers aligned, waiting for the human
- Waiting External Eval: executed, waiting for CI, logs, users, cloud evaluation, or another external system
- Done: verified and closed

If custom states are not available, use labels or issue-title prefixes:

- `gate:review`
- `gate:approval`
- `waiting:external-eval`
- `state:applied-awaiting-verification`
- `blocked:<reason>`

When using gate labels, remove the old gate label in the same update that adds the new gate label.

## Gate Rule

Proceed when both reviewer slots are complete and all blocking feedback is resolved.

A Block from either reviewer holds the gate. The orchestrator must address it or the human must explicitly override it in the issue before execution.

Use a third reviewer only when the human asks for a tie-break or extra risk review.

## Plan Drift Rule

When the local plan changes materially, the orchestrator must add an execution-log comment that names what changed.

A change is material if it alters acceptance criteria, scope, non-goals, gates, commands, verification, rollback conditions, or sensitive-data boundaries.

Typo fixes, formatting, and rewording without semantic change are not material.

For tracked code changes, include the commit SHA when available.

For uncommitted plan changes, include the plan path and a short summary of the changed gate, scope, or command.

If a saved plan, deploy artifact, or generated evidence file is replaced, record the new path and checksum when useful.

## Safety Boundaries

- Do not paste secrets, raw credentials, token values, sensitive resource names, or raw plan output into issues.
- Use sanitized summaries for plans, logs, findings, and metadata.
- Destructive, costly, cloud-mutating, deploy, apply, push, or external-posting actions require explicit human approval.
- The approved workflow may authorize issue closeout after acceptance criteria pass; otherwise human approval is required.
- Saved plans must be applied by explicit filename, not by a stale default path.
- Local-only plan documents stay uncommitted when the task says so.

## GitHub Boundary

Use an issue tracker as the agent orchestration board.

Use GitHub Issues or PRs when the work is repo-native, public, or should be tied directly to branches, commits, code review, and PR closure.

When a branch or PR exists, link it from the issue. Do not duplicate sensitive operational evidence into GitHub.

If a PR is opened, its description should briefly include:

- what changed
- why
- issue link
- acceptance criteria checked
- risk
- how to test
- what was intentionally not done
- follow-up issues

## Close Discipline

Do not close an issue just because code was written or an action completed.

Close only when verification has passed and closeout is authorized, or when the issue explicitly records why verification is deferred or impossible.

If an external system must update later, move the issue to a waiting state.
