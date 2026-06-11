# Example Reviewer Verdict

Reviewer output can be returned to the human relay or orchestrator. It does not need to be posted directly to the tracker.

```text
Reviewer slot: 2
Agent/session: Claude Code
Read other reviews first: no

Verdict: Approve with nits

Blocking findings:
- None.

Non-blocking findings:
- Add one test for retry exhaustion so the final failure path is covered.

Questions:
- None.

Required changes before execution:
- None. The orchestrator can implement the plan and include the extra test if it fits the touched code.
```

## Example Internal Reviewer 1 Record

For an internal Reviewer 1 subagent, record the verdict verbatim before synthesis.

```text
Internal Reviewer 1 verdict

Reviewer slot: 1
Agent/session: named Codex subagent `reviewer1`
Read other reviews first: no

Verdict: Approve

Blocking findings:
- None.

Non-blocking findings:
- None.

Questions:
- None.

Required changes before merge:
- None.
```
