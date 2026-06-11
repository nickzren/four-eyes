# Issue Tracker Setup

Four Eyes works with Linear, GitHub Issues, Jira, or any tracker that supports issues and comments.

The tracker is not the source of truth for the technical plan, and it is not the reviewer message bus.

Use the tracker as the gate, audit, and status record. The orchestrator decides when to post progress, synthesis, gate changes, and closeout.

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
- phase branch mode, if enabled
- review transport
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

When autonomy mode is `review-approved-auto-execute`, all expected reviewers for the selected tier returning `Approve` or `Approve with nits` authorize local execution of the reviewed slice if there are no blockers, required changes before execution, unresolved execution-affecting questions, dirty worktree conflicts, scope changes, or unreviewed commands. Commit and push to a named phase branch may be pre-authorized only by phase branch mode. Publish, merge, deploy, apply, protected-branch push, live/external mutation, destructive/costly action, production data/resource change, closeout unless already authorized, scope change, and unreviewed commands still require human approval.

## Phase Branch Mode

For high-throughput phases, record:

```text
Phase branch mode: on
Phase branch flow: implementation-first
Base branch: <base>
Phase branch: <branch>
Remote push: allowed | disallowed
Merge target: <target>
Post-merge branch cleanup: yes | no
```

When enabled, the orchestrator may create, commit to, and push the named phase branch without per-commit human approval. With `implementation-first`, reviewers review the completed phase branch diff and verification evidence. Human approval is still required before merge into the target branch. The merge approval may include post-merge verification, tracker closeout, and branch deletion.

This label controls execution authorization only. It does not require any tool-run workflow. In manual relay mode, the human passes reviewer verdicts back to the orchestrator, and the orchestrator decides the next tracker update.

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

If a big local executable plan has no named phases or slices, the orchestrator may infer practical phases and create matching child issues. Mark each child issue with `Phase source: inferred by orchestrator`, explain the boundary, and keep the parent issue as the summary and sequencing record.

Set ready child slice issues to Review. Keep downstream or unready child slice issues Todo or Blocked.

When a child slice reaches Done or Waiting External Eval, the orchestrator may promote the next committed unblocked child slice to Review and prepare reviewer prompts; this is tracker preparation, not a human approval gate. If the next committed child slice is still blocked, leave its gate and note the blocker in the parent issue.

Avoid separate reviewer issues by default. Review identity belongs in the review artifact, synthesis, or orchestrator-posted tracker update.

## GitHub Integration

If the tracker can link branches, commits, or pull requests automatically, enable it.

Branch names should include the issue ID when possible.

Use PR review transport when the repo has a remote and CI or branch protection. The PR is the review artifact; the tracker remains the gate and status record.

When available, protect the merge target with required approvals and status checks.

Prefer squash merge for phase branches unless the repo has a different established convention.

Even with automatic links, keep the issue closeout explicit:

- what changed
- what was verified
- what remains
- whether sensitive data stayed out of public surfaces
