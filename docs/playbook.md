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
- the orchestrator launches internal Reviewer 1; the human relays manual external Reviewer 2 by default
- optional direct Claude review is allowed only through a native isolated invocation tool under exact human-approved phase, model, call, and cost bounds
- reviewers return verdicts to the orchestrator or human
- the human pastes the expected reviews back to the orchestrator after they are complete

Manual mode preserves independent judgment and keeps the process simple. It relies on the orchestrator to isolate any internal reviewer subagent and on human discipline for external message passing.

## Tracker Ownership

The issue tracker is the audit and status record, not the reviewer message bus.

Reviewers return verdicts to the orchestrator or human relay. They never write the tracker. The orchestrator decides what to record there.

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

Record these fields in order:

```text
Reviewer 2 handoff: manual external reviewer | direct Claude reviewer
Direct Reviewer 2 authorization: none | human-approved phase + full model + maximum calls + maximum cost
```

Manual external Reviewer 2 is first/default, and the human relays its prompt and verdict. Direct Claude review is optional only when the orchestrator platform already provides a native invocation tool that creates an isolated fresh-context reviewer session. The human must authorize the exact task or phase, full model identity, maximum calls, and maximum cost amount and currency. There is no standing or orchestrator-selected opt-in. If the platform cannot honor every authorized bound or isolation cannot be established, direct mode is unavailable and the workflow uses manual relay.

Every internal or directly invoked reviewer receives only the sealed review packet and its own prior findings:

- issue or plan summary
- PR or branch target
- verification evidence
- neutral prior phase summary when needed
- the reviewer prompt and slot number

Do not pass the parent orchestrator transcript, hidden reasoning, other reviewer output, synthesis, or combined conclusions into a reviewer before that reviewer has posted its own verdict.

Create `reviewer1` once for the current phase or parent workflow and reuse the same subagent across fix/re-review rounds. Reuse across phases is allowed when those phases belong to the same parent plan and continuity helps the reviewer understand what already happened. Start a new `reviewer1` only for an unrelated workflow, when the human asks for a reset, or if the subagent context was contaminated with peer review, synthesis, hidden reasoning, or unrelated task context. Send one verdict request per reviewer per review round; delta rounds send only the delta packet when that reviewer already holds its own prior findings. A returned verdict or terminal outcome stands: do not argue, re-prompt, retry, resample, or switch transport inside the same round. A later attempt requires a new numbered round and any approval required by its gate.

A completed review returns exactly `Approve`, `Approve with nits`, or `Block`. An `error`, `timeout`, or `could-not-review` outcome uses `Verdict: not issued` and holds the gate. Reserve `Block` for completed reviewer judgment, not invocation or transport failure.

Hold every internal or relayed verdict until all expected slots for the round have returned or are recorded as Block, error, timeout, or could-not-review. Direct PR reviews posted by an external reviewer are outside orchestrator control. The embargo is vacuous in `light` tier because it has one expected slot. After the embargo lifts, post every verdict carried on a reviewer's behalf verbatim, then post synthesis. Do not replace the original verdict with an orchestrator summary.

Before trusting a subagent handoff in a new tool or runtime, run a one-time isolation check: spawn a test reviewer subagent and confirm it cannot describe the parent orchestrator's current task unless that task is passed in the review packet. If the check fails or cannot be verified, use manual external reviewer handoff for that slot.

Manual external Reviewer 2 should start as a fresh session for the parent workflow and may keep that session across phases and review rounds. A native direct invocation must create an isolated fresh-context session for each verdict request; continuity enters only through that reviewer's own prior findings in the packet. The repository cannot verify this platform property, so the platform and human own that trust boundary. Do not reuse reviewer context for unrelated workflows.

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
- execute review-first work only after its review gate is clear; implementation-first phase branch work may execute before review but must reach Review before merge
- post verification, commit summary, and remaining risks
- after every issue or gate update, tell the human the current gate and exact next action

### Reviewer 1

Usually a separate agent session or a named reviewer subagent.

Responsibilities:

- review independently before reading other reviewer output or orchestrator synthesis
- when prompted with a current-work issue reference, treat it as a review request: read the provided issue or packet context, review the current diff and verification evidence, and return the review to the orchestrator or human relay
- review against the linked local plan file, current repo state, current implementation diff and verification evidence if present, issue body, and orchestrator-provided plan/update content
- if the local plan file is not accessible, require its full public-safe contents through the manual-relay artifact; a summary or hash alone is could-not-review
- check acceptance criteria, correctness, scope, safety, missing tests, and operational risks
- inspect the exact identified review artifact and independently recompute or confirm its hash
- fail closed as could-not-review when the workflow revision or artifact identity is missing, malformed, mismatched, or inaccessible
- avoid unrelated suggestions unless severe
- return findings with the required header

### Reviewer 2

Usually a different model or agent family from the orchestrator, especially when Reviewer 1 is an orchestrator-created same-family subagent.

Responsibilities are the same as Reviewer 1.

### Human Approver

The human owns final approval for real risk gates:

- execution when autonomy mode is `manual`
- commands outside the pre-authorized local command classes or reviewed plan
- commit or push when phase branch mode is not enabled
- push to protected branches, tags, releases, or unscoped branches
- merge into `main` or another protected branch
- publish
- closeout unless already authorized by workflow
- scope changes
- live or external systems, databases, cloud, deploys, destructive actions, costly actions, or production data/resource changes
- any action the plan or workflow marks as approval-gated

Human approval is not required for tracker-only workflow preparation such as creating planned child issues, moving a ready slice to its recorded next gate, posting reviewer prompts, synthesizing reviews, or updating gate metadata.

## Autonomy Mode

Every non-trivial plan or slice must set:

```text
Autonomy mode: review-approved-auto-execute | manual
```

Default to `review-approved-auto-execute` for local repo code, docs, tests, or plan edits inside the reviewed slice. If autonomy mode is omitted, treat it as `review-approved-auto-execute` unless a manual condition applies. Use `manual` for live or external systems, databases, cloud, deploys, apply actions, destructive or costly actions, production data/resource changes, ambiguous ownership, or any slice the human marks approval-gated.

Local execution means working-tree file changes and verification commands inside the reviewed slice. It excludes network mutation, external state changes, and starting persistent processes or services unless another recorded workflow setting explicitly authorizes the exact operation, such as phase-branch push or bounded PR transport.

Within the assigned local repo slice, these command classes are pre-authorized:

- read-only inspection of the repo, plan, diff, history, and local tool output
- existing repo-documented test, lint, type-check, build, and verification commands
- bounded formatting or code-generation commands whose outputs stay inside the assigned slice and remain reviewable
- temporary local evidence writes to the plan's approved evidence path

A command or flag does not require approval only because it was absent from the plan. Human approval is required when a command leaves those classes, expands beyond the assigned slice, installs or upgrades software, changes external or live state, starts a persistent service, requires elevated privilege, or is destructive, costly, or hard to reverse. A pipeline is pre-authorized only when every stage stays inside the same pre-authorized class and all outputs remain local and in scope. A reviewed plan may pre-authorize additional exact commands only when they remain local, reversible, in scope, and below every human gate.

A reviewer question is execution-affecting if its answer would change what or how the orchestrator executes. Cosmetic, follow-up, or post-execution questions do not block auto-execute.

Dirty worktree conflicts include uncommitted changes outside the slice scope, unmerged rebase or merge state, or untracked files conflicting with expected slice outputs.

Required changes before execution must be addressed and recorded in synthesis before auto-execute.

When autonomy mode is `review-approved-auto-execute`, all expected reviewers for the selected tier returning `Approve` or `Approve with nits` authorize the orchestrator to execute the reviewed local slice when there are no blockers, required changes before execution, unresolved execution-affecting questions, dirty worktree conflicts, scope changes, or commands outside the pre-authorized classes or reviewed plan. The orchestrator must not ask for `Approved: execute ...` for that slice.

Auto-execute alone does not authorize commit, push, publish, merge, deploy, apply, live/external mutation, destructive/costly action, closeout unless already authorized, scope change, commands outside the pre-authorized classes or reviewed plan, or work outside the assigned tracker issue set. Commit and push require phase branch mode or explicit human approval. Bounded PR writes require `Review transport: pr`. Merge and protected-branch push remain separate human gates.

## Phase Branch Mode

For repo implementation phases, phase branch mode is the default high-throughput path when branch pushes are safe. The plan may disable it or require pre-review.

```text
Phase branch mode: on | off
Base branch: <main or other base>
Phase branch: <phase branch name>
Worktree mode: on | off
Worktree reference: none | <ownership-category>/<opaque worktree reference>
Remote push: allowed | disallowed
Merge target: <main or other protected branch>
Post-merge branch cleanup: yes | no
Abandoned branch cleanup: yes | ask | no
```

Default to `Post-merge branch cleanup: yes` and `Abandoned branch cleanup: ask`.

When phase branch mode is `on`, the orchestrator may create the phase branch, commit to it, and push updates to that exact branch without asking the human for every commit or push, if all of these are true:

- the branch name, base branch, and merge target are recorded in the plan or issue
- the work stays inside the approved phase scope
- pushes go only to the named phase branch
- branch pushes do not deploy, mutate live systems, publish releases, or trigger hard-to-reverse external actions
- verification commands are run before review
- reviewers review the branch diff and verification evidence before merge approval

Phase branch mode is implementation-first by default: the orchestrator completes the phase on the branch, then reviewers review the branch diff once. Require pre-implementation review only when the plan, risk class, or human explicitly asks for it.

This intentionally allows local commits to the named phase branch before review. The review gate is before protected-branch push, merge, apply, deploy, or closeout.

Phase branch mode alone does not authorize:

- direct commits or pushes to `main` or protected branches
- force-push, rebase of shared history, tag creation, release creation, or branch deletion before merge except through the explicit abandoned-branch cleanup path
- deploy, apply, cloud/database mutation, destructive action, or costly action
- merge into the target branch

The human merge approval may authorize merge, post-merge verification, tracker closeout, and phase branch cleanup. Use an exact phrase such as:

```text
Approved: merge <phase branch> into <target branch>, verify, close the issue, and delete the phase branch.
```

If the repository has branch-push side effects, such as preview deploys, production deploys, release publishing, or data mutation, remote push is a human gate unless the human explicitly pre-authorizes that side effect.

### Branch Lifecycle

Every agent-created phase branch must be resolved at closeout.

Resolution must be exactly one of:

- merged, verified, and deleted locally and remotely when post-merge cleanup is authorized
- abandoned, its workflow-created PR closed if present, and deleted locally and remotely when abandoned cleanup is authorized
- intentionally kept, with reason, next owner, and a revisit trigger such as a follow-up issue or date recorded
- handed off to the human, with the exact blocker recorded

Before deleting any phase branch, record in the tracker closeout:

- branch name
- local tip SHA
- remote tip SHA, if present
- PR link or identifier, if present
- reason for deletion

If local and remote tips differ at cleanup time, treat the branch as needing preservation and hand it off to the human.

Merged branch cleanup uses normal merged-branch deletion after merge and post-merge verification, when `Post-merge branch cleanup: yes`.

Abandoned branch cleanup is the explicit path for deleting an unmerged branch. It is allowed only when all of these are true:

- the branch was created by this workflow
- the branch name matches the approved phase branch
- any open PR for the branch was created by this workflow and is closed as part of the same abandoned cleanup; otherwise hand off to the human
- the branch has no work that needs preservation
- the branch name, local tip SHA, remote tip SHA if present, and abandonment reason are recorded first
- remote deletion and closing any workflow-created PR are pre-authorized with `Abandoned branch cleanup: yes` or explicitly approved by the human

When `Abandoned branch cleanup: ask`, the orchestrator records the branch state and asks before deleting. When `Abandoned branch cleanup: no`, the orchestrator records the branch state and leaves the branch for the named owner or follow-up.

Never auto-delete main, protected, release, or unscoped branches; tags; branches this workflow did not create; branches whose names do not match the approved phase branch; branches whose local and remote tips differ; branches with open PRs not created by this workflow; branches with PRs or work needing preservation; or branches whose deletion triggers deploy, preview, or other external side effects unless explicitly approved.

## Workflow Revision And Artifact Identity

The workflow revision is the full pushed repo commit SHA in the marker at the top of every synced workflow document. Record that full SHA on every active task issue and every verdict. Every loaded workflow document and the task issue must use the same full revision. Missing, abbreviated, conflicting, or mixed workflow revisions fail closed. The standing workflow-doc issue records successful sync history, but it does not override document markers.

The task issue also records the current positive review round and review transport. A new or changed artifact starts a new round. Preserve the reviewer provenance fields, then use the transport-specific identity fields below with identical wording and order.

PR verdict identity:

```text
Review round: <positive integer>
Reviewed head: <full commit SHA>
PR diff SHA-256: <bare lowercase 64-character digest of exact merge-base-to-head diff>
Workflow revision: <full commit SHA>
```

Manual-relay verdict identity:

```text
Review round: <positive integer>
Review stage: plan | implementation | delta
Base: <full commit SHA or none>
Reviewed head: <full commit SHA or uncommitted at HEAD <full SHA>>
Prior reviewed head: <full commit SHA or none>
Review artifact SHA-256: <bare lowercase 64-character digest>
Workflow revision: <full commit SHA>
```

A missing, malformed, or mismatched identity is could-not-review and holds the gate. Hash fields contain only the bare lowercase digest. A reviewer inspects the exact identified artifact and echoes its identity. Hash-only content that the reviewer cannot access is not reviewable; return could-not-review.

### Canonical Artifact And Repository Commands

Run this block from the repository root in Bash. Here, repository root means the root of the checkout holding the reviewed work. For a worktree-mode-on phase, compute the before/after review fingerprint in the validated phase worktree and separately require the primary-checkout fingerprint to equal its stored pre-creation value. Other documents and templates refer here instead of copying it. Commit, PR, and merge-capable reviews always use `scope=(.)` so no changed path can sit outside the reviewed artifact. Right-size or split an oversized phase instead of narrowing the hash. Every producer propagates failure explicitly; do not rely on Bash `errexit` or local diff defaults.

```bash
set -o pipefail || exit 1
export LC_ALL=C

scope=(.)

sha256_bare() {
  local output
  output=$(shasum -a 256) || return 1
  [[ "$output" =~ ^([0-9a-f]{64})[[:space:]]+-$ ]] || return 1
  printf '%s\n' "${BASH_REMATCH[1]}" || return 1
}

canonical_diff() {
  GIT_ATTR_NOSYSTEM=1 git \
    -c core.attributesFile=/dev/null \
    -c core.quotePath=true \
    -c diff.mnemonicPrefix=false \
    -c diff.suppressBlankEmpty=false \
    diff \
    --diff-algorithm=myers \
    --no-indent-heuristic \
    --inter-hunk-context=0 \
    --src-prefix=a/ \
    --dst-prefix=b/ \
    --unified=3 \
    --no-ext-diff \
    --no-textconv \
    --no-color \
    --no-renames \
    --no-relative \
    --ignore-submodules=none \
    --submodule=short \
    --full-index \
    --binary \
    -O/dev/null \
    "$@" || return 1
}

write_untracked_manifest() {
  local output=$1 names="${1}.names" sorted="${1}.sorted" file_path digest
  git ls-files --others --exclude-standard -z -- "${scope[@]}" >"$names" || return 1
  perl -0 -e 'print sort <STDIN>' <"$names" >"$sorted" || return 1
  : >"$output" || return 1
  while IFS= read -r -d '' file_path; do
    if [[ -L "$file_path" ]]; then
      digest=$(perl -e '$p = shift; defined($t = readlink($p)) or die "readlink: $p\n"; print $t' "$file_path" |
        sha256_bare) || return 1
    elif [[ -f "$file_path" ]]; then
      digest=$(sha256_bare <"$file_path") || return 1
    else
      printf 'unsupported or missing untracked path: %s\n' "$file_path" >&2
      return 1
    fi
    printf '%s\0%s\0' "$digest" "$file_path" >>"$output" || return 1
  done <"$sorted" || return 1
}

repository_fingerprint() {
  local evidence_dir=$1 head_sha staged_sha unstaged_sha untracked_sha
  [[ -d "$evidence_dir" ]] || return 1
  head_sha=$(git rev-parse --verify 'HEAD^{commit}') || return 1
  staged_sha=$(canonical_diff --cached "$head_sha" -- "${scope[@]}" | sha256_bare) || return 1
  unstaged_sha=$(canonical_diff -- "${scope[@]}" | sha256_bare) || return 1
  write_untracked_manifest "$evidence_dir/untracked.manifest" || return 1
  untracked_sha=$(sha256_bare <"$evidence_dir/untracked.manifest") || return 1
  printf 'HEAD=%s\nstaged=%s\nunstaged=%s\nuntracked=%s\n' \
    "$head_sha" "$staged_sha" "$unstaged_sha" "$untracked_sha" || return 1
}

append_packet_record() {
  local label=$1 file=$2 size
  size=$(wc -c <"$file") || return 1
  size=${size//[[:space:]]/}
  [[ "$size" =~ ^[0-9]+$ ]] || return 1
  printf '%s\0%s\0' "$label" "$size" || return 1
  cat "$file" || return 1
}

append_untracked_content_records() {
  local evidence_dir=$1 body=$2 file_path one="$1/untracked.one"
  while IFS= read -r -d '' file_path; do
    if [[ -L "$file_path" ]]; then
      perl -e '$p = shift; defined($t = readlink($p)) or die "readlink: $p\n"; print $t' \
        "$file_path" >"$one" || return 1
    elif [[ -f "$file_path" ]]; then
      cat "$file_path" >"$one" || return 1
    else
      return 1
    fi
    append_packet_record untracked-content "$one" >>"$body" || return 1
  done <"$evidence_dir/untracked.manifest.sorted" || return 1
}
```

Do not pin `core.autocrlf` in this recipe. It affects working-tree conversion rather than object-to-object PR diffs. If canonical unstaged bytes differ across machines with otherwise unchanged content, fail closed and compare checkout line-ending normalization and `core.autocrlf` before starting a new round.

Before dispatching review, create a retained evidence directory, capture the repository tuple, and hash each reviewed plan directly by path even when it is ignored:

```bash
evidence_dir=$(mktemp -d /tmp/four-eyes.XXXXXX) || exit 1
before_tuple=$(repository_fingerprint "$evidence_dir") || exit 1
plan_sha256=$(sha256_bare <"$plan_path") || exit 1
printf 'Evidence retained for OS cleanup: %s\n' "$evidence_dir" || exit 1
```

After all expected slots return, and again immediately before the next gated action, recompute and compare. Omit the plan comparison only when no plan was reviewed:

```bash
after_evidence_dir=$(mktemp -d /tmp/four-eyes.XXXXXX) || exit 1
after_tuple=$(repository_fingerprint "$after_evidence_dir") || exit 1
after_plan_sha256=$(sha256_bare <"$plan_path") || exit 1
[[ "$before_tuple" == "$after_tuple" && "$plan_sha256" == "$after_plan_sha256" ]] || {
  printf 'repository or reviewed plan changed during review\n' >&2
  exit 1
}
printf 'Evidence retained for OS cleanup: %s\n' "$after_evidence_dir" || exit 1
```

Create only the artifact needed for the selected transport:

```bash
# Plan:
plan_sha256=$(sha256_bare <"$plan_path") || exit 1

# Committed manual-relay diff:
base_sha=$(git rev-parse --verify "$base_ref^{commit}") || exit 1
reviewed_head=$(git rev-parse --verify "$head_ref^{commit}") || exit 1
artifact_base=$(git merge-base "$base_sha" "$reviewed_head") || exit 1
canonical_diff "$artifact_base" "$reviewed_head" -- "${scope[@]}" >"$evidence_dir/committed.diff" || exit 1
review_artifact_sha256=$(sha256_bare <"$evidence_dir/committed.diff") || exit 1

# PR diff; forge_base_sha and forge_head_sha must come from current forge state:
git cat-file -e "$forge_base_sha^{commit}" || exit 1
git cat-file -e "$forge_head_sha^{commit}" || exit 1
pr_merge_base=$(git merge-base "$forge_base_sha" "$forge_head_sha") || exit 1
canonical_diff "$pr_merge_base" "$forge_head_sha" -- "${scope[@]}" >"$evidence_dir/pr.diff" || exit 1
pr_diff_sha256=$(sha256_bare <"$evidence_dir/pr.diff") || exit 1

# Uncommitted manual-relay components:
head_sha=$(git rev-parse --verify 'HEAD^{commit}') || exit 1
canonical_diff --cached "$head_sha" -- "${scope[@]}" >"$evidence_dir/staged.diff" || exit 1
canonical_diff -- "${scope[@]}" >"$evidence_dir/unstaged.diff" || exit 1
write_untracked_manifest "$evidence_dir/untracked.manifest" || exit 1
: >"$evidence_dir/uncommitted.body" || exit 1
append_packet_record staged-diff "$evidence_dir/staged.diff" >>"$evidence_dir/uncommitted.body" || exit 1
append_packet_record unstaged-diff "$evidence_dir/unstaged.diff" >>"$evidence_dir/uncommitted.body" || exit 1
append_packet_record untracked-manifest "$evidence_dir/untracked.manifest" >>"$evidence_dir/uncommitted.body" || exit 1
case "${reviewer_has_repo_access:-}" in
  yes) ;;
  # Inspect every untracked name and byte before selecting no.
  no) append_untracked_content_records "$evidence_dir" "$evidence_dir/uncommitted.body" || exit 1 ;;
  *) printf 'reviewer_has_repo_access must be yes or no\n' >&2; exit 1 ;;
esac
review_artifact_sha256=$(sha256_bare <"$evidence_dir/uncommitted.body") || exit 1
```

The packet grammar is exact: each record is UTF-8 label, NUL, ASCII decimal byte length, NUL, then exactly that many raw bytes. The fixed labels are `staged-diff`, `unstaged-diff`, `untracked-manifest`, followed by one `untracked-content` record per manifest path in sorted order. Omit content records when the reviewer has approved repository access. When content records are required, inspect every untracked name and byte before running the append command; if anything cannot be shared safely, record could-not-review. Put the body digest in the identity header carried by the relay prompt or envelope. Send `uncommitted.body` unchanged as the immutable attachment; do not prepend the header or alter the body after hashing.

Capture the fingerprint before review and recompute it after all expected slots return and immediately before every next gated action. Recompute the applicable artifact hash too, including reviewed ignored plans. Every tuple and identity must match. Unexplained drift invalidates the round; never auto-revert it.

For PR transport, resolve the base and head full SHAs from current forge state, ensure those exact commits exist locally, and generate the exact merge-base-to-head bytes with the canonical command. Do not trust stale remote-tracking refs. Immediately before merge, resolve and recompute both the head SHA and PR diff SHA-256; either mismatch invalidates every approval.

This fingerprint is orchestrator-attested. It detects changes visible to these commands but does not protect against a lying orchestrator, ignored-file mutation other than separately hashed reviewed plans, external-state mutation, or a compromised forge.

## Review Transport

Every phase should state:

```text
Review transport: pr | manual-relay
```

Default to `pr` when the repo has a remote and CI or branch protection. Use `manual-relay` for local, no-remote, or simple work where a PR adds overhead.

Selecting `Review transport: pr` pre-authorizes only these writes for the recorded phase branch and merge target: create or update its PR, maintain the bounded PR description, request the expected reviewers, and post or submit the expected reviewer verdicts. It does not authorize merge, closing unrelated PRs, changing repository settings, or any other GitHub write.

When review transport is `pr`:

- the orchestrator opens or updates a PR from the phase branch to the merge target after verification
- the issue records the current review round, workflow revision, full reviewed head SHA, and PR diff SHA-256
- the PR body includes the tracker issue link only when the repo is private or the tracker is accessible to the PR audience; otherwise it includes the tracker issue ID only
- the PR body includes the sanitized plan summary, acceptance criteria, verification evidence, and risk notes
- reviewers review the PR diff directly and write their verdict before reading other reviews
- verdict mapping is `Approve` -> approve, `Approve with nits` -> approve with comments, and `Block` -> request changes
- reviewer bodies include the required reviewer header
- the PR is the review artifact; the tracker remains the gate and status record
- branch protection should dismiss stale approvals when the head changes
- immediately before merge, the orchestrator compares the current forge head and canonical PR diff SHA-256 with every approval; all must match

Merge is the default routine per-phase human gate. Existing risk gates remain unchanged: deploy, apply, external mutation, destructive or costly action, scope change, tier downgrade, protected-branch push, and branch pushes with side effects still require human approval.

Automation ladder:

1. Current baseline: PR transport with human-invoked external reviewers.
2. Current Codex-led default: reused named internal Reviewer 1, human-relayed external Reviewer 2.
3. Optional where the orchestrator platform provides native isolated invocation and the human records the exact phase, full model identity, maximum calls, and maximum cost amount and currency: orchestrator invokes only Reviewer 2 directly.
4. Future: CI-triggered reviewers.

Rung 3 is never globally or orchestrator-authorized; each task or phase requires the recorded human decision and enforceable bounds. Rung 4 is not implemented or pre-authorized.

## Review Tier

Every plan, phase, or slice should state the review tier:

```text
Review tier: skip | light | full
```

- `skip`: tiny docs, typos, formatting, simple issue/admin work, or other changes from the playbook skip list. Run verification when useful and keep the configured branch or merge gate.
- `light`: the default for routine low-risk, reversible repo work. Use one reviewer from a different model family than the agent that authored the change. Allow one bounded fix and one delta review by that same reviewer only when scope and risk stay unchanged; this is not an open-ended autonomous fix loop. A scope or risk change, failed verification, could-not-review result, sensitive path, oversized diff, second changed artifact, or unresolved delta verdict escalates to `full` or a human decision.
- `full`: the normal Four Eyes gate: two independent reviewers, synthesis, bounded fix/re-review, and human approval for real-risk gates.

In `light` tier, do not run a same-family internal Reviewer 1 subagent. The single reviewer must provide the cross-family check, so the human relays that external reviewer prompt.

The human or local plan sets the review tier. If the tier is missing, use `light` for routine low-risk repo work and `full` for high-risk or broad work, or ask the human. The orchestrator may escalate the tier but must not downgrade its own work without explicit human instruction.

Always use `full` for security, infrastructure, schema/data, production, deploy, destructive, costly, external-state, or hard-to-reverse work.

Use the highest available reasoning for agents that judge: orchestrator decisions, reviewers, synthesis, blocker resolution, and non-trivial fixes.

## Required Reviewer Header

Every completed verdict starts with the existing provenance fields:

```text
Reviewer slot: <1|2>
Agent/session: <agent name>
Read other reviews first: no
```

Immediately follow those fields with the exact PR or manual-relay verdict identity block defined above. Do not reorder, rename, or omit identity fields. Then use exactly one outcome form.

Completed review:

```text
Review status: completed
Verdict: Approve | Approve with nits | Block
```

Terminal result with no verdict:

```text
Review status: error | timeout | could-not-review
Reason: <brief exact reason>
Verdict: not issued
```

The reviewer returns `could-not-review` when it cannot inspect the identified artifact. The orchestrator records `error` or `timeout` when no reviewer response can be obtained. Every terminal result holds the gate and cannot be counted as an approval.

## Plan-First Rule

For non-trivial repo, infrastructure, cloud, security, deploy, cleanup, migration, debugging, or operational work, create a temporary local executable plan when the task input is not clear enough to execute safely. Task input can be a user prompt, tracker issue, local note, or existing plan.

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

If reviewers cannot access the local plan file, the orchestrator must provide the full public-safe plan contents as the manual-relay artifact. A checksum or sanitized summary alone does not permit review; return could-not-review when the full artifact cannot be shared safely through an approved path.

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
- after a child slice reaches Done or Waiting External Eval, the orchestrator checks the next committed child slice; if it is ready and uses implementation-first phase branch flow, move it to In Progress and implement it, otherwise move it to Review and post filled reviewer prompts without asking for human approval
- if the next committed child slice is not ready, leave its current gate and post a brief blocker note in the parent issue
- reviewers review every ready slice and return feedback to the orchestrator or human relay
- the orchestrator owns sequencing and may execute only the next ready slice according to its recorded phase branch flow and gates
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
- delta re-review may send the exact delta packet plus that reviewer's own prior findings, but it must bind the current complete head or artifact and prior reviewed head
- after any artifact change, every expected `full`-tier slot re-reviews it; `light` permits only its one bounded same-reviewer delta, then escalates to `full` or a human decision

### Phase Review

For high-throughput bug fixing, review phases instead of every bug:

- The plan may define Phase 1, Phase 2, and later phases, each with concrete tasks, files, verification, and acceptance criteria.
- In phase branch mode, the orchestrator may complete all fixes in the current phase, commit them, and push the phase branch before asking reviewers to review.
- Reviewers review the phase diff and verification evidence once, not every individual bug.
- The orchestrator fixes all blocking feedback in one batch.
- Re-review may focus on the blocker delta, but every expected slot must bind its new verdict to the changed complete head or artifact.
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
5. Orchestrator runs verification and updates the tracker with the current round, workflow revision, transport-specific artifact identity, phase branch, diff summary, and reviewer prompts.
6. If review transport is `pr`, the orchestrator opens or updates the PR and uses the exact identified PR artifact. If Reviewer 1 can run as a named isolated internal subagent, the orchestrator creates or reuses it. The human sends every manual external reviewer prompt. An exactly authorized direct Reviewer 2 instead receives only its sealed packet and own prior findings through the platform's native isolated invocation tool.
7. Reviewers inspect the exact artifact and verification evidence independently, then return verdicts through the selected transport. The orchestrator holds internal and relayed verdicts under the embargo until every expected slot has returned or has a terminal record.
8. After the embargo lifts, the orchestrator posts carried verdicts verbatim, recomputes repository and artifact identity, synthesizes feedback, fixes blockers on the same phase branch, commits and pushes updates when authorized, and requests the required delta review.
9. When all expected reviewers approve the unchanged current artifact, the orchestrator recomputes its identity and asks the human for the merge approval phrase.
10. After approval, orchestrator merges into the target branch, runs post-merge verification, updates or closes the tracker item if authorized, records branch cleanup SHAs, and deletes the phase branch if authorized.

This flow is meant to reduce review loops. It trades pre-implementation review for branch isolation and a hard merge gate.

## Standard Task Flow

Use this flow when phase branch mode is off, or when pre-implementation review is required.

1. Orchestrator creates a temporary local executable plan when the task input is not clear enough to execute safely.
2. Orchestrator creates one issue or decomposes the plan into parent and child slice issues.
3. Orchestrator adds the temporary plan path, sanitized summary, acceptance criteria, boundaries, expected files or resources, current gate, and review request. Current gate: Review for ready issue(s); Todo or Blocked for downstream or unready child slice issues.
4. The orchestrator creates or reuses any internal Reviewer 1 subagent with only the review packet and its own prior review history. The human sends the ready issue link(s), exact accessible review artifact, and task prompt only to external expected reviewer slots. Current gate: Review for ready issue(s).
5. Reviewers return verdicts independently to the orchestrator or human relay. The orchestrator holds internal and relayed verdicts under the embargo until every expected slot has returned or has a terminal record. Current gate: Review.
6. After the embargo lifts, the orchestrator posts carried verdicts verbatim, recomputes repository and artifact identity, and synthesizes the expected reviews. Current gate: In Progress when auto-execute is authorized and execution is starting, Approval if human approval is needed, Review if material changes need re-review, or Blocked if blockers remain.
7. Orchestrator updates code or plan if needed. Current gate: Review if material changes need re-review.
8. If changes are material, repeat review on the updated slice.
9. Human approves execution, apply, deploy, or merge when needed. Skip this for local execution authorized by autonomy mode. Current gate: Approval until approved.
10. Orchestrator executes the approved or auto-authorized slice and posts verification. If phase branch mode is enabled, the orchestrator may commit and push updates to the named phase branch as part of this work. If execution creates material code, doc, config, infra, data, or plan changes, Current gate: Review.
11. Reviewers review the exact identified implementation artifact and verification evidence before merge, apply, deploy, or closeout approval.
12. After the verdict embargo lifts, the orchestrator posts carried verdicts verbatim, recomputes repository and artifact identity, synthesizes implementation reviews, and updates the tracker with the status, gate, and required human action. Current gate: Approval if aligned, Review if material changes need re-review, or Blocked if blockers remain.
13. Orchestrator commits only the intended tracked changes when phase branch mode authorizes branch commits, when the human approves the commit, or when the approved workflow explicitly calls for it.
14. Orchestrator closes the issue only after verification, or moves it to an explicit waiting state.

If execution is read-only and creates no material diff, the orchestrator may move directly to Waiting External Eval, Approval, or Done according to the approved workflow and verification state.

In multi-slice mode, steps 5-7 run independently for each ready slice.

In multi-slice mode, advancing the next committed ready slice is tracker work owned by the orchestrator. An implementation-first phase branch slice moves to In Progress and is implemented before Review; a pre-review slice moves to Review before execution. If autonomy mode authorizes local execution, reviewer approval is the execution gate for review-first work. If phase branch mode is enabled, commits and pushes to the named phase branch may be handled by the orchestrator. The next human approval is for manual execution, protected-branch push, publish, merge, closeout unless already authorized by workflow, scope changes, live or external systems, databases, cloud, deploys, destructive actions, costly actions, production data/resource changes, or any action the plan or workflow marks as approval-gated.

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
- increment the review round and record the workflow revision and exact transport-specific artifact identity
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

An error, timeout, could-not-review result, identity mismatch, unexplained repository drift, or unknown or mixed workflow revision also holds the gate. Any changed head or artifact invalidates every prior approval. In `full` tier, all expected slots re-review the changed artifact. `Light` may apply one bounded, in-scope, same-risk fix and send the changed artifact to the same cross-family reviewer once. A scope or risk change, second changed artifact, or unresolved delta verdict escalates to `full` or a human decision.

Resolve every accepted nit before the next gate in one of two ways:

- defer it without changing the artifact, recording the reason and follow-up
- implement it and obtain the required delta review of the changed artifact; Light may use its one bounded same-reviewer delta when scope and risk stay unchanged

Do not carry an approval across an implemented nit. Immediately before the next gated action, recompute the live repository fingerprint and artifact identity, including reviewed ignored temporary plans, and compare them with every approval.

When autonomy mode is `review-approved-auto-execute`, all expected reviewers for the selected tier returning `Approve` or `Approve with nits` authorize local execution when no Autonomy Mode stop condition or required change before execution applies. Otherwise move to Approval when the next action needs human approval.

Use a third reviewer only when the human asks for a tie-break or extra risk review.

## Plan Drift Rule

When the local plan changes materially, the orchestrator must add an execution-log comment that names what changed.

A change is material if it alters acceptance criteria, scope, non-goals, gates, commands, verification, rollback conditions, or sensitive-data boundaries.

Typo fixes, formatting, and rewording without semantic change are not material.

For tracked code changes, include the full commit SHA when available. Any changed reviewed head or artifact starts a new round and invalidates prior approvals.

For uncommitted plan changes, include the plan path and a short summary of the changed gate, scope, or command.

For multi-slice plans, update affected child slice issues in the same change.

If a saved plan, deploy artifact, or generated evidence file is replaced, record the new path and checksum when useful.

## Safety Boundaries

- Do not paste secrets, raw credentials, token values, sensitive resource names, or raw plan output into issues.
- Use sanitized summaries for plans, logs, findings, and metadata.
- Destructive, costly, cloud-mutating, deploy, apply, protected-branch push, or external posting outside the assigned tracker issue set requires explicit human approval, except for bounded PR operations explicitly pre-authorized by `Review transport: pr`.
- Phase branch commits and pushes may be pre-authorized only by phase branch mode.
- Auto-execution is limited to reviewed local work inside the assigned slice.
- The approved workflow may authorize issue closeout after acceptance criteria pass; otherwise human approval is required.
- Saved plans must be applied by explicit filename, not by a stale default path.
- Local-only plan documents stay uncommitted when the task says so.

## GitHub Boundary

Use an issue tracker as the agent orchestration board.

Use GitHub Issues or PRs when the work is repo-native, public, or should be tied directly to branches, commits, code review, and PR closure.

When a branch or PR exists, link it from the issue. Do not duplicate sensitive operational evidence into GitHub.

When available, use branch protection on the merge target with required approvals, required status checks, and dismissal of stale approvals after new commits.

Prefer squash merge for phase branches unless the repo has a different convention or the reviewed plan names commits that must remain reachable. When commit preservation is required, prohibit squash, use a commit-preserving merge, and verify every named commit is an ancestor of the merge target before deleting the branch.

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

## Worktree Lifecycle

The worktree lifecycle requires no named plugin, skill, marketplace product, or vendor-specific integration.

### Mode And Location

- `(Phase branch mode: on, Worktree mode: on)` is the default phase-branch path: use one dedicated named-branch worktree and keep the primary checkout coordination-only.
- `(Phase branch mode: off, Worktree mode: off)` preserves the existing primary-checkout execution and uncommitted-review path.
- `(Phase branch mode: on, Worktree mode: off)` requires explicit human approval because it disables collision protection.
- `(Phase branch mode: off, Worktree mode: on)` is invalid.
- A compliant platform mechanism is allowed; otherwise use `git worktree`. Git's own same-branch and path refusals are the mechanical enforcement. Pre-creation inspection records a readable stop reason but does not replace those refusals.
- Never use force to create or remove a worktree. Never remove a worktree automatically before its lifecycle record is complete.
- Prefer a worktree path outside the repository root. A project-local root is allowed only when `git check-ignore -v` exits zero for it and identifies an existing positive repository-specific rule in a tracked repository ignore file or that repository's own Git metadata; a negation or host-global rule is insufficient.
- After creation, recompute the primary-checkout fingerprint. If the fingerprint command fails or its untracked digest changes, the worktree location is non-compliant.
- Absolute paths, usernames, host layout, remote URLs, remote names, and full refs stay in local or private evidence. Public surfaces carry only the opaque worktree reference, ownership category, checkout kind, remote-subject category, and expected/live comparison result.
- Concurrent worktrees provide filesystem isolation, not semantic independence. Use the existing parent/child dependency record to declare whether phases may run concurrently.

### Ownership And Creation

- Before fresh creation, require the primary checkout on the recorded base branch at the stored base SHA, clean under `git status --porcelain=v1 --untracked-files=all`, and equal to its canonical stored fingerprint.
- Before fresh creation, require `git worktree list --porcelain` to show no conflicting path or checkout, require the full local phase ref absent, and require an authoritative live query of the bound remote subject to report the full remote phase ref absent.
- Create the named phase branch and worktree together from the exact base without force. The primary checkout stays on the base branch and performs no phase implementation.
- Before sealing ownership, require the primary branch, HEAD, cleanliness, and fingerprint to remain exactly unchanged.
- Before sealing ownership, require the phase worktree at the canonical recorded path, on the exact named phase branch, at the base SHA, clean, fingerprintable, and bound to the expected Git common directory and distinct per-worktree Git directory.
- Repeat the authoritative live remote-absence query after local creation. Only when every primary, phase, local-ref, Git-identity, fingerprint, and remote postcondition matches may the orchestrator seal the immutable creation record and record local `absent -> <base SHA>` and remote `absent` expected states.
- A failed creation postcondition creates only a recovery record from observed facts and a human handoff. Never adopt, remove, retry, or advance expected state automatically.
- A phase-worktree immutable record binds opaque reference, canonical path, owner/category, checkout kind `named branch`, expected full local branch ref, initial full HEAD SHA, Git common directory, per-worktree Git directory, base SHA, stored primary pre-creation fingerprint, credential-free canonical remote identity or `none`, remote name or `none`, full remote ref or `none`, and initial expected remote state.
- Resume is not creation. Resume requires the complete immutable record, mutable expected local and remote states, exact path and Git identities, clean phase and primary fingerprints, local HEAD descending from base, and an authoritative live remote match. Any mismatch hands off.

### Baseline And State Transitions

- Before edits, run only the repository's documented setup and verification commands in the phase worktree and record exact results. Never run a generic dependency installer automatically.
- If the repository documents no verification command, the reviewed plan must define one or explicitly record that no baseline is available.
- A failing baseline proceeds only after the human accepts the exact command, bounded failure signature, and impact. A plan-authored acceptance alone is insufficient.
- Immediately before every authorized commit, require the exact full phase ref and expected local SHA. Afterward, require the same branch, a different new SHA that descends from both the previous expected SHA and immutable base, then record previous/new values and advance expected local state.
- A missing, premature, unauthorized, unchanged, or non-descendant local-ref transition hands off and is never absorbed.
- The immutable remote subject uniquely keys every remote comparison. When it is `none`, remote name, full ref, expected state, and live state must all be `none`.
- Obtain authoritative remote state from a live query to the exact remote or forge subject, never from remote-tracking refs alone.
- Before every authorized push or remote deletion, require authoritative live state to equal expected state. Freeze the expected local tip as a push's intended remote SHA.
- After every authorized push or remote deletion, query the same subject again and require the intended exact new state before recording previous/new values or advancing expected remote state.
- Any remote subject, pre-transition, or post-transition mismatch hands off and is never absorbed.
- Creation, resume, review dispatch, local or remote transition, and cleanup compare authoritative live state with expected state. Unexpected advance, deletion, appearance, subject change, or ref change hands off.

### Review Worktrees

- Reviewer worktrees are optional and apply only to a repo-backed reviewer of a commit-bound `(Phase branch mode: on, Worktree mode: on)` implementation artifact that needs local execution.
- A plan, packet-only, forge-only, no-repo, or `(off, off)` uncommitted reviewer has no worktree obligation and inspects the immutable supplied artifact directly.
- The immutable packet or forge artifact, never a mutable worktree, is the source of reviewed bytes.
- A reviewer-created worktree uses a distinct throwaway detached checkout at the exact reviewed SHA and records opaque reference, canonical path, reviewer owner, cleanup owner, checkout kind `detached`, reviewed SHA, Git common directory, and per-worktree Git directory. All remote fields are `none`.
- A reviewer-created worktree follows the same compliant-location and ownership rules as a phase worktree.
- A reviewer that creates a worktree must require detached HEAD at the exact SHA, work read-only, record clean status, remove it normally, and verify its exact path absent from `git worktree list --porcelain` from a retained checkout before returning a verdict.
- Dirty reviewer state or failed cleanup returns `Review status: could-not-review` with `Verdict: not issued`; any drafted judgment is non-counting evidence. A reviewer that created no worktree has no cleanup obligation. Only the orchestrator records `error` or `timeout` when no response can be obtained.

### Merge And Cleanup

- Worktree removal and branch resolution are separate. Resolve every phase worktree as merged, abandoned, intentionally kept branch, or human handoff. Remove the owned worktree before deleting its branch.
- Before requesting merge approval, bind the credential-free target repository identity, full target ref, exact live target tip, exact reviewed phase head, canonical reviewed-artifact digest, intended target, and merge strategy.
- Immediately before an approved forge merge, re-query the exact target and artifact and require all bound identities and approvals unchanged. Also require the primary checkout still on its stored base branch and SHA, clean, at its stored fingerprint, with that base an ancestor of the live target tip.
- Execute only the exact human-approved merge. Immediately afterward require the authoritative target ref at the reported merge commit, require the approved strategy and parent identities, and record previous/new target states before any local transition.
- Before changing the primary checkout, re-require its stored branch, SHA, cleanliness, and fingerprint and require its base SHA to be an ancestor of the verified merge commit.
- Only exact closeout authorization permits a fast-forward-only move of the primary target branch directly to the verified merge commit. Never create another merge, rebase, reset, force, or move to a later target tip.
- After the primary fast-forward, require the exact target branch and merge-commit HEAD, clean state, and successful new fingerprint before recording the new coordination base and running post-merge verification there.
- Merged cleanup requires complete ownership, expected cleanup HEAD equal to the latest approved reviewed head and local tip, applicable authoritative remote equality or expected absence, clean status, and verified merge ancestry.
- For merged cleanup, record state; exit the worktree; remove it normally without force; verify its exact path absent from `git worktree list --porcelain` from a retained checkout; then apply the existing merged branch cleanup rule.
- Before authorized local phase-ref deletion, require the worktree absent and the full local ref equal to expected local state. After deletion, require the ref absent before recording previous/new state and advancing expected local state to `absent`.
- Before authorized remote branch deletion, require authoritative live state equal to the expected exact SHA. Afterward, require the exact ref absent before recording previous/new state and advancing expected remote state to `absent`.
- Independently verified forge auto-deletion is accepted only when evidence binds the exact expected ref and SHA and a live query confirms absence; then record `absent` without issuing a deletion command.
- Remote deletion is not lease-protected because force variants are prohibited. The bounded control is a workflow-owned branch with unauthorized concurrent pushes plus exact pre-transition and post-transition live checks.
- Abandoned cleanup requires complete ownership, applicable expected state, authoritative local and remote state, PR state, cleanliness, and preservation need. Dirty, divergent, changed, unowned, or preservation-needed state hands off.
- A clean abandoned worktree is removed and verified absent before the PR and branch are resolved under `Abandoned branch cleanup`. No approved reviewed head or remote SHA is required when its expected state is `absent`.
- An intentionally kept branch still requires complete ownership, exact retained local expected SHA, authoritative remote state, clean status, branch tips, reason, next owner, and revisit trigger. Remove and verify the worktree while leaving branch, expected local SHA, remote state, and PR unchanged.
- Never run `git worktree prune` in the normal lifecycle. A stale entry is an out-of-band, human-gated repair.
- Cleanup removes only the exact path in the ownership record and only when its live branch or detached SHA matches that record. Never remove another agent's worktree.
- Cleanup failure keeps the issue open and records the opaque reference, branch, owner/category, path privately, observed state, and blocker.
- Worktree mode on with phase branch mode on pre-authorizes compliant named-branch creation and normal worktree removal. Phase branch mode separately authorizes branch creation, commits, allowed pushes, and approved merged-branch cleanup. Every existing human gate remains.

<!-- BEGIN FOUR EYES ROLE CONTRACTS SOURCE -->
# Four Eyes Role Contracts

This is a compact, derived loading surface for active agents. It is not the definition of Four Eyes and must not be edited independently. Canonical policy remains in `README.md`, `docs/playbook.md`, and `docs/templates.md`. Generate this document from the marked Playbook source with `ruby scripts/check-docs.rb --write-derived`.

## Authority

- Four Eyes is tool-agnostic and manual-first. One orchestrator owns execution and synthesis; reviewers judge independently; the human owns real-risk gates.
- The task issue and any reviewed local plan define scope, modes, tier, branch, transport, verification, stop conditions, and the next gated action.
- The orchestrator may escalate review or safety requirements. It must not downgrade a human-selected tier, expand scope, or cross a human gate on its own.
- Shared truth is the task issue, temporary local plan when one exists, exact repository state, immutable review artifact, and verification evidence. Agent memory is not authoritative.

## Orchestrator

- Own the temporary plan when needed, tracker state, phase boundaries, implementation, verification, reviewer handoff, verdict embargo, synthesis, and closeout.
- In the Codex-led default, launch the isolated internal Reviewer 1 subagent. Return manual external reviewer prompts to the human; invoke direct Reviewer 2 only through a native isolated tool under exact human-approved phase, full model, maximum-call, and maximum-cost bounds. Direct mode has no standing or orchestrator-selected opt-in.
- Give each reviewer only the immutable packet and that reviewer's own prior findings. Never provide peer verdicts, synthesis, hidden reasoning, or the parent transcript before independent judgment.
- Wait for every expected slot to return a verdict or terminal record. Then post carried verdicts verbatim before synthesis.
- Completed reviews return `Approve`, `Approve with nits`, or `Block`. Error, timeout, and could-not-review records use `Verdict: not issued`. Every such outcome holds the gate and stands for its numbered round; never retry, resample, or switch transport in that round.
- Implementation-first phase work may execute on its recorded branch before review when phase branch mode authorizes it, but it must pass review before merge. Review-first local work auto-executes only after the selected tier approves with no blockers, required changes before execution, unresolved execution-affecting questions, scope change, dirty conflict, or unapproved command.

## Reviewer

- Review independently against the filled immutable packet, accessible plan or full plan bytes, exact artifact, acceptance criteria, scope, verification, and current repository state.
- Reproduce or confirm the transport-specific identity. If the artifact is inaccessible, incomplete, malformed, or mismatched, return `could-not-review` with `Verdict: not issued`.
- Return one completed verdict: `Approve`, `Approve with nits`, or `Block`, with blocking findings, non-blocking findings, questions, and required changes before the next gated action.
- Reviewer 1 may be a named same-family subagent reused within the parent workflow. That gives context isolation and continuity, not model-family independence.
- Manual external Reviewer 2 starts as a fresh session for the parent workflow unless the human explicitly chooses otherwise, and may continue across that parent's phases and review rounds. Native direct Reviewer 2 starts in isolated fresh context for each request and receives only its own prior findings for continuity. The repository cannot verify that platform isolation; the platform and human own the trust boundary.
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

- The tracker is the status, gate, and audit record, not the reviewer message bus. Reviewers never write it; the orchestrator decides when to post progress, verdicts, synthesis, approvals, and closeout.
- Record the current gate, next gated action, positive review round, workflow revision, exact artifact identity, branch/PR, verification, reviewer outcomes, nit disposition, and branch resolution.
- Keep tracker and public PR content brief, sanitized, and public-safe. Never post secrets, raw credentials, private links on public surfaces, raw sensitive logs, or unrelated task history.
- Every loaded synced workflow document must carry the same full revision marker as the task issue. Unknown or mixed revisions hold the gate.

## Branch

- Use one recorded phase branch per independently mergeable phase. Implementation-first work may be committed and pushed there before review when phase branch mode authorizes it.
- With phase branch mode on, default to one owned phase worktree, keep the primary checkout fixed, verify baseline, and remove it before branch deletion; the packet remains the review artifact, only a repo-backed reviewer that creates a detached worktree must remove it before verdict, and the contract has no named integration dependency.
- Review the complete phase artifact before merge. Merge to `main` or another protected branch always remains a human gate.
- Every agent-created phase branch must resolve as merged and deleted, abandoned under its explicit cleanup gate, intentionally kept with owner and revisit trigger, or handed to the human with the blocker recorded.
- Record local and remote tip SHAs before deletion. Divergent tips, unscoped branches, non-workflow PRs, preservation needs, or cleanup side effects require human handoff.

## Loading

- Default orchestrator bootstrap is the task issue, Four Eyes Default Workflow, and Four Eyes Role Contracts.
- Load Four Eyes Playbook only for exact policy detail or canonical commands; Templates only to fill an artifact; Issue Tracker Setup only for tracker-neutral behavior; Linear Setup only for Linear creation or sync.
- Reviewers receive a filled immutable packet and task evidence. They do not need the workflow-document set unless a disputed rule itself is under review.
- Synced workflow documents begin with the full workflow revision and source-body digest markers. Compare every loaded marker with the task issue; missing, abbreviated, mixed, or mismatched markers hold the gate.
- `docs/role-contracts.md` is generated byte-for-byte from this marked source. Direct edits are invalid.
<!-- END FOUR EYES ROLE CONTRACTS SOURCE -->
