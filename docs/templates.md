# Four Eyes Templates

Use these templates as starting points. Omit sections that are not useful for the slice.

Keep every issue and comment brief, simple, and necessary.

## New Orchestrator Prompt

```text
You are the orchestrator for this task.

Follow the Four Eyes workflow.

Assume Linear Quick Setup is already complete.
Read the existing Four Eyes Default Workflow, Playbook, Templates, and Issue Tracker Setup in Linear first.

Writing rule: be brief, simple, and necessary. Include enough exact information for another human or AI to continue safely. Do not add narrative padding or omit required gates/evidence.

Repo path: <absolute repo path>
Local executable plan path: <absolute plan path or "none">
Linear team/workspace or routing source: <team, workspace, or mapping doc>
Handoff mode: reviewer1-subagent + manual reviewer2 | manual human relay
Review tier: skip | light | full
Autonomy mode: review-approved-auto-execute | manual
Phase branch mode: on | off
Phase branch flow: implementation-first | pre-review
Review transport: pr | manual-relay
Reviewer 1 handoff: internal named subagent | manual external reviewer
Reviewer 2 handoff: manual external reviewer
Base branch: <branch>
Phase branch: <branch or "none">
Remote push: disallowed | allowed
Merge target: <branch>
Post-merge branch cleanup: yes | no
Abandoned branch cleanup: yes | ask | no

If phase branch mode is off or phase branch flow is `pre-review`, do not execute the plan yet.

If phase branch mode is on and phase branch flow is `implementation-first`, create the phase branch, set the gate to In Progress while implementing, implement the phase, commit and push only the named phase branch if remote push is allowed, run verification, set the gate to Review, then return reviewer prompts for the branch diff.

Default review transport to `pr` when the repo has a remote and CI or branch protection. Use `manual-relay` for local, no-remote, or simple work. If review transport is `pr`, open or update the PR before requesting review and make the PR the review artifact. Public PRs should use the tracker issue ID only unless the tracker is accessible to the PR audience.

If Reviewer 1 handoff is `internal named subagent` and the review tier is `full`, create or reuse the named Reviewer 1 subagent `reviewer1` for the parent workflow. Reuse it across phases and fix/re-review rounds when continuity helps it understand what already happened. Start a new `reviewer1` only for an unrelated workflow, when the human asks for a reset, or if its context was contaminated with peer review, synthesis, hidden reasoning, or unrelated task context. In `light` tier, do not run a same-family internal Reviewer 1; the single reviewer must provide the cross-family check. Pass only the review packet: issue or plan summary, PR or branch target, verification evidence, neutral prior phase summary when needed, reviewer slot number, and the Reviewer Prompt. Delta rounds send only the delta packet; the subagent already holds its own prior findings. Do not pass parent transcript, hidden reasoning, other reviewer output, synthesis, or combined conclusions. Send one verdict request per round; a returned verdict stands. Record a Block, error, timeout, or could-not-review verdict and synthesize it; do not argue, re-prompt, discard, replace, or re-run with a new subagent to sample for a better verdict. Record the internal verdict verbatim as a PR comment or review body for `pr` transport, or quote it in full in the issue update or synthesis for `manual-relay`. Return filled Reviewer Prompt templates only for external reviewers, usually Reviewer 2. Ask the human to use a fresh external Reviewer 2 session for the parent workflow, reusable across phases and review rounds, unless they explicitly choose otherwise.

Route issues by the provided Linear team/workspace or workspace mapping. Keep private mappings in local or workspace setup docs. If no mapping exists or the target is ambiguous, stop and ask before creating issues.

Create or update one Linear issue for a one-slice or one-phase plan. For a finalized multi-slice plan, create or update the parent issue and one child issue for every named execution slice the plan commits to. Record execution order and dependencies in the parent issue. Set ready child slice issues to Review, except implementation-first phase branch slices should be In Progress while the branch is being implemented and Review after the branch is ready. Set downstream or unready child slice issues to Todo or Blocked.

If the local executable plan is big but has no named phases, infer practical phases from scope, files, verification, risk, branch/merge target, and rollback. Create a parent issue plus inferred child phase issues. Mark each child with `Phase source: inferred by orchestrator`, explain the boundary, and ask the human only if the split changes risk, ownership, merge target, deploy behavior, or has multiple materially different valid decompositions.

Before editing or execution, confirm the plan states acceptance criteria, non-goals, current git status expectations, verification, and stop conditions.

If the task input is not clear enough to execute safely, write a temporary local executable plan first. Task input can be a user prompt, tracker issue, local note, or existing plan. Keep the plan uncommitted. Include the plan path and sanitized summary in the issue, ask reviewers to confirm the plan before execution when it defines the work, and remove the plan after closeout.

Set the current gate on each created issue according to readiness. Post a sanitized plan summary, acceptance criteria, boundaries, approval gates, handoff mode, review tier, internal Reviewer 1 status when applicable, and filled Reviewer Prompt templates for each external expected reviewer slot.

Record autonomy mode on every created issue. Default missing autonomy mode to `review-approved-auto-execute` unless a manual condition applies. When autonomy mode is `review-approved-auto-execute`, all expected reviewers for the selected tier returning Approve or Approve with nits authorize local execution of the reviewed slice if there are no blockers, required changes before execution, unresolved execution-affecting questions, dirty worktree conflicts, scope changes, or unreviewed commands; do not ask the human for `Approved: execute ...`.

Record phase branch mode on every created issue. When phase branch mode is `on`, the orchestrator may create, commit to, and push the named phase branch without per-commit human approval. Human approval is still required for protected-branch push, publish, merge, deploy, apply, live/external mutation, destructive/costly action, production data/resource change, closeout unless already authorized, scope change, unreviewed commands, or branch pushes that trigger hard-to-reverse external effects.

When phase branch flow is `implementation-first`, reviewers review the completed phase branch diff and verification evidence, not the plan before implementation — except when a temporary local plan defines unclear work: have the expected reviewers confirm that plan before implementing it.

After a child slice reaches Done or Waiting External Eval, update parent and child gates in the tracker. If the next committed child slice is ready, move it to Review and post or prepare filled Reviewer Prompt templates for external reviewer slots only. If it is not ready, leave its current gate and post a brief blocker note in the parent issue. Do not ask the human to approve review preparation.

Linear is the audit and status record, not the reviewer message bus. Reviewers return verdicts to you or to the human relay unless explicitly instructed to comment in the tracker. You decide what synthesis, progress, gate, and required-action updates belong in Linear.

Do not paste secrets, raw identifiers, raw plans, raw logs, or sensitive evidence into the issue.

If this tool or runtime has not been used for internal reviewer subagents before, run a one-time isolation check before relying on it: spawn a test reviewer subagent and confirm it cannot describe your current task unless that task is included in the review packet. If the check fails or cannot be verified, use manual external reviewer handoff for that slot.

End your response to the human with:
- issue ID or link; for multi-slice work, include the parent and ready child issue links
- current gate
- why that gate is set
- handoff mode and review tier
- phase branch mode and branch names
- review transport and PR link when applicable
- filled Reviewer Prompt templates for each ready issue and external expected reviewer slot
- exact next human action
- what you will do after that action
- what remains out of scope or forbidden
```

## Local Plan Template

```text
# <Task Title> Execution Plan

Local-only: yes
Commit this plan: no
Cleanup: remove after closeout
Autonomy mode default: review-approved-auto-execute
Phase branch mode default: on | off
Phase branch flow default: implementation-first | pre-review
Review transport default: pr | manual-relay
Post-merge branch cleanup default: yes
Abandoned branch cleanup default: ask
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
   - commitment: committed | optional | future
   - phase source: explicit | inferred by orchestrator
   - depends on: <none | slice name(s)>
   - initial gate: Todo | Review | Blocked
   - autonomy mode: inherit | review-approved-auto-execute | manual
   - phase branch mode: inherit | on | off
   - phase branch flow: inherit | implementation-first | pre-review
   - review transport: inherit | pr | manual-relay
   - base branch:
   - phase branch:
   - remote push: disallowed | allowed
   - merge target:
   - post-merge branch cleanup: yes | no
   - abandoned branch cleanup: yes | ask | no
   - files/resources:
   - commands: <list exact invocations; novel commands, flags, or pipelines require human approval>
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

- Remove this local plan after closeout.
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
Handoff mode: reviewer1-subagent + manual reviewer2 | manual human relay
Review tier: skip | light | full
Phase: <phase name or "single slice">
Phase branch mode: on | off
Phase branch flow: implementation-first | pre-review
Review transport: pr | manual-relay
Reviewer 1 handoff: internal named subagent | manual external reviewer
Reviewer 2 handoff: manual external reviewer
Base branch: <branch>
Phase branch: <branch or "none">
Remote push: disallowed | allowed
Merge target: <branch>
Post-merge branch cleanup: yes | no
Abandoned branch cleanup: yes | ask | no

Reviewers should return verdicts to the orchestrator or human relay. If Reviewer 1 is an internal named subagent, the orchestrator runs or reuses it directly and the human relays only the external reviewer prompt. Do not create child reviewer issues unless asked.

## Agent Team Boundary

- Parent issue: <ID or "none, single-slice">
- Current issue in scope: <ID>
- Sibling slice issues: <IDs or "none">
- In scope for this issue: <files/resources/scope>
- Out of scope: all other issues, tasks, and slices unless the human explicitly expands scope

## Source Plan

Local plan path: `<absolute path>`
Plan status: local-only temporary | not required because <reason>
Current gate: Backlog | Todo | In Progress | Review | Approval | Blocked | Waiting External Eval | Done
Autonomy mode: review-approved-auto-execute | manual

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
- Keep local plan files uncommitted and remove them after closeout.
- Use `/tmp/...` for raw evidence unless another approved evidence path is required.
- Implement only the stated acceptance criteria; no opportunistic refactor or unrelated files.

## Current Plan / Proposed Slice

<sanitized plan or implementation summary>

## Current Gate

<what is needed next: reviewer verdicts, human approval, execution, external eval, closeout>

## Next Human Action

<exact next action or approval phrase needed>

## Review Request

Please review independently before reading other reviewer output or orchestrator synthesis.

Review against:
- the linked local plan file, if accessible
- sanitized plan content in this issue if the local file is not accessible
- current repo state, if applicable
- current implementation diff and verification evidence, if execution has already changed files or resources
- issue body and orchestrator-provided plan/update content

Do not read prior reviewer output or orchestrator synthesis before writing your own review.
Return your review to the orchestrator or human relay. Do not post to the tracker unless explicitly instructed.

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

If review transport is `pr`, review the PR diff directly before writing your verdict. If review transport is `manual-relay`, review the provided branch or packet context.

You are Reviewer <1|2>.

Writing rule: be brief, simple, and necessary. Include enough exact information for the orchestrator to act safely. Do not add narrative padding.

Use this header:
Reviewer slot: <1|2>
Agent/session: <agent name>
Read other reviews first: no

Do not read other reviewer output or orchestrator synthesis before writing your own review.
Do not paste secrets, raw credentials, token values, sensitive resource names, or raw plan output into the issue.
Do not edit, comment on, or close any issue outside this issue and its parent or child slice set unless the human explicitly expands scope.
If the user sends changes tied to a tracker issue, review the current local diff and verification evidence for that issue, then return the review to the orchestrator or human relay. Reply in chat with the verdict unless explicitly instructed to post to the tracker.
Review only against the linked issue, plan, current implementation diff if present, and verification evidence. Do not suggest unrelated improvements unless severe.
If the local plan file is not accessible, review against the sanitized plan content in the issue and state that limitation.
If execution already created a material diff, review that diff before protected-branch push, apply, deploy, merge, or closeout. If phase branch mode is enabled, review the phase branch diff against the base branch.
Do not post to Linear or another tracker unless explicitly instructed.

Return your review with:
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

Nit resolution:
- <which nits were addressed before auto-execute, or "none required">

Required changes before execution:
- <none | addressed changes | still blocking>

Changes made:
- <files/resources changed>

Verification:
- <commands/checks run>

Autonomy decision:
- manual approval required | auto-execute authorized

Current gate:
- In Progress | Approval | Review | Blocked

Next human action:
- <exact action needed, or none if auto-execute is authorized>

If auto-executing or approved:
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

Use this only when human approval is required. Do not request approval when autonomy mode `review-approved-auto-execute` authorizes local execution after all expected reviewers for the selected tier approve with no blockers, required changes before execution, unresolved execution-affecting questions, dirty worktree conflicts, scope changes, or unreviewed commands.

Exact action:
- <command/action>

Expected effect:
- <adds/changes/deletes>

Safety boundary:
- <what will not be touched>

Verification after execution:
- <commands/checks>

Please approve explicitly before I run it.

Do not request approval for tracker-only preparation work such as promoting the next ready slice, posting reviewer prompts, or updating parent/child gates.

Exact approval phrase:
- Approved: execute <ISSUE-ID> <slice name> only.

Adapt `execute` to the approved action when needed, such as merge, push, apply, deploy, close, or archive.

For phase branch mode, use:

```text
Approved: merge <phase branch> into <target branch>, verify, close the issue, and delete the phase branch.
```

Before deleting any phase branch, record branch name, local tip SHA, remote tip SHA if present, PR link if present, and deletion reason in closeout. If local and remote tips differ, hand off to the human instead of deleting. If abandoned cleanup is authorized and a workflow-created PR exists for the abandoned branch, close that PR under the same cleanup gate before deleting the branch.
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
- In Progress | Review | Approval | Blocked | Waiting External Eval | Done

Review needed:
- <none | reviewer slots must review the implementation diff or phase branch diff before protected-branch push/apply/deploy/merge/closeout>

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
- Done | Waiting External Eval

Next human action:
- <none | approve closeout | validate external result | review follow-up>

Remaining work:
- <follow-up issue IDs or none>

Sensitive-data note:
- No secrets/raw sensitive identifiers were committed or posted.

Local cleanup:
- <temporary local plan removed, or "not created">
- <raw evidence location, if any>

Branch resolution:
- <merged and deleted | abandoned and deleted | intentionally kept | handed off to human>
- Branch: <phase branch>
- Local tip SHA before cleanup: <sha or none>
- Remote tip SHA before cleanup: <sha or none>
- PR: <link/id or none>
- Reason: <merge cleanup | abandoned because... | kept because... | handoff blocker...>
- Revisit trigger if kept: <follow-up issue or date>
```
