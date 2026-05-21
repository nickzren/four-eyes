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

Changes made:
- Plan updated to include retry-exhaustion test.

Verification:
- Not run yet. This is still pre-implementation.

Current gate:
- Approval.

Next human action:
- Approve or reject execution.

Exact approval phrase:
- Approved: execute EXAMPLE-123 retry classification slice only.

If approved:
- The orchestrator will edit only the reviewed files, run the agreed checks, and update the issue with verification.

If blocked:
- The orchestrator will keep the issue at Review or Blocked and address the blocker before execution.

Still out of scope:
- No deploys, data changes, unrelated refactors, or other slices.
```
