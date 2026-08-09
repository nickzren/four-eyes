# Example Multi-Phase Coordination

## Parent Ledger

```text
Title: Retry workflow cleanup

Current gate: Review
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

Plan digest: dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
Workflow revision: cccccccccccccccccccccccccccccccccccccccc

| Phase | Depends on | Status | Branch/PR | Gate | Next action |
| --- | --- | --- | --- | --- | --- |
| Retry classification | none | review | phase/retry-classification / PR #10 | Review | collect both verdicts |
| Retry metrics | Retry classification | blocked | none | Blocked | wait for dependency to become terminal |
| Vendor evaluation | none | waiting external eval | none | Waiting External Eval | recheck vendor result |
```

`waiting external eval` is non-terminal. The independent Retry classification phase may proceed, while Retry metrics remains unready because it depends on a non-terminal phase.

## Active Phase

```text
Title: Retry classification

Current gate: Review
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
