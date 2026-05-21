# Four Eyes Templates

Use these templates as starting points. Omit sections that are not useful for the slice.

Keep every issue and comment brief, simple, and necessary.

## New Orchestrator Prompt

```text
You are the orchestrator for this task.

Follow the Four Eyes workflow.

Assume Linear Quick Setup is already complete.
Read the existing Four Eyes Playbook and Templates in Linear first.

Writing rule: be brief, simple, and necessary. Include enough exact information for another human or AI to continue safely. Do not add narrative padding or omit required gates/evidence.

Repo path: <absolute repo path>
Local executable plan path: <absolute plan path>

Do not execute the plan yet.

Create or update one Linear issue from the local plan. If the plan has independent execution gates, different repos, different owners, or separate approvals, decompose it into parent/slice issues. Otherwise keep one issue.

Before editing or execution, confirm the plan states acceptance criteria, non-goals, current git status expectations, verification, and stop conditions.

Set the current gate to Review. Post a sanitized plan summary, acceptance criteria, boundaries, approval gates, and Reviewer 1 / Reviewer 2 prompts.

Do not paste secrets, raw identifiers, raw plans, raw logs, or sensitive evidence into the issue.

End your response to the human with:
- issue ID or link
- current gate
- why that gate is set
- exact next human action
- what you will do after that action
- what remains out of scope or forbidden
```

## Local Plan Template

```text
# <Task Title> Execution Plan

Local-only: yes | no
Commit this plan: yes | no
Repo/path: <absolute repo/path>
Issue: <fill after creation>

## Goal

<what needs to be done>

## Acceptance Criteria

- <observable condition that makes the slice done>

## Scope

In scope:
- <repo/path/resource>

Out of scope:
- <repo/path/resource>

## Current Evidence

- <repo facts, command outputs, live-state summaries, sanitized>

## Existing Patterns To Follow

- <local style/API/module/runbook/SOP to follow>

## Execution Slices

1. <slice name>
   - files/resources:
   - commands:
   - approval required before:
   - verification:
   - stop conditions:

## Sensitive-Data Boundary

- <what must remain local only>
- <what can be summarized in the issue>

## Review Gates

- Reviewer 1:
- Reviewer 2:
- Human approval needed for:

## Cleanup

- Remove/refresh this local plan when complete unless it should become durable documentation.
- Keep raw evidence under `/tmp/...` unless another approved evidence path is required.
```

## Task Issue Template

```text
## Workflow

Use the Four Eyes workflow.

Writing rule: brief, simple, necessary, with no missing gate/evidence details.

Orchestrator: <agent/session>
Reviewer 1: <agent/session>
Reviewer 2: <agent/session>

Reviewers should comment on this same issue. Do not create child reviewer issues unless asked.

## Source Plan

Local plan path: `<absolute path>`
Plan status: local-only | committed | not required because <reason>
Current gate: Todo | Review | Approval | Waiting External Eval | Done

## Goal

<what needs to be done>

## Acceptance Criteria

- <criteria copied or summarized from the plan>

## Scope

- <repo/path/resource in scope>
- <repo/path/resource out of scope>

## Boundaries

- No destructive/costly/cloud-mutating action without explicit human approval.
- Do not paste secrets, raw credentials, token values, sensitive resource names, or raw plan output into the issue.
- Keep local-only plan files uncommitted if marked local-only.
- Use `/tmp/...` for raw evidence unless another approved evidence path is required.
- Implement only the stated acceptance criteria; no opportunistic refactor or unrelated files.

## Current Plan / Proposed Slice

<sanitized plan or implementation summary>

## Current Gate

<what is needed next: reviewer comments, human approval, execution, external eval, closeout>

## Next Human Action

<exact next action or approval phrase needed>

## Review Request

Please review independently before reading other comments or orchestrator synthesis comments.

Review against:
- the linked local plan file, if accessible
- sanitized plan content in this issue if the local file is not accessible
- current repo state, if applicable
- current implementation diff and verification evidence, if execution has already changed files or resources
- issue body and orchestrator-provided plan/update comments

Do not read prior reviewer comments or orchestrator synthesis comments before writing your own review.
Post your review as a comment on this same issue.

Check:
- acceptance criteria gaps
- correctness
- ownership boundaries
- unnecessary scope expansion
- safety and rollback
- missing tests or verification
- sensitive-data exposure
- whether the next gate is ready

Use the required reviewer header from the playbook.
```

## Reviewer Prompt

```text
Review <ISSUE-ID> using the issue body, orchestrator-provided plan/update content, linked local plan file if accessible, current implementation diff if present, verification evidence, and local repo state if applicable.

You are Reviewer <1|2>.

Writing rule: be brief, simple, and necessary. Include enough exact information for the orchestrator to act safely. Do not add narrative padding.

Use this header:
Reviewer slot: <1|2>
Agent/session: <agent name>
Read other reviews first: no

Do not read other reviewer comments or orchestrator synthesis comments before writing your own review.
Do not paste secrets, raw credentials, token values, sensitive resource names, or raw plan output into the issue.
If the user sends changes tied to a tracker issue, review the current local diff and verification evidence for that issue, then post the review as a comment on that same issue. Reply in chat only with brief status or if the tracker is inaccessible.
Review only against the linked issue, plan, current implementation diff if present, and verification evidence. Do not suggest unrelated improvements unless severe.
If the local plan file is not accessible, review against the sanitized plan content in the issue and state that limitation.
If execution already created a material diff, review that diff before commit, push, apply, deploy, merge, or closeout.
Post your review as a comment on the same issue.

Return your review as a comment with:
- Verdict: Approve | Approve with nits | Block
- Blocking findings
- Non-blocking findings
- Questions
- Required changes before execution
```

## Synthesis Comment

```text
Primary synthesis

Reviewer outcomes:
- Reviewer 1: <verdict>
- Reviewer 2: <verdict>

Blocking feedback:
- <finding and decision>

Non-blocking feedback:
- <finding and decision>

Changes made:
- <files/resources changed>

Verification:
- <commands/checks run>

Current gate:
- Ready for human approval | Needs another review | Blocked on <reason>

Next human action:
- <exact action needed, for example: Approved: execute <ISSUE-ID> <slice name> only.>

If approved:
- <what the orchestrator will do>

If blocked:
- <what the orchestrator will do>

Still out of scope:
- <actions still forbidden>
```

## Approval Request

```text
Approval request

I am ready to execute the reviewed slice.

Exact action:
- <command/action>

Expected effect:
- <adds/changes/deletes>

Safety boundary:
- <what will not be touched>

Verification after execution:
- <commands/checks>

Please approve explicitly before I run it.

Exact approval phrase:
- Approved: execute <ISSUE-ID> <slice name> only.

Adapt `execute` to the approved action when needed, such as merge, push, apply, deploy, close, or archive.
```

## Execution Log

```text
Execution log

Changed:
- <what changed>

Source plan:
- `<path>`

Commit/artifact:
- <commit SHA, saved plan path, checksum, or none>

Verification:
- <narrow checks run and result>
- <if broad checks have unrelated failures, state that plainly>

Current gate:
- Review | Approval | Executing | Waiting External Eval | Done

Review needed:
- <none | reviewer slots must review the implementation diff before commit/push/apply/deploy/merge/closeout>

Next human action:
- <exact next action or none>

Sensitive-data note:
- <what remains local only>
```

## Waiting External Evaluation

```text
Waiting external evaluation

Executed:
- <what completed>

Immediate verification:
- <what passed now>

Waiting on:
- <CI / logs / user validation / cloud evaluation / other>

Next read-only recheck:
- <time or trigger>

Do not close yet because:
- <verification not complete>
```

## Closeout

```text
Closeout

Executed:
- <what ran>

Acceptance criteria checked:
- <criteria and result>

Verification:
- <checks and results>

Committed:
- <commit hash/message or not committed>

Resulting issue state will be set to:
- Done | Waiting External Eval | Follow-up created

Next human action:
- <none | approve closeout | validate external result | review follow-up>

Remaining work:
- <follow-up issue IDs or none>

Sensitive-data note:
- No secrets/raw sensitive identifiers were committed or posted.

Local cleanup:
- <local plan removed/refreshed/left intentionally>
- <raw evidence location, if any>
```
