# Four Eyes

Human-approved review workflow for agent-made changes.

One orchestrator does the work, isolated reviewers who did not author it judge it, and a human authorizes consequential actions. The policy is tool-agnostic and rule-only; it needs no workflow runtime, tracker, plugin, or skill.

## Roles

- **Orchestrator**: plans when needed, implements, verifies, prepares the review, synthesizes verdicts, and keeps the record current.
- **Reviewer**: isolated and not an author of the change. Reviews read-only, returns a verdict and proposed fixes to the orchestrator, and never edits the record.
- **Human**: confirms the review level when it is unclear and authorizes gated actions.

## Review Levels

Record the level each change actually received. Do not describe a review as stronger than it was.

| Level | Reviewers | Use for |
| --- | --- | --- |
| Skip | none | tiny docs, typos, formatting, simple administration |
| Independent review | one isolated non-author reviewer | the default for routine, reversible work |
| Four-Eyes | two isolated non-author reviewers of the same change | consequential work |

- Choose the level by consequence: impact if wrong, reversibility, and uncertainty. Do not choose it by keywords alone. A production data migration or an access-control change warrants Four-Eyes; a local fixture-data change usually does not.
- Independent review may use any available harness. Human relay is optional.
- Four-Eyes reviewers should preferably come from different model families. Each reviewer gives a verdict before seeing the other's.
- Skip removes the review requirement only. Authorization for merges, publication, deployment, and destructive actions still applies.
- The human or plan sets the level. The orchestrator may raise it, but lowers it only with the human's agreement.

## Workflow

1. Write a short plan when the task is not clear enough to execute. Review the plan first when design is the main risk or the human asks.
2. Implement on a branch. Use a worktree when work runs concurrently or unrelated changes need protection; otherwise it is optional.
3. Run the repository's own verification.
4. Identify the change: for a pull request, its base and head commits; for local work, the base commit and a captured diff, including untracked files. Committing only to obtain review is not required.
5. Send each reviewer the identified change, the task or plan, and the verification evidence. Do not send other reviewers' current verdicts or orchestrator synthesis.
6. Wait for every expected verdict, then synthesize.
7. Fix blocking findings and send the delta to the same reviewers.
8. Before a gated action, confirm the change still matches what was reviewed.
9. Obtain authorization when it is missing, act, verify the result, update the record, and clean up.

## Review Identity

- A verdict applies only to the change it identifies.
- If the head commit or captured diff changes, earlier approvals do not carry over. Review the delta.
- Before merge or apply, recheck that the target change is still the reviewed one.

## Verdicts

Reviewers return `Approve`, `Approve with nits`, `Block`, or `could-not-review` with a reason. Non-Skip work requires approval from every expected reviewer. Missing reviews and `could-not-review` hold the gate.

- **Block** holds the gate. Fix and recheck, or obtain the human's explicit, scoped exception; the unresolved finding stays recorded.
- **Nits** are deferred by default and recorded with their disposition.
- **Transient failures** such as timeouts or tool errors may be retried a bounded number of times on the unchanged change. Retries are not review rounds and do not add reviewers.
- **Cleanup problems**, such as a leftover reviewer worktree, are tracked separately. They do not invalidate an intact review.

## Review Cap

Independent review gets one initial review and one recheck. Four-Eyes gets one initial review and two rechecks. At the cap, stop and return the remaining findings to the human. Do not automatically add reviewers, raise reasoning effort, or start another loop.

## Authorization

Reviewer approval satisfies the review requirement. It does not grant human authorization for a gated action. Reuse existing human authorization within its recorded scope; ask only when it is missing or the action changes.

Gated actions:

- merge to a protected branch
- publication or release
- deployment, apply, or other live or external-system changes
- destructive or costly actions
- scope changes

Tool or harness permissions do not substitute for human authorization.

## Branches And Worktrees

- Follow the repository's normal merge strategy, including squash. After merging, verify that the reviewed change landed on the target.
- Never force-push, force-remove, or rewrite shared history.
- Delete only branches and worktrees this workflow created, after confirming their state matches what was merged or abandoned.

## Record

Keep one concise record where the work lives: the pull request, one parent issue for multi-phase work, or a local note when there is no forge. Include scope, review level, reviewed revision, checks run, findings and their resolution, authorization, and next action.

## Reasoning Effort

Use the configured reasoning effort. Raise it only when the task warrants it.

## Reviewer Prompt

Use [reviewer-template.md](reviewer-template.md).

## Use In Another Repository

Add this to the target repository's `AGENTS.md`:

```markdown
## Four Eyes

Review agent-made changes with Four Eyes levels: Skip, Independent review, or Four-Eyes.

Policy: https://github.com/nickzren/four-eyes at <full 40-character commit SHA>
```

For Claude Code, add a target-repository `CLAUDE.md` containing `@AGENTS.md`.

Pin the policy by full commit SHA. A workflow keeps the revision it started with. Earlier, more detailed revisions of this policy remain available at their commit SHAs.

## License

MIT
