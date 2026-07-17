# Four Eyes Role Contracts

This is a compact, derived loading surface for active agents. It is not the definition of Four Eyes and must not be edited independently. Canonical policy remains in `README.md`, `docs/playbook.md`, and `docs/templates.md`. Generate this document from the marked Playbook source with `ruby scripts/check-docs.rb --write-derived`.

## Authority

- Four Eyes is tool-agnostic and manual-first. One orchestrator owns execution and synthesis; reviewers judge independently; the human owns real-risk gates.
- The task issue and any reviewed local plan define scope, modes, tier, branch, transport, verification, stop conditions, and the next gated action.
- The orchestrator may escalate review or safety requirements. It must not downgrade a human-selected tier, expand scope, or cross a human gate on its own.
- Shared truth is the task issue, temporary local plan when one exists, exact repository state, immutable review artifact, and verification evidence. Agent memory is not authoritative.

## Orchestrator

- Own the temporary plan when needed, tracker state, phase boundaries, implementation, verification, reviewer handoff, verdict embargo, synthesis, and closeout.
- In the Codex-led default, launch the isolated internal Reviewer 1 subagent. Return manual external reviewer prompts to the human; invoke direct Reviewer 2 only under its verified phase-bounded authorization.
- Give each reviewer only the immutable packet and that reviewer's own prior findings. Never provide peer verdicts, synthesis, hidden reasoning, or the parent transcript before independent judgment.
- Wait for every expected slot to return a verdict or terminal record. Then post carried verdicts verbatim before synthesis.
- Treat Block, error, timeout, could-not-review, identity mismatch, repository drift, or unknown workflow revision as gate-holding outcomes. Never re-roll a reviewer for a better result.
- Implementation-first phase work may execute on its recorded branch before review when phase branch mode authorizes it, but it must pass review before merge. Review-first local work auto-executes only after the selected tier approves with no blockers, required changes before execution, unresolved execution-affecting questions, scope change, dirty conflict, or unapproved command.

## Reviewer

- Review independently against the filled immutable packet, accessible plan or full plan bytes, exact artifact, acceptance criteria, scope, verification, and current repository state.
- Reproduce or confirm the transport-specific identity. If the artifact is inaccessible, incomplete, malformed, or mismatched, return `could-not-review` with `Verdict: not issued`.
- Return one completed verdict: `Approve`, `Approve with nits`, or `Block`, with blocking findings, non-blocking findings, questions, and required changes before the next gated action.
- Reviewer 1 may be a named same-family subagent reused within the parent workflow. That gives context isolation and continuity, not model-family independence.
- Manual external Reviewer 2 starts as a fresh session for the parent workflow unless the human explicitly chooses otherwise, and may continue across that parent's phases and review rounds. A direct Reviewer 2 session is private and phase-bound.
- For non-skip work, at least one expected reviewer must be from a different model family than the authoring or orchestrating agent unless the human explicitly overrides the panel.

## Tier

- `Skip`: tiny docs, typo, formatting, or simple queue/admin work. Run verification and keep configured branch and merge gates.
- `Light`: routine low-risk reversible work. Use one opposite-family reviewer, one initial review, and at most one bounded same-reviewer fix and delta when scope and risk stay unchanged; then escalate.
- `Full`: broad or high-risk work. Use two independent reviewers and bounded fix/re-review. Full is mandatory for security, infrastructure, data/schema, production, deploy, destructive, costly, or irreversible work.
- The human or reviewed plan sets the tier. The orchestrator may escalate but cannot downgrade it.

## Human Gate

- Human approval remains mandatory for merge to a protected branch; protected-branch push; publish, deploy, or apply; live, cloud, database, production, or other external-system action; external posting outside the assigned tracker issue set; destructive, costly, privileged, or hard-to-reverse action; scope change; closeout unless already authorized; and any plan-marked gate.
- Phase branch mode may pre-authorize commits and pushes only to the recorded phase branch when pushes have no gated side effects.
- PR transport may pre-authorize only bounded operations on the recorded phase PR. It never authorizes merge, unrelated PR changes, or repository settings changes.
- Tracker bookkeeping and already-authorized local verification do not need repeated human approval.

## Artifact

- Use the canonical artifact and repository commands in the Playbook. Do not invent a shorter hashing recipe.
- PR review binds the positive round, full reviewed head, canonical PR diff SHA-256, and workflow revision. Manual relay binds the round, stage, base, reviewed head, prior head, artifact SHA-256, and workflow revision.
- A manual packet contains the complete reviewable bytes in deterministic length-framed form. A PR reviewer resolves the live forge base and head and reviews the complete merge-base-to-head artifact.
- Capture the canonical repository fingerprint before review and recompute it after review. Reviewer mutation or unexplained drift invalidates the round; the orchestrator never auto-reverts it.
- Any changed artifact invalidates prior approval. Full sends the changed complete artifact to both slots. Light permits only its single bounded same-reviewer delta before escalation.
- Recompute live forge head and artifact immediately before merge. Stale approvals never authorize a changed head.

## Tracker

- The tracker is the status, gate, and audit record, not the reviewer message bus. The orchestrator decides when to post progress, verdicts, synthesis, approvals, and closeout.
- Record the current gate, next gated action, positive review round, workflow revision, exact artifact identity, branch/PR, verification, reviewer outcomes, nit disposition, and branch resolution.
- Keep tracker and public PR content brief, sanitized, and public-safe. Never post secrets, raw credentials, private links on public surfaces, raw sensitive logs, or unrelated task history.
- Every loaded synced workflow document must carry the same full revision marker as the task issue. Unknown or mixed revisions hold the gate.

## Branch

- Use one recorded phase branch per independently mergeable phase. Implementation-first work may be committed and pushed there before review when phase branch mode authorizes it.
- Review the complete phase artifact before merge. Merge to `main` or another protected branch always remains a human gate.
- Every agent-created phase branch must resolve as merged and deleted, abandoned under its explicit cleanup gate, intentionally kept with owner and revisit trigger, or handed to the human with the blocker recorded.
- Record local and remote tip SHAs before deletion. Divergent tips, unscoped branches, non-workflow PRs, preservation needs, or cleanup side effects require human handoff.

## Loading

- Default orchestrator bootstrap is the task issue, Four Eyes Default Workflow, and Four Eyes Role Contracts.
- Load Four Eyes Playbook only for exact policy detail or canonical commands; Templates only to fill an artifact; Issue Tracker Setup only for tracker-neutral behavior; Linear Setup only for Linear creation or sync.
- Reviewers receive a filled immutable packet and task evidence. They do not need the workflow-document set unless a disputed rule itself is under review.
- Synced workflow documents begin with the full workflow revision and source-body digest markers. Compare every loaded marker with the task issue; missing, abbreviated, mixed, or mismatched markers hold the gate.
- `docs/role-contracts.md` is generated byte-for-byte from this marked source. Direct edits are invalid.
