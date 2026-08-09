# Example Multi-Slice Issues

## Parent Issue

```text
Title: EXAMPLE-200 Retry workflow cleanup

Current gate: Review
Next gated action: merge
Autonomy mode: review-approved-auto-execute
Phase branch mode: on
Phase branch flow: implementation-first
Review transport: pr
Handoff mode: reviewer1-subagent + manual reviewer2
Reviewer 2 handoff: manual external reviewer
Direct Reviewer 2 authorization: none
Base branch: main
Phase branch: none
Worktree mode: on
Worktree reference: none
Remote push: disallowed
Merge target: main

Active child: EXAMPLE-201
Current review artifact:
Review round: 1
Reviewed head: 1111111111111111111111111111111111111111
PR diff SHA-256: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
Workflow revision: cccccccccccccccccccccccccccccccccccccccc

Execution order:
1. EXAMPLE-201 retry classification
2. EXAMPLE-202 retry metrics

Dependencies:
- EXAMPLE-202 depends on EXAMPLE-201.

Child issues in scope:
- EXAMPLE-201
- EXAMPLE-202

Out of scope:
- all other issues and tasks
```

## Ready Child Slice

```text
Title: EXAMPLE-201 retry classification

Current gate: Review
Next gated action: merge
Autonomy mode: review-approved-auto-execute
Phase branch mode: on
Phase branch flow: implementation-first
Review transport: pr
Reviewer 2 handoff: manual external reviewer
Direct Reviewer 2 authorization: none
Base branch: main
Phase branch: phase/EXAMPLE-201-retry-classification
Worktree mode: on
Worktree reference: phase-execution/EXAMPLE-201-worktree
Remote push: allowed
Merge target: main

Current review artifact:
Review round: 1
Reviewed head: 1111111111111111111111111111111111111111
PR diff SHA-256: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
Workflow revision: cccccccccccccccccccccccccccccccccccccccc

Commitment: committed
Depends on: none

Next human action:
- This example uses manual Reviewer 2: send the ready slice context, PR link, exact artifact identity, and verification evidence with the filled Reviewer Prompt. If exactly authorized direct Claude review is recorded instead, the orchestrator dispatches only its sealed packet and own prior findings through the platform's native isolated tool. The orchestrator runs or reuses Reviewer 1 as a named isolated subagent.
- After both slots return or have terminal records, the orchestrator posts carried verdicts verbatim, recomputes identity, and synthesizes. If reviewers approve with no blockers and identity still matches, the orchestrator asks for human merge approval. If either reviewer blocks or the artifact changes, the orchestrator fixes the phase branch and requests the required delta review.
```

## Orchestrator Output

```text
Internal Reviewer 1 subagent:

- Orchestrator creates or reuses the named `reviewer1` subagent with only the review packet and its own prior review history.
- This prompt is internal only. If no internal Reviewer 1 is available, prepare a separate external Reviewer 1 prompt for the human to relay.

Human-facing Reviewer 2 prompt for EXAMPLE-201:

Review EXAMPLE-201 using the issue body, linked local plan file if accessible, current repo state if applicable, and verification evidence if present.

You are Reviewer 2.

Reviewer slot: 2
Agent/session: Claude Code
Read other reviews first: no
Review round: 1
Reviewed head: 1111111111111111111111111111111111111111
PR diff SHA-256: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
Workflow revision: cccccccccccccccccccccccccccccccccccccccc

Continue with the full Reviewer Prompt template from docs/templates.md.
```

## Blocked Child Slice

```text
Title: EXAMPLE-202 retry metrics

Current gate: Blocked
Next gated action: implementation
Autonomy mode: review-approved-auto-execute
Phase branch mode: on
Phase branch flow: implementation-first
Review transport: pr
Reviewer 2 handoff: manual external reviewer
Direct Reviewer 2 authorization: none
Base branch: main
Phase branch: none
Worktree mode: on
Worktree reference: none
Remote push: disallowed
Merge target: main
Current review round: 1
Workflow revision: cccccccccccccccccccccccccccccccccccccccc

Commitment: committed
Depends on: EXAMPLE-201

Blocked because:
- retry metrics should not be reviewed until retry classification is approved.

Next human action:
- None until EXAMPLE-201 reaches Done or Waiting External Eval.

Then:
- The orchestrator moves this implementation-first slice to In Progress and implements it before requesting review.
```
