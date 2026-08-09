# Example Closeout

```text
Closeout

Executed:
- Implemented retry classification in the existing sync worker helper.
- Added focused retry tests.

Acceptance criteria checked:
- 429 and 503 retry with backoff: pass.
- permanent 4xx responses do not retry: pass.
- existing success path unchanged: pass.
- targeted tests pass: pass.

Verification:
- `pytest tests/test_sync_worker.py`: pass.
- `git diff --check`: pass.

Committed:
- `abc1234 fix(sync): Add retry classification`

Resulting issue state will be set to:
- Done

Next human action:
- None.

Remaining work:
- None.

Sensitive-data note:
- No secrets, raw logs, or sensitive identifiers were committed or posted.

Local cleanup:
- Local execution plan removed.
- Raw test output not retained.

Branch resolution:
- Merged and deleted after approved merge.
- Branch: phase/EXAMPLE-retry-behavior
- Local tip SHA before cleanup: abc1234
- Remote tip SHA before cleanup: abc1234
- PR: <PR link>
- Reason: post-merge cleanup authorized.

Worktree resolution:
- Reference: phase-execution/EXAMPLE-retry-worktree
- Owner/category: orchestrator/phase-execution
- Checkout kind: named branch
- Remote subject: bound
- Expected/live remote comparison: match
- Resolution path: merged
- Blocker: none
```

## Abandoned Worktree Example

```text
Worktree resolution:
- Reference: phase-execution/EXAMPLE-abandoned-worktree
- Owner/category: orchestrator/phase-execution
- Checkout kind: named branch
- Remote subject: bound
- Expected/live remote comparison: match
- Resolution path: abandoned
- Blocker: none
```

## Kept Branch Example

```text
Branch resolution:
- Intentionally kept.
- Branch: phase/EXAMPLE-retry-behavior
- Local tip SHA before cleanup: abc1234
- Remote tip SHA before cleanup: abc1234
- PR: <PR link>
- Reason: waiting for upstream API decision.
- Next owner: <owner>
- Revisit trigger: EXAMPLE-123 or 2026-07-01.

Worktree resolution:
- Reference: phase-execution/EXAMPLE-kept-worktree
- Owner/category: orchestrator/phase-execution
- Checkout kind: named branch
- Remote subject: bound
- Expected/live remote comparison: match
- Resolution path: intentionally kept branch
- Blocker: none
```

## Reviewer Detached Worktree Example

```text
Worktree resolution:
- Reference: reviewer-verification/EXAMPLE-r2-round-1
- Owner/category: Reviewer 2/reviewer-verification
- Checkout kind: detached
- Remote subject: none
- Expected/live remote comparison: none
- Resolution path: reviewer detached
- Blocker: none
```

Complete paths, Git identities, local expected-state transitions, ref pre/post checks, clean diagnostics, removal results, and retained-checkout absence verification stay in private local evidence.
