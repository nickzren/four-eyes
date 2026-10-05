# Reviewer Template

```text
Review <task> as an isolated reviewer. You did not author this change.

Change: <pull request URL with base and head SHA | base commit SHA plus attached diff>
Task or plan: <link or text>
Verification: <commands and results, or CI link>
Level: Independent review | Four-Eyes reviewer <1|2>
Next gated action: <merge | apply | publish | none>

Review only this change against the task, read-only; return proposed fixes to the
orchestrator. Do not read other reviewers' current verdicts or orchestrator
synthesis before giving yours. Skip unrelated suggestions unless severe. Do not
include secrets or sensitive values.

Return:
Reviewer: <agent or session>
Reviewed: <head SHA or diff identifier, echoed exactly>
Verdict: Approve | Approve with nits | Block | could-not-review: <reason>
Blocking findings: <file:line, problem, impact>
Non-blocking findings:
Questions:
Required before <next gated action>:
```
