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

- a Codex App orchestrator or another primary agent owns the plan, execution, synthesis, and coordination record
- when available, the orchestrator runs Reviewer 1 as a named isolated subagent and reuses it for the phase or parent workflow
- the orchestrator launches internal Reviewer 1; the human relays manual external Reviewer 2 by default
- optional direct Claude review is allowed only through a native isolated invocation tool under exact human-approved phase, model, call, and cost bounds
- reviewers return verdicts to the orchestrator or human
- the human pastes the expected reviews back to the orchestrator after they are complete

Manual mode preserves independent judgment and keeps the process simple. It relies on the orchestrator to isolate any internal reviewer subagent and on human discipline for external message passing.

## Coordination Ownership

The selected pull request, GitHub parent issue, or temporary local record carries coordination state. It is not the reviewer message bus.

Reviewers return verdicts to the orchestrator or human relay. They may submit a review verdict through the selected transport, but they never edit coordination metadata, status, the phase ledger, or closeout.

The orchestrator owns coordination updates:

- phase or slice status
- synthesized reviewer outcome
- current gate
- verification summary
- required human action
- remaining blockers or risks

## Reviewer Handoff And Isolation

Default Codex-led handoff:

- Reviewer 1: named Codex subagent `reviewer1`, created by the orchestrator and reused across review rounds for the phase or parent workflow
- Reviewer 2: external reviewer satisfying the model-family rule, usually Claude Code, prompted by the human

Record these fields in order:

```text
Reviewer 2 handoff: manual external reviewer | direct Claude reviewer
Direct Reviewer 2 authorization: none | human-approved phase + full model + maximum calls + maximum cost
```

Manual external Reviewer 2 is first/default, and the human relays its prompt and verdict. Direct Claude review is optional only when the orchestrator platform already provides a native invocation tool that creates an isolated fresh-context reviewer session. The human must authorize the exact task or phase, full model identity, maximum calls, and maximum cost amount and currency. There is no standing or orchestrator-selected opt-in. If the platform cannot honor every authorized bound or isolation cannot be established, direct mode is unavailable and the workflow uses manual relay.

Every internal or directly invoked reviewer receives only the sealed review packet and its own prior findings:

- coordination-record or plan summary
- PR or branch target
- verification evidence
- neutral prior phase summary when needed
- the reviewer prompt and slot number

Do not pass the parent orchestrator transcript, hidden reasoning, other reviewer output, synthesis, or combined conclusions into a reviewer before that reviewer has posted its own verdict.

Create `reviewer1` once for the current phase or parent workflow and reuse the same subagent across fix/re-review rounds. Reuse across phases is allowed when those phases belong to the same parent plan and continuity helps the reviewer understand what already happened. Start a new `reviewer1` only for an unrelated workflow, when the human asks for a reset, or if the subagent context was contaminated with peer review, synthesis, hidden reasoning, or unrelated task context. Send one verdict request per reviewer per review round; delta rounds send only the delta packet when that reviewer already holds its own prior findings. A returned verdict or terminal outcome stands: do not argue, re-prompt, retry, resample, or switch transport inside the same round. A later attempt requires a new numbered round and any approval required by its gate.

A completed review returns exactly `Approve`, `Approve with nits`, or `Block`. An `error`, `timeout`, or `could-not-review` outcome uses `Verdict: not issued` and holds the gate. Reserve `Block` for completed reviewer judgment, not invocation or transport failure.

Hold every internal or relayed verdict until all expected slots for the round have returned or are recorded as Block, error, timeout, or could-not-review. Direct PR reviews posted by an external reviewer are outside orchestrator control. The embargo is vacuous in `light` tier because it has one expected slot. After the embargo lifts, post every verdict carried on a reviewer's behalf verbatim, then post synthesis. Do not replace the original verdict with an orchestrator summary.

Before trusting a subagent handoff in a new tool or runtime, run a one-time isolation check: spawn a test reviewer subagent and confirm it cannot describe the parent orchestrator's current task unless that task is passed in the review packet. If the check fails or cannot be verified, use manual external reviewer handoff for that slot.

The human may select any existing Claude Code session as manual external Reviewer 2 regardless of prior authorship, implementation, design, remedy proposals, reviews, historical peer output or synthesis, or unrelated work. Prior involvement and historical exposure alone are not `could-not-review`. Disclose relevant provenance and verify the exact artifact against canonical sources and evidence rather than treating prior proposals or conclusions as evidence. Do not provide current-round Reviewer 1 output, synthesis, hidden orchestrator reasoning, or combined conclusions before Reviewer 2 returns its verdict; current-round exposure is `could-not-review`. The session may continue across phases and rounds. A native direct invocation must still create isolated fresh context for each verdict request; continuity enters only through that reviewer's own prior findings in the packet. The repository cannot verify session history or platform isolation, so the human and platform own those trust boundaries.

A same-family subagent gives context separation and continuity, not model-family diversity. For non-skip work, each family represented by the current orchestrator or an agent that materially authored the current reviewed artifact needs at least one expected reviewer from another family unless the human records an override for that uncovered family. Historical participation unrelated to the current artifact does not alter this check. The override may explicitly authorize the exact current implementer session as Light's sole reviewer.

## Roles

### Orchestrator

Usually the primary agent session.

Responsibilities:

- create or update the local executable plan when needed
- select and maintain the coordination record from the plan
- decide whether work stays in one pull request or needs a GitHub parent ledger
- identify acceptance criteria, non-goals, and current git status before editing
- check existing implementation patterns before adding new ones
- keep sensitive data out of issues, commits, and broad summaries
- synthesize expected reviewer feedback for the selected tier
- resolve blockers or ask the human for an explicit override
- execute review-first work only after its review gate is clear; implementation-first phase branch work may execute before review but must reach Status `review` and Gate `review` before merge
- post verification, commit summary, and remaining risks
- after every coordination-record or gate update, tell the human the current gate and exact next action

### Reviewer 1

Usually a separate agent session or a named reviewer subagent.

Responsibilities:

- review independently before reading other reviewer output or orchestrator synthesis
- when prompted with a current-work coordination-record reference, treat it as a review request: read the provided record or packet context, review the current diff and verification evidence, and return the review to the orchestrator or human relay
- review against the linked local plan file, current repo state, current implementation diff and verification evidence if present, coordination-record content, and orchestrator-provided plan/update content
- if the local plan file is not accessible, require its full public-safe contents through the manual-relay artifact; a summary or hash alone is could-not-review
- check acceptance criteria, correctness, scope, safety, missing tests, and operational risks
- inspect the exact identified review artifact and independently recompute or confirm its hash
- fail closed as could-not-review when the workflow revision or artifact identity is missing, malformed, mismatched, or inaccessible
- avoid unrelated suggestions unless severe
- return findings with the required header

### Reviewer 2

Reviewer 2 normally satisfies the model-family rule, especially when Reviewer 1 is an orchestrator-created same-family subagent.

Responsibilities are the same as Reviewer 1.

### Human Approver

The human owns final approval for real risk gates:

- execution when autonomy mode is `manual`
- commands outside the pre-authorized local command classes or reviewed plan
- local commit when phase branch mode is not enabled; remote push when neither the pre-authorized path nor exact human approval applies
- push to protected branches, tags, releases, or unscoped branches
- merge into `main` or another protected branch
- publish
- closeout unless already authorized by workflow
- scope changes
- live or external systems, databases, cloud, deploys, destructive actions, costly actions, or production data/resource changes
- any action the plan or workflow marks as approval-gated

Human approval is not required for in-scope coordination preparation such as opening the recorded pull request, creating the authorized parent ledger, moving a phase to its recorded next gate, posting reviewer prompts, synthesizing reviews, or updating gate metadata.

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

Auto-execute alone does not authorize commit, push, publish, merge, deploy, apply, live/external mutation, destructive/costly action, closeout unless already authorized, scope change, commands outside the pre-authorized classes or reviewed plan, or work outside the assigned coordination record. Local commit requires phase branch mode or explicit human approval. Remote push follows Push Authorization below, including its independent exact-human-approval path. Bounded PR writes require `Review transport: pr`. Merge and protected-branch push remain separate human gates.

## Phase Branch Mode

For repo implementation phases, phase branch mode is the default high-throughput path when branch pushes are safe. The plan may disable it or require pre-review.

```text
Phase branch mode: on | off
Base branch: <main or other base>
Phase branch: <phase branch name>
Worktree mode: on | off
Worktree reference: none | <ownership-category>/<opaque worktree reference>
Remote push: disallowed | allowed
Merge target: <main or other protected branch>
Post-merge branch cleanup: yes | no
Abandoned branch cleanup: yes | ask | no
```

Default to `Post-merge branch cleanup: yes` and `Abandoned branch cleanup: ask`.

When phase branch mode is `on`, the orchestrator may create the recorded phase branch and commit in-scope work to it without asking the human for every local commit.

The pre-authorized remote-push path permits updates to that exact branch without asking the human for every push only if all of these are true:

- the branch name, base branch, and merge target are recorded in the plan or coordination record
- the work stays inside the approved phase scope
- pushes go only to the named phase branch
- the authoritative coordination record says `Remote push: allowed`
- branch pushes do not deploy, mutate live systems, publish releases, or trigger hard-to-reverse external actions
- verification commands are run before review
- reviewers review the branch diff and verification evidence before merge approval

Exact human approval for a specifically identified push remains an independent authorization path under Push Authorization.

Phase branch mode is implementation-first by default: the orchestrator completes the phase on the branch, then reviewers review the branch diff once. Require pre-implementation review only when the plan, risk class, or human explicitly asks for it.

This intentionally allows local commits to the named phase branch before review. The review gate is before protected-branch push, merge, apply, deploy, or closeout.

Phase branch mode alone does not authorize:

- direct commits or pushes to `main` or protected branches
- force-push, rebase of shared history, tag creation, release creation, or branch deletion before merge except through the explicit abandoned-branch cleanup path
- deploy, apply, cloud/database mutation, destructive action, or costly action
- merge into the target branch

The human merge approval may authorize merge, post-merge verification, coordination closeout, and phase branch cleanup. Use an exact phrase such as:

```text
Approved: merge <phase branch> into <target branch>, verify, close the coordination record, and delete the phase branch.
```

If the repository has branch-push side effects, such as preview deploys, production deploys, release publishing, or data mutation, remote push is a human gate unless the human explicitly pre-authorizes that side effect.

### Branch Lifecycle

Every agent-created phase branch must be resolved at closeout.

Resolution must be exactly one of:

- merged, verified, and deleted locally and remotely when post-merge cleanup is authorized
- abandoned, its workflow-created PR closed if present, and deleted locally and remotely when abandoned cleanup is authorized
- intentionally kept, with reason, next owner, and a revisit trigger such as a follow-up issue or date recorded
- handed off to the human, with the exact blocker recorded

Before deleting any phase branch, record in the coordination closeout:

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

## Push Authorization

1. Remote push has two authorization paths: either `Phase branch mode: on` together with an authoritative `Remote push: allowed`, or exact human approval for a specifically identified push.
2. A missing `Remote push` value, or `Remote push: disallowed`, blocks the pre-authorized path. The exact-human-approval path remains available.
3. Local commits to the recorded phase branch remain pre-authorized by phase branch mode alone. Only remote push authority is narrowed.
4. Reviewing an existing unchanged pull request requires no push authorization. Other bounded pull request operations continue under `Review transport: pr`.
5. Plan and per-phase selections and parent defaults are inputs, never execution authorities. Resolve inheritance into explicit effective values for each phase. A phase selection is approved only when recorded in the review-approved plan whose digest binds that phase's authority, or exact human approval for that phase and value is recorded in that authority. An approved selection overrides an inherited default only for that phase and its recorded scope.
6. The sole effective phase authority is the mode-specific record defined by Coordination Record Contract rule 5. A phase pull request in `github-issue` mode references its parent phase authority and cannot grant permission independently.
7. Before execution, record the resolved phase values in that authority and verify agreement with inputs approved under rule 5. Any authority transfer preserves the existing effective phase permissions, records verified takeover, and marks superseded copies non-authoritative; it creates no grant.
8. A missing effective grant or disagreement between effective phase inputs and their authority blocks push until the human resolves it. A different inherited default is not a disagreement when a phase override approved under rule 5 is recorded. Superseded copies cannot authorize execution.
9. `Remote push default: disallowed` states the value a new record starts from. It is not itself an authorization.
10. Option order in any recorded field carries no meaning and never conveys a default.

## Workflow Revision And Artifact Identity

The workflow revision is one recorded full repository commit SHA. Resolve it to an exact commit and load policy surfaces from that commit, not from mutable working-tree files. Record the full SHA in the coordination record, every review packet, and every verdict. Missing, abbreviated, conflicting, mixed, or unresolvable workflow revisions fail closed.

The authoritative coordination record also records the current positive review round and review transport. A new or changed artifact starts a new round. Preserve the reviewer provenance fields, then use the transport-specific identity fields below with identical wording and order.

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

Default to `pr` for remote phase-branch implementation. Use `manual-relay` for local or no-remote work, or when the plan explicitly records that a pull request adds no useful coordination or audit value.

Selecting `Review transport: pr` pre-authorizes only these writes for the recorded phase branch and merge target: create or update its PR, maintain the bounded PR description, request the expected reviewers, and post or submit the expected reviewer verdicts. It does not authorize merge, closing unrelated PRs, changing repository settings, or any other GitHub write.

When review transport is `pr`:

- the orchestrator opens or updates a PR from the phase branch to the merge target after verification
- the coordination record holds the current review round, workflow revision, full reviewed head SHA, and PR diff SHA-256
- the PR body links the GitHub parent coordination issue when one exists
- the PR body includes the sanitized plan summary, acceptance criteria, verification evidence, and risk notes
- reviewers review the PR diff directly and write their verdict before reading other reviews
- verdict mapping is `Approve` -> approve, `Approve with nits` -> approve with comments, and `Block` -> request changes
- reviewer bodies include the required reviewer header
- the PR is the review artifact; authority follows the selected mode in Coordination Record Contract
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

- `skip`: tiny docs, typos, formatting, simple coordination/admin work, or other changes from the playbook skip list. Run verification when useful and keep the configured branch or merge gate.
- `light`: the default for routine low-risk, reversible repo work. Use one reviewer satisfying the model-family rule. Allow one bounded fix and one delta review by that same reviewer only when scope and risk stay unchanged; this is not an open-ended autonomous fix loop. A scope or risk change, failed verification, could-not-review result, sensitive path, oversized diff, second changed artifact, or unresolved delta verdict escalates to `full` or a human decision.
- `full`: the normal Four Eyes gate: two independent reviewers, synthesis, bounded fix/re-review, and human approval for real-risk gates.

In `light` tier, do not run a same-family internal Reviewer 1 subagent. The single reviewer must satisfy the model-family rule, so the human relays that external reviewer prompt.

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

For non-trivial repo, infrastructure, cloud, security, deploy, cleanup, migration, debugging, or operational work, create a temporary local executable plan when the task input is not clear enough to execute safely. Task input can be a user prompt, GitHub issue, pull request, local note, or existing plan.

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

A local plan file is not required for simple coordination admin, queue triage, one-line fixes, tiny doc edits, or tasks the human explicitly wants handled directly.

When a local plan defines or clarifies the work, reviewers review the plan as part of the gate before execution; for implementation-first phase branches, that means before implementation starts. The plan must be specific enough for reviewers to confirm scope, acceptance criteria, commands, verification, stop conditions, and human gates.

## Local Plan Storage

Use the least durable place that still supports the work:

- repo-local temporary plan when agents need it next to code
- `/tmp/...` for ephemeral evidence, raw command output, sensitive metadata, or large generated artifacts

Local executable plans are temporary coordination artifacts. Do not commit them, and prefer a gitignored path for repo-local plans so bulk staging cannot pick them up. If the work produces durable documentation, write that documentation separately from the temporary execution plan.

Remove the temporary local plan after the task, phase, or parent workflow is complete. If work pauses before completion, keep the plan only as long as it is needed to resume safely.

If reviewers cannot access the local plan file, the orchestrator must provide the full public-safe plan contents as the manual-relay artifact. A checksum or sanitized summary alone does not permit review; return could-not-review when the full artifact cannot be shared safely through an approved path.

## Coordination Record Contract

1. Every non-trivial task records `Coordination record: pr | github-issue | local`.
2. `pr` is the default for single-phase remote work; authority transfers to the pull request only after rule 6 verification.
3. `github-issue` uses exactly one parent issue carrying a compact phase ledger; each phase's explicitly identified record within that issue is its authority, and phase pull requests reference it.
4. `local` is the no-forge fallback; it provides resumability, not permanent audit. Work needing durable history uses `pr` or `github-issue`.
5. Each phase has one effective permission authority: in `pr` mode, the recorded local execution-state file until verified transfer to its pull request; in `github-issue` mode, its identified parent-issue phase record; in `local` mode, its recorded local file. Parent defaults and plan inputs are not execution authorities.
6. In `pr` mode, prepare the pull request as non-authoritative, copy the local record's public-safe state and effective permissions, and verify content and cross-references before recording and verifying takeover in the old authority. Mark that old record superseded and name its successor. A failure before takeover preserves the old authority; uncertain takeover stops execution and hands off. The candidate never grants permission before verified takeover.
7. Reviewers may submit verdicts through the selected review transport, including pull request reviews. A direct pull request verdict may change forge review status; it never changes the Four Eyes gate, ledger status, or closeout metadata. Reviewers never edit coordination metadata, status, the phase ledger, or closeout. The orchestrator owns every coordination update.
8. Promote `pr` to `github-issue` when a second phase becomes committed, when a dependency or blocker exists outside the current pull request, or when deferred work must survive the current pull request's closeout. Continuing a single-phase pull request across sessions is not a promotion trigger.
9. Promotion is check-act-verify-record: prepare one non-authoritative parent issue with the plan digest, ledger, current pull request, dependencies, gate, and each phase's unchanged effective permissions; verify content and backlinks before recording and verifying takeover in the old authority. Mark superseded records non-authoritative and name the successor. A failure before takeover preserves the old authority; uncertain takeover stops execution and hands off. Transfer grants no new permission.
10. Multi-phase work uses one parent ledger. Do not create a child issue for each committed execution slice.
11. Create child issues only for independently owned, externally blocked, or durable follow-up work.
12. Selecting `Coordination record: github-issue` pre-authorizes creating, updating, and closing exactly one parent coordination issue plus explicitly accepted durable follow-ups. It authorizes no unrelated issue operations.
13. The parent ledger uses the fixed columns `Phase | Depends on | Status | Branch/PR | Gate | Next action`.
14. Ledger status values are `todo`, `ready`, `in progress`, `review`, `waiting external eval`, `blocked`, and one terminal value.
15. `waiting external eval` is not terminal. Independent phases may advance while unrelated work waits; declared dependencies must satisfy rule 16. Readiness does not clear any review, permission, or human gate.
16. A phase becomes `ready` only when every declared dependency has a verified terminal resolution and all its required results are available and verified. Record each required result and its accessible verification evidence in the phase's authority record. A terminal label alone is insufficient. Removing or replacing a dependency requires the existing scope-change and plan-review gates before advancement.
17. Terminal values are `merged`, `completed`, `abandoned`, `retained`, and `handed off`. `blocked` is never terminal, and any failed cleanup remains `blocked`.
18. `merged` requires the pull request merged and the reviewed head ancestral to the target.
19. `completed` is the successful terminal value for work producing no merge, such as `local` mode. It requires the recorded verification evidence present and the working tree clean.
20. `abandoned` requires authoritative local and remote tip equality, closure of any applicable pull request, clean worktree removal, resolved branches, and a recorded reason and tip SHA.
21. `retained` requires resolved branch and worktree state plus recorded tip SHA, owner, and revisit trigger.
22. `handed off` requires a recorded blocker, owner, next action, and recorded human acceptance of ownership. Without recorded acceptance the phase stays `blocked`.
23. Record closeout evidence in the coordination record and verify it landed before removing any temporary plan or local state record.
24. In `pr` mode, post the final closeout record to the pull request before removing the temporary plan and execution-state record.
25. Parent closeout requires every phase terminal, with each claimed resolution verified against real Git or forge state. Record partial or abandoned outcomes as such; never call missing required results successful delivery.

`Status` records lifecycle progress. `Gate` records the condition controlling the next transition, such as `none`, `dependencies`, `review`, `human approval`, `external evaluation`, `blocker resolution`, or `human handoff`; do not use it as a duplicate status field.

## Local Coordination Record

1. The execution-state record lives at one canonical gitignored path recorded in the task's bound state, rooted in the primary coordination checkout.
2. It belongs to the primary checkout and therefore survives phase-worktree removal; never place it inside a phase worktree.
3. Before use, require it to be a regular file and not a symlink.
4. It records the workflow revision, the plan digest it is bound to, the phase ledger, the current gate, and the next action.
5. Its content is public-safe from creation, because `pr` mode copies it into the pull request. Never write absolute paths, usernames, host directory layout, credentials, or private identifiers into it.
6. A workflow-revision or plan-digest mismatch holds the gate; it is never silently rebound.
7. Write it atomically, then read it back and require the readback to match what was written.
8. It survives the entire parent workflow and is removed only after every phase is terminal and closeout is verified.
9. Verify its absence after removal, from a checkout that still exists.

## Repository Revision Loading

1. Workflow policy loads from this repository at one recorded full commit SHA.
2. Resolve the recorded SHA to an exact commit before loading, and load policy surfaces from that commit rather than from mutable working-tree files.
3. A missing, abbreviated, mixed, or unresolvable revision holds the gate.
4. The workflow revision is the full repository commit SHA carried by coordination records, packets, and verdicts.
5. External document synchronization, source-body markers, readback checks, and a standing synchronization issue are not required.

## Policy Transition And Trust Boundary

1. A workflow remains governed by the workflow revision it recorded. `main` advancing never rebinds it, and no new approval is required merely because the tip moved.
2. The push authorization rules apply to workflows that bind the revision containing them. A workflow pinned to an earlier revision retains its recorded policy until closeout.
3. Offline and `manual-relay` work remain valid. No rule requires reaching the remote in order to load policy.
4. New policy governs only agents that load it. Four Eyes cannot prevent deliberate operation from an obsolete checkout or an obsolete policy revision, and does not claim to.
5. Revision selection is orchestrator-attested, appears in review evidence, and is open to human challenge at any gate.

## Right-Sizing Slices

Review cost is per review run. Batch related changes with shared scope, risk, verification, and rollback. Split when gates, rollback, owners, repos, deploy windows, or risk classes differ, or when the phase diff becomes too large to review well.

## Token-Efficient Review

- reviewers inspect the PR or repo artifact directly; do not narrate a diff that Git already expresses
- CI or check links replace pasted logs when CI exists
- delta re-review sends the exact delta plus that reviewer's own prior findings while binding the current complete artifact
- every changed Full-tier artifact returns to both expected slots, but normal delta inspection stays focused unless semantic risk requires a wider reread; Light permits one bounded same-reviewer delta before escalation

## Documentation Enforcement Boundary

- Use exact mechanical enforcement when silent drift could change authority, a gate, artifact identity, reviewer isolation, terminal or cleanup behavior, a public/private boundary, or canonical generated output.
- Use structural validation for required headings, identifiers, fields, ordering, allowed values, and state coherence when explanatory wording does not carry authority.
- Leave visible explanatory and cosmetic prose to normal review when its drift cannot silently change workflow behavior.

## Review Efficiency

1. Review rounds are capped in exactly two buckets: plan and implementation.
2. Each bucket allows at most three panel rounds: one initial review plus two subsequent panel rounds.
3. A round recorded with `Review stage: delta` counts inside the bucket whose artifact it revises and never starts a new cap.
4. A panel round starts when its first reviewer slot is dispatched.
5. Every numbered round counts against its bucket, including rounds ending in error, timeout, or could-not-review.
6. At the cap the orchestrator stops and returns the current findings to the human.
7. At the cap the human chooses exactly one of: authorize a stated positive number of additional rounds; descope and authorize a stated positive number of rounds to review the changed artifact; override a blocker with recorded risk; or abandon.
8. Additional rounds increment the exhausted bucket. They never reset it and never expand model, call, or cost authorization.
9. A round cap never converts a blocker into a nit. Blockers remain blockers at and after the cap.
10. Accepted nits are deferred by default without changing the artifact.
11. Implement an accepted nit immediately only when the human requires it, an acceptance criterion requires it, or an existing gate requires it.
12. Record every deferred no-action nit in the coordination record closeout with its reason.
13. Record every deferred actionable nit as a follow-up in the coordination record closeout.
14. `Review transport: pr` authorizes no issue creation.
15. `Coordination record: github-issue` retains its existing authority to create, update, and close exactly one parent coordination issue plus explicitly accepted durable follow-ups.
16. Any other external follow-up record requires exact human authorization naming the records, normally bundled into merge approval.
17. Both full-tier reviewers bind approval to the complete current artifact identity in every round.
18. A normal delta round inspects the exact delta, its affected context, that reviewer's own prior findings, and the verification relevant to that delta.
19. Require a wider reread when the delta changes scope, risk, authority, gates, identity mechanics, or shared behavior.
20. Review scope is semantic, not filename-based. A validator change is not automatically a low-risk delta.
21. A validator change affecting authority, gates, identity, or cleanup receives focused inspection of the changed code plus its affected call sites and tests.

## Phase Review

Review phases instead of every bug. The plan may infer phases from related scope, files, verification, risk, branch target, and rollback. Ask the human only when decomposition changes risk, ownership, merge target, deploy behavior, or has multiple materially different valid answers.

For each phase, keep one branch, worktree, verification strategy, and gate. The orchestrator may implement the complete phase before review when implementation-first flow authorizes it. Reviewers inspect the phase diff once; blocking feedback is fixed in one batch.

## Phase Branch Flow

Use this flow when phase branch mode is enabled:

1. Orchestrator confirms the phase scope, base branch, phase branch, merge target, verification, and stop conditions. If a temporary local plan defines unclear work, expected reviewers confirm the plan before implementation starts.
2. Orchestrator creates the phase branch from the base branch.
3. Orchestrator implements the whole phase on that branch.
4. Orchestrator commits only the named phase branch and pushes it only when Push Authorization permits it.
5. Orchestrator runs verification and updates the coordination record with the current round, workflow revision, transport-specific artifact identity, phase branch, diff summary, and reviewer prompts.
6. If review transport is `pr`, the orchestrator opens or updates the PR and uses the exact identified PR artifact. If Reviewer 1 can run as a named isolated internal subagent, the orchestrator creates or reuses it. The human sends every manual external reviewer prompt. An exactly authorized direct Reviewer 2 instead receives only its sealed packet and own prior findings through the platform's native isolated invocation tool.
7. Reviewers inspect the exact artifact and verification evidence independently, then return verdicts through the selected transport. The orchestrator holds internal and relayed verdicts under the embargo until every expected slot has returned or has a terminal record.
8. After the embargo lifts, the orchestrator posts carried verdicts verbatim, recomputes repository and artifact identity, synthesizes feedback, fixes blockers on the same phase branch, commits locally when phase branch mode authorizes it, pushes only when Push Authorization permits it, and requests the required delta review.
9. When all expected reviewers approve the unchanged current artifact, the orchestrator recomputes its identity and asks the human for the merge approval phrase.
10. After approval, orchestrator merges into the target branch, runs post-merge verification, records coordination closeout, records branch cleanup SHAs, and deletes the phase branch if authorized.

This flow is meant to reduce review loops. It trades pre-implementation review for branch isolation and a hard merge gate.

## Standard Task Flow

Use this flow when phase branch mode is off, or when pre-implementation review is required.

1. Orchestrator creates a temporary local executable plan when the task input is not clear enough to execute safely.
2. Orchestrator selects `pr`, `github-issue`, or `local` and records any phase dependencies in one ledger.
3. Orchestrator records the temporary plan path, sanitized summary, acceptance criteria, boundaries, expected files or resources, status, gate, and review request. Ready review phases use Status `review` and Gate `review`; downstream phases use Status `todo` or `blocked` and Gate `dependencies`.
4. The orchestrator creates or reuses any internal Reviewer 1 subagent with only the review packet and its own prior review history. The human sends the exact accessible review artifact and task prompt only to external expected reviewer slots. Status: `review`; Gate: `review`.
5. Reviewers return verdicts independently to the orchestrator or human relay. The orchestrator holds internal and relayed verdicts under the embargo until every expected slot has returned or has a terminal record. Status: `review`; Gate: `review`.
6. After the embargo lifts, the orchestrator posts carried verdicts verbatim, recomputes repository and artifact identity, and synthesizes the expected reviews. Use Status `in progress` and Gate `none` when auto-execution starts; Status `ready` and Gate `human approval` when human approval is required; Status `review` and Gate `review` for material re-review; or Status `blocked` and Gate `blocker resolution` while blockers remain.
7. Orchestrator updates code or plan if needed. Material changes use Status `review` and Gate `review`.
8. If changes are material, repeat review on the updated slice.
9. Human approves execution, apply, deploy, or merge when needed. Skip this for local execution authorized by autonomy mode. Until approval, use Status `ready` and Gate `human approval`.
10. Orchestrator executes the approved or auto-authorized slice and posts verification. If phase branch mode is enabled, the orchestrator may commit updates to the named phase branch and may push them only when Push Authorization permits it. Material execution changes use Status `review` and Gate `review`.
11. Reviewers review the exact identified implementation artifact and verification evidence before merge, apply, deploy, or closeout approval.
12. After the verdict embargo lifts, the orchestrator posts carried verdicts verbatim, recomputes repository and artifact identity, synthesizes implementation reviews, and updates the coordination record with the status, gate, and required human action. Use Status `ready` and Gate `human approval` when aligned, Status `review` and Gate `review` for material re-review, or Status `blocked` and Gate `blocker resolution` while blockers remain.
13. Orchestrator commits only the intended tracked changes when phase branch mode authorizes branch commits, when the human approves the commit, or when the approved workflow explicitly calls for it.
14. Orchestrator records a terminal status only after verification, or records an explicit non-terminal waiting state.

If execution is read-only and creates no material diff, use Status `completed` when verification is complete and no further action remains, Status `waiting external eval` with Gate `external evaluation` when an external result is pending, or Status `ready` with Gate `human approval` when an explicit human action is required.

In multi-phase mode, steps 5-7 run independently for each ready phase.

In multi-phase mode, advancing the next ready phase is coordination work owned by the orchestrator. Readiness requires verified terminal dependencies and available verified required results under Coordination Record Contract rule 16; it clears no other gate. An implementation-first phase uses Status `in progress` and Gate `none` before it reaches Status `review` and Gate `review`; a pre-review phase starts at Status `review` and Gate `review`. If autonomy mode authorizes local execution, reviewer approval is the execution gate for review-first work. If phase branch mode is enabled, commits to the named phase branch may be handled by the orchestrator; pushes also require Push Authorization. The next human approval is for manual execution, protected-branch push, publish, merge, closeout unless already authorized by workflow, scope changes, live or external systems, databases, cloud, deploys, destructive actions, costly actions, production data/resource changes, or any action the plan or workflow marks as approval-gated.

## Orchestrator Next-Action Rule

After creating or updating a coordination record, changing a gate, posting a synthesis, requesting approval, or closing out work, the orchestrator must end its user-facing response with:

- authoritative coordination record
- current gate
- why that gate is set
- exact next human action
- what the orchestrator will do after that action
- what remains out of scope or forbidden

When the current gate is `human approval`, include an exact approval phrase the human can send, such as:

```text
Approved: execute <ISSUE-ID> <slice name> only.
```

Adapt the approval verb to the action, such as execute, merge, push, apply, deploy, close, or archive.

If execution is still forbidden, say that plainly.

## Implementation Discipline

Before editing:

- read the coordination record, local plan, linked spec, and relevant existing files
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
- confirm the next gate is correctly recorded in the coordination record

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

- update the coordination record to Status `review` and Gate `review`
- increment the review round and record the workflow revision and exact transport-specific artifact identity
- identify the exact files, resources, or diff to review
- include verification already run
- tell reviewers where to return feedback, either to the orchestrator or human relay
- keep protected-branch push, apply, deploy, merge, and closeout out of scope until reviews are synthesized and the human approves the next gated action

Reviewers must review the current implementation diff and verification evidence, not only the original plan.

If the approved action itself is apply, deploy, or another external mutation and creates no reviewable local diff, post verification and move to Status `waiting external eval` with Gate `external evaluation`, or to the applicable terminal status, according to the approved workflow.

## Gate State

The current gate must be visible in the authoritative coordination record, not only buried in chat.

Lifecycle status values:

- Todo: local plan exists or task is ready to prepare
- Ready: every dependency has verified terminal resolution and available verified required results; the phase awaits an authorized transition
- In Progress: orchestrator actively working
- Review: implementation or plan is waiting for expected reviewer slots
- Blocked: blocked by reviewer finding, missing evidence, external decision, unresolved ownership, or prior slice
- Waiting External Eval: executed, waiting for CI, logs, users, cloud evaluation, or another external system
- Merged, Completed, Abandoned, Retained, or Handed Off: verified terminal resolution

Gate values name the condition controlling the next transition:

- None: no gate blocks the next authorized action
- Dependencies: a declared prerequisite is non-terminal or its required result is missing, unavailable, or unverified
- Review: waiting for expected reviewer slots
- Human Approval: waiting for an explicit human decision
- External Evaluation: waiting for a recorded external result
- Blocker Resolution: waiting for an in-scope blocker to be resolved
- Human Handoff: waiting for recorded human acceptance of ownership

For a `github-issue` record whose forge lacks custom states, use labels or issue-title prefixes. For `pr` or `local`, write the state directly in that coordination record.

- `gate:review`
- `gate:human-approval`
- `waiting:external-eval`
- `gate:blocker-resolution`

When using gate labels, remove the old gate label in the same update that adds the new gate label.

## Gate Rule

Proceed when the expected reviewer slots for the selected tier are complete and all blocking feedback is resolved.

A Block from any expected reviewer holds the gate. The orchestrator must address it or the human must explicitly override it in the coordination record before execution.

An error, timeout, could-not-review result, identity mismatch, unexplained repository drift, or unknown or mixed workflow revision also holds the gate. Any changed head or artifact invalidates every prior approval. In `full` tier, all expected slots bind approval to the changed complete artifact; normal delta inspection stays focused unless semantic risk requires a wider reread. `Light` may apply one bounded, in-scope, same-risk fix and send the changed artifact to the same reviewer satisfying the model-family rule once. A scope or risk change, second changed artifact, or unresolved delta verdict escalates to `full` or a human decision.

Accepted nits are deferred by default. Resolve every accepted nit before the next gate in one of two ways:

- defer it without changing the artifact, recording the reason and whether it is no-action or an actionable follow-up
- implement it and obtain the required delta review of the changed artifact; Light may use its one bounded same-reviewer delta when scope and risk stay unchanged

Do not carry an approval across an implemented nit. Immediately before the next gated action, recompute the live repository fingerprint and artifact identity, including reviewed ignored temporary plans, and compare them with every approval.

When autonomy mode is `review-approved-auto-execute`, all expected reviewers for the selected tier returning `Approve` or `Approve with nits` authorize local execution when no Autonomy Mode stop condition or required change before execution applies. Otherwise use Status `ready` and Gate `human approval` when the next action needs human approval.

Use a third reviewer only when the human asks for a tie-break or extra risk review.

## Plan Drift Rule

When the local plan changes materially, the orchestrator must add an execution-log comment that names what changed.

A change is material if it alters acceptance criteria, scope, non-goals, gates, commands, verification, rollback conditions, or sensitive-data boundaries.

Typo fixes, formatting, and rewording without semantic change are not material.

For tracked code changes, include the full commit SHA when available. Any changed reviewed head or artifact starts a new round and invalidates prior approvals.

For uncommitted plan changes, include the plan path and a short summary of the changed gate, scope, or command.

For multi-phase plans, update affected ledger rows in the same change.

If a saved plan, deploy artifact, or generated evidence file is replaced, record the new path and checksum when useful.

## Safety Boundaries

- Do not paste secrets, raw credentials, token values, sensitive resource names, or raw plan output into public coordination records.
- Use sanitized summaries for plans, logs, findings, and metadata.
- Destructive, costly, cloud-mutating, deploy, apply, protected-branch push, or external posting outside the assigned coordination record requires explicit human approval, except for bounded PR operations explicitly pre-authorized by `Review transport: pr` or the single parent issue authorized by `Coordination record: github-issue`.
- Phase branch commits may be pre-authorized by phase branch mode. Remote pushes require Push Authorization.
- Auto-execution is limited to reviewed local work inside the assigned slice.
- The approved workflow may authorize coordination closeout after acceptance criteria pass; otherwise human approval is required.
- Saved plans must be applied by explicit filename, not by a stale default path.
- Local-only plan documents stay uncommitted when the task says so.

## GitHub Boundary

Use the selected pull request, GitHub parent issue, or local record as the coordination board.

Use one GitHub parent issue only when multi-phase state or a durable blocker cannot live in the current pull request.

When both a parent issue and pull request exist, backlink them and keep sensitive operational evidence local.

When available, use branch protection on the merge target with required approvals, required status checks, and dismissal of stale approvals after new commits.

Every reviewed phase-branch pull request uses a commit-preserving merge. Squash is outside the normal phase-branch workflow and requires an explicitly reviewed alternative closeout procedure.

If a PR is opened, its description should briefly include:

- what changed
- why
- parent coordination issue link, when one exists
- acceptance criteria checked
- risk
- how to test
- what was intentionally not done
- accepted durable follow-up issues

## Close Discipline

Do not close a coordination record just because code was written or an action completed.

Close only when verification has passed and closeout is authorized, or when the coordination record explicitly states why verification is deferred or impossible.

If an external system must update later, move the coordination record to a waiting state.

## Worktree Lifecycle

The worktree lifecycle requires no named plugin, skill, marketplace product, or vendor-specific integration.

### Mode And Location

- `(Phase branch mode: on, Worktree mode: on)` is the default phase-branch path: use one dedicated named-branch worktree and keep the primary checkout coordination-only.
- `(Phase branch mode: off, Worktree mode: off)` preserves the existing primary-checkout execution and uncommitted-review path.
- `(Phase branch mode: on, Worktree mode: off)` requires explicit human approval because it disables collision protection.
- `(Phase branch mode: off, Worktree mode: on)` is invalid.
- A compliant platform mechanism is allowed; otherwise use `git worktree`. Git's own same-branch and path refusals are the mechanical enforcement. Pre-creation inspection records a readable stop reason but does not replace those refusals.
- Never use force to create or remove a worktree. Never remove a worktree automatically before its immutable ownership record and pre-cleanup facts are complete.
- Prefer a worktree path outside the repository root. A project-local root is allowed only when `git check-ignore -v` exits zero for it and identifies an existing positive repository-specific rule in a tracked repository ignore file or that repository's own Git metadata; a negation or host-global rule is insufficient.
- After creation, recompute the primary-checkout fingerprint. If the fingerprint command fails or its untracked digest changes, the worktree location is non-compliant.
- Absolute paths, usernames, host layout, remote URLs, remote names, full refs, local expected-state transitions, and cleanup diagnostics stay in local or private evidence. Public surfaces carry only the opaque worktree reference, ownership category, checkout kind, remote-subject category, expected/live comparison result, lifecycle path, and blocker.
- Concurrent worktrees provide filesystem isolation, not semantic independence. Use the existing parent/child dependency record to declare whether phases may run concurrently.

### Ownership And Creation

- Before fresh creation, require the primary checkout on the recorded base branch at the stored base SHA, clean under `git status --porcelain=v1 --untracked-files=all`, and equal to its canonical stored fingerprint.
- Before fresh creation, require `git worktree list --porcelain` to show no conflicting path or checkout and require the full local phase ref absent. When a remote subject is bound, require an authoritative live query to report the full remote phase ref absent; when no remote is bound, require remote subject, name, full ref, expected state, and live state all to be `none`.
- Create the named phase branch and worktree together from the exact base without force. The primary checkout stays on the base branch and performs no phase implementation.
- Before sealing ownership, require the primary branch, HEAD, cleanliness, and fingerprint to remain exactly unchanged.
- Before sealing ownership, require the phase worktree at the canonical recorded path, on the exact named phase branch, at the base SHA, clean, fingerprintable, and bound to the expected Git common directory and distinct per-worktree Git directory.
- After local creation, repeat the authoritative live remote-absence query for a bound remote, or re-require the complete all-`none` tuple when no remote is bound. Only when every primary, phase, local-ref, Git-identity, fingerprint, and remote postcondition matches may the orchestrator seal the immutable creation record and record local `absent -> <base SHA>` plus remote expected state `absent` or `none`.
- A failed creation postcondition creates only a recovery record from observed facts and a human handoff. Never adopt, remove, retry, or advance expected state automatically.
- A phase-worktree immutable record binds opaque reference, canonical path, owner/category, checkout kind `named branch`, expected full local branch ref, initial full HEAD SHA, Git common directory, per-worktree Git directory, base SHA, stored primary pre-creation fingerprint, credential-free canonical remote identity or `none`, remote name or `none`, full remote ref or `none`, and initial expected remote state `absent` or `none`.
- Resume is not creation. Resume requires owner/category, checkout kind, canonical path, expected branch ref, base SHA, Git common directory, per-worktree Git directory, immutable remote subject tuple, and stored primary fingerprint to equal the immutable record; live local ref and worktree HEAD must equal mutable expected local state and descend from base; authoritative live remote state must equal mutable expected remote state; the primary must be clean at its stored fingerprint; and the phase checkout must be clean and successfully fingerprinted at the exact expected HEAD, with that fresh fingerprint recorded as the resumed execution baseline. Any mismatch hands off.

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
- Execute only the exact human-approved merge. Immediately afterward require the authoritative target ref at the exact reported merge commit, require that commit to have exactly two parents in order with the pre-merge target tip first and exact reviewed phase head second, require both bound commits to be ancestors of it, and record previous/new target states before any local transition.
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
- Cleanup failure keeps the coordination record open and records the opaque reference, branch, owner/category, path privately, observed state, and blocker.
- Worktree mode on with phase branch mode on pre-authorizes compliant named-branch creation and normal worktree removal. Phase branch mode separately authorizes branch creation, local commits, and approved merged-branch cleanup; remote push also requires Push Authorization. Every existing human gate remains.

<!-- BEGIN FOUR EYES ROLE CONTRACTS SOURCE -->
# Four Eyes Role Contracts

This is a compact, derived loading surface for active agents. It is not the definition of Four Eyes and must not be edited independently. Canonical policy remains in `README.md`, `docs/playbook.md`, and `docs/templates.md`. Generate this document from the marked Playbook source with `ruby scripts/check-docs.rb --write-derived`.

## Authority

- Four Eyes is tool-agnostic and manual-first. One orchestrator owns execution and synthesis; reviewers judge independently; the human owns real-risk gates.
- The task context, coordination record, and any reviewed local plan define scope, modes, tier, branch, transport, verification, stop conditions, and the next gated action.
- The orchestrator may escalate review or safety requirements. It must not downgrade a human-selected tier, expand scope, or cross a human gate on its own.
- Shared truth is the coordination record, temporary local plan when one exists, exact repository state, immutable review artifact, and verification evidence. Agent memory is not authoritative.

## Orchestrator

- Own the temporary plan when needed, coordination state, phase boundaries, implementation, verification, reviewer handoff, verdict embargo, synthesis, and closeout.
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
- Human-selected manual Reviewer 2 may use any existing Claude Code session. Prior work or context alone, including historical peer output or synthesis, is not `could-not-review`. Disclose relevant provenance, verify canonical sources rather than prior conclusions, and embargo current-round Reviewer 1 output and synthesis until verdict; current-round exposure is `could-not-review`. Native direct Reviewer 2 remains fresh per request.
- For non-skip work, each current-orchestrator or material current-artifact-author family needs a reviewer from another family unless the human records an override for that uncovered family.

## Tier

- `Skip`: tiny docs, typo, formatting, or simple queue/admin work. Run verification and keep configured branch and merge gates.
- `Light`: routine low-risk reversible work. Use one reviewer satisfying the model-family rule, one initial review, and at most one bounded same-reviewer fix and delta; then escalate.
- `Full`: broad or high-risk work. Use two independent reviewers and bounded fix/re-review. Full is mandatory for security, infrastructure, data/schema, production, deploy, destructive, costly, or irreversible work.
- The human or reviewed plan sets the tier. The orchestrator may escalate but cannot downgrade it.
- Plan and implementation review each stop after three panel rounds unless the human grants more. Defer accepted nits by default; bind approval to the complete artifact and focus normal delta inspection unless semantic risk widens.

## Human Gate

- Human approval remains mandatory for merge to a protected branch; protected-branch push; publish, deploy, or apply; live, cloud, database, production, or other external-system action; external posting outside the assigned coordination record; destructive, costly, privileged, or hard-to-reverse action; scope change; closeout unless already authorized; and any plan-marked gate.
- Phase branch mode may pre-authorize local commits only to the recorded phase branch. Remote push follows Push Authorization: the pre-authorized path requires the authoritative coordination record to say `Remote push: allowed`, and exact human approval remains available.
- PR transport may pre-authorize only bounded operations on the recorded phase PR. It never authorizes merge, unrelated PR changes, or repository settings changes.
- Authorized coordination bookkeeping and local verification do not need repeated human approval.

## Artifact

- Use the canonical artifact and repository commands in the Playbook. Do not invent a shorter hashing recipe.
- PR review binds the positive round, full reviewed head, canonical PR diff SHA-256, and workflow revision. Manual relay binds the round, stage, base, reviewed head, prior head, artifact SHA-256, and workflow revision.
- A manual packet contains the complete reviewable bytes in deterministic length-framed form. A PR reviewer resolves the live forge base and head and reviews the complete merge-base-to-head artifact.
- Capture the canonical repository fingerprint before review and recompute it after review. Reviewer mutation or unexplained drift invalidates the round; the orchestrator never auto-reverts it.
- Any changed artifact invalidates prior approval. Full sends the changed complete artifact to both slots. Light permits only its single bounded same-reviewer delta before escalation.
- Recompute live forge head and artifact immediately before merge. Stale approvals never authorize a changed head.

## Coordination

- Every non-trivial task selects `pr`, `github-issue`, or `local`; the orchestrator alone owns coordination metadata, gates, ledgers, and closeout.
- Use a pull request for single-phase remote work, one GitHub parent ledger for multi-phase or durable blocked work, and a temporary local record only for resumability without forge coordination.
- Record the current gate, next action, round, full workflow revision, artifact identity, verified dependency results, verification, verdicts, nit disposition, and branch or worktree resolution.
- Keep public coordination content brief and sanitized. Never post secrets, raw credentials, private links on public surfaces, raw sensitive logs, absolute local paths, or unrelated task history.

## Branch

- Use one recorded phase branch per independently mergeable phase. Implementation-first work may be committed there before review when phase branch mode authorizes it, and pushed only when Push Authorization permits it.
- With phase branch mode on, default to one owned phase worktree, keep the primary checkout fixed, verify baseline, and remove it before branch deletion; the packet remains the review artifact, only a repo-backed reviewer that creates a detached worktree must remove it before verdict, and the contract has no named integration dependency.
- Review the complete phase artifact before merge. Merge to `main` or another protected branch always remains a human gate.
- Every agent-created phase branch must resolve as merged and deleted, abandoned under its explicit cleanup gate, intentionally kept with owner and revisit trigger, or handed to the human with the blocker recorded.
- Record local and remote tip SHAs before deletion. Divergent tips, unscoped branches, non-workflow PRs, preservation needs, or cleanup side effects require human handoff.

## Loading

- Default orchestrator bootstrap is the task context, Four Eyes Default Workflow, and Four Eyes Role Contracts.
- Load Four Eyes Playbook only for exact policy detail or canonical commands; Templates only to fill an artifact; Coordination Records only for coordination behavior.
- Reviewers receive a filled immutable packet and task evidence. They do not need the workflow-document set unless a disputed rule itself is under review.
- Load every policy surface from one recorded full repository commit SHA. Missing, abbreviated, mixed, or unresolvable revisions hold the gate.
- `docs/role-contracts.md` is generated byte-for-byte from this marked source. Direct edits are invalid.
<!-- END FOUR EYES ROLE CONTRACTS SOURCE -->
