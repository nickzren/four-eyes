# Coordination Records

Four Eyes uses one of three coordination records: a pull request, one GitHub parent issue, or a temporary local record.

The coordination record is not the source of reviewed bytes and is not the reviewer message bus. The orchestrator owns its status, gate, ledger, and closeout updates.

## Routing

Use `pr` for single-phase remote work, `github-issue` for multi-phase work or durable blockers, and `local` when no forge record is available.

Keep private repository mappings and local paths in local evidence, not in public coordination records.

## Recommended Fields

Record:

- coordination record type and authoritative record
- workflow revision and plan digest, when a plan exists
- current gate and next gated action
- autonomy, branch, worktree, review transport, and reviewer handoff modes
- exact review round and artifact identity
- goal, acceptance criteria, scope, and safety boundaries
- verification, reviewer outcomes, nit disposition, and closeout

For multi-phase work, use the fixed ledger columns `Phase | Depends on | Status | Branch/PR | Gate | Next action`.

`Status` records lifecycle progress. `Gate` records the condition controlling the next transition, such as `none`, `dependencies`, `review`, `human approval`, `external evaluation`, `blocker resolution`, or `human handoff`; do not use it as a duplicate status field.

## Recommended Record Shape

Load the task context, Four Eyes Default Workflow, and Four Eyes Role Contracts by default. Load the Playbook, Templates, or Coordination Records only when their exact policy, template, or coordination behavior is needed. Reviewers receive filled immutable packets and do not need the workflow-document set.

Record Reviewer 2 transport and direct-mode limits in this exact order:

```text
Reviewer 2 handoff: manual external reviewer | direct Claude reviewer
Direct Reviewer 2 authorization: none | human-approved phase + full model + maximum calls + maximum cost
```

Manual external Reviewer 2 is the default. Select direct review only when the platform supplies isolated fresh context and the human authorizes the exact task or phase, full model identity, maximum calls, and maximum cost amount and currency.

Every task loads policy from one recorded full repository commit SHA. Missing, abbreviated, mixed, or unresolvable revisions hold the gate.

## Autonomy Mode

Record `Autonomy mode: review-approved-auto-execute | manual`.

Use `review-approved-auto-execute` by default. It authorizes in-scope local execution after the selected review gate clears, but never bypasses merge, protected-branch push, external-system mutation, deployment, destructive or costly action, scope change, or another recorded human gate.

Use `manual` when the human requests per-step control or when exact command, scope, target, or risk boundaries cannot be recorded safely.

## Phase Branch Mode

Record these fields:

```text
Phase branch mode: on | off
Phase branch flow: implementation-first | pre-review
Review transport: pr | manual-relay
Coordination record: pr | github-issue | local
Reviewer 1 handoff: internal named subagent | manual external reviewer
Reviewer 2 handoff: manual external reviewer | direct Claude reviewer
Direct Reviewer 2 authorization: none | human-approved phase + full model + maximum calls + maximum cost
Base branch: <branch>
Phase branch: <branch or "none">
Worktree mode: on | off
Worktree reference: none | <ownership-category>/<opaque worktree reference>
Remote push: disallowed | allowed
Merge target: <branch>
Post-merge branch cleanup: yes | no
Abandoned branch cleanup: yes | ask | no
```

With phase branch mode on, default worktree mode to on and keep the primary checkout fixed on the recorded base. Human approval remains required for protected-branch merge and every other risk-class gate.

Public coordination records never include worktree paths, usernames, host layout, remote URLs, remote names, full refs, local expected-state transitions, or cleanup diagnostics. Record only the opaque reference, ownership category, checkout kind, remote-subject category, expected/live comparison result, lifecycle path, and blocker if any. Detailed ownership and state transitions stay in private local evidence.

## Multi-Phase Ledger And Durable Follow-Ups

Multi-phase work uses one GitHub parent issue with a compact phase ledger. Do not create a child issue for each committed phase.

Promote a pull-request record to a GitHub parent issue when a second phase becomes committed, a dependency or blocker exists outside the current pull request, or deferred work must survive pull-request closeout.

Create child issues only for independently owned work, externally blocked work, or accepted durable follow-up work.

Ledger status values are `todo`, `ready`, `in progress`, `review`, `waiting external eval`, `blocked`, and one terminal value. `waiting external eval` is non-terminal. A phase becomes ready only when every phase it depends on is terminal.

Terminal values are `merged`, `completed`, `abandoned`, `retained`, and `handed off`. Verify every terminal claim against Git or forge state before recording it.

## GitHub Integration

For `pr`, the local execution-state record remains authoritative until its public-safe content is copied into the pull request and verified. After that, the pull request is authoritative.

For `github-issue`, create exactly one parent issue carrying the plan digest, ledger, pull requests, dependencies, current gate, and next action. Promotion is complete only after the issue and pull request backlink agree.

Prefer a commit-preserving merge when branch-tip recovery or reviewed-commit ancestry is part of the approved closeout. Otherwise retain the repository's configured merge preference.

Reviewers may submit review verdicts, but they do not edit coordination metadata or the ledger. The orchestrator posts carried verdicts verbatim after the verdict embargo and owns synthesis and closeout.

Record and verify pre-cleanup branch and worktree facts first. Perform only the authorized worktree, pull-request, and branch resolution, then record and verify the final closeout results in the authoritative coordination record. Remove temporary plans and local state records only after that final record is verified.
