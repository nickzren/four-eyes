# Four Eyes Playbook

Use this workflow when a task is important enough to need independent agent judgment before execution, apply, deploy, merge, or another hard-to-reverse action.

## Communication Rule

Every agent message, issue, comment, review, synthesis, approval request, and closeout should be brief, simple, and necessary.

Include enough exact information for another human or AI to continue safely:

- repo or path
- plan path
- scope
- acceptance criteria
- current gate
- blockers
- commands
- approvals
- verification

Do not add narrative padding, duplicate old context, raw logs, secrets, or sensitive identifiers.

## Manual-First Policy

This playbook is the Four Eyes policy. It works with any orchestrator and reviewer tools that preserve independent judgment, shared state, auditability, and human gates.

The supported workflow is manual-first:

- a Codex App orchestrator or another primary agent owns the plan, execution, synthesis, and tracker updates
- when available, the orchestrator runs Reviewer 1 as a named isolated subagent and reuses it for the phase or parent workflow
- the human relays only reviewer prompts the orchestrator cannot launch directly, usually Reviewer 2
- reviewers return verdicts to the orchestrator or human
- the human pastes the expected reviews back to the orchestrator after they are complete

Manual mode preserves independent judgment and keeps the process simple. It relies on the orchestrator to isolate any internal reviewer subagent and on human discipline for external message passing.

## Tracker Ownership

The issue tracker is the audit and status record, not the reviewer message bus.

Reviewers return verdicts to the orchestrator or human relay. They do not post directly to the tracker unless the orchestrator or human explicitly asks for that mode.

The orchestrator owns tracker updates:

- phase or slice status
- synthesized reviewer outcome
- current gate
- verification summary
- required human action
- remaining blockers or risks

## Reviewer Handoff And Isolation

Default Codex-led handoff:

- Reviewer 1: named Codex subagent `reviewer1`, created by the orchestrator and reused across review rounds for the phase or parent workflow
- Reviewer 2: external opposite-family reviewer, usually Claude Code, prompted by the human

A reviewer subagent must receive only the review packet and its own prior review history:

- issue or plan summary
- PR or branch target
- verification evidence
- neutral prior phase summary when needed
- the reviewer prompt and slot number

Do not pass the parent orchestrator transcript, hidden reasoning, other reviewer output, synthesis, or combined conclusions into a reviewer before that reviewer has posted its own verdict.

Create `reviewer1` once for the current phase or parent workflow and reuse the same subagent across fix/re-review rounds. Reuse across phases is allowed when those phases belong to the same parent plan and continuity helps the reviewer understand what already happened. Start a new `reviewer1` only for an unrelated workflow, when the human asks for a reset, or if the subagent context was contaminated with peer review, synthesis, hidden reasoning, or unrelated task context. Send one verdict request per review round; delta rounds send only the delta packet, since the subagent already holds its own prior findings. A returned verdict stands: do not argue with or re-prompt the reviewer inside a round, and never discard, replace, or re-run a Block, error, timeout, or could-not-review verdict with a new subagent to sample for a better one.

Record internal Reviewer 1's verdict verbatim. In `pr` transport, post it as a PR comment or review body. In `manual-relay`, quote it in full in the issue update or synthesis. Do not replace the original verdict with an orchestrator summary.

Before trusting a subagent handoff in a new tool or runtime, run a one-time isolation check: spawn a test reviewer subagent and confirm it cannot describe the parent orchestrator's current task unless that task is passed in the review packet. If the check fails or cannot be verified, use manual external reviewer handoff for that slot.

External Reviewer 2 should start as a fresh session for the parent workflow and may keep that session across phases and review rounds. Do not reuse a reviewer session for unrelated workflows unless the human explicitly chooses a long-lived reviewer conversation. If prior workflow context is needed, pass it as a neutral prior phase summary in the review packet.

A same-family subagent gives isolated reviewer continuity, not model-family independence. For non-skip work, at least one expected reviewer should be from a different model family than the agent that authored or orchestrated the change, unless the human explicitly overrides the review panel.

## Roles

### Orchestrator

Usually the primary agent session.

Responsibilities:

- create or update the local executable plan when needed
- create or update the issue tracker item from the plan
- decide whether the plan stays one issue or splits into execution-slice issues
- identify acceptance criteria, non-goals, and current git status before editing
- check existing implementation patterns before adding new ones
- keep sensitive data out of issues, commits, and broad summaries
- synthesize expected reviewer feedback for the selected tier
- resolve blockers or ask the human for an explicit override
- execute only after the review gate is clear
- post verification, commit summary, and remaining risks
- after every issue or gate update, tell the human the current gate and exact next action

### Reviewer 1

Usually a separate agent session or a named reviewer subagent.

Responsibilities:

- review independently before reading other reviewer output or orchestrator synthesis
- when prompted with a current-work issue reference, treat it as a review request: read the provided issue or packet context, review the current diff and verification evidence, and return the review to the orchestrator or human relay
- review against the linked local plan file, current repo state, current implementation diff and verification evidence if present, issue body, and orchestrator-provided plan/update content
- if the local plan file is not accessible, review against sanitized plan content in the issue and state that limitation
- check acceptance criteria, correctness, scope, safety, missing tests, and operational risks
- avoid unrelated suggestions unless severe
- return findings with the required header

### Reviewer 2

Usually a different model or agent family from the orchestrator, especially when Reviewer 1 is an orchestrator-created same-family subagent.

Responsibilities are the same as Reviewer 1.

### Human Approver

The human owns final approval for real risk gates:

- execution when autonomy mode is `manual`
- commands not listed in the reviewed plan
- commit or push when phase branch mode is not enabled
- push to protected branches, tags, releases, or unscoped branches
- merge into `main` or another protected branch
- publish
- closeout unless already authorized by workflow
- scope changes
- live or external systems, databases, cloud, deploys, destructive actions, costly actions, or production data/resource changes
- any action the plan or workflow marks as approval-gated

Human approval is not required for tracker-only workflow preparation such as creating planned child issues, promoting the next ready slice to Review, posting reviewer prompts, synthesizing reviews, or updating gate metadata.

## Autonomy Mode

Every non-trivial plan or slice must set:

```text
Autonomy mode: review-approved-auto-execute | manual
```

Default to `review-approved-auto-execute` for local repo code, docs, tests, or plan edits inside the reviewed slice. If autonomy mode is omitted, treat it as `review-approved-auto-execute` unless a manual condition applies. Use `manual` for live or external systems, databases, cloud, deploys, apply actions, destructive or costly actions, production data/resource changes, ambiguous ownership, or any slice the human marks approval-gated.

Local execution means working-tree file changes and verification commands inside the reviewed slice. It excludes network mutation, external state changes, and starting persistent processes or services.

Reviewed commands are the commands, arguments, and flags listed in the reviewed plan. Novel commands, novel flags, chained pipelines, or commands outside the reviewed command list require human approval.

A reviewer question is execution-affecting if its answer would change what or how the orchestrator executes. Cosmetic, follow-up, or post-execution questions do not block auto-execute.

Dirty worktree conflicts include uncommitted changes outside the slice scope, unmerged rebase or merge state, or untracked files conflicting with expected slice outputs.

Required changes before execution must be addressed and recorded in synthesis before auto-execute.

When autonomy mode is `review-approved-auto-execute`, all expected reviewers for the selected tier returning `Approve` or `Approve with nits` authorize the orchestrator to execute the reviewed local slice when there are no blockers, required changes before execution, unresolved execution-affecting questions, dirty worktree conflicts, scope changes, or unreviewed commands. The orchestrator must not ask for `Approved: execute ...` for that slice.

Auto-execute alone does not authorize commit, push, publish, merge, deploy, apply, live/external mutation, destructive/costly action, closeout unless already authorized, scope change, commands not listed in the reviewed plan, or work outside the assigned tracker issue set. Commit and push require phase branch mode or explicit human approval. Merge and protected-branch push remain separate human gates.

## Phase Branch Mode

For repo implementation phases, phase branch mode is the default high-throughput path when branch pushes are safe. The plan may disable it or require pre-review.

```text
Phase branch mode: on | off
Base branch: <main or other base>
Phase branch: <phase branch name>
Remote push: allowed | disallowed
Merge target: <main or other protected branch>
Post-merge branch cleanup: yes | no
```

When phase branch mode is `on`, the orchestrator may create the phase branch, commit to it, and push updates to that exact branch without asking the human for every commit or push, if all of these are true:

- the branch name, base branch, and merge target are recorded in the plan or issue
- the work stays inside the approved phase scope
- pushes go only to the named phase branch
- branch pushes do not deploy, mutate live systems, publish releases, or trigger hard-to-reverse external actions
- verification commands are run before review
- reviewers review the branch diff and verification evidence before merge approval

Phase branch mode is implementation-first by default: the orchestrator completes the phase on the branch, then reviewers review the branch diff once. Require pre-implementation review only when the plan, risk class, or human explicitly asks for it.

This intentionally allows local commits to the named phase branch before review. The review gate is before protected-branch push, merge, apply, deploy, or closeout.

Phase branch mode does not authorize:

- direct commits or pushes to `main` or protected branches
- force-push, rebase of shared history, tag creation, release creation, or branch deletion before merge
- deploy, apply, cloud/database mutation, destructive action, or costly action
- merge into the target branch

The human merge approval may authorize merge, post-merge verification, tracker closeout, and phase branch cleanup. Use an exact phrase such as:

```text
Approved: merge <phase branch> into <target branch>, verify, close the issue, and delete the phase branch.
```

If the repository has branch-push side effects, such as preview deploys, production deploys, release publishing, or data mutation, remote push is a human gate unless the human explicitly pre-authorizes that side effect.

## Review Transport

Every phase should state:

```text
Review transport: pr | manual-relay
```

Default to `pr` when the repo has a remote and CI or branch protection. Use `manual-relay` for local, no-remote, or simple work where a PR adds overhead.

When review transport is `pr`:

- the orchestrator opens or updates a PR from the phase branch to the merge target after verification
- the PR body includes the tracker issue link only when the repo is private or the tracker is accessible to the PR audience; otherwise it includes the tracker issue ID only
- the PR body includes the sanitized plan summary, acceptance criteria, verification evidence, and risk notes
- reviewers review the PR diff directly and write their verdict before reading other reviews
- verdict mapping is `Approve` -> approve, `Approve with nits` -> approve with comments, and `Block` -> request changes
- reviewer bodies include the required reviewer header
- the PR is the review artifact; the tracker remains the gate and status record

Merge is the default routine per-phase human gate. Existing risk gates remain unchanged: deploy, apply, external mutation, destructive or costly action, scope change, tier downgrade, protected-branch push, and branch pushes with side effects still require human approval.

Automation ladder:

1. Current baseline: PR transport with human-invoked external reviewers.
2. Current Codex-led default: reused named internal Reviewer 1, human-relayed external Reviewer 2.
3. Future: orchestrator invokes all reviewers against the PR or branch.
4. Future: CI-triggered reviewers.

Rungs 3 and 4 are not implemented or pre-authorized by this playbook.

## Review Tier

Every plan, phase, or slice should state the review tier:

```text
Review tier: skip | light | full
```

- `skip`: tiny docs, typos, formatting, simple issue/admin work, or other changes from the playbook skip list. Run verification when useful and keep the configured branch or merge gate.
- `light`: the default for routine low-risk, reversible repo work. Use one reviewer from a different model family than the agent that authored the change, one round, and no autonomous fix loop. A blocker, failed verification, could-not-review result, sensitive path, or oversized diff escalates to `full` or to a human decision.
- `full`: the normal Four Eyes gate: two independent reviewers, synthesis, bounded fix/re-review, and human approval for real-risk gates.

In `light` tier, do not run a same-family internal Reviewer 1 subagent. The single reviewer must provide the cross-family check, so the human relays only that external reviewer prompt unless the orchestrator can launch a different-family reviewer directly.

The human or local plan sets the review tier. If the tier is missing, use `light` for routine low-risk repo work and `full` for high-risk or broad work, or ask the human. The orchestrator may escalate the tier but must not downgrade its own work without explicit human instruction.

Always use `full` for security, infrastructure, schema/data, production, deploy, destructive, costly, external-state, or hard-to-reverse work.

Use the highest available reasoning for agents that judge: orchestrator decisions, reviewers, synthesis, blocker resolution, and non-trivial fixes.

## Required Reviewer Header

Reviewer 1:

```text
Reviewer slot: 1
Agent/session: <agent name>
Read other reviews first: no
```

Reviewer 2:

```text
Reviewer slot: 2
Agent/session: <agent name>
Read other reviews first: no
```

## Plan-First Rule

For non-trivial repo, infrastructure, cloud, security, deploy, cleanup, migration, debugging, or operational work, create a temporary local executable plan when the ticket or request is not clear enough to execute safely.

The plan should state:

- goal
- acceptance criteria
- scope and non-goals
- source-of-truth repo or path
- proposed execution slices
- review gates
- approval gates
- commands or runbook steps
- verification steps
- rollback or stop conditions
- sensitive-data boundaries

A local plan file is not required for simple issue admin, queue triage, one-line fixes, tiny doc edits, or tasks the human explicitly wants handled directly.

When a local plan defines or clarifies the work, reviewers review the plan as part of the gate before execution; for implementation-first phase branches, that means before implementation starts. The plan must be specific enough for reviewers to confirm scope, acceptance criteria, commands, verification, stop conditions, and human gates.

## Local Plan Storage

Use the least durable place that still supports the work:

- repo-local temporary plan when agents need it next to code
- `/tmp/...` for ephemeral evidence, raw command output, sensitive metadata, or large generated artifacts

Local executable plans are temporary coordination artifacts. Do not commit them, and prefer a gitignored path for repo-local plans so bulk staging cannot pick them up. If the work produces durable documentation, write that documentation separately from the temporary execution plan.

Remove the temporary local plan after the issue, phase, or parent workflow is complete. If work pauses before completion, keep the plan only as long as it is needed to resume safely.

If reviewers cannot access the local plan file, the orchestrator must include enough sanitized plan content in the issue for review to proceed safely.

## Issue Rule

The issue tracker is the gate, audit, and status record. It should summarize and gate the local plan, not replace it, and it should not be used as the default reviewer message bus.

Use one issue when the plan is one execution slice.

Use a parent issue plus child slice issues when the local plan has multiple named execution slices the plan commits to, independent execution gates, different repos, different owners, different deploy windows, independent rollback or verification, or different approvals.

Route issues by the provided Linear team/workspace or workspace mapping. Keep private mappings in local or workspace setup docs. If no mapping exists or the target is ambiguous, stop and ask before creating issues.

Do not create separate reviewer child issues by default. Reviewer identity belongs in the review artifact, synthesis, or orchestrator-posted tracker update.

### Multi-Slice Plans

When a finalized local plan contains multiple execution slices:

- a slice is ready when it has no unresolved upstream dependency, missing evidence, owner ambiguity, or approval blocker
- create the parent issue and one child issue for every named execution slice the plan commits to
- record the intended execution order and inter-slice dependencies in the parent issue
- use the parent issue as the overview gate; child issues carry exact slice gates such as Review, Approval, In Progress, Blocked, or Waiting External Eval
- parent gate mirrors the next active child gate; use Blocked only when no child is actionable, and Done only after all children are verified and closed
- assign each ready child slice the Review gate, except implementation-first phase branch slices use In Progress while the branch is being implemented and Review after the branch is ready
- keep downstream or unready slices Todo or Blocked when they depend on earlier slices, external decisions, missing evidence, or unresolved ownership
- after a child slice reaches Done or Waiting External Eval, the orchestrator checks the next committed child slice; if it is ready, move it to Review and post filled reviewer prompts without asking for human approval
- if the next committed child slice is not ready, leave its current gate and post a brief blocker note in the parent issue
- reviewers review every ready slice and return feedback to the orchestrator or human relay
- the orchestrator owns sequencing and may execute only the next approved slice
- post-execution review on each slice still applies before protected-branch push, apply, deploy, merge, or closeout
- the parent issue is the agent team boundary; agents may read related issues for context but must not edit, comment on, or close any issue outside the parent and its child slice issues unless the human explicitly expands scope
- if the parent plan changes materially, update affected slice issues in the same change under the Plan Drift Rule

Key distinction: create and review broadly; execute narrowly.

### Right-Sizing Slices

Review cost is per review run, not per change. Size slices to the run:

- Batch related low-risk cleanup into one slice, one issue, one review run with a combined acceptance list.
- Split into separate slices only when gates, rollback, owners, repos, deploy windows, or risk class differ.
- Do not open one issue per tiny change; do not hide unrelated risk classes inside one slice.
- Split an oversized phase diff instead of mega-reviewing it.

### Token-Efficient Review

Keep review tokens focused on judgment:

- reviewers inspect PR or repo diffs directly; do not paste large diffs into prompts, issues, or PR comments
- CI or check links replace pasted logs when CI exists
- re-review is delta-only by default: send the delta diff, plus that reviewer's own prior blocking findings only when the reviewer instance does not already hold them in context
- full re-review is required only when scope, risk, or acceptance criteria changed

### Phase Review

For high-throughput bug fixing, review phases instead of every bug:

- The plan may define Phase 1, Phase 2, and later phases, each with concrete tasks, files, verification, and acceptance criteria.
- In phase branch mode, the orchestrator may complete all fixes in the current phase, commit them, and push the phase branch before asking reviewers to review.
- Reviewers review the phase diff and verification evidence once, not every individual bug.
- The orchestrator fixes all blocking feedback in one batch.
- Re-review should focus on the blocker delta unless risk changed or the phase expanded.
- Default loop: initial review plus one fix/re-review. If still blocked, the human decides whether to continue, split, downgrade, or defer.

### Phase Inference

If a big executable plan exists locally but does not define phases, the orchestrator should infer phases before creating tracker child issues.

Use phase boundaries that keep each phase executable and reviewable:

- shared goal and acceptance criteria
- related files or modules
- one verification strategy
- one branch, merge target, and rollback path
- one risk class
- no hidden deploy, cloud, database, destructive, costly, or external-state action

The orchestrator may create the parent issue and inferred phase child issues as tracker preparation without human approval. Each inferred child issue must say:

- `Phase source: inferred by orchestrator`
- why the phase boundary was chosen
- branch name, base branch, and merge target if phase branch mode is enabled
- what remains out of scope
- when the phase should stop and ask the human

Ask the human before executing or creating many child issues only when the split changes risk, ownership, merge target, deploy behavior, or there are multiple materially different valid decompositions.

If phase inference is unclear, default to one phase rather than many tiny issues, and record the uncertainty in the parent issue.

## Phase Branch Flow

Use this flow when phase branch mode is enabled:

1. Orchestrator confirms the phase scope, base branch, phase branch, merge target, verification, and stop conditions. If a temporary local plan defines unclear work, expected reviewers confirm the plan before implementation starts.
2. Orchestrator creates the phase branch from the base branch.
3. Orchestrator implements the whole phase on that branch.
4. Orchestrator commits and pushes only the named phase branch when remote push is allowed.
5. Orchestrator runs verification and updates the tracker with the phase branch, diff summary, and reviewer prompts.
6. If review transport is `pr`, the orchestrator opens or updates the PR and uses the PR as the review artifact. If Reviewer 1 can run as a named isolated subagent, the orchestrator creates or reuses it directly. The human sends only the remaining external reviewer prompt, usually Reviewer 2. If no isolated subagent is available, the human sends packets to all expected reviewers.
7. Reviewers review the PR or branch diff and verification evidence independently, then return verdicts through the selected transport.
8. Orchestrator synthesizes feedback, fixes blockers on the same phase branch, commits and pushes the updates, and requests delta review when needed.
9. When all expected reviewers approve, orchestrator asks the human for the merge approval phrase.
10. After approval, orchestrator merges into the target branch, runs post-merge verification, updates or closes the tracker item if authorized, and deletes the phase branch if authorized.

This flow is meant to reduce review loops. It trades pre-implementation review for branch isolation and a hard merge gate.

## Standard Task Flow

Use this flow when phase branch mode is off, or when pre-implementation review is required.

1. Orchestrator creates a temporary local executable plan when the ticket or request is not clear enough to execute safely.
2. Orchestrator creates one issue or decomposes the plan into parent and child slice issues.
3. Orchestrator adds the temporary plan path, sanitized summary, acceptance criteria, boundaries, expected files or resources, current gate, and review request. Current gate: Review for ready issue(s); Todo or Blocked for downstream or unready child slice issues.
4. The orchestrator creates or reuses any internal Reviewer 1 subagent with only the review packet and its own prior review history. The human sends the ready issue link(s), local plan or sanitized summary, and task prompt only to external expected reviewer slots. Current gate: Review for ready issue(s).
5. Reviewers return verdicts independently to the orchestrator or human relay. Current gate: Review.
6. Orchestrator synthesizes the expected reviews. Current gate: In Progress when auto-execute is authorized and execution is starting, Approval if human approval is needed, Review if material changes need re-review, or Blocked if blockers remain.
7. Orchestrator updates code or plan if needed. Current gate: Review if material changes need re-review.
8. If changes are material, repeat review on the updated slice.
9. Human approves execution, apply, deploy, or merge when needed. Skip this for local execution authorized by autonomy mode. Current gate: Approval until approved.
10. Orchestrator executes the approved or auto-authorized slice and posts verification. If phase branch mode is enabled, the orchestrator may commit and push updates to the named phase branch as part of this work. If execution creates material code, doc, config, infra, data, or plan changes, Current gate: Review.
11. Reviewers review the implementation diff, phase branch diff when applicable, and verification evidence before merge, apply, deploy, or closeout approval.
12. Orchestrator synthesizes implementation reviews and updates the tracker with the status, gate, and required human action. Current gate: Approval if aligned, Review if material changes need re-review, or Blocked if blockers remain.
13. Orchestrator commits only the intended tracked changes when phase branch mode authorizes branch commits, when the human approves the commit, or when the approved workflow explicitly calls for it.
14. Orchestrator closes the issue only after verification, or moves it to an explicit waiting state.

If execution is read-only and creates no material diff, the orchestrator may move directly to Waiting External Eval, Approval, or Done according to the approved workflow and verification state.

In multi-slice mode, steps 5-7 run independently for each ready slice.

In multi-slice mode, preparing the next committed ready slice for Review is tracker work owned by the orchestrator. If autonomy mode authorizes local execution, reviewer approval is the execution gate. If phase branch mode is enabled, commits and pushes to the named phase branch may be handled by the orchestrator. The next human approval is for manual execution, protected-branch push, publish, merge, closeout unless already authorized by workflow, scope changes, live or external systems, databases, cloud, deploys, destructive actions, costly actions, production data/resource changes, or any action the plan or workflow marks as approval-gated.

## Orchestrator Next-Action Rule

After creating or updating an issue, changing a gate, posting a synthesis, requesting approval, or closing out work, the orchestrator must end its user-facing response with:

- issue ID or link
- current gate
- why that gate is set
- exact next human action
- what the orchestrator will do after that action
- what remains out of scope or forbidden

When the current gate is Approval, include an exact approval phrase the human can send, such as:

```text
Approved: execute <ISSUE-ID> <slice name> only.
```

Adapt the approval verb to the action, such as execute, merge, push, apply, deploy, close, or archive.

If execution is still forbidden, say that plainly.

## Implementation Discipline

Before editing:

- read the issue, local plan, linked spec, and relevant existing files
- identify acceptance criteria and non-goals
- inspect current git status so unrelated work is not disturbed
- check current implementation patterns before adding new ones

While editing:

- implement only the stated acceptance criteria
- do not change unrelated files
- do not refactor opportunistically
- preserve existing behavior unless the plan explicitly changes it
- follow existing code style, architecture, naming, and UI conventions
- add or update tests when the change affects logic, data flow, permissions, integrations, or user-visible behavior

Before review, commit, PR, deploy, or apply:

- run the narrowest useful verification command for the files or resources touched
- if a broad check is known to have unrelated failures, say that plainly and include the targeted checks that passed
- review the diff for unrelated changes
- confirm the next gate is correctly recorded in the issue

## Post-Execution Review Rule

Every material change created during execution must be reviewed before protected-branch push, apply, deploy, merge, or closeout.

Material changes include:

- code changes
- tests
- docs or runbooks
- CI/CD, infrastructure, or configuration
- database migrations or data changes
- local executable plans when their scope, gates, commands, verification, or safety boundaries changed

After material execution changes, the orchestrator must:

- update the issue Current gate to Review
- identify the exact files, resources, or diff to review
- include verification already run
- tell reviewers where to return feedback, either to the orchestrator or human relay
- keep protected-branch push, apply, deploy, merge, and closeout out of scope until reviews are synthesized and the human approves the next gated action

Reviewers must review the current implementation diff and verification evidence, not only the original plan.

If the approved action itself is apply, deploy, or another external mutation and creates no reviewable local diff, post verification and move to Waiting External Eval or Done according to the approved workflow.

## Gate State

The current gate must be visible in the issue tracker, not only buried in comments.

Recommended states:

- Backlog: idea not started
- Todo: local plan exists or task is ready to prepare
- In Progress: orchestrator actively working
- Review: waiting for expected reviewer slots
- Approval: reviewers aligned, waiting for the human
- Blocked: blocked by reviewer finding, missing evidence, external decision, unresolved ownership, or prior slice
- Waiting External Eval: executed, waiting for CI, logs, users, cloud evaluation, or another external system
- Done: verified and closed

If custom states are not available, use labels or issue-title prefixes:

- `gate:review`
- `gate:approval`
- `waiting:external-eval`
- `state:applied-awaiting-verification`
- `blocked:<reason>`

When using gate labels, remove the old gate label in the same update that adds the new gate label.

## Gate Rule

Proceed when the expected reviewer slots for the selected tier are complete and all blocking feedback is resolved.

A Block from any expected reviewer holds the gate. The orchestrator must address it or the human must explicitly override it in the issue before execution.

When autonomy mode is `review-approved-auto-execute`, all expected reviewers for the selected tier returning `Approve` or `Approve with nits` authorize local execution when no Autonomy Mode stop condition or required change before execution applies. Otherwise move to Approval when the next action needs human approval.

Use a third reviewer only when the human asks for a tie-break or extra risk review.

## Plan Drift Rule

When the local plan changes materially, the orchestrator must add an execution-log comment that names what changed.

A change is material if it alters acceptance criteria, scope, non-goals, gates, commands, verification, rollback conditions, or sensitive-data boundaries.

Typo fixes, formatting, and rewording without semantic change are not material.

For tracked code changes, include the commit SHA when available.

For uncommitted plan changes, include the plan path and a short summary of the changed gate, scope, or command.

For multi-slice plans, update affected child slice issues in the same change.

If a saved plan, deploy artifact, or generated evidence file is replaced, record the new path and checksum when useful.

## Safety Boundaries

- Do not paste secrets, raw credentials, token values, sensitive resource names, or raw plan output into issues.
- Use sanitized summaries for plans, logs, findings, and metadata.
- Destructive, costly, cloud-mutating, deploy, apply, protected-branch push, or external posting outside the assigned tracker issue set requires explicit human approval.
- Phase branch commits and pushes may be pre-authorized only by phase branch mode.
- Auto-execution is limited to reviewed local work inside the assigned slice.
- The approved workflow may authorize issue closeout after acceptance criteria pass; otherwise human approval is required.
- Saved plans must be applied by explicit filename, not by a stale default path.
- Local-only plan documents stay uncommitted when the task says so.

## GitHub Boundary

Use an issue tracker as the agent orchestration board.

Use GitHub Issues or PRs when the work is repo-native, public, or should be tied directly to branches, commits, code review, and PR closure.

When a branch or PR exists, link it from the issue. Do not duplicate sensitive operational evidence into GitHub.

When available, use branch protection on the merge target with required approvals and required status checks.

Prefer squash merge for phase branches unless the repo has a different established convention.

If a PR is opened, its description should briefly include:

- what changed
- why
- issue link when the repo is private or the tracker is accessible to the PR audience; otherwise issue ID only
- acceptance criteria checked
- risk
- how to test
- what was intentionally not done
- follow-up issues

## Close Discipline

Do not close an issue just because code was written or an action completed.

Close only when verification has passed and closeout is authorized, or when the issue explicitly records why verification is deferred or impossible.

If an external system must update later, move the issue to a waiting state.
