# Example Multi-Phase Coordination

## Parent Ledger

The parent fields below are default inputs, not phase grants. Each identified phase record in this parent issue is its effective authority. This example's phase A is Retry classification; phase B is Retry metrics.

```text
Title: Retry workflow cleanup

Status: review
Current gate: review
Next gated action: merge Phase 1
Autonomy mode: review-approved-auto-execute
Phase branch mode: on
Phase branch flow: implementation-first
Review transport: pr
Coordination record: github-issue
Handoff mode: reviewer1-subagent + manual reviewer2
Reviewer 2 handoff: manual external reviewer
Direct Reviewer 2 authorization: none
Base branch: main
Phase branch: none
Worktree mode: on
Worktree reference: none
Remote push: disallowed
Merge target: main

Plan digest: dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
Workflow revision: cccccccccccccccccccccccccccccccccccccccc

| Phase | Depends on | Status | Branch/PR | Gate | Next action |
| --- | --- | --- | --- | --- | --- |
| Retry classification | none | review | phase/retry-classification / PR #10 | review | collect both verdicts |
| Retry metrics | Retry classification | blocked | none | dependencies | wait for the verified classification result |
| Vendor evaluation | none | waiting external eval | none | external evaluation | recheck vendor result |
```

`Status` records lifecycle progress; `Gate` controls transition. Retry metrics waits for Retry classification's terminal resolution and verified result evidence in its parent phase authority. Vendor evaluation's non-terminal `waiting external eval` does not block independent Retry classification.

The following result evidence is part of the Retry metrics phase authority in this parent issue, below the fixed ledger. Its resolved effective push value remains disallowed, matching the parent input; classification's override cannot grant metrics permission.

| Dependent | Required result | Accessible verification evidence | Satisfied |
| --- | --- | --- | --- |
| Retry metrics | Retained classification interface and tests | PR #10's commit-bound test report pending; retain interface and report while metrics needs them | no: prerequisite in review, result unverified |

These are illustrative dispositions, not live transaction tests:

| Dependency condition | Readiness disposition |
| --- | --- |
| Abandoned, merged, completed, retained, or handed off without the required verified result | blocked; terminal label alone is insufficient |
| Verified terminal resolution with retained required interface and accessible test evidence | ready; review, execution and human gates still apply |
| Non-terminal prerequisite with a provisional interface | blocked; no early phase-level dependency consumption |
| Removed or replaced dependency | human scope decision and revised-plan review before advancement; verify any replacement results |
| Partial parent closeout with verified abandoned phases | record partial delivery, not success for missing results |

| Authority event | Effective authority and disposition |
| --- | --- |
| Verified PR-to-parent promotion | Parent phase record takes over after verified content, backlinks and takeover in the old authority; preserve classification's approved allowed value and metrics' disallowed value |
| Superseded PR says allowed, parent phase says disallowed | parent phase governs; stale PR grants nothing |
| Preparation readback fails | old authority remains; promotion-dependent actions held |
| Takeover write/readback uncertain | stop for human reconciliation; retain both observed records, grant neither candidate authority nor automatic retry |

## Active Phase

This record lives inside the same parent issue and is Retry classification's sole phase authority. Exact human approval for this phase and the allowed push value is recorded here under Push Authorization rule 5, limited to its named branch; no other phase inherits the override. PR #10 references this record rather than granting permission independently.

```text
Title: Retry classification

Status: review
Current gate: review
Next gated action: merge
Autonomy mode: review-approved-auto-execute
Phase branch mode: on
Phase branch flow: implementation-first
Review transport: pr
Coordination record: github-issue
Reviewer 2 handoff: manual external reviewer
Direct Reviewer 2 authorization: none
Base branch: main
Phase branch: phase/retry-classification
Worktree mode: on
Worktree reference: phase-execution/retry-classification
Remote push: allowed
Merge target: main

Review round: 1
Reviewed head: 1111111111111111111111111111111111111111
PR diff SHA-256: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
Workflow revision: cccccccccccccccccccccccccccccccccccccccc
```

Reviewer 1 receives only its sealed packet and own prior findings. The human relays the filled Reviewer 2 prompt. After both slots return, the orchestrator posts carried verdicts verbatim, rechecks identity, synthesizes, and updates the parent ledger.

## Durable Follow-Up

Create a child issue only when the follow-up has independent ownership, an external blocker, or accepted work that must survive parent closeout. Do not create one merely because the plan has another phase.
