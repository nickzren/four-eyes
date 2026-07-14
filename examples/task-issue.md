# Example Task Issue

## Workflow

Use the Four Eyes workflow.

Orchestrator: Codex App
Reviewer 1: named Codex subagent `reviewer1`
Reviewer 2: Claude Code
Handoff mode: reviewer1-subagent + manual reviewer2
Review tier: full

## Source Plan

Local plan path: `/path/to/repo/tmp/example-execution-plan.md`
Plan status: local-only temporary
Current gate: Review
Autonomy mode: review-approved-auto-execute
Phase branch mode: on
Phase branch flow: implementation-first
Review transport: pr
Base branch: main
Phase branch: phase/EXAMPLE-retry-behavior
Remote push: allowed
Merge target: main
Post-merge branch cleanup: yes
Abandoned branch cleanup: ask

## Current Review Artifact

Review round: 1
Reviewed head: 1111111111111111111111111111111111111111
PR diff SHA-256: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
Workflow revision: cccccccccccccccccccccccccccccccccccccccc

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

Review. Phase branch is ready for Reviewer 1 and Reviewer 2 verdicts. The orchestrator runs or reuses Reviewer 1 internally and the human relays Reviewer 2.

Next gated action: merge

## Next Human Action

Send the Reviewer 2 prompt, issue context, PR link, exact artifact identity, and verification evidence to Claude Code. The orchestrator runs or reuses Reviewer 1 as a named isolated subagent. Reviewers inspect the exact PR artifact and return verdicts through the selected transport.

The orchestrator holds carried verdicts until both slots return or have terminal records, posts them verbatim, recomputes the live forge head and PR diff SHA-256, then synthesizes. If both reviewers approve with no blockers and identity still matches, the orchestrator asks for human merge approval. If either reviewer blocks or the artifact changes, the orchestrator fixes the phase branch and requests the required delta review.

## Review Request

Please review independently before reading other reviewer output or orchestrator synthesis.

Review the exact identified PR artifact and verification evidence before merge or closeout.

Check acceptance criteria, scope, safety, tests, and whether this is ready for the next gate.

Return your verdict to the human relay or orchestrator. Do not post directly to the tracker unless explicitly instructed.
