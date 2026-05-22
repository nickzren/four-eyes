# Issue Tracker Setup

Four Eyes works with Linear, GitHub Issues, Jira, or any tracker that supports issues and comments.

The tracker is not the source of truth for the technical plan. It is the gate and coordination record.

For Linear-specific setup, see Four Eyes Linear Setup.

## Routing

Route issues by the provided Linear team/workspace or workspace mapping.

Keep private mappings in local or workspace setup docs, not in this public workflow.

If no mapping exists or the target is ambiguous, stop and ask before creating issues.

## Recommended Fields

Use statuses or labels for the current gate:

- Backlog
- Todo
- In Progress
- Review
- Approval
- Blocked
- Waiting External Eval
- Done

If custom statuses are not available, use labels:

- `gate:review`
- `gate:approval`
- `waiting:external-eval`
- `state:applied-awaiting-verification`
- `blocked:<reason>`

Remove stale gate labels when adding a new gate label.

## Recommended Issue Shape

Every non-trivial task issue should include:

- source plan path or link
- current gate
- autonomy mode
- goal
- acceptance criteria
- scope and non-goals
- safety boundaries
- sanitized plan summary
- reviewer prompts
- execution log
- closeout

## Autonomy Mode

Every active task issue should record:

```text
Autonomy mode: review-approved-auto-execute | manual
```

Use `review-approved-auto-execute` for reviewed local repo code, docs, tests, or plan edits. If autonomy mode is missing, treat it as `review-approved-auto-execute` unless a manual condition applies. Use `manual` for live/external systems, databases, cloud, deploys, apply actions, destructive or costly actions, production data/resource changes, ambiguous ownership, or human-marked approval gates.

When autonomy mode is `review-approved-auto-execute`, two reviewer outcomes of `Approve` or `Approve with nits` authorize local execution of the reviewed slice if there are no blockers, required changes before execution, unresolved execution-affecting questions, dirty worktree conflicts, scope changes, or unreviewed commands. Commit, push, publish, merge, deploy, apply, live/external mutation, destructive/costly action, production data/resource change, closeout unless already authorized, scope change, and unreviewed commands still require human approval.

## Parent And Child Issues

Use one issue for one execution slice.

Use a parent issue plus child slice issues when the plan has multiple named execution slices it commits to, especially when slices differ by:

- different repos
- different owners
- different approvals
- different deploy windows
- independent rollback or verification
- independent execution gates

Create one child issue for each committed execution slice. Record intended execution order and inter-slice dependencies in the parent issue.

Set ready child slice issues to Review. Keep downstream or unready child slice issues Todo or Blocked.

When a child slice reaches Done or Waiting External Eval, promote the next committed unblocked child slice to Review automatically and post reviewer prompts; this is tracker preparation, not a human approval gate. If the next committed child slice is still blocked, leave its gate and note the blocker in the parent issue.

Avoid separate reviewer issues by default. Review identity belongs in the comment body.

## GitHub Integration

If the tracker can link branches, commits, or pull requests automatically, enable it.

Branch names should include the issue ID when possible.

Even with automatic links, keep the issue closeout explicit:

- what changed
- what was verified
- what remains
- whether sensitive data stayed out of public surfaces
