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

## Private Lifecycle Evidence Example

This local-only record is not posted to the tracker or public PR.

```text
Private worktree lifecycle evidence

- Reference: phase-execution/EXAMPLE-retry-worktree
- Canonical path: <private canonical phase-worktree path>
- Owner/category: orchestrator/phase-execution
- Checkout kind: named branch
- Expected branch/ref or reviewed SHA: refs/heads/phase/EXAMPLE-retry-behavior at abc1234
- Git common directory: <private canonical common Git directory>
- Per-worktree Git directory: <private canonical per-worktree Git directory>
- Base SHA: 1111111111111111111111111111111111111111
- Stored primary fingerprint: <HEAD/staged/unstaged/untracked values>
- Remote identity/name/full ref: <private remote identity/name/full ref>
- Expected/live remote state: abc1234/abc1234
- Previous/new local expected state: abc1234/absent
- Local ref pre-delete check: exact match
- Local ref post-delete check: absent
- Clean status: clean
- Removal result: removed normally
- Retained-checkout absence check: passed
- Resolution path: merged
- Blocker: none
```

Reviewer-detached evidence uses the same field order with checkout kind `detached`, the exact reviewed SHA, remote tuple `none/none/none`, and non-applicable branch-transition fields.

```text
Private worktree lifecycle evidence

- Reference: reviewer-verification/EXAMPLE-r2-round-1
- Canonical path: <private canonical reviewer-worktree path>
- Owner/category: Reviewer 2/reviewer-verification
- Checkout kind: detached
- Expected branch/ref or reviewed SHA: 2222222222222222222222222222222222222222
- Git common directory: <private canonical common Git directory>
- Per-worktree Git directory: <private canonical per-worktree Git directory>
- Base SHA: not applicable
- Stored primary fingerprint: not applicable
- Remote identity/name/full ref: none/none/none
- Expected/live remote state: none/none
- Previous/new local expected state: none
- Local ref pre-delete check: not applicable
- Local ref post-delete check: not applicable
- Clean status: clean
- Removal result: removed normally
- Retained-checkout absence check: passed
- Resolution path: reviewer detached
- Blocker: none
```
