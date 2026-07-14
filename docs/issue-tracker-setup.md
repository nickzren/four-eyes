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

- temporary source plan path or link, when the task input was not clear enough to execute directly
- current gate
- next gated action
- autonomy mode
- phase branch mode, if enabled
- review transport
- current positive review round
- workflow revision from the standing workflow-doc sync note
- exact transport-specific artifact identity
- reviewer handoff
- verbatim reviewer verdicts or links to them
- goal
- acceptance criteria
- scope and non-goals
- safety boundaries
- sanitized plan summary
- reviewer prompts
- execution log
- closeout

Local executable plans are temporary coordination artifacts. Do not commit them. Keep the issue tracker to sanitized summaries and remove the local plan after closeout.

Until synced documents carry their own revision markers, use the full pushed repo commit SHA in the latest successful sync note on the standing workflow-doc review issue as the authoritative workflow revision. Unknown or mixed revisions hold the gate. Generate artifact identities and repository fingerprints with the canonical commands in the Playbook; do not copy those commands into tracker templates.

Hold orchestrator-carried internal and relayed verdicts until all expected slots for the round have returned or have a Block, error, timeout, or could-not-review record. Direct PR reviews posted by external reviewers are outside orchestrator control. After the embargo lifts, post carried verdicts verbatim before synthesis.

## Autonomy Mode

Every active task issue should record:

```text
Autonomy mode: review-approved-auto-execute | manual
```

Use `review-approved-auto-execute` for reviewed local repo code, docs, tests, or plan edits. If autonomy mode is missing, treat it as `review-approved-auto-execute` unless a manual condition applies. Use `manual` for live/external systems, databases, cloud, deploys, apply actions, destructive or costly actions, production data/resource changes, ambiguous ownership, or human-marked approval gates.

When autonomy mode is `review-approved-auto-execute`, all expected reviewers for the selected tier returning `Approve` or `Approve with nits` authorize local execution of the reviewed slice if there are no blockers, required changes before execution, unresolved execution-affecting questions, dirty worktree conflicts, scope changes, or commands outside the pre-authorized local classes or reviewed plan. Repo-local inspection and existing repo verification commands are pre-authorized. Commands that expand scope, install software, start persistent services, change external state, or are destructive, costly, privileged, or hard to reverse still require human approval; listing or reviewing them only makes the approval request specific. Commit and push to a named phase branch may be pre-authorized only by phase branch mode. Publish, merge, deploy, apply, protected-branch push, live/external mutation, destructive/costly action, production data/resource change, closeout unless already authorized, and scope change still require human approval.

Record each accepted nit as either deferred without an artifact change, with reason and follow-up, or implemented with delta review. A changed artifact requires all expected `full`-tier slots to re-review. `Light` has one round; a blocker or changed artifact escalates to `full` or a human decision.

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
Abandoned branch cleanup: yes | ask | no
```

When enabled, the orchestrator may create, commit to, and push the named phase branch without per-commit human approval. With `implementation-first`, reviewers review the completed phase branch diff and verification evidence. Human approval is still required before merge into the target branch. The merge approval may include post-merge verification, tracker closeout, and branch deletion.

Default to `Post-merge branch cleanup: yes` and `Abandoned branch cleanup: ask`. Every agent-created phase branch must be resolved at closeout as merged and deleted, abandoned with any workflow-created PR closed and branch deleted, intentionally kept with owner and revisit trigger, or handed off to the human. Record branch name, local tip SHA, remote tip SHA if present, PR link if present, and reason before deletion. If local and remote tips differ, preserve the branch and hand off to the human.

This label controls execution authorization only. It does not require any tool-run workflow. In manual relay mode, the human passes external reviewer verdicts back to the orchestrator, and the orchestrator decides the next tracker update.

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

Set ready implementation-first phase branch slices to In Progress while the branch is being implemented and Review after the branch is ready. Set other ready slices to Review. Keep downstream or unready child slice issues Todo or Blocked.

When a child slice reaches Done or Waiting External Eval, the orchestrator may advance the next committed unblocked child slice without human approval. Move an implementation-first phase branch slice to In Progress and implement it before Review; move a pre-review slice to Review and prepare reviewer prompts. If the next committed child slice is still blocked, leave its gate and note the blocker in the parent issue.

Avoid separate reviewer issues by default. Review identity belongs in the review artifact, synthesis, or orchestrator-posted tracker update.

## GitHub Integration

If the tracker can link branches, commits, or pull requests automatically, enable it.

Branch names should include the issue ID when possible.

Use PR review transport when the repo has a remote and CI or branch protection. The PR is the review artifact; the tracker remains the gate and status record.

Selecting PR review transport pre-authorizes creating or updating the PR for the recorded phase branch and merge target, maintaining its bounded review description, requesting expected reviewers, and submitting expected reviewer verdicts. It does not authorize merge, unrelated PR changes, repository-setting changes, or other GitHub writes.

When available, protect the merge target with required approvals, status checks, and dismissal of stale approvals after new commits. Before merge, compare the current forge head and canonical PR diff SHA-256 with every approval. Any changed head or artifact invalidates prior approvals.

Prefer squash merge for phase branches unless the repo has a different established convention.

Even with automatic links, keep the issue closeout explicit:

- what changed
- what was verified
- what remains
- whether sensitive data stayed out of public surfaces
- temporary local plans and working artifacts removed
- phase branch resolution, including tip SHAs before cleanup
