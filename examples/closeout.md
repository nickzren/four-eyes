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
```
