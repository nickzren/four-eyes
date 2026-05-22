# Example Multi-Slice Issues

## Parent Issue

```text
Title: EXAMPLE-200 Retry workflow cleanup

Current gate: Review
Autonomy mode: review-approved-auto-execute

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
Autonomy mode: review-approved-auto-execute

Commitment: committed
Depends on: none

Next human action:
- Send this ready slice issue to Reviewer 1 and Reviewer 2 with filled Reviewer Prompt templates. If both reviewers approve with no blockers, the orchestrator may execute this reviewed local slice automatically.
```

## Orchestrator Output

```text
Reviewer 1 prompt for EXAMPLE-201:

Review EXAMPLE-201 using the issue body, linked local plan file if accessible, current repo state if applicable, and verification evidence if present.

You are Reviewer 1.

Reviewer slot: 1
Agent/session: <agent name>
Read other reviews first: no

Continue with the full Reviewer Prompt template from docs/templates.md.
```

## Blocked Child Slice

```text
Title: EXAMPLE-202 retry metrics

Current gate: Blocked
Autonomy mode: review-approved-auto-execute

Commitment: committed
Depends on: EXAMPLE-201

Blocked because:
- retry metrics should not be reviewed until retry classification is approved.

Next human action:
- None until EXAMPLE-201 reaches Done or Waiting External Eval.
```
