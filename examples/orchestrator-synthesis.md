# Example Orchestrator Synthesis

```text
Primary synthesis

Reviewer outcomes:
- Reviewer 1: Approve with nits
- Reviewer 2: Approve

Blocking feedback:
- None.

Non-blocking feedback:
- Add retry-exhaustion test. Accepted.

Nit resolution:
- Retry-exhaustion test was added on the phase branch.

Required changes before merge:
- None.

Changes made:
- Implemented retry classification on `phase/EXAMPLE-retry-behavior`.
- Added retryable, non-retryable, and retry-exhaustion tests.

Verification:
- `pytest tests/test_sync_worker.py`: pass.
- `git diff --check`: pass.

Autonomy decision:
- phase branch approved; merge requires human approval

Current gate:
- Approval.

Next human action:
- Approve merge to `main`, post-merge verification, closeout, and phase branch deletion.

Exact approval phrase:
- Approved: merge phase/EXAMPLE-retry-behavior into main, verify, close the issue, and delete the phase branch.

If blocked:
- The orchestrator will keep the issue at Review or Blocked, fix the phase branch, push the update, and request delta review.

Still out of scope:
- No merge to `main`, deploys, data changes, unrelated refactors, or other slices.
```
