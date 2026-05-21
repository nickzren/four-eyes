# Issue Tracker Setup

Four Eyes works with Linear, GitHub Issues, Jira, or any tracker that supports issues and comments.

The tracker is not the source of truth for the technical plan. It is the gate and coordination record.

## Recommended Fields

Use statuses or labels for the current gate:

- Backlog
- Todo
- In Progress
- Review
- Approval
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
- goal
- acceptance criteria
- scope and non-goals
- safety boundaries
- sanitized plan summary
- reviewer prompts
- execution log
- closeout

## Parent And Child Issues

Use one issue for one execution slice.

Use a parent issue only when the plan splits into independent slices:

- different repos
- different owners
- different approvals
- different deploy windows
- independent rollback or verification

Avoid separate reviewer issues by default. Review identity belongs in the comment body.

## GitHub Integration

If the tracker can link branches, commits, or pull requests automatically, enable it.

Branch names should include the issue ID when possible.

Even with automatic links, keep the issue closeout explicit:

- what changed
- what was verified
- what remains
- whether sensitive data stayed out of public surfaces

