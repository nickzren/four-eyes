# Example Reviewer Verdict

Reviewer output returns to the human relay or orchestrator and is never posted directly to the tracker by the reviewer. The orchestrator holds carried verdicts until all expected slots return or have terminal records, then posts them verbatim before synthesis.

An exactly authorized direct Claude reviewer returns the same structured outcome privately to the orchestrator. A direct invocation `error`, `timeout`, or `could-not-review` has `Verdict: not issued`, stands for that round, and holds the gate; it is never silently retried or replaced by manual relay inside the same round.

```text
Reviewer slot: 2
Agent/session: Claude Code
Read other reviews first: no
Review round: 1
Reviewed head: 1111111111111111111111111111111111111111
PR diff SHA-256: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
Workflow revision: cccccccccccccccccccccccccccccccccccccccc
Review status: completed

Verdict: Approve with nits

Blocking findings:
- None.

Non-blocking findings:
- Add one test for retry exhaustion so the final failure path is covered.

Questions:
- None.

Required changes before merge:
- None. Defer the nit with a reason and follow-up without changing the artifact, or implement it and request delta review.
```

## Example Internal Reviewer 1 Record

For an internal Reviewer 1 subagent, hold the verdict until all expected slots return or have terminal records, then record it verbatim before synthesis.

```text
Internal Reviewer 1 verdict

Reviewer slot: 1
Agent/session: named Codex subagent `reviewer1`
Read other reviews first: no
Review round: 1
Reviewed head: 1111111111111111111111111111111111111111
PR diff SHA-256: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
Workflow revision: cccccccccccccccccccccccccccccccccccccccc
Review status: completed

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
