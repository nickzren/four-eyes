# Example Orchestrator Synthesis

```text
Primary synthesis

Review transport: pr
Review round: 2
Reviewed head: 2222222222222222222222222222222222222222
PR diff SHA-256: bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
Workflow revision: cccccccccccccccccccccccccccccccccccccccc

Verdict embargo:
- Both Full-tier slots returned for round 2.
- Orchestrator-carried verdicts were posted verbatim before synthesis.

Reviewer outcomes:
- Round 1 Reviewer 1: Approve.
- Round 1 Reviewer 2: Approve with nits.
- Round 2 Reviewer 1: Approve.
- Round 2 Reviewer 2: Approve.

Blocking feedback:
- None.

Non-blocking feedback:
- Add retry-exhaustion test. Accepted.

Nit resolution:
- The retry-exhaustion test was implemented after round 1, changing the head and invalidating both approvals.
- Both Full-tier slots reviewed the new head and PR diff in round 2.

Required changes before merge:
- None.

Changes made:
- Implemented retry classification on `phase/EXAMPLE-retry-behavior`.
- Added retryable, non-retryable, and retry-exhaustion tests.

Verification:
- `pytest tests/test_sync_worker.py`: pass.
- `git diff --check`: pass.

Review artifact:
- PR: <PR link>.
- Live forge head and canonical PR diff SHA-256 were recomputed after review and match both round 2 approvals.

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
