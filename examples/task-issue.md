# Example Task Issue

## Workflow

Use the Four Eyes workflow.

Orchestrator: Primary agent
Reviewer 1: Reviewer agent A
Reviewer 2: Reviewer agent B

## Source Plan

Local plan path: `/path/to/repo/docs/example-execution-plan.md`
Plan status: local-only
Current gate: Review
Autonomy mode: review-approved-auto-execute
Phase branch mode: on
Phase branch flow: implementation-first
Base branch: main
Phase branch: phase/EXAMPLE-retry-behavior
Remote push: allowed
Merge target: main

## Goal

Update the background job retry behavior so transient API failures retry safely.

## Acceptance Criteria

- transient HTTP 429 and 503 responses retry with backoff
- permanent 4xx responses do not retry
- existing success path is unchanged
- targeted tests pass

## Scope

In scope:

- `src/jobs/sync_worker.*`
- retry tests

Out of scope:

- API client rewrite
- scheduler changes
- production deploy

## Boundaries

- No deploy without explicit human approval.
- No unrelated refactor.
- No raw logs or credentials in issue comments.

## Current Plan

Implement retry classification in the existing worker helper. Add focused tests for retryable and non-retryable responses.

## Current Gate

Review. Phase branch is ready for Reviewer 1 and Reviewer 2 verdicts.

## Next Human Action

Send the reviewer prompt, issue context, phase branch, diff summary, and verification evidence to Reviewer 1 and Reviewer 2 separately. Paste both reviewer replies back to the orchestrator.

If both reviewers approve with no blockers, the orchestrator asks for human merge approval. If either reviewer blocks, the orchestrator fixes the phase branch and requests delta review.

## Review Request

Please review independently before reading other reviewer output or orchestrator synthesis.

Review the phase branch diff and verification evidence before merge or closeout.

Check acceptance criteria, scope, safety, tests, and whether this is ready for the next gate.

Return your verdict to the human relay or orchestrator. Do not post directly to the tracker unless explicitly instructed.
