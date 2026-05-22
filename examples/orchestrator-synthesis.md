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
- Retry-exhaustion test will be included during auto-execute.

Required changes before execution:
- None.

Changes made:
- Plan updated to include retry-exhaustion test.

Verification:
- Not run yet. This is still pre-implementation.

Autonomy decision:
- auto-execute authorized

Current gate:
- In Progress.

Next human action:
- None for execution. Reviewer approval authorized local execution under autonomy mode.

If auto-executing:
- The orchestrator will edit only the reviewed files, run the agreed checks, and move the issue back to Review if execution creates a material diff.

If blocked:
- The orchestrator will keep the issue at Review or Blocked and address the blocker before execution.

Still out of scope:
- No deploys, data changes, unrelated refactors, or other slices.
```
