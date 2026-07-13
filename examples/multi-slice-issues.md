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
Merge target: main

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
Base branch: main
Phase branch: phase/EXAMPLE-201-retry-classification
Remote push: allowed
Merge target: main

Commitment: committed
Depends on: none

Next human action:
- Send this ready slice context, PR link, and verification evidence to Reviewer 2 with the filled Reviewer Prompt template. The orchestrator runs or reuses Reviewer 1 as a named isolated subagent. Reviewers inspect the PR diff directly.
- If reviewers approve with no blockers, the orchestrator asks for human merge approval. If either reviewer blocks, the orchestrator fixes the phase branch and requests delta review.
```

## Orchestrator Output

```text
Internal Reviewer 1 subagent:

- Orchestrator creates or reuses the named `reviewer1` subagent with only the review packet and its own prior review history.
- Do not send this prompt to the human unless subagents are unavailable.

Human-facing Reviewer 2 prompt for EXAMPLE-201:

Review EXAMPLE-201 using the issue body, linked local plan file if accessible, current repo state if applicable, and verification evidence if present.

You are Reviewer 2.

Reviewer slot: 2
Agent/session: Claude Code
Read other reviews first: no

Continue with the full Reviewer Prompt template from docs/templates.md.
```

## Blocked Child Slice

```text
Title: EXAMPLE-202 retry metrics

Current gate: Blocked
Next gated action: implementation
Autonomy mode: review-approved-auto-execute

Commitment: committed
Depends on: EXAMPLE-201

Blocked because:
- retry metrics should not be reviewed until retry classification is approved.

Next human action:
- None until EXAMPLE-201 reaches Done or Waiting External Eval.

Then:
- The orchestrator moves this implementation-first slice to In Progress and implements it before requesting review.
```
