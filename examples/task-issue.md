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

Waiting for Reviewer 1 and Reviewer 2 comments.

## Review Request

Please review independently before reading other comments.

Check acceptance criteria, scope, safety, tests, and whether this is ready for implementation.

