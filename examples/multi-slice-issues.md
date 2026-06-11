# Example Multi-Slice Issues

## Parent Issue

```text
Title: EXAMPLE-200 Retry workflow cleanup

Current gate: Review
Autonomy mode: review-approved-auto-execute
Phase branch mode: on
Phase branch flow: implementation-first
Review transport: pr
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
- Send this ready slice context, PR link, and verification evidence to Reviewer 1 and Reviewer 2 with filled Reviewer Prompt templates. Reviewers inspect the PR diff directly.
- If reviewers approve with no blockers, the orchestrator asks for human merge approval. If either reviewer blocks, the orchestrator fixes the phase branch and requests delta review.
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
