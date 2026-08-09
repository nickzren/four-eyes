# Example Closeout

```text
Closeout

Coordination record: local

Executed:
- Completed a read-only retry-configuration audit.
- Produced no repository diff and used no phase branch or worktree.

Acceptance criteria checked:
- documented retry settings inspected: pass.
- no repository mutation: pass.

Verification:
- documented read-only verification command: pass.
- working tree clean: pass.

Committed:
- Not committed; no material diff.

Resulting coordination status:
- completed

Next human action:
- None.

Remaining work:
- None.

Sensitive-data note:
- No secrets, raw logs, or sensitive identifiers were committed or posted.

Branch resolution:
- No phase branch existed.

Temporary artifacts after this final local record is verified:
- Remove the temporary local plan and execution-state record, then verify absence.
- Raw output not retained.
```

## Merged PR And Worktree Example

```text
Pre-cleanup resolution record

- Reviewed head: abc1234
- Local tip SHA: abc1234
- Remote tip SHA: abc1234
- PR: <PR link>
- Authorized resolution: merged cleanup

Final closeout results

Resulting coordination status:
- merged

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

```text
Temporary artifacts after this final PR record is verified:
- Remove the temporary local plan and execution-state record, then verify absence.
```

## Non-Terminal Waiting Example

```text
Coordination update

Status: waiting external eval
Gate: external evaluation
Next action: recheck the recorded external result
Closeout: not allowed; the coordination record remains open
```

## Abandoned Worktree Example

```text
Resulting coordination status:
- abandoned

Branch resolution:
- Abandoned and deleted under the authorized cleanup gate.
- Branch: phase/EXAMPLE-abandoned
- Local tip SHA before cleanup: def5678
- Remote tip SHA before cleanup: def5678
- PR: <PR link>
- Reason: superseded work; no preservation required.

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
Resulting coordination status:
- retained

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

## Handed-Off Example

```text
Resulting coordination status:
- handed off

Blocker:
- Cleanup has an unapproved external side effect.

Owner and next action:
- Human owner accepted responsibility to decide the cleanup path.

Branch resolution:
- Handed off to human.
- Branch: phase/EXAMPLE-side-effect
- Local tip SHA before cleanup: fedcba9
- Remote tip SHA before cleanup: fedcba9
- PR: <PR link>
- Reason: explicit human decision required.
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

This local-only record is not posted to a public coordination record.

```text
Private worktree lifecycle evidence

- Reference: phase-execution/EXAMPLE-retry-worktree
- Canonical path: <private canonical phase-worktree path>
- Owner/category and cleanup owner: orchestrator/phase-execution | orchestrator
- Checkout kind: named branch
- Expected branch/ref or reviewed SHA: refs/heads/phase/EXAMPLE-retry-behavior at aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
- Git common directory: <private canonical common Git directory>
- Per-worktree Git directory: <private canonical per-worktree Git directory>
- Base SHA: 1111111111111111111111111111111111111111
- Stored primary fingerprint: HEAD=1111111111111111111111111111111111111111; staged=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855; unstaged=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855; untracked=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
- Remote identity/name/full ref: example.invalid/four-eyes | origin | refs/heads/phase/EXAMPLE-retry-behavior
- Expected/live remote state: absent/absent
- Previous/new local expected state: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/absent
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
- Owner/category and cleanup owner: Reviewer 2/reviewer-verification | Reviewer 2
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
