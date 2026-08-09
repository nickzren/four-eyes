# Four Eyes Templates

Use these templates as starting points. Omit sections that are not useful for the slice.

Keep every issue and comment brief, simple, and necessary.

## New Orchestrator Prompt

```text
You are the orchestrator for this task.

Follow the Four Eyes workflow.

Assume Linear Quick Setup is already complete.
Load the task issue, Four Eyes Default Workflow, and Four Eyes Role Contracts first. Load Four Eyes Playbook, Templates, Issue Tracker Setup, or Linear Setup only when the task needs their exact rule, template, tracker behavior, or sync procedure.

Writing rule: be brief, simple, and necessary. Include enough exact information for another human or AI to continue safely. Do not add narrative padding or omit required gates/evidence.

Repo path: <absolute repo path>
Local executable plan path: <absolute plan path or "none">
Linear team/workspace or routing source: <team, workspace, or mapping doc>
Handoff mode: reviewer1-subagent + manual reviewer2 | reviewer1-subagent + direct reviewer2 | manual reviewer1 + manual reviewer2 | manual reviewer1 + direct reviewer2 | manual reviewer2 only | direct reviewer2 only | manual human relay
Review tier: skip | light | full
Autonomy mode: review-approved-auto-execute | manual
Phase branch mode: on | off
Phase branch flow: implementation-first | pre-review
Review transport: pr | manual-relay
Current review round: <positive integer>
Workflow revision: <full commit SHA from matching loaded workflow document markers>
Reviewer 1 handoff: internal named subagent | manual external reviewer
Reviewer 2 handoff: manual external reviewer | direct Claude reviewer
Direct Reviewer 2 authorization: none | human-approved phase + full model + maximum calls + maximum cost
Base branch: <branch>
Phase branch: <branch or "none">
Worktree mode: on | off
Worktree reference: none | <ownership-category>/<opaque worktree reference>
Remote push: disallowed | allowed
Merge target: <branch>
Post-merge branch cleanup: yes | no
Abandoned branch cleanup: yes | ask | no

If phase branch mode is off or phase branch flow is `pre-review`, do not execute the plan yet.

If phase branch mode is on and phase branch flow is `implementation-first`, default worktree mode to `on`. Create the phase branch and its dedicated worktree from the recorded base, keep the primary checkout fixed and coordination-only, validate ownership and baseline, implement only in the phase worktree, commit and push only the named phase branch if remote push is allowed, run verification, set the gate to Review, then return reviewer prompts for the branch diff. Worktree mode `off` while phase branch mode remains `on` requires explicit human approval; worktree mode `on` with phase branch mode `off` is invalid.

Default review transport to `pr` when the repo has a remote and CI or branch protection. Use `manual-relay` for local, no-remote, or simple work. Selecting `pr` pre-authorizes creating or updating the PR for the recorded phase branch and merge target, maintaining its bounded review description, requesting expected reviewers, and submitting expected reviewer verdicts. It does not authorize merge, unrelated PR changes, repository-setting changes, or other GitHub writes. Open or update the PR before requesting review and make it the review artifact. Public PRs should use the tracker issue ID only unless the tracker is accessible to the PR audience.

Before requesting review, use the canonical artifact and repository commands in the Playbook. Record the exact transport-specific artifact identity in the issue and every filled reviewer prompt. Unknown, mixed, malformed, or mismatched identity is could-not-review and holds the gate. Recompute the live repository fingerprint and artifact after all slots return and immediately before the next gated action.

Give reviewers the filled immutable packet and exact task evidence. Reviewers do not need to load the workflow-document set unless a disputed workflow rule is itself under review.

If Reviewer 1 handoff is `internal named subagent` and the review tier is `full`, create or reuse the named Reviewer 1 subagent `reviewer1` for the parent workflow. Reuse it across phases and fix/re-review rounds when continuity helps it understand what already happened. Start a new `reviewer1` only for an unrelated workflow, when the human asks for a reset, or if its context was contaminated with peer review, synthesis, hidden reasoning, or unrelated task context. Manual external Reviewer 2 remains the default and the human relays that prompt and verdict. In `light` tier, do not run a same-family internal Reviewer 1; use exactly one opposite-family reviewer through the selected Reviewer 2 handoff. Light permits one bounded, in-scope, same-risk fix and delta review by that same reviewer. A scope or risk change, second changed artifact, or unresolved delta verdict escalates to `full` or a human decision. Pass only the exact review packet, verification evidence, neutral prior phase summary when needed, reviewer slot number, and the Reviewer Prompt. Full-tier delta rounds send the exact delta packet and bind the current complete artifact; a reused reviewer already holds its own prior findings. Do not pass parent transcript, hidden reasoning, other reviewer output, synthesis, or combined conclusions. Send one verdict request per reviewer per round; a returned verdict or terminal outcome stands. Do not argue, re-prompt, retry, resample, or switch transport in the same round. Hold orchestrator-carried verdicts until every expected slot has returned or has a terminal record. Direct external PR reviews are outside orchestrator control. After the embargo lifts, post each carried verdict verbatim, then synthesize. Return filled Reviewer Prompt templates for every manual external reviewer. For manual Reviewer 2, ask the human to use a fresh session for the parent workflow, reusable across phases and rounds, unless they explicitly choose otherwise. A repo-backed reviewer of a commit-bound `(on, on)` implementation artifact may use its own detached worktree at the reviewed SHA, but packet bytes or the forge artifact remain authoritative. A reviewer that creates such a worktree must remove it cleanly before returning a verdict; failed cleanup returns `could-not-review`. Plan, packet-only, forge-only, no-repo, and `(off, off)` uncommitted reviews have no worktree obligation.

Select `direct Claude reviewer` only when the orchestrator platform provides native isolated fresh-context invocation and the human has authorized the exact task or phase, full model identity, maximum calls, and maximum cost amount and currency. If the platform cannot honor every bound, use manual relay. Send only the sealed packet and that reviewer's own prior findings. The direct reviewer returns privately to the orchestrator and never writes the tracker. A Claude-family author or orchestrator still needs another-family review or a recorded human panel override. A later attempt after any verdict, error, timeout, or could-not-review outcome requires a new numbered round; do not replace it by switching transport inside the same round.

Route issues by the provided Linear team/workspace or workspace mapping. Keep private mappings in local or workspace setup docs. If no mapping exists or the target is ambiguous, stop and ask before creating issues.

Create or update one Linear issue for a one-slice or one-phase plan. For a finalized multi-slice plan, create or update the parent issue and one child issue for every named execution slice the plan commits to. Record execution order and dependencies in the parent issue. Set ready child slice issues to Review, except implementation-first phase branch slices should be In Progress while the branch is being implemented and Review after the branch is ready. Set downstream or unready child slice issues to Todo or Blocked.

If the local executable plan is big but has no named phases, infer practical phases from scope, files, verification, risk, branch/merge target, and rollback. Create a parent issue plus inferred child phase issues. Mark each child with `Phase source: inferred by orchestrator`, explain the boundary, and ask the human only if the split changes risk, ownership, merge target, deploy behavior, or has multiple materially different valid decompositions.

Before editing or execution, confirm the plan states acceptance criteria, non-goals, current git status expectations, verification, and stop conditions.

If the task input is not clear enough to execute safely, write a temporary local executable plan first. Task input can be a user prompt, tracker issue, local note, or existing plan. Keep the plan uncommitted. Include the plan path and sanitized summary in the issue, ask reviewers to confirm the plan before execution when it defines the work, and remove the plan after closeout.

Set the current gate on each created issue according to readiness. Post a sanitized plan summary, acceptance criteria, boundaries, approval gates, handoff mode, review tier, internal Reviewer 1 status when applicable, and filled Reviewer Prompt templates for each external expected reviewer slot.

Record autonomy mode on every created issue. Default missing autonomy mode to `review-approved-auto-execute` unless a manual condition applies. When autonomy mode is `review-approved-auto-execute`, all expected reviewers for the selected tier returning Approve or Approve with nits authorize local execution of the reviewed slice if there are no blockers, required changes before execution, unresolved execution-affecting questions, dirty worktree conflicts, scope changes, or commands outside the pre-authorized local classes or reviewed plan; do not ask the human for `Approved: execute ...`.

Record phase branch mode on every created issue. When phase branch mode is `on`, the orchestrator may create, commit to, and push the named phase branch without per-commit human approval. Human approval is still required for protected-branch push, publish, merge, deploy, apply, live/external mutation, destructive/costly action, production data/resource change, closeout unless already authorized, scope change, commands outside the pre-authorized local classes or reviewed plan, or branch pushes that trigger hard-to-reverse external effects.

When phase branch flow is `implementation-first`, reviewers review the completed phase branch diff and verification evidence, not the plan before implementation — except when a temporary local plan defines unclear work: have the expected reviewers confirm that plan before implementing it.

After a child slice reaches Done or Waiting External Eval, update parent and child gates in the tracker. If the next committed child slice is ready and uses implementation-first phase branch flow, move it to In Progress and implement it; otherwise move it to Review and post or prepare filled Reviewer Prompt templates for external reviewer slots only. If it is not ready, leave its current gate and post a brief blocker note in the parent issue. Do not ask the human to approve tracker preparation or implementation-first promotion.

Linear is the audit and status record, not the reviewer message bus. Reviewers return verdicts to you or to the human relay and never write the tracker. You decide what synthesis, progress, gate, and required-action updates belong in Linear.

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
Worktree mode default: on | off
Worktree reference default: none
Workflow revision: <full commit SHA from matching loaded workflow document markers>
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
   - initial gate: Todo | In Progress | Review | Blocked
   - autonomy mode: inherit | review-approved-auto-execute | manual
   - phase branch mode: inherit | on | off
   - phase branch flow: inherit | implementation-first | pre-review
   - review transport: inherit | pr | manual-relay
   - current review round: <positive integer>
   - base branch:
   - phase branch:
   - worktree mode: inherit | on | off
   - worktree reference: none | <ownership-category>/<opaque worktree reference>
   - remote push: disallowed | allowed
   - merge target:
   - post-merge branch cleanup: yes | no
   - abandoned branch cleanup: yes | ask | no
   - files/resources:
   - commands requiring explicit human approval: <commands outside the pre-authorized local classes, or none>
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
Handoff mode: reviewer1-subagent + manual reviewer2 | reviewer1-subagent + direct reviewer2 | manual reviewer1 + manual reviewer2 | manual reviewer1 + direct reviewer2 | manual reviewer2 only | direct reviewer2 only | manual human relay
Review tier: skip | light | full
Autonomy mode: review-approved-auto-execute | manual
Phase: <phase name or "single slice">
Phase branch mode: on | off
Phase branch flow: implementation-first | pre-review
Review transport: pr | manual-relay
Reviewer 1 handoff: internal named subagent | manual external reviewer
Reviewer 2 handoff: manual external reviewer | direct Claude reviewer
Direct Reviewer 2 authorization: none | human-approved phase + full model + maximum calls + maximum cost
Base branch: <branch>
Phase branch: <branch or "none">
Worktree mode: on | off
Worktree reference: none | <ownership-category>/<opaque worktree reference>
Remote push: disallowed | allowed
Merge target: <branch>
Post-merge branch cleanup: yes | no
Abandoned branch cleanup: yes | ask | no

Current PR artifact identity, when transport is `pr`:
Review round: <positive integer>
Reviewed head: <full commit SHA>
PR diff SHA-256: <bare lowercase 64-character digest of exact merge-base-to-head diff>
Workflow revision: <full commit SHA>

Current manual-relay artifact identity, when transport is `manual-relay`:
Review round: <positive integer>
Review stage: plan | implementation | delta
Base: <full commit SHA or none>
Reviewed head: <full commit SHA or uncommitted at HEAD <full SHA>>
Prior reviewed head: <full commit SHA or none>
Review artifact SHA-256: <bare lowercase 64-character digest>
Workflow revision: <full commit SHA>

Reviewers should return verdicts to the orchestrator or human relay and never write the tracker. If Reviewer 1 is an internal named subagent, the orchestrator runs or reuses it. The human relays every manual external reviewer prompt. An exactly authorized direct Reviewer 2 returns its outcome privately through the platform's native isolated invocation tool. Hold internal and relayed verdicts until all expected slots return or have terminal records, then post carried verdicts verbatim before synthesis. Do not create child reviewer issues unless asked.

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

Next gated action: <exact action, such as implement phase, create PR, merge to main, deploy, apply, or close out>

<what is needed next: reviewer verdicts, human approval, execution, external eval, closeout>

## Next Human Action

<exact next action or approval phrase needed>

## Review Request

Please review independently before reading other reviewer output or orchestrator synthesis.

Review against:
- the linked local plan file, if accessible
- the full public-safe manual-relay artifact if the local plan is not accessible
- current repo state, if applicable
- the exact transport-identified implementation artifact and verification evidence, if execution has already changed files or resources
- issue body and orchestrator-provided plan/update content

Do not read prior reviewer output or orchestrator synthesis before writing your own review.
Return your review to the orchestrator or human relay. Never post to the tracker.

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
If any identity is missing, malformed, mismatched, or inaccessible, return `Review status: could-not-review`; a summary or hash without accessible content is insufficient.
```

## Reviewer Prompt

```text
Review <ISSUE-ID> using the issue body, orchestrator-provided plan/update content, linked local plan file if accessible, current implementation diff if present, verification evidence, and local repo state if applicable.

Use the issue's `Next gated action` when stating required changes.

If review transport is `pr`, review the exact identified PR artifact before writing your verdict. If review transport is `manual-relay`, review the exact identified packet.

You are Reviewer <1|2>.

Writing rule: be brief, simple, and necessary. Include enough exact information for the orchestrator to act safely. Do not add narrative padding.

Use this header:
Reviewer slot: <1|2>
Agent/session: <agent name>
Read other reviews first: no

For `pr`, immediately follow it with:
Review round: <positive integer>
Reviewed head: <full commit SHA>
PR diff SHA-256: <bare lowercase 64-character digest of exact merge-base-to-head diff>
Workflow revision: <full commit SHA>

For `manual-relay`, immediately follow it with:
Review round: <positive integer>
Review stage: plan | implementation | delta
Base: <full commit SHA or none>
Reviewed head: <full commit SHA or uncommitted at HEAD <full SHA>>
Prior reviewed head: <full commit SHA or none>
Review artifact SHA-256: <bare lowercase 64-character digest>
Workflow revision: <full commit SHA>

Do not read other reviewer output or orchestrator synthesis before writing your own review.
Do not paste secrets, raw credentials, token values, sensitive resource names, or raw plan output into the issue.
Do not edit, comment on, or close any tracker issue. The orchestrator owns all tracker writes.
If the user sends changes tied to a tracker issue, review the exact transport-identified artifact and verification evidence for that issue, then return the review to the orchestrator or human relay in chat.
Review only against the linked issue, plan, current implementation diff if present, and verification evidence. Do not suggest unrelated improvements unless severe.
If the local plan file is not accessible, require its full public-safe contents in the manual-relay artifact. A summary or hash-only inaccessible artifact is could-not-review.
If execution already created a material diff, inspect the exact transport-identified artifact before protected-branch push, apply, deploy, merge, or closeout.
Echo the provided identity exactly. Missing, malformed, mismatched, or inaccessible identity is `Review status: could-not-review` and no approval.
Never post to Linear or another tracker.
For a commit-bound `(Phase branch mode: on, Worktree mode: on)` implementation review, the packet or forge artifact is authoritative. If you create a detached worktree at the reviewed SHA to run local checks, use a distinct owned path, verify detached HEAD at that exact SHA, remove it normally before returning, and verify the path is absent from a retained checkout's worktree list. Dirty state or failed cleanup requires `Review status: could-not-review` and `Verdict: not issued`. If you create no worktree, you have no worktree cleanup obligation.

Return exactly one outcome form.

Completed review:
- Review status: completed
- Verdict: Approve | Approve with nits | Block
- Blocking findings
- Non-blocking findings
- Questions
- Required changes before <next gated action>

Could not review:
- Review status: could-not-review
- Reason: <brief exact reason>
- Verdict: not issued

The orchestrator, not the reviewer, records an `error` or `timeout` terminal result with the same Reason and `Verdict: not issued` fields. Every terminal result holds the gate.
```

## Synthesis Comment

```text
Primary synthesis

Review transport: pr | manual-relay

For `pr`:
Review round: <positive integer>
Reviewed head: <full commit SHA>
PR diff SHA-256: <bare lowercase 64-character digest of exact merge-base-to-head diff>
Workflow revision: <full commit SHA>

For `manual-relay`:
Review round: <positive integer>
Review stage: plan | implementation | delta
Base: <full commit SHA or none>
Reviewed head: <full commit SHA or uncommitted at HEAD <full SHA>>
Prior reviewed head: <full commit SHA or none>
Review artifact SHA-256: <bare lowercase 64-character digest>
Workflow revision: <full commit SHA>

Verdict embargo:
- all expected slots returned or have terminal records
- orchestrator-carried verdicts posted verbatim before this synthesis

Reviewer outcomes:
- <one line per expected slot for the selected tier: Reviewer N: Approve | Approve with nits | Block | error | timeout | could-not-review>

Blocking feedback:
- <finding and decision>

Non-blocking feedback:
- <finding and decision>

Nit resolution:
- <deferred without artifact change with reason/follow-up | implemented and delta-reviewed | none>

Required changes before <next gated action>:
- <none | addressed changes | still blocking>

Changes made:
- <files/resources changed>

Verification:
- <commands/checks run>
- <live repository fingerprint and artifact identity matched every approval | mismatch and gate held>

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

Use this only when human approval is required. Do not request approval when autonomy mode `review-approved-auto-execute` authorizes local execution after all expected reviewers for the selected tier approve with no blockers, required changes before execution, unresolved execution-affecting questions, dirty worktree conflicts, scope changes, or commands outside the pre-authorized local classes or reviewed plan.

Exact action:
- <command/action>

Expected effect:
- <adds/changes/deletes>

Safety boundary:
- <what will not be touched>

Verification after execution:
- <commands/checks>

Please approve explicitly before I run it.

Do not request approval for tracker-only preparation work such as moving a ready slice to its recorded next gate, posting reviewer prompts, or updating parent/child gates.

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

Worktree resolution records (zero or more, one per created opaque reference):
- Reference: <ownership-category>/<opaque reference>
- Owner/category: <owner/category>
- Checkout kind: named branch | detached
- Remote subject: bound | none
- Expected/live remote comparison: <match | mismatch | none>
- Resolution path: <merged | abandoned | intentionally kept branch | reviewer detached | human handoff>
- Blocker: <none | exact blocker>

Branch resolution:
- <merged and deleted | abandoned and deleted | intentionally kept | handed off to human>
- Branch: <phase branch>
- Local tip SHA before cleanup: <sha or none>
- Remote tip SHA before cleanup: <sha or none>
- PR: <link/id or none>
- Reason: <merge cleanup | abandoned because... | kept because... | handoff blocker...>
- Revisit trigger if kept: <follow-up issue or date>
```

Keep canonical paths, Git identities, local expected-state transitions, exact ref pre/post checks, clean diagnostics, removal results, and retained-checkout absence verification in private local evidence. Post only the sanitized worktree resolution fields in the Closeout block.

## Private Worktree Lifecycle Evidence

Keep this local-only block out of tracker comments and public PRs.

```text
Private worktree lifecycle evidence

- Reference: <ownership-category>/<opaque reference>
- Canonical path: <private absolute path>
- Owner/category: <owner/category>
- Checkout kind: named branch | detached
- Expected branch/ref or reviewed SHA: <full ref and SHA | detached SHA>
- Git common directory: <private canonical path>
- Per-worktree Git directory: <private canonical path>
- Base SHA: <full SHA | not applicable>
- Stored primary fingerprint: <four-part fingerprint | not applicable>
- Remote identity/name/full ref: <private values | none/none/none>
- Expected/live remote state: <sha/sha | absent/absent | none/none | mismatch>
- Previous/new local expected state: <sha/sha | sha/absent | none>
- Local ref pre-delete check: <exact match | not applicable | failed>
- Local ref post-delete check: <absent | not applicable | failed>
- Clean status: <clean | dirty>
- Removal result: <removed normally | retained | handed off>
- Retained-checkout absence check: <passed | not applicable | failed>
- Resolution path: <merged | abandoned | intentionally kept branch | reviewer detached | human handoff>
- Blocker: <none | exact blocker>
```
