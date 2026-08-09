#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "uri"

module FourEyesDocs
  class CheckError < StandardError; end

  class Checker
    ROLE_BEGIN = "<!-- BEGIN FOUR EYES ROLE CONTRACTS SOURCE -->\n"
    ROLE_END = "<!-- END FOUR EYES ROLE CONTRACTS SOURCE -->"
    RULE_GROUPS = ["Authority", "Orchestrator", "Reviewer", "Tier", "Human Gate", "Artifact", "Coordination", "Branch", "Loading"].freeze
    LOADING_SENTENCE = "Load the task context, Four Eyes Default Workflow, and Four Eyes Role Contracts first. Load Four Eyes Playbook, Templates, or Coordination Records only when the task needs their exact rule, template, or coordination behavior."
    DEFAULT_LOADING_BLOCK = "Default orchestrator bootstrap is:\n\n- the task context\n- Four Eyes Default Workflow\n- Four Eyes Role Contracts\n\n"
    DEFAULT_LOADING_BULLETS = ["- the task context", "- Four Eyes Default Workflow", "- Four Eyes Role Contracts"].freeze
    LOAD_ON_DEMAND_RULE = "Load Four Eyes Playbook only for exact policy detail or canonical commands, Templates only to fill an artifact, and Coordination Records only for coordination behavior. Reviewers receive a filled immutable packet and exact task evidence; they do not need the workflow-document set unless a disputed rule itself is under review."
    ROLE_LOADING_RULE = "- Default orchestrator bootstrap is the task context, Four Eyes Default Workflow, and Four Eyes Role Contracts."
    COORDINATION_LOADING_RULE = "Load the task context, Four Eyes Default Workflow, and Four Eyes Role Contracts by default. Load the Playbook, Templates, or Coordination Records only when their exact policy, template, or coordination behavior is needed. Reviewers receive filled immutable packets and do not need the workflow-document set."
    HANDOFF_MODE_LINE = "Handoff mode: reviewer1-subagent + manual reviewer2 | reviewer1-subagent + direct reviewer2 | manual reviewer1 + manual reviewer2 | manual reviewer1 + direct reviewer2 | manual reviewer2 only | direct reviewer2 only | manual human relay"
    REVIEWER2_HANDOFF_LINE = "Reviewer 2 handoff: manual external reviewer | direct Claude reviewer"
    REVIEWER2_AUTHORIZATION_LINE = "Direct Reviewer 2 authorization: none | human-approved phase + full model + maximum calls + maximum cost"
    REVIEWER2_FIELD_PREFIXES = [
      "Reviewer 2 handoff:",
      "Direct Reviewer 2 authorization:"
    ].freeze
    REVIEWER2_OPTION_LINES = [
      REVIEWER2_HANDOFF_LINE,
      REVIEWER2_AUTHORIZATION_LINE
    ].freeze
    REVIEWER2_FIELD_OCCURRENCES = {
      "README.md" => 1,
      "docs/playbook.md" => 1,
      "docs/templates.md" => 2,
      "docs/coordination-records.md" => 2,
      "examples/task-issue.md" => 1,
      "examples/multi-slice-issues.md" => 2
    }.freeze
    REVIEWER2_OPTION_OCCURRENCES = {
      "README.md" => 1,
      "docs/playbook.md" => 1,
      "docs/templates.md" => 2,
      "docs/coordination-records.md" => 2
    }.freeze
    AUTOMATION_LADDER_LINES = [
      "1. Current baseline: PR transport with human-invoked external reviewers.",
      "2. Current Codex-led default: reused named internal Reviewer 1, human-relayed external Reviewer 2.",
      "3. Optional where the orchestrator platform provides native isolated invocation and the human records the exact phase, full model identity, maximum calls, and maximum cost amount and currency: orchestrator invokes only Reviewer 2 directly.",
      "4. Future: CI-triggered reviewers.",
      "Rung 3 is never globally or orchestrator-authorized; each task or phase requires the recorded human decision and enforceable bounds. Rung 4 is not implemented or pre-authorized."
    ].freeze
    PRE_BOOTSTRAP_COMPONENTS = {
      "README.md#Default Workflow" => 2_630,
      "docs/playbook.md" => 54_802,
      "docs/templates.md" => 25_609,
      "docs/issue-tracker-setup.md" => 8_995
    }.freeze
    PRE_BOOTSTRAP_TOTAL = 92_036
    PRE_BOOTSTRAP_RECORD_RULE = "The reproducible pre-change source bootstrap at revision `225430672fad342d693137254c256ca44f2bd8ef` was 92,036 UTF-8 bytes:"
    POST_BOOTSTRAP_MEMBERS = ["README.md#Default Workflow", "docs/role-contracts.md"].freeze
    POST_BOOTSTRAP_BUDGET = 13_000
    POST_BOOTSTRAP_RECORD_RULE = "The current bootstrap is the README Default Workflow section plus generated Role Contracts. `ruby scripts/check-docs.rb` reports its bytes, savings, and reduction; the current bootstrap must not exceed #{POST_BOOTSTRAP_BUDGET.to_s.reverse.scan(/.{1,3}/).join(",").reverse} bytes."
    COORDINATION_RECORD_LINE = "Coordination record: pr | github-issue | local"
    WORKTREE_MODE_LINE = "Worktree mode: on | off"
    WORKTREE_REFERENCE_LINE = "Worktree reference: none | <ownership-category>/<opaque worktree reference>"
    WORKTREE_FIELD_PREFIXES = ["Worktree mode:", "Worktree reference:"].freeze
    WORKTREE_OPTION_LINES = [WORKTREE_MODE_LINE, WORKTREE_REFERENCE_LINE].freeze
    WORKTREE_FIELD_OCCURRENCES = {
      "docs/playbook.md" => 1,
      "docs/templates.md" => 2,
      "docs/coordination-records.md" => 1,
      "examples/task-issue.md" => 1,
      "examples/multi-slice-issues.md" => 2
    }.freeze
    WORKTREE_OPTION_OCCURRENCES = {
      "docs/playbook.md" => 1,
      "docs/templates.md" => 2,
      "docs/coordination-records.md" => 1
    }.freeze
    WORKTREE_DEFAULT_LINES = [
      "Worktree mode default: on | off",
      "Worktree reference default: none"
    ].freeze
    WORKTREE_SLICE_LINES = [
      "   - worktree mode: inherit | on | off",
      "   - worktree reference: none | <ownership-category>/<opaque worktree reference>"
    ].freeze
    WORKTREE_CLOSEOUT_PREFIXES = [
      "- Reference:",
      "- Owner/category:",
      "- Checkout kind:",
      "- Remote subject:",
      "- Expected/live remote comparison:",
      "- Resolution path:",
      "- Blocker:"
    ].freeze
    WORKTREE_CLOSEOUT_TEMPLATE_LINES = [
      "- Reference: <ownership-category>/<opaque reference>",
      "- Owner/category: <owner/category>",
      "- Checkout kind: named branch | detached",
      "- Remote subject: bound | none",
      "- Expected/live remote comparison: <match | mismatch | none>",
      "- Resolution path: <merged | abandoned | intentionally kept branch | reviewer detached | human handoff>",
      "- Blocker: <none | exact blocker>"
    ].freeze
    PRIVATE_WORKTREE_CLOSEOUT_PREFIXES = [
      "- Canonical path:",
      "- Owner/category and cleanup owner:",
      "- Expected branch/ref or reviewed SHA:",
      "- Git common directory:",
      "- Per-worktree Git directory:",
      "- Base SHA:",
      "- Stored primary fingerprint:",
      "- Remote identity/name/full ref:",
      "- Expected/live remote state:",
      "- Previous/new local expected state:",
      "- Local ref pre-delete check:",
      "- Local ref post-delete check:",
      "- Clean status:",
      "- Removal result:",
      "- Retained-checkout absence check:"
    ].freeze
    PRIVATE_WORKTREE_EVIDENCE_LINES = [
      "- Reference: <ownership-category>/<opaque reference>",
      "- Canonical path: <private absolute path>",
      "- Owner/category and cleanup owner: <owner/category> | <cleanup owner>",
      "- Checkout kind: named branch | detached",
      "- Expected branch/ref or reviewed SHA: <full ref and SHA | detached SHA>",
      "- Git common directory: <private canonical path>",
      "- Per-worktree Git directory: <private canonical path>",
      "- Base SHA: <full SHA | not applicable>",
      "- Stored primary fingerprint: <four-part fingerprint | not applicable>",
      "- Remote identity/name/full ref: <private values | none/none/none>",
      "- Expected/live remote state: <sha/sha | absent/absent | none/none | mismatch>",
      "- Previous/new local expected state: <sha/sha | sha/absent | none>",
      "- Local ref pre-delete check: <exact match | not applicable | failed>",
      "- Local ref post-delete check: <absent | not applicable | failed>",
      "- Clean status: <clean | dirty>",
      "- Removal result: <removed normally | retained | handed off>",
      "- Retained-checkout absence check: <passed | not applicable | failed>",
      "- Resolution path: <merged | abandoned | intentionally kept branch | reviewer detached | human handoff>",
      "- Blocker: <none | exact blocker>"
    ].freeze
    PRIVATE_WORKTREE_EXAMPLE_LINES = [
      [
        "- Reference: phase-execution/EXAMPLE-retry-worktree",
        "- Canonical path: <private canonical phase-worktree path>",
        "- Owner/category and cleanup owner: orchestrator/phase-execution | orchestrator",
        "- Checkout kind: named branch",
        "- Expected branch/ref or reviewed SHA: refs/heads/phase/EXAMPLE-retry-behavior at aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "- Git common directory: <private canonical common Git directory>",
        "- Per-worktree Git directory: <private canonical per-worktree Git directory>",
        "- Base SHA: 1111111111111111111111111111111111111111",
        "- Stored primary fingerprint: HEAD=1111111111111111111111111111111111111111; staged=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855; unstaged=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855; untracked=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        "- Remote identity/name/full ref: example.invalid/four-eyes | origin | refs/heads/phase/EXAMPLE-retry-behavior",
        "- Expected/live remote state: absent/absent",
        "- Previous/new local expected state: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/absent",
        "- Local ref pre-delete check: exact match",
        "- Local ref post-delete check: absent",
        "- Clean status: clean",
        "- Removal result: removed normally",
        "- Retained-checkout absence check: passed",
        "- Resolution path: merged",
        "- Blocker: none"
      ],
      [
        "- Reference: reviewer-verification/EXAMPLE-r2-round-1",
        "- Canonical path: <private canonical reviewer-worktree path>",
        "- Owner/category and cleanup owner: Reviewer 2/reviewer-verification | Reviewer 2",
        "- Checkout kind: detached",
        "- Expected branch/ref or reviewed SHA: 2222222222222222222222222222222222222222",
        "- Git common directory: <private canonical common Git directory>",
        "- Per-worktree Git directory: <private canonical per-worktree Git directory>",
        "- Base SHA: not applicable",
        "- Stored primary fingerprint: not applicable",
        "- Remote identity/name/full ref: none/none/none",
        "- Expected/live remote state: none/none",
        "- Previous/new local expected state: none",
        "- Local ref pre-delete check: not applicable",
        "- Local ref post-delete check: not applicable",
        "- Clean status: clean",
        "- Removal result: removed normally",
        "- Retained-checkout absence check: passed",
        "- Resolution path: reviewer detached",
        "- Blocker: none"
      ]
    ].freeze
    PUBLIC_WORKTREE_RECORD_RULE = "Public coordination records never include worktree paths, usernames, host layout, remote URLs, remote names, full refs, local expected-state transitions, or cleanup diagnostics. Record only the opaque reference, ownership category, checkout kind, remote-subject category, expected/live comparison result, lifecycle path, and blocker if any. Detailed ownership and state transitions stay in private local evidence."
    DEFAULT_WORKTREE_RULE = "5. For each implementation phase, the orchestrator creates a phase branch and dedicated worktree while the primary checkout stays fixed and coordination-only."
    ROLE_WORKTREE_RULE = "- With phase branch mode on, default to one owned phase worktree, keep the primary checkout fixed, verify baseline, and remove it before branch deletion; the packet remains the review artifact, only a repo-backed reviewer that creates a detached worktree must remove it before verdict, and the contract has no named integration dependency."
    WORKTREE_REQUIRED_RULES = [
      "The worktree lifecycle requires no named plugin, skill, marketplace product, or vendor-specific integration.",
      "- `(Phase branch mode: on, Worktree mode: on)` is the default phase-branch path: use one dedicated named-branch worktree and keep the primary checkout coordination-only.",
      "- `(Phase branch mode: off, Worktree mode: off)` preserves the existing primary-checkout execution and uncommitted-review path.",
      "- `(Phase branch mode: on, Worktree mode: off)` requires explicit human approval because it disables collision protection.",
      "- `(Phase branch mode: off, Worktree mode: on)` is invalid.",
      "- A compliant platform mechanism is allowed; otherwise use `git worktree`. Git's own same-branch and path refusals are the mechanical enforcement. Pre-creation inspection records a readable stop reason but does not replace those refusals.",
      "- Never use force to create or remove a worktree. Never remove a worktree automatically before its lifecycle record is complete.",
      "- Prefer a worktree path outside the repository root. A project-local root is allowed only when `git check-ignore -v` exits zero for it and identifies an existing positive repository-specific rule in a tracked repository ignore file or that repository's own Git metadata; a negation or host-global rule is insufficient.",
      "- After creation, recompute the primary-checkout fingerprint. If the fingerprint command fails or its untracked digest changes, the worktree location is non-compliant.",
      "- Absolute paths, usernames, host layout, remote URLs, remote names, full refs, local expected-state transitions, and cleanup diagnostics stay in local or private evidence. Public surfaces carry only the opaque worktree reference, ownership category, checkout kind, remote-subject category, expected/live comparison result, lifecycle path, and blocker.",
      "- Concurrent worktrees provide filesystem isolation, not semantic independence. Use the existing parent/child dependency record to declare whether phases may run concurrently.",
      "- Before fresh creation, require the primary checkout on the recorded base branch at the stored base SHA, clean under `git status --porcelain=v1 --untracked-files=all`, and equal to its canonical stored fingerprint.",
      "- Before fresh creation, require `git worktree list --porcelain` to show no conflicting path or checkout and require the full local phase ref absent. When a remote subject is bound, require an authoritative live query to report the full remote phase ref absent; when no remote is bound, require remote subject, name, full ref, expected state, and live state all to be `none`.",
      "- Create the named phase branch and worktree together from the exact base without force. The primary checkout stays on the base branch and performs no phase implementation.",
      "- Before sealing ownership, require the primary branch, HEAD, cleanliness, and fingerprint to remain exactly unchanged.",
      "- Before sealing ownership, require the phase worktree at the canonical recorded path, on the exact named phase branch, at the base SHA, clean, fingerprintable, and bound to the expected Git common directory and distinct per-worktree Git directory.",
      "- After local creation, repeat the authoritative live remote-absence query for a bound remote, or re-require the complete all-`none` tuple when no remote is bound. Only when every primary, phase, local-ref, Git-identity, fingerprint, and remote postcondition matches may the orchestrator seal the immutable creation record and record local `absent -> <base SHA>` plus remote expected state `absent` or `none`.",
      "- A failed creation postcondition creates only a recovery record from observed facts and a human handoff. Never adopt, remove, retry, or advance expected state automatically.",
      "- A phase-worktree immutable record binds opaque reference, canonical path, owner/category, checkout kind `named branch`, expected full local branch ref, initial full HEAD SHA, Git common directory, per-worktree Git directory, base SHA, stored primary pre-creation fingerprint, credential-free canonical remote identity or `none`, remote name or `none`, full remote ref or `none`, and initial expected remote state `absent` or `none`.",
      "- Resume is not creation. Resume requires owner/category, checkout kind, canonical path, expected branch ref, base SHA, Git common directory, per-worktree Git directory, immutable remote subject tuple, and stored primary fingerprint to equal the immutable record; live local ref and worktree HEAD must equal mutable expected local state and descend from base; authoritative live remote state must equal mutable expected remote state; the primary must be clean at its stored fingerprint; and the phase checkout must be clean and successfully fingerprinted at the exact expected HEAD, with that fresh fingerprint recorded as the resumed execution baseline. Any mismatch hands off.",
      "- Before edits, run only the repository's documented setup and verification commands in the phase worktree and record exact results. Never run a generic dependency installer automatically.",
      "- If the repository documents no verification command, the reviewed plan must define one or explicitly record that no baseline is available.",
      "- A failing baseline proceeds only after the human accepts the exact command, bounded failure signature, and impact. A plan-authored acceptance alone is insufficient.",
      "- Immediately before every authorized commit, require the exact full phase ref and expected local SHA. Afterward, require the same branch, a different new SHA that descends from both the previous expected SHA and immutable base, then record previous/new values and advance expected local state.",
      "- A missing, premature, unauthorized, unchanged, or non-descendant local-ref transition hands off and is never absorbed.",
      "- The immutable remote subject uniquely keys every remote comparison. When it is `none`, remote name, full ref, expected state, and live state must all be `none`.",
      "- Obtain authoritative remote state from a live query to the exact remote or forge subject, never from remote-tracking refs alone.",
      "- Before every authorized push or remote deletion, require authoritative live state to equal expected state. Freeze the expected local tip as a push's intended remote SHA.",
      "- After every authorized push or remote deletion, query the same subject again and require the intended exact new state before recording previous/new values or advancing expected remote state.",
      "- Any remote subject, pre-transition, or post-transition mismatch hands off and is never absorbed.",
      "- Creation, resume, review dispatch, local or remote transition, and cleanup compare authoritative live state with expected state. Unexpected advance, deletion, appearance, subject change, or ref change hands off.",
      "- Reviewer worktrees are optional and apply only to a repo-backed reviewer of a commit-bound `(Phase branch mode: on, Worktree mode: on)` implementation artifact that needs local execution.",
      "- A plan, packet-only, forge-only, no-repo, or `(off, off)` uncommitted reviewer has no worktree obligation and inspects the immutable supplied artifact directly.",
      "- The immutable packet or forge artifact, never a mutable worktree, is the source of reviewed bytes.",
      "- A reviewer-created worktree uses a distinct throwaway detached checkout at the exact reviewed SHA and records opaque reference, canonical path, reviewer owner, cleanup owner, checkout kind `detached`, reviewed SHA, Git common directory, and per-worktree Git directory. All remote fields are `none`.",
      "- A reviewer-created worktree follows the same compliant-location and ownership rules as a phase worktree.",
      "- A reviewer that creates a worktree must require detached HEAD at the exact SHA, work read-only, record clean status, remove it normally, and verify its exact path absent from `git worktree list --porcelain` from a retained checkout before returning a verdict.",
      "- Dirty reviewer state or failed cleanup returns `Review status: could-not-review` with `Verdict: not issued`; any drafted judgment is non-counting evidence. A reviewer that created no worktree has no cleanup obligation. Only the orchestrator records `error` or `timeout` when no response can be obtained.",
      "- Worktree removal and branch resolution are separate. Resolve every phase worktree as merged, abandoned, intentionally kept branch, or human handoff. Remove the owned worktree before deleting its branch.",
      "- Before requesting merge approval, bind the credential-free target repository identity, full target ref, exact live target tip, exact reviewed phase head, canonical reviewed-artifact digest, intended target, and merge strategy.",
      "- Immediately before an approved forge merge, re-query the exact target and artifact and require all bound identities and approvals unchanged. Also require the primary checkout still on its stored base branch and SHA, clean, at its stored fingerprint, with that base an ancestor of the live target tip.",
      "- Execute only the exact human-approved merge. Immediately afterward require the authoritative target ref at the exact reported merge commit, require that commit to have exactly two parents in order with the pre-merge target tip first and exact reviewed phase head second, require both bound commits to be ancestors of it, and record previous/new target states before any local transition.",
      "- Before changing the primary checkout, re-require its stored branch, SHA, cleanliness, and fingerprint and require its base SHA to be an ancestor of the verified merge commit.",
      "- Only exact closeout authorization permits a fast-forward-only move of the primary target branch directly to the verified merge commit. Never create another merge, rebase, reset, force, or move to a later target tip.",
      "- After the primary fast-forward, require the exact target branch and merge-commit HEAD, clean state, and successful new fingerprint before recording the new coordination base and running post-merge verification there.",
      "- Merged cleanup requires complete ownership, expected cleanup HEAD equal to the latest approved reviewed head and local tip, applicable authoritative remote equality or expected absence, clean status, and verified merge ancestry.",
      "- For merged cleanup, record state; exit the worktree; remove it normally without force; verify its exact path absent from `git worktree list --porcelain` from a retained checkout; then apply the existing merged branch cleanup rule.",
      "- Before authorized local phase-ref deletion, require the worktree absent and the full local ref equal to expected local state. After deletion, require the ref absent before recording previous/new state and advancing expected local state to `absent`.",
      "- Before authorized remote branch deletion, require authoritative live state equal to the expected exact SHA. Afterward, require the exact ref absent before recording previous/new state and advancing expected remote state to `absent`.",
      "- Independently verified forge auto-deletion is accepted only when evidence binds the exact expected ref and SHA and a live query confirms absence; then record `absent` without issuing a deletion command.",
      "- Remote deletion is not lease-protected because force variants are prohibited. The bounded control is a workflow-owned branch with unauthorized concurrent pushes plus exact pre-transition and post-transition live checks.",
      "- Abandoned cleanup requires complete ownership, applicable expected state, authoritative local and remote state, PR state, cleanliness, and preservation need. Dirty, divergent, changed, unowned, or preservation-needed state hands off.",
      "- A clean abandoned worktree is removed and verified absent before the PR and branch are resolved under `Abandoned branch cleanup`. No approved reviewed head or remote SHA is required when its expected state is `absent`.",
      "- An intentionally kept branch still requires complete ownership, exact retained local expected SHA, authoritative remote state, clean status, branch tips, reason, next owner, and revisit trigger. Remove and verify the worktree while leaving branch, expected local SHA, remote state, and PR unchanged.",
      "- Never run `git worktree prune` in the normal lifecycle. A stale entry is an out-of-band, human-gated repair.",
      "- Cleanup removes only the exact path in the ownership record and only when its live branch or detached SHA matches that record. Never remove another agent's worktree.",
      "- Cleanup failure keeps the issue open and records the opaque reference, branch, owner/category, path privately, observed state, and blocker.",
      "- Worktree mode on with phase branch mode on pre-authorizes compliant named-branch creation and normal worktree removal. Phase branch mode separately authorizes branch creation, commits, allowed pushes, and approved merged-branch cleanup. Every existing human gate remains."
    ].freeze
    COORDINATION_FIELD_OCCURRENCES = {
      "README.md" => 1,
      "docs/templates.md" => 2,
      "docs/coordination-records.md" => 1,
      "examples/task-issue.md" => 1,
      "examples/multi-slice-issues.md" => 2,
      "examples/closeout.md" => 1
    }.freeze
    COORDINATION_OPTION_OCCURRENCES = {
      "README.md" => 1,
      "docs/templates.md" => 2,
      "docs/coordination-records.md" => 1
    }.freeze
    COORDINATION_REQUIRED_RULES = [
      "1. Every non-trivial task records `Coordination record: pr | github-issue | local`.",
      "2. `pr` is the default for single-phase remote work; the pull request is the coordination record once it exists.",
      "3. `github-issue` uses exactly one parent issue carrying a compact phase ledger for multi-phase work or durable blockers.",
      "4. `local` is the no-forge fallback; it provides resumability, not permanent audit. Work needing durable history uses `pr` or `github-issue`.",
      "5. Before the pull request exists, `pr` mode keeps a temporary local execution-state record at the recorded canonical path.",
      "6. When the pull request opens, copy the execution-state content into it, verify the copy landed and matches, and only then treat the pull request as authoritative. Until that verification passes, the local record remains authoritative.",
      "7. Reviewers may submit verdicts through the selected review transport, including pull request reviews. A direct pull request verdict may change forge review status; it never changes the Four Eyes gate, ledger status, or closeout metadata. Reviewers never edit coordination metadata, status, the phase ledger, or closeout. The orchestrator owns every coordination update.",
      "8. Promote `pr` to `github-issue` when a second phase becomes committed, when a dependency or blocker exists outside the current pull request, or when deferred work must survive the current pull request's closeout. Continuing a single-phase pull request across sessions is not a promotion trigger.",
      "9. Promotion is check-act-verify-record: create the parent issue carrying the plan digest, phase ledger, current pull request, dependencies, and current gate; verify the issue content matches what was written; backlink the pull request to the issue; and switch authority to the parent issue only after both records agree. Any mismatch stops and hands off.",
      "10. Multi-phase work uses one parent ledger. Do not create a child issue for each committed execution slice.",
      "11. Create child issues only for independently owned, externally blocked, or durable follow-up work.",
      "12. Selecting `Coordination record: github-issue` pre-authorizes creating, updating, and closing exactly one parent coordination issue plus explicitly accepted durable follow-ups. It authorizes no unrelated issue operations.",
      "13. The parent ledger uses the fixed columns `Phase | Depends on | Status | Branch/PR | Gate | Next action`.",
      "14. Ledger status values are `todo`, `ready`, `in progress`, `review`, `waiting external eval`, `blocked`, and one terminal value.",
      "15. `waiting external eval` is not terminal. A phase whose dependencies are all terminal may proceed regardless of any unrelated phase waiting on external evaluation; a phase that depends on a waiting phase stays unready.",
      "16. A phase becomes `ready` only when every phase it depends on is terminal.",
      "17. Terminal values are `merged`, `completed`, `abandoned`, `retained`, and `handed off`. `blocked` is never terminal, and any failed cleanup remains `blocked`.",
      "18. `merged` requires the pull request merged and the reviewed head ancestral to the target.",
      "19. `completed` is the successful terminal value for work producing no merge, such as `local` mode. It requires the recorded verification evidence present and the working tree clean.",
      "20. `abandoned` requires authoritative local and remote tip equality, closure of any applicable pull request, clean worktree removal, resolved branches, and a recorded reason and tip SHA.",
      "21. `retained` requires resolved branch and worktree state plus recorded tip SHA, owner, and revisit trigger.",
      "22. `handed off` requires a recorded blocker, owner, next action, and recorded human acceptance of ownership. Without recorded acceptance the phase stays `blocked`.",
      "23. Record closeout evidence in the coordination record and verify it landed before removing any temporary plan or local state record.",
      "24. In `pr` mode, post the final closeout record to the pull request before removing the temporary plan and execution-state record.",
      "25. Parent completion requires every phase terminal, with each claimed resolution verified against real Git or forge state rather than the ledger's own claim."
    ].freeze
    LOCAL_RECORD_REQUIRED_RULES = [
      "1. The execution-state record lives at one canonical gitignored path recorded in the task's bound state, rooted in the primary coordination checkout.",
      "2. It belongs to the primary checkout and therefore survives phase-worktree removal; never place it inside a phase worktree.",
      "3. Before use, require it to be a regular file and not a symlink.",
      "4. It records the workflow revision, the plan digest it is bound to, the phase ledger, the current gate, and the next action.",
      "5. Its content is public-safe from creation, because `pr` mode copies it into the pull request. Never write absolute paths, usernames, host directory layout, credentials, or private identifiers into it.",
      "6. A workflow-revision or plan-digest mismatch holds the gate; it is never silently rebound.",
      "7. Write it atomically, then read it back and require the readback to match what was written.",
      "8. It survives the entire parent workflow and is removed only after every phase is terminal and closeout is verified.",
      "9. Verify its absence after removal, from a checkout that still exists."
    ].freeze
    REVISION_LOADING_REQUIRED_RULES = [
      "1. Workflow policy loads from this repository at one recorded full commit SHA.",
      "2. Resolve the recorded SHA to an exact commit before loading, and load policy surfaces from that commit rather than from mutable working-tree files.",
      "3. A missing, abbreviated, mixed, or unresolvable revision holds the gate.",
      "4. The workflow revision is the full repository commit SHA carried by coordination records, packets, and verdicts.",
      "5. External document synchronization, source-body markers, readback checks, and a standing synchronization issue are not required."
    ].freeze
    FIELD_PREFIXES = [
      "Handoff mode:",
      "Review tier:",
      "Autonomy mode:",
      "Phase branch mode:",
      "Phase branch flow:",
      "Review transport:",
      "Coordination record:",
      "Reviewer 1 handoff:",
      "Reviewer 2 handoff:",
      "Direct Reviewer 2 authorization:",
      "Base branch:",
      "Phase branch:",
      "Worktree mode:",
      "Worktree reference:",
      "Remote push:",
      "Merge target:",
      "Post-merge branch cleanup:",
      "Abandoned branch cleanup:"
    ].freeze
    STALE_PHRASES = [
      "Read the existing Four Eyes Default Workflow, Playbook, Templates, and Issue Tracker Setup in Linear first.",
      "Until document markers exist",
      "Until document-level revision markers exist",
      "Until synced documents carry their own revision markers",
      "from latest successful sync note",
      "workflow revision from the standing workflow-doc sync note",
      "latest successful sync note in the standing workflow-doc tracker issue is authoritative",
      "four runtime documents",
      "five documents total",
      "all six payloads byte-exact",
      "six successful byte comparisons",
      "compare every byte with the generated expected payload",
      "This proves stable Linear serialization, not source-body byte preservation.",
      "launch only the isolated internal Reviewer 1 subagent. Return every external reviewer prompt to the human for relay.",
      "External Reviewer 2 starts as a fresh session for the parent workflow unless the human explicitly chooses otherwise",
      "direct Claude adapter",
      "Claude adapter status:",
      "Claude contract manifest SHA-256:",
      "Claude Reviewer 2 Adapter",
      "scripts/claude-reviewer2.rb",
      "scripts/check-claude-reviewer2.rb",
      "schemas/reviewer-verdict.schema.json",
      "adapter terminal record",
      "unless explicitly instructed to comment in the tracker",
      "Do not post to the tracker unless explicitly instructed.",
      "unless explicitly instructed to post to the tracker",
      "Do not post to Linear or another tracker unless explicitly instructed.",
      "Do not post directly to the tracker unless explicitly instructed."
    ].freeze
    RETIRED_POLICY_PATTERNS = [
      /\bLinear\b/i,
      /synced workflow document/i,
      /sync payload/i,
      /standing workflow-doc/i,
      /one child issue for every/i,
      /phase child issue/i
    ].freeze

    attr_reader :root

    def initialize(root, bootstrap_members: POST_BOOTSTRAP_MEMBERS)
      @root = File.expand_path(root)
      @bootstrap_members = bootstrap_members
    end

    def check!
      check_derived!
      check_rule_groups!
      report = check_bootstrap!
      check_loading_prompts!
      check_field_order!
      check_reviewer2_handoff!
      check_coordination_contract!
      check_worktree_contract!
      check_links!
      check_stale_phrases!
      check_retired_policy!
      report
    end

    def write_derived!
      File.binwrite(path("docs/role-contracts.md"), role_contracts_source)
    end

    def canonical_body(bytes, label = "source body")
      normalize_text(bytes, label).sub(/\n*\z/, "") + "\n"
    end

    def normalize_text(bytes, label = "source body")
      value = bytes.dup.force_encoding(Encoding::UTF_8)
      fail_check("#{label}: invalid UTF-8") unless value.valid_encoding?
      fail_check("#{label}: NUL byte") if value.include?("\0")

      value = value.gsub("\r\n", "\n")
      fail_check("#{label}: bare CR") if value.include?("\r")
      value
    end

    private

    def path(relative)
      File.join(root, relative)
    end

    def read(relative)
      File.binread(path(relative))
    rescue Errno::ENOENT
      fail_check("missing file: #{relative}")
    end

    def normalized_read(relative)
      normalize_text(read(relative), relative)
    end

    def role_contracts_source
      playbook = normalized_read("docs/playbook.md")
      unless playbook.scan(ROLE_BEGIN).length == 1 && playbook.scan(ROLE_END).length == 1
        fail_check("marked Role Contracts source missing or malformed")
      end
      start = playbook.index(ROLE_BEGIN)
      finish = start && playbook.index(ROLE_END, start + ROLE_BEGIN.length)
      fail_check("marked Role Contracts source missing or malformed") unless start && finish

      body = playbook[(start + ROLE_BEGIN.length)...finish]
      fail_check("marked Role Contracts source is not canonical") unless canonical_body(body, "Role Contracts source") == body
      body
    end

    def default_workflow_source
      default_workflow_source_from(read("README.md"), "README.md")
    end

    def default_workflow_source_from(bytes, label)
      readme = normalize_text(bytes, label)
      headings = level_two_headings(readme)
      matches = headings.select { |_position, identity| identity == "Default Workflow" }
      fail_check("README Default Workflow section missing or duplicated") unless matches.length == 1

      start = matches.first.first
      finish = headings.map(&:first).find { |position| position > start } || readme.length
      readme[start...finish]
    end

    def check_derived!
      expected = role_contracts_source
      actual = normalized_read("docs/role-contracts.md")
      fail_check("generated Role Contracts differ from marked Playbook source") unless actual == expected
    end

    def check_rule_groups!
      contract = normalized_read("docs/role-contracts.md")
      headings = level_two_headings(contract)
      positions = RULE_GROUPS.map do |group|
        matches = heading_positions(contract, "## #{group}")
        fail_check("missing role-contract rule group: #{group}") unless matches.length == 1
        matches.first
      end
      fail_check("role-contract rule group order mismatch") unless positions == positions.sort

      RULE_GROUPS.each_with_index do |group, index|
        start = positions[index]
        finish = headings.map(&:first).find { |position| position > start } || contract.length
        body = contract[start...finish]
        operative_bullet = markdown_lines(body).any? do |entry|
          entry[:context] == :prose && entry[:line].start_with?("- ")
        end
        fail_check("empty role-contract rule group: #{group}") unless operative_bullet
      end
    end

    def check_bootstrap!
      fail_check("bootstrap membership mismatch") unless @bootstrap_members == POST_BOOTSTRAP_MEMBERS
      fail_check("pre-change bootstrap total mismatch") unless PRE_BOOTSTRAP_COMPONENTS.values.sum == PRE_BOOTSTRAP_TOTAL

      readme = normalized_read("README.md")
      context_budget = section(readme, "## Context Budget", "## Source Of Truth")
      PRE_BOOTSTRAP_COMPONENTS.each do |name, bytes|
        display_name = name == "README.md#Default Workflow" ? "README Default Workflow section" : "complete #{File.basename(name, ".md").split("-").map(&:capitalize).join(" ")}"
        expected = "- #{display_name}: #{bytes.to_s.reverse.scan(/.{1,3}/).join(",").reverse} bytes"
        require_unique_operative_line_in_section!(readme, context_budget, expected, "pre-change bootstrap record missing: #{name}")
      end
      require_unique_operative_line_in_section!(readme, context_budget, PRE_BOOTSTRAP_RECORD_RULE, "pre-change bootstrap total record missing")
      require_unique_operative_line_in_section!(readme, context_budget, POST_BOOTSTRAP_RECORD_RULE, "current bootstrap budget record missing")

      post_bytes = default_workflow_source.bytesize + normalized_read("docs/role-contracts.md").bytesize
      fail_check("bootstrap byte budget exceeded: #{post_bytes} > #{POST_BOOTSTRAP_BUDGET}") if post_bytes > POST_BOOTSTRAP_BUDGET
      saved = PRE_BOOTSTRAP_TOTAL - post_bytes
      {
        before: PRE_BOOTSTRAP_TOTAL,
        after: post_bytes,
        saved: saved,
        reduction: (saved.to_f * 100 / PRE_BOOTSTRAP_TOTAL)
      }
    end

    def check_loading_prompts!
      readme = normalized_read("README.md")
      readme_section = section(readme, "## Run Your First Review", "## Example Agent Mix")
      readme_prompt = unique_text_prompt(readme_section, "orchestrator loading prompt mismatch in README.md")
      require_unique_line_in_section!(readme, readme_prompt, LOADING_SENTENCE, "orchestrator loading prompt mismatch in README.md")

      templates = normalized_read("docs/templates.md")
      orchestrator_section = section(templates, "## New Orchestrator Prompt", "## Local Plan Template")
      orchestrator_prompt = unique_text_prompt(orchestrator_section, "orchestrator loading prompt mismatch in docs/templates.md")
      require_unique_line_in_section!(templates, orchestrator_prompt, LOADING_SENTENCE, "orchestrator loading prompt mismatch in docs/templates.md")

      loading = section(readme, "## Loading", "## Context Budget")
      load_rule_starts = operative_line_positions(loading, "Default orchestrator bootstrap is:")
      load_rule_finishes = operative_line_positions(loading, LOAD_ON_DEMAND_RULE)
      fail_check("default loading instructions mismatch") unless load_rule_starts.length == 1 && load_rule_finishes.length == 1
      bootstrap_region = loading[load_rule_starts.first...load_rule_finishes.first]
      loading_bullets = bootstrap_region.lines.map(&:chomp).select { |line| line.start_with?("- ") }
      fail_check("default loading instructions mismatch") unless bootstrap_region == DEFAULT_LOADING_BLOCK && loading_bullets == DEFAULT_LOADING_BULLETS
      require_unique_operative_line_in_section!(readme, loading, LOAD_ON_DEMAND_RULE, "default loading instructions mismatch")

      role_contracts = normalized_read("docs/role-contracts.md")
      role_loading = section(role_contracts, "## Loading")
      require_unique_operative_line_in_section!(role_contracts, role_loading, ROLE_LOADING_RULE, "role-contract loading instructions mismatch")

      coordination = normalized_read("docs/coordination-records.md")
      coordination_loading = section(coordination, "## Recommended Record Shape", "## Autonomy Mode")
      require_unique_operative_line_in_section!(coordination, coordination_loading, COORDINATION_LOADING_RULE, "coordination loading instructions mismatch")
    end

    def check_field_order!
      templates = normalized_read("docs/templates.md")
      new_section = section(templates, "## New Orchestrator Prompt", "## Local Plan Template")
      task_issue_section = section(templates, "## Task Issue Template", "## Reviewer Prompt")
      new_prompt = unique_text_prompt(new_section, "workflow field template mismatch")
      task_issue = unique_text_prompt(task_issue_section, "workflow field template mismatch")
      expected_lines = workflow_field_lines(new_prompt)
      actual_lines = workflow_field_lines(task_issue)
      fail_check("workflow field order mismatch") unless expected_lines == actual_lines
    end

    def workflow_field_lines(content)
      positions = FIELD_PREFIXES.map do |prefix|
        matches = []
        content.scan(/^#{Regexp.escape(prefix)}.*$/) do
          match = Regexp.last_match
          matches << [match.begin(0), match[0]]
        end
        fail_check("workflow field missing: #{prefix}") if matches.empty?
        fail_check("workflow field occurrence mismatch: #{prefix}") unless matches.length == 1
        matches.first
      end
      fail_check("workflow field order mismatch") unless positions.map(&:first) == positions.map(&:first).sort
      positions.map(&:last)
    end

    def check_reviewer2_handoff!
      occurrences = Hash.new(0)
      option_occurrences = Hash.new(0)
      markdown_paths.each do |relative|
        lines = normalized_read(relative).lines.map(&:chomp)
        lines.each_with_index do |line, index|
          if line.start_with?("Handoff mode:") && line.include?("|")
            fail_check("handoff mode options mismatch in #{relative}") unless line == HANDOFF_MODE_LINE
          end
          next unless line.start_with?(REVIEWER2_FIELD_PREFIXES.first)

          occurrences[relative] += 1
          block = lines[index, REVIEWER2_FIELD_PREFIXES.length]
          unless block&.length == REVIEWER2_FIELD_PREFIXES.length &&
              REVIEWER2_FIELD_PREFIXES.zip(block).all? { |prefix, value| value.start_with?(prefix) }
            fail_check("Reviewer 2 field block mismatch in #{relative}")
          end
          option_occurrences[relative] += 1 if block == REVIEWER2_OPTION_LINES
          if line.include?("|") && block != REVIEWER2_OPTION_LINES
            fail_check("Reviewer 2 option block mismatch in #{relative}")
          end
        end
      end

      REVIEWER2_FIELD_OCCURRENCES.each do |relative, expected|
        actual = occurrences.fetch(relative, 0)
        fail_check("Reviewer 2 field occurrence mismatch in #{relative}") unless actual == expected
      end
      REVIEWER2_OPTION_OCCURRENCES.each do |relative, expected|
        actual = option_occurrences.fetch(relative, 0)
        fail_check("Reviewer 2 option occurrence mismatch in #{relative}") unless actual == expected
      end

      playbook = normalized_read("docs/playbook.md")
      ladder = section(playbook, "## Review Transport", "## Review Tier")
      AUTOMATION_LADDER_LINES.each do |line|
        require_unique_operative_line_in_section!(playbook, ladder, line, "automation ladder mismatch")
      end
    end

    def check_coordination_contract!
      occurrences = Hash.new(0)
      option_occurrences = Hash.new(0)
      markdown_paths.each do |relative|
        normalized_read(relative).lines.each do |line|
          value = line.chomp
          next unless value.start_with?("Coordination record:")

          fail_check("unexpected coordination field occurrence in #{relative}") unless COORDINATION_FIELD_OCCURRENCES.key?(relative)
          occurrences[relative] += 1
          option_occurrences[relative] += 1 if value == COORDINATION_RECORD_LINE
          next if value == COORDINATION_RECORD_LINE

          selected = value.delete_prefix("Coordination record: ")
          fail_check("invalid selected coordination record in #{relative}") unless %w[pr github-issue local].include?(selected)
        end
      end

      COORDINATION_FIELD_OCCURRENCES.each do |relative, expected|
        fail_check("coordination field occurrence mismatch in #{relative}") unless occurrences.fetch(relative, 0) == expected
      end
      COORDINATION_OPTION_OCCURRENCES.each do |relative, expected|
        fail_check("coordination option occurrence mismatch in #{relative}") unless option_occurrences.fetch(relative, 0) == expected
      end

      playbook = normalized_read("docs/playbook.md")
      check_exact_rule_section!(playbook, "## Coordination Record Contract", "## Local Coordination Record", COORDINATION_REQUIRED_RULES, "coordination record")
      check_exact_rule_section!(playbook, "## Local Coordination Record", "## Repository Revision Loading", LOCAL_RECORD_REQUIRED_RULES, "local coordination record")
      check_exact_rule_section!(playbook, "## Repository Revision Loading", "## Right-Sizing Slices", REVISION_LOADING_REQUIRED_RULES, "repository revision loading")
    end

    def check_exact_rule_section!(content, start_heading, end_heading, expected, label)
      bounded = section(content, start_heading, end_heading)
      actual = markdown_lines(bounded).each_with_object([]) do |entry, rules|
        line = entry[:line]
        rules << line if entry[:context] == :prose && line.match?(/\A\d+\. /)
      end
      fail_check("#{label} rules mismatch") unless actual == expected
    end

    def check_worktree_contract!
      occurrences = Hash.new(0)
      option_occurrences = Hash.new(0)
      markdown_paths.each do |relative|
        lines = normalized_read(relative).lines.map(&:chomp)
        lines.each_with_index do |line, index|
          next unless line.start_with?(WORKTREE_FIELD_PREFIXES.first)

          fail_check("unexpected worktree field occurrence in #{relative}") unless WORKTREE_FIELD_OCCURRENCES.key?(relative)
          occurrences[relative] += 1
          block = lines[index, WORKTREE_FIELD_PREFIXES.length]
          unless block&.length == WORKTREE_FIELD_PREFIXES.length &&
              WORKTREE_FIELD_PREFIXES.zip(block).all? { |prefix, value| value.start_with?(prefix) }
            fail_check("worktree field block mismatch in #{relative}")
          end
          fail_check("worktree field anchor mismatch in #{relative}") unless index.positive? && lines[index - 1].start_with?("Phase branch:")
          fail_check("worktree field anchor mismatch in #{relative}") unless lines[index + WORKTREE_FIELD_PREFIXES.length]&.start_with?("Remote push:")
          option_occurrences[relative] += 1 if block == WORKTREE_OPTION_LINES
          if line.include?("|") && block != WORKTREE_OPTION_LINES
            fail_check("worktree option block mismatch in #{relative}")
          end
          next if block == WORKTREE_OPTION_LINES

          mode = block.fetch(0).delete_prefix("Worktree mode: ")
          reference = block.fetch(1).delete_prefix("Worktree reference: ")
          fail_check("invalid selected worktree mode in #{relative}") unless %w[on off].include?(mode)
          unless reference == "none" || reference.match?(/\A[a-z0-9][a-z0-9-]*\/[A-Za-z0-9][A-Za-z0-9._-]*\z/)
            fail_check("invalid selected worktree reference in #{relative}")
          end
          phase_branch = lines[index - 1].delete_prefix("Phase branch: ")
          phase_mode_line = lines[0...index].reverse.find { |candidate| candidate.start_with?("Phase branch mode:") }
          fail_check("selected worktree mode lacks phase mode in #{relative}") unless phase_mode_line
          phase_mode = phase_mode_line.delete_prefix("Phase branch mode: ")
          unless %w[on off].include?(phase_mode) && !(phase_mode == "off" && mode == "on")
            fail_check("invalid phase/worktree mode combination in #{relative}")
          end
          fail_check("worktree-off reference mismatch in #{relative}") if mode == "off" && reference != "none"
          if phase_branch == "none"
            fail_check("non-executable worktree reference mismatch in #{relative}") unless reference == "none"
          elsif mode == "on"
            fail_check("executable worktree reference missing in #{relative}") if reference == "none"
          end
        end
      end

      WORKTREE_FIELD_OCCURRENCES.each do |relative, expected|
        fail_check("worktree field occurrence mismatch in #{relative}") unless occurrences.fetch(relative, 0) == expected
      end
      unexpected = occurrences.keys - WORKTREE_FIELD_OCCURRENCES.keys
      fail_check("unexpected worktree field occurrence in #{unexpected.first}") unless unexpected.empty?
      WORKTREE_OPTION_OCCURRENCES.each do |relative, expected|
        fail_check("worktree option occurrence mismatch in #{relative}") unless option_occurrences.fetch(relative, 0) == expected
      end

      templates = normalized_read("docs/templates.md")
      local_plan = section(templates, "## Local Plan Template", "## Task Issue Template")
      WORKTREE_DEFAULT_LINES.each do |line|
        require_unique_line_in_section!(templates, local_plan, line, "worktree default field mismatch")
        total = markdown_paths.sum { |relative| normalized_read(relative).lines.count { |candidate| candidate.chomp == line } }
        fail_check("worktree default field occurrence mismatch") unless total == 1
      end
      WORKTREE_SLICE_LINES.each do |line|
        require_unique_line_in_section!(templates, local_plan, line, "worktree slice field mismatch")
        total = markdown_paths.sum { |relative| normalized_read(relative).lines.count { |candidate| candidate.chomp == line } }
        fail_check("worktree slice field occurrence mismatch") unless total == 1
      end
      default_positions = WORKTREE_DEFAULT_LINES.map { |line| local_plan.index(line) }
      slice_positions = WORKTREE_SLICE_LINES.map { |line| local_plan.index(line) }
      fail_check("worktree default field order mismatch") unless default_positions == default_positions.sort
      fail_check("worktree slice field order mismatch") unless slice_positions == slice_positions.sort

      playbook = normalized_read("docs/playbook.md")
      lifecycle_starts = heading_positions(playbook, "## Worktree Lifecycle")
      fail_check("worktree lifecycle section missing or duplicated") unless lifecycle_starts.length == 1
      lifecycle_start = lifecycle_starts.first
      lifecycle_finish = playbook.index(ROLE_BEGIN, lifecycle_start)
      fail_check("worktree lifecycle section boundary missing") unless lifecycle_finish
      lifecycle = playbook[lifecycle_start...lifecycle_finish]
      WORKTREE_REQUIRED_RULES.each do |line|
        require_unique_operative_line_in_section!(playbook, lifecycle, line, "worktree lifecycle rule missing")
      end
      actual_rules = lifecycle.lines.map(&:chomp).each_with_object([]) do |line, rules|
        next if line.empty? || line.match?(/\A\#{1,6}(?:[ \t]|\z)/)

        rules << line
      end
      fail_check("unchecked worktree lifecycle rule") unless actual_rules == WORKTREE_REQUIRED_RULES

      readme = normalized_read("README.md")
      default_workflow = default_workflow_source
      require_unique_operative_line_in_section!(readme, default_workflow, DEFAULT_WORKTREE_RULE, "default workflow worktree rule missing")

      role_contracts = normalized_read("docs/role-contracts.md")
      branch = section(role_contracts, "## Branch", "## Loading")
      require_unique_operative_line_in_section!(role_contracts, branch, ROLE_WORKTREE_RULE, "role-contract worktree rule missing")

      closeout = normalized_read("examples/closeout.md")
      private_example_start = closeout.index("## Private Lifecycle Evidence Example")
      fail_check("private worktree evidence example missing") unless private_example_start
      public_closeout = closeout[0...private_example_start]
      check_worktree_closeout_examples!(public_closeout)

      closeout_template = section(templates, "## Closeout", "## Private Worktree Lifecycle Evidence")
      template_lines = closeout_template.lines.map(&:chomp)
      template_start = template_lines.index(WORKTREE_CLOSEOUT_TEMPLATE_LINES.first)
      fail_check("worktree closeout template field mismatch") unless template_start
      template_block = template_lines[template_start, WORKTREE_CLOSEOUT_TEMPLATE_LINES.length]
      fail_check("worktree closeout template field mismatch") unless template_block == WORKTREE_CLOSEOUT_TEMPLATE_LINES
      fail_check("worktree closeout template trailing field") unless template_lines[template_start + WORKTREE_CLOSEOUT_TEMPLATE_LINES.length].to_s.empty?

      [closeout_template, public_closeout].each do |content|
        PRIVATE_WORKTREE_CLOSEOUT_PREFIXES.each do |prefix|
          fail_check("private worktree evidence exposed in public closeout") if content.lines.any? { |line| line.start_with?(prefix) }
        end
      end

      private_template = section(templates, "## Private Worktree Lifecycle Evidence")
      private_prompt = unique_text_prompt(private_template, "private worktree evidence template missing")
      private_lines = private_prompt.lines.map(&:chomp)
      expected_private_lines = ["Private worktree lifecycle evidence", ""] + PRIVATE_WORKTREE_EVIDENCE_LINES
      fail_check("private worktree evidence template mismatch") unless private_lines == expected_private_lines

      private_example = section(closeout, "## Private Lifecycle Evidence Example")
      check_private_worktree_evidence_examples!(private_example)

      coordination = normalized_read("docs/coordination-records.md")
      phase_mode = section(coordination, "## Phase Branch Mode", "## Parent And Child Issues")
      require_unique_operative_line_in_section!(coordination, phase_mode, PUBLIC_WORKTREE_RECORD_RULE, "public worktree record rule missing")

      reviewer = normalized_read("examples/reviewer-comment.md")
      fail_check("reviewer worktree cleanup rule missing") unless reviewer.include?("Dirty state or failed cleanup returns `could-not-review` with `Verdict: not issued`.")
    end

    def check_worktree_closeout_examples!(content)
      records = []
      lines = content.lines.map(&:chomp)
      lines.each_with_index do |line, index|
        next unless line == "Worktree resolution:"

        block = lines[index + 1, WORKTREE_CLOSEOUT_PREFIXES.length]
        unless block&.length == WORKTREE_CLOSEOUT_PREFIXES.length &&
            WORKTREE_CLOSEOUT_PREFIXES.zip(block).all? { |prefix, value| value.start_with?(prefix) }
          fail_check("worktree closeout example field mismatch")
        end
        fail_check("worktree closeout example trailing field") unless lines[index + 1 + WORKTREE_CLOSEOUT_PREFIXES.length] == "```"
        records << block.to_h { |value| value.split(": ", 2) }
      end
      fail_check("worktree closeout example count mismatch") unless records.length == 4

      expected = {
        "merged" => ["named branch", "bound", "match"],
        "abandoned" => ["named branch", "bound", "match"],
        "intentionally kept branch" => ["named branch", "bound", "match"],
        "reviewer detached" => ["detached", "none", "none"]
      }
      actual_paths = records.map { |record| record.fetch("- Resolution path") }
      fail_check("worktree closeout paths mismatch") unless actual_paths.sort == expected.keys.sort
      records.each do |record|
        path = record.fetch("- Resolution path")
        checkout, remote, comparison = expected.fetch(path)
        fail_check("worktree closeout path state mismatch: #{path}") unless record.fetch("- Checkout kind") == checkout
        fail_check("worktree closeout path state mismatch: #{path}") unless record.fetch("- Remote subject") == remote
        fail_check("worktree closeout path state mismatch: #{path}") unless record.fetch("- Expected/live remote comparison") == comparison
        fail_check("worktree closeout reference missing: #{path}") if record.fetch("- Reference").empty?
        fail_check("worktree closeout owner missing: #{path}") if record.fetch("- Owner/category").empty?
        fail_check("worktree closeout blocker missing: #{path}") if record.fetch("- Blocker").empty?
      end
    end

    def check_private_worktree_evidence_examples!(content)
      blocks = fenced_code_blocks(content).select do |block|
        block[:info] == "text" && block[:body].start_with?("Private worktree lifecycle evidence\n")
      end
      fail_check("private worktree evidence example count mismatch") unless blocks.length == 2

      blocks.zip(PRIVATE_WORKTREE_EXAMPLE_LINES).each do |block, expected_fields|
        lines = block[:body].lines.map(&:chomp)
        expected_lines = ["Private worktree lifecycle evidence", ""] + expected_fields
        fail_check("private worktree evidence example mismatch") unless lines.length == expected_lines.length
        path = expected_fields.find { |line| line.start_with?("- Resolution path: ") }.split(": ", 2).last
        fail_check("private worktree evidence state mismatch: #{path}") unless lines == expected_lines
      end
    end

    def section(content, start_heading, end_heading = nil)
      headings = level_two_headings(content)
      start_identity = level_two_heading_identity(start_heading)
      starts = headings.select { |_position, identity| identity == start_identity }.map(&:first)
      fail_check("section missing or duplicated: #{start_heading}") unless starts.length == 1
      start = starts.first
      next_heading = headings.find { |position, _identity| position > start }

      if end_heading
        end_identity = level_two_heading_identity(end_heading)
        finishes = headings.select { |_position, identity| identity == end_identity }.map(&:first)
        fail_check("section missing or duplicated: #{end_heading}") unless finishes.length == 1
        finish = finishes.first
        unless start < finish && next_heading && next_heading.first == finish
          fail_check("section order mismatch: #{start_heading}")
        end
      else
        finish = next_heading ? next_heading.first : content.length
      end
      content[start...finish]
    end

    def exact_line_positions(content, expected)
      offset = 0
      content.each_line.with_object([]) do |line, positions|
        positions << offset if line.delete_suffix("\n") == expected
        offset += line.length
      end
    end

    def require_unique_line_in_section!(content, bounded_section, expected, message)
      scoped_count = exact_line_positions(bounded_section, expected).length
      total_count = exact_line_positions(content, expected).length
      fail_check(message) unless scoped_count == 1 && total_count == 1
    end

    def require_unique_operative_line_in_section!(content, bounded_section, expected, message)
      scoped_count = operative_line_positions(bounded_section, expected).length
      total_count = exact_line_positions(content, expected).length
      fail_check(message) unless scoped_count == 1 && total_count == 1
    end

    def operative_line_positions(content, expected)
      markdown_lines(content).each_with_object([]) do |entry, positions|
        positions << entry[:offset] if entry[:context] == :prose && entry[:line] == expected
      end
    end

    def unique_text_prompt(content, message)
      prompts = fenced_code_blocks(content).select { |block| block[:info] == "text" }
      fail_check(message) unless prompts.length == 1
      prompts.first[:body]
    end

    def fenced_code_blocks(content)
      blocks = []
      current = nil
      markdown_lines(content).each do |entry|
        case entry[:context]
        when :fence_open
          current = {
            body_start: entry[:finish],
            info: entry.fetch(:fence).fetch(:info)
          }
        when :fence_close
          next unless current

          blocks << {
            body: content[current.fetch(:body_start)...entry[:offset]],
            info: current.fetch(:info)
          }
          current = nil
        end
      end
      blocks
    end

    def heading_positions(content, expected_heading)
      expected_identity = level_two_heading_identity(expected_heading)
      fail_check("invalid level-two heading: #{expected_heading}") unless expected_identity

      level_two_headings(content).each_with_object([]) do |(position, identity), positions|
        positions << position if identity == expected_identity
      end
    end

    def level_two_headings(content)
      entries = markdown_lines(content)
      entries.each_with_index.each_with_object([]) do |(entry, index), headings|
        next unless entry[:context] == :prose

        identity = level_two_heading_identity(entry[:line])
        unless identity.nil?
          headings << [entry[:offset], identity]
          next
        end

        setext_heading = setext_level_two_heading(entries, index)
        headings << setext_heading if setext_heading
      end
    end

    def level_two_heading_identity(line)
      parts = atx_heading_parts(line)
      return unless parts && parts.fetch(:level) == 2

      identity = parts.fetch(:content).rstrip.sub(/[ \t]+#+\z/, "").rstrip
      identity = "" if identity.match?(/\A#+\z/)
      validate_heading_identity!(identity)
    end

    def atx_heading_parts(line)
      match = /\A {0,3}(\#{1,6})(?:[ \t]+(.*))?\z/.match(line)
      return unless match

      {
        level: match[1].length,
        content: match[2] || ""
      }
    end

    def validate_heading_identity!(identity)
      unsupported = identity.match?(/[\\`*_{}\[\]<>~#]/) || identity.match?(/&(?:\#\d+|\#x[0-9a-f]+|[a-z][a-z0-9]+);/i)
      fail_check("unsupported inline syntax in level-two heading") if unsupported
      identity
    end

    def setext_level_two_heading(entries, index)
      return unless index.positive?
      underline = entries[index][:line]
      return unless setext_underline_level(underline) == 2
      fail_check("indented Setext headings are not allowed in checked workflow Markdown") if underline.match?(/\A[ \t]/)

      paragraph = []
      cursor = index - 1
      while cursor >= 0 && setext_paragraph_line?(entries[cursor])
        paragraph.unshift(entries[cursor])
        cursor -= 1
      end
      return if paragraph.empty?

      identity = paragraph.map { |entry| entry[:line].strip }.join(" ")
      [paragraph.first[:offset], validate_heading_identity!(identity)]
    end

    def setext_paragraph_line?(entry)
      return false unless entry[:context] == :prose

      line = entry[:line]
      return false if line.strip.empty? || atx_heading_parts(line)
      return false if line.match?(/\A {0,3}>/)
      return false if markdown_list_line?(line) || thematic_break_line?(line) || setext_underline_level(line)

      true
    end

    def markdown_lines(content)
      entries = []
      offset = 0
      fence = nil
      in_comment = false

      content.each_line do |raw_line|
        line = raw_line.delete_suffix("\n")
        entry = {
          offset: offset,
          finish: offset + raw_line.length,
          line: line
        }

        if fence
          if fence_closing?(line, fence)
            entry[:context] = :fence_close
            entry[:fence] = fence
            fence = nil
          else
            entry[:context] = :fence_body
          end
        elsif in_comment
          entry[:context] = :comment
          in_comment = continue_block_comment?(line)
        elsif (opening = fence_opening(line))
          entry[:context] = :fence_open
          entry[:fence] = opening
          fence = opening
        elsif indented_code_line?(line)
          content = line.lstrip
          if container_prefixed_heading?(content)
            fail_check("ambiguous indented heading is not allowed in checked workflow Markdown")
          elsif raw_html_after_containers?(content)
            fail_check("raw HTML blocks are not allowed in checked workflow Markdown")
          end
          entry[:context] = :indented_code
        else
          visible_line = mask_inline_code_spans(line)
          if container_line_contains_heading?(visible_line)
            fail_check("container-prefixed headings are not allowed in checked workflow Markdown")
          elsif list_line_contains_heading?(visible_line)
            fail_check("list-contained headings are not allowed in checked workflow Markdown")
          elsif raw_html_after_containers?(visible_line.lstrip)
            fail_check("raw HTML blocks are not allowed in checked workflow Markdown")
          elsif visible_line.match?(/\A {0,3}<!--/)
            entry[:context] = :comment
            in_comment = block_comment_open_after_line?(line)
          elsif visible_line.include?("<!--") || visible_line.include?("-->")
            fail_check("inline HTML comments are not allowed in checked workflow Markdown")
          else
            entry[:context] = :prose
          end
        end

        entries << entry
        offset = entry[:finish]
      end

      entries
    end

    def block_comment_open_after_line?(line)
      opening = line.index("<!--")
      fail_check("invalid HTML comment structure") unless opening
      fail_check("invalid HTML comment structure") if line.index("<!--", opening + 4)

      closing = line.index("-->", opening + 4)
      return true unless closing

      trailing = line[(closing + 3)..]
      fail_check("invalid HTML comment structure") unless trailing.strip.empty?
      false
    end

    def continue_block_comment?(line)
      fail_check("invalid HTML comment structure") if line.include?("<!--")

      closing = line.index("-->")
      return true unless closing

      trailing = line[(closing + 3)..]
      fail_check("invalid HTML comment structure") unless trailing.strip.empty?
      false
    end

    def mask_inline_code_spans(line)
      masked = line.dup
      cursor = 0
      while cursor < line.length
        unless line[cursor] == "`" && !escaped_character?(line, cursor)
          cursor += 1
          next
        end

        opening_start = cursor
        opening_length = backtick_run_length(line, cursor)
        cursor += opening_length
        closing_end = nil

        while cursor < line.length
          unless line[cursor] == "`"
            cursor += 1
            next
          end

          candidate_length = backtick_run_length(line, cursor)
          if candidate_length == opening_length
            closing_end = cursor + candidate_length
            break
          end
          cursor += candidate_length
        end

        fail_check("multiline or unclosed inline code spans are not allowed in checked workflow Markdown") unless closing_end
        masked[opening_start...closing_end] = " " * (closing_end - opening_start)
        cursor = closing_end
      end
      masked
    end

    def backtick_run_length(line, start)
      finish = start
      finish += 1 while finish < line.length && line[finish] == "`"
      finish - start
    end

    def escaped_character?(line, index)
      backslashes = 0
      cursor = index - 1
      while cursor >= 0 && line[cursor] == "\\"
        backslashes += 1
        cursor -= 1
      end
      backslashes.odd?
    end

    def indented_code_line?(line)
      columns = 0
      line.each_char do |character|
        case character
        when " "
          columns += 1
        when "\t"
          columns += 4 - (columns % 4)
        else
          break
        end
      end
      columns >= 4
    end

    def thematic_break_line?(line)
      line.match?(/\A {0,3}(?:(?:\*[ \t]*){3,}|(?:-[ \t]*){3,}|(?:_[ \t]*){3,})\z/)
    end

    def setext_underline_level(line)
      return 1 if line.match?(/\A {0,3}=+[ \t]*\z/)
      return 2 if line.match?(/\A {0,3}-+[ \t]*\z/)
    end

    def list_line_contains_heading?(line)
      match = /\A {0,3}(?:[-+*]|\d{1,9}[.)])[ \t]+(.*)\z/.match(line)
      return false unless match

      content = match[1].lstrip
      return true if container_prefixed_heading?(content)
      content.match?(/(?:\A|[ \t])\#{1,6}(?:[ \t]|\z)/)
    end

    def container_line_contains_heading?(line)
      match = /\A {0,3}>[ \t]?(.*)\z/.match(line)
      match && container_prefixed_heading?(match[1].lstrip)
    end

    def container_prefixed_heading?(content)
      loop do
        return true if atx_heading_parts(content) || setext_underline_level(content)

        content = content_after_container_prefix(content)
        return false unless content
      end
    end

    def raw_html_after_containers?(content)
      loop do
        return true if raw_html_block_start?(content)

        content = content_after_container_prefix(content)
        return false unless content
      end
    end

    def content_after_container_prefix(content)
      match = /\A>[ \t]?(.*)\z/.match(content)
      match ||= /\A(?:[-+*]|\d{1,9}[.)])[ \t]+(.*)\z/.match(content)
      match && match[1].lstrip
    end

    def raw_html_block_start?(line)
      line.match?(/\A {0,3}(?:<\?|<![A-Z]|<!\[CDATA\[|<\/?[A-Za-z][A-Za-z0-9-]*(?:[ \t]|\/?>|\z))/i)
    end

    def fence_opening(line)
      match = /\A {0,3}(`{3,}|~{3,})(.*)\z/.match(line)
      return unless match

      marker = match[1]
      info = match[2]
      return if marker.start_with?("`") && info.include?("`")

      {
        character: marker[0],
        info: info.strip,
        length: marker.length
      }
    end

    def fence_closing?(line, fence)
      character = Regexp.escape(fence.fetch(:character))
      length = fence.fetch(:length)
      line.match?(/\A {0,3}#{character}{#{length},}[ \t]*\z/)
    end

    def markdown_list_line?(line)
      line.match?(/\A {0,3}(?:[-+*]|\d{1,9}[.)])[ \t]+/)
    end

    def check_links!
      markdown_paths.each do |relative|
        content = normalized_read(relative)
        content.scan(/!?\[[^\]]*\]\(([^)]+)\)/).flatten.each do |raw_target|
          target = raw_target.strip.sub(/\A</, "").sub(/>\z/, "").split(/\s+/, 2).first
          next if target.nil? || target.empty? || target.start_with?("#") || target.match?(/\A[a-z][a-z0-9+.-]*:/i)

          clean = URI::DEFAULT_PARSER.unescape(target.split(/[?#]/, 2).first)
          resolved = File.expand_path(clean, File.dirname(path(relative)))
          fail_check("broken local Markdown link in #{relative}: #{target}") unless File.exist?(resolved)
        end
      end
    end

    def check_stale_phrases!
      corpus = markdown_paths.map { |relative| normalized_read(relative) }.join("\n")
      STALE_PHRASES.each do |phrase|
        fail_check("stale phrase present: #{phrase}") if corpus.include?(phrase)
      end
    end

    def check_retired_policy!
      corpus = markdown_paths.map { |relative| normalized_read(relative) }.join("\n")
      RETIRED_POLICY_PATTERNS.each do |pattern|
        fail_check("retired coordination policy present: #{pattern.source}") if corpus.match?(pattern)
      end
    end

    def markdown_paths
      ["AGENTS.md", "README.md"] + Dir.chdir(root) { Dir.glob("{docs,examples}/**/*.md").sort }
    end

    def fail_check(message)
      raise CheckError, message
    end
  end

  class SelfTest
    def initialize(source_root)
      @source_root = source_root
      @checks = 0
    end

    def run!
      with_fixture { |root| Checker.new(root).check! }
      pass("valid repository")

      expect_failure("derived-file drift", "generated Role Contracts differ") do |root|
        append(root, "docs/role-contracts.md", "drift\n")
      end

      expect_failure("derived-file trailing-byte drift", "generated Role Contracts differ") do |root|
        append(root, "docs/role-contracts.md", "\n")
      end

      Checker::RULE_GROUPS.each do |group|
        expect_failure("missing #{group} rule group", "missing role-contract rule group: #{group}") do |root|
          replace(root, "docs/playbook.md", "\n## #{group}\n", "\n## Removed #{group}\n")
          Checker.new(root).write_derived!
        end
      end

      expect_failure("duplicate Role Contracts marker pair", "marked Role Contracts source missing or malformed") do |root|
        append(root, "docs/playbook.md", "\n#{Checker::ROLE_BEGIN}# Competing Role Contracts source\n#{Checker::ROLE_END}\n")
      end

      expect_failure("stray Role Contracts marker", "marked Role Contracts source missing or malformed") do |root|
        append(root, "docs/playbook.md", "\n#{Checker::ROLE_BEGIN}")
      end

      expect_failure("empty role-contract rule group", "empty role-contract rule group: Authority") do |root|
        content = read(root, "docs/playbook.md")
        content.sub!(/\n## Authority\n.*?(?=\n## Orchestrator\n)/m, "\n## Authority\n") || raise("Authority fixture missing")
        write(root, "docs/playbook.md", content)
        Checker.new(root).write_derived!
      end

      expect_failure("bullet in intervening role-contract group", "empty role-contract rule group: Authority") do |root|
        content = read(root, "docs/playbook.md")
        replacement = "\n## Authority\n\n## Unrelated\n\n- Borrowed bullet.\n"
        content.sub!(/\n## Authority\n.*?(?=\n## Orchestrator\n)/m, replacement) || raise("Authority fixture missing")
        write(root, "docs/playbook.md", content)
        Checker.new(root).write_derived!
      end

      expect_failure("commented role-contract rule group", "missing role-contract rule group: Authority") do |root|
        replace(root, "docs/playbook.md", "\n## Authority\n", "\n<!--\n## Authority\n-->\n")
        Checker.new(root).write_derived!
      end

      expect_failure("reopened comment hides role-contract rule group", "invalid HTML comment structure") do |root|
        content = read(root, "docs/playbook.md")
        match = /\n## Authority\n.*?(?=\n## Orchestrator\n)/m.match(content) || raise("Authority fixture missing")
        content.sub!(match[0], "\n<!-- first\n--> <!-- second#{match[0]}-->\n")
        write(root, "docs/playbook.md", content)
        Checker.new(root).write_derived!
      end

      expect_failure("raw HTML hides role-contract rule group", "raw HTML blocks are not allowed") do |root|
        content = read(root, "docs/playbook.md")
        match = /\n## Authority\n.*?(?=\n## Orchestrator\n)/m.match(content) || raise("Authority fixture missing")
        content.sub!(match[0], "\n<script>#{match[0]}</script>\n")
        write(root, "docs/playbook.md", content)
        Checker.new(root).write_derived!
      end

      expect_failure("fenced role-contract rule group body", "empty role-contract rule group: Authority") do |root|
        content = read(root, "docs/playbook.md")
        match = /\n## Authority\n(.*?)(?=\n## Orchestrator\n)/m.match(content) || raise("Authority fixture missing")
        replacement = "\n## Authority\n```text\n#{match[1]}```\n"
        content.sub!(match[0], replacement)
        write(root, "docs/playbook.md", content)
        Checker.new(root).write_derived!
      end

      with_fixture do |root|
        checker = Checker.new(root, bootstrap_members: ["README.md#Default Workflow"])
        assert_failure("wrong bootstrap membership", "bootstrap membership mismatch") { checker.check! }
      end

      expect_failure("bootstrap budget overflow", "bootstrap byte budget exceeded") do |root|
        insert_before_role_end(root, "x" * Checker::POST_BOOTSTRAP_BUDGET)
        Checker.new(root).write_derived!
      end

      expect_failure("commented bootstrap total record", "pre-change bootstrap total record missing") do |root|
        replace(root, "README.md", Checker::PRE_BOOTSTRAP_RECORD_RULE, "<!--\n#{Checker::PRE_BOOTSTRAP_RECORD_RULE}\n-->")
      end

      expect_failure("mismatched current bootstrap budget", "current bootstrap budget record missing") do |root|
        replace(root, "README.md", Checker::POST_BOOTSTRAP_RECORD_RULE, Checker::POST_BOOTSTRAP_RECORD_RULE.sub("13,000", "14,000"))
      end

      expect_failure("orchestrator prompt mismatch", "orchestrator loading prompt mismatch") do |root|
        replace(root, "README.md", Checker::LOADING_SENTENCE, "Load everything first.")
      end

      expect_failure("relocated README loading prompt", "orchestrator loading prompt mismatch in README.md") do |root|
        replace(root, "README.md", Checker::LOADING_SENTENCE, "Load every workflow document first.")
        append(root, "README.md", "\n#{Checker::LOADING_SENTENCE}\n")
      end

      expect_failure("relocated template loading prompt", "orchestrator loading prompt mismatch in docs/templates.md") do |root|
        replace(root, "docs/templates.md", Checker::LOADING_SENTENCE, "Load every workflow document first.")
        append(root, "docs/templates.md", "\n#{Checker::LOADING_SENTENCE}\n")
      end

      expect_failure("README loading prompt moved outside fence", "orchestrator loading prompt mismatch in README.md") do |root|
        replace(root, "README.md", Checker::LOADING_SENTENCE, "Load the supplied task context first.")
        replace(root, "README.md", "\n```\n\n## Example Agent Mix", "\n```\n\n#{Checker::LOADING_SENTENCE}\n\n## Example Agent Mix")
      end

      expect_failure("template loading prompt moved outside fence", "orchestrator loading prompt mismatch in docs/templates.md") do |root|
        replace(root, "docs/templates.md", Checker::LOADING_SENTENCE, "Load the supplied task context first.")
        replace(root, "docs/templates.md", "\n```\n\n## Local Plan Template", "\n```\n\n#{Checker::LOADING_SENTENCE}\n\n## Local Plan Template")
      end

      expect_failure("extended template loading prompt", "orchestrator loading prompt mismatch in docs/templates.md") do |root|
        replace(root, "docs/templates.md", Checker::LOADING_SENTENCE, "#{Checker::LOADING_SENTENCE} Also load every workflow document.")
      end

      expect_failure("operative loading expansion", "default loading instructions mismatch") do |root|
        block = Checker::DEFAULT_LOADING_BLOCK
        replace(root, "README.md", block, "#{block.chomp}\n- Four Eyes Playbook\n\n")
      end

      expect_failure("commented default loading block", "default loading instructions mismatch") do |root|
        block = "#{Checker::DEFAULT_LOADING_BLOCK}#{Checker::LOAD_ON_DEMAND_RULE}"
        replace(root, "README.md", block, "<!--\n#{block}\n-->")
      end

      expect_failure("field-order drift", "workflow field order mismatch") do |root|
        path = "docs/templates.md"
        content = read(root, path)
        first = "Review tier: skip | light | full\n"
        second = "#{Checker::HANDOFF_MODE_LINE}\n"
        content.sub!(second + first, first + second) || raise("test fixture field pair missing")
        write(root, path, content)
      end

      expect_failure("Reviewer 2 field omission", "Reviewer 2 field block mismatch") do |root|
        replace(root, "examples/task-issue.md", "Direct Reviewer 2 authorization: none\n", "")
      end

      expect_failure("Reviewer 2 option drift", "Reviewer 2 option block mismatch") do |root|
        content = read(root, "docs/templates.md")
        content.gsub!(Checker::REVIEWER2_HANDOFF_LINE, "Reviewer 2 handoff: direct Claude reviewer | manual external reviewer")
        write(root, "docs/templates.md", content)
      end

      expect_failure("Reviewer 2 options replaced by concrete values", "Reviewer 2 option occurrence mismatch in README.md") do |root|
        replace(
          root,
          "README.md",
          "#{Checker::REVIEWER2_OPTION_LINES.join("\n")}\n",
          "Reviewer 2 handoff: manual external reviewer\nDirect Reviewer 2 authorization: none\n"
        )
      end

      expect_failure("coordination field omission", "workflow field missing: Coordination record:") do |root|
        replace(root, "docs/templates.md", "#{Checker::COORDINATION_RECORD_LINE}\n", "")
      end

      expect_failure("coordination option drift", "invalid selected coordination record in README.md") do |root|
        replace(root, "README.md", "\n#{Checker::COORDINATION_RECORD_LINE}\n", "\nCoordination record: pr | local | github-issue\n")
      end

      expect_failure("coordination rule omission", "coordination record rules mismatch") do |root|
        replace(root, "docs/playbook.md", "#{Checker::COORDINATION_REQUIRED_RULES[7]}\n", "")
      end

      expect_failure("coordination rule extension", "coordination record rules mismatch") do |root|
        replace(root, "docs/playbook.md", Checker::COORDINATION_REQUIRED_RULES[0], "#{Checker::COORDINATION_REQUIRED_RULES[0]} Extra text.")
      end

      expect_failure("local record rule relocation", "local coordination record rules mismatch") do |root|
        rule = Checker::LOCAL_RECORD_REQUIRED_RULES[1]
        replace(root, "docs/playbook.md", "#{rule}\n", "")
        append(root, "docs/playbook.md", "\n#{rule}\n")
      end

      expect_failure("repository revision rule order", "repository revision loading rules mismatch") do |root|
        first = "#{Checker::REVISION_LOADING_REQUIRED_RULES[0]}\n"
        second = "#{Checker::REVISION_LOADING_REQUIRED_RULES[1]}\n"
        replace(root, "docs/playbook.md", first + second, second + first)
      end

      expect_failure("combined handoff option drift", "handoff mode options mismatch") do |root|
        content = read(root, "docs/templates.md")
        content.gsub!(Checker::HANDOFF_MODE_LINE, "Handoff mode: reviewer1-subagent + direct reviewer2 | reviewer1-subagent + manual reviewer2")
        write(root, "docs/templates.md", content)
      end

      expect_failure("automation ladder drift", "automation ladder mismatch") do |root|
        replace(root, "docs/playbook.md", Checker::AUTOMATION_LADDER_LINES.fetch(2), "3. Future: orchestrator invokes Reviewer 2.")
      end

      expect_failure("Autonomy field-order drift", "workflow field order mismatch") do |root|
        path = "docs/templates.md"
        content = read(root, path)
        first = "Review tier: skip | light | full\n"
        second = "Autonomy mode: review-approved-auto-execute | manual\n"
        content.sub!(first + second, second + first) || raise("Autonomy field pair missing")
        write(root, path, content)
      end

      expect_failure("conflicting duplicate workflow field", "workflow field occurrence mismatch: Autonomy mode:") do |root|
        replace(
          root,
          "docs/templates.md",
          "Autonomy mode: review-approved-auto-execute | manual\n",
          "Autonomy mode: review-approved-auto-execute | manual\nAutonomy mode: manual\n"
        )
      end

      expect_failure("workflow field moved outside orchestrator prompt", "workflow field missing: Autonomy mode:") do |root|
        replace(root, "docs/templates.md", "Autonomy mode: review-approved-auto-execute | manual\n", "")
        replace(root, "docs/templates.md", "\n```\n\n## Local Plan Template", "\n```\n\nAutonomy mode: review-approved-auto-execute | manual\n\n## Local Plan Template")
      end

      expect_failure("workflow field moved outside task-issue prompt", "workflow field missing: Autonomy mode:") do |root|
        path = "docs/templates.md"
        content = read(root, path)
        section_start = content.index("## Task Issue Template") || raise("Task Issue fixture missing")
        field_start = content.index("Autonomy mode: review-approved-auto-execute | manual\n", section_start) || raise("Task Issue Autonomy fixture missing")
        content.slice!(field_start, "Autonomy mode: review-approved-auto-execute | manual\n".length)
        anchor = "\n```\n\n## Reviewer Prompt"
        content.sub!(anchor, "\n```\n\nAutonomy mode: review-approved-auto-execute | manual\n\n## Reviewer Prompt") || raise("Task Issue close fixture missing")
        write(root, path, content)
      end

      expect_failure("worktree field omission", "workflow field missing: Worktree mode:") do |root|
        replace(root, "docs/templates.md", "#{Checker::WORKTREE_OPTION_LINES.join("\n")}\n", "")
      end

      expect_failure("worktree field order drift", "workflow field order mismatch") do |root|
        block = "#{Checker::WORKTREE_OPTION_LINES.join("\n")}\n"
        reversed = "#{Checker::WORKTREE_OPTION_LINES.reverse.join("\n")}\n"
        replace(root, "docs/templates.md", block, reversed)
      end

      expect_failure("worktree field anchor drift", "worktree field anchor mismatch") do |root|
        block = "#{Checker::WORKTREE_OPTION_LINES.join("\n")}\n"
        replace(root, "docs/coordination-records.md", block, "Remote note: local only\n#{block}")
      end

      expect_failure("worktree option drift", "worktree option block mismatch") do |root|
        replace(root, "docs/coordination-records.md", Checker::WORKTREE_MODE_LINE, "Worktree mode: off | on")
      end

      expect_failure("invalid selected worktree mode", "invalid selected worktree mode") do |root|
        replace(root, "examples/task-issue.md", "Worktree mode: on", "Worktree mode: maybe")
      end

      expect_failure("invalid phase/worktree mode combination", "invalid phase/worktree mode combination") do |root|
        replace(root, "examples/task-issue.md", "Phase branch mode: on", "Phase branch mode: off")
      end

      with_fixture do |root|
        replace(root, "examples/task-issue.md", "Worktree mode: on", "Worktree mode: off")
        replace(root, "examples/task-issue.md", "Worktree reference: phase-execution/EXAMPLE-retry-worktree", "Worktree reference: none")
        Checker.new(root).check!
        pass("phase-on worktree-off exception shape")
      end

      expect_failure("worktree-off reference mismatch", "worktree-off reference mismatch") do |root|
        replace(root, "examples/task-issue.md", "Worktree mode: on", "Worktree mode: off")
      end

      expect_failure("missing executable worktree reference", "executable worktree reference missing") do |root|
        replace(root, "examples/task-issue.md", "Worktree reference: phase-execution/EXAMPLE-retry-worktree", "Worktree reference: none")
      end

      expect_failure("non-ready worktree reference", "non-executable worktree reference mismatch") do |root|
        replace(root, "examples/multi-slice-issues.md", "Phase branch: none\nWorktree mode: on\nWorktree reference: none", "Phase branch: none\nWorktree mode: on\nWorktree reference: phase-execution/not-ready")
      end

      expect_failure("worktree default omission", "worktree default field mismatch") do |root|
        replace(root, "docs/templates.md", "#{Checker::WORKTREE_DEFAULT_LINES.first}\n", "")
      end

      expect_failure("worktree default duplicate", "worktree default field occurrence mismatch") do |root|
        append(root, "README.md", "\n#{Checker::WORKTREE_DEFAULT_LINES.first}\n")
      end

      expect_failure("worktree slice field omission", "worktree slice field mismatch") do |root|
        replace(root, "docs/templates.md", "#{Checker::WORKTREE_SLICE_LINES.first}\n", "")
      end

      expect_failure("unexpected worktree field block", "unexpected worktree field occurrence") do |root|
        append(root, "README.md", "\nPhase branch: none\nWorktree mode: off\nWorktree reference: none\nRemote push: disallowed\n")
      end

      Checker::WORKTREE_REQUIRED_RULES.each_with_index do |line, index|
        expect_failure("worktree lifecycle rule #{index + 1} omission", "worktree lifecycle rule missing") do |root|
          replace(root, "docs/playbook.md", "#{line}\n", "")
        end
      end

      expect_failure("unchecked worktree lifecycle addition", "unchecked worktree lifecycle rule") do |root|
        replace(root, "docs/playbook.md", "\n### Mode And Location\n", "\n### Mode And Location\n\n- Unreviewed lifecycle expansion.\n")
      end

      [
        ["prose", "Unreviewed operative prose."],
        ["numbered", "1. Unreviewed numbered rule."],
        ["asterisk", "* Unreviewed asterisk rule."],
        ["plus", "+ Unreviewed plus rule."],
        ["indented", "    - Unreviewed indented rule."]
      ].each do |name, addition|
        expect_failure("unchecked #{name} lifecycle addition", "unchecked worktree lifecycle rule") do |root|
          replace(root, "docs/playbook.md", "\n### Mode And Location\n", "\n### Mode And Location\n\n#{addition}\n")
        end
      end

      expect_failure("default workflow worktree omission", "default workflow worktree rule missing") do |root|
        replace(root, "README.md", "#{Checker::DEFAULT_WORKTREE_RULE}\n", "")
      end

      expect_failure("role-contract worktree omission", "role-contract worktree rule missing") do |root|
        replace(root, "docs/playbook.md", "#{Checker::ROLE_WORKTREE_RULE}\n", "")
        Checker.new(root).write_derived!
      end

      expect_failure("merged worktree closeout omission", "worktree closeout example field mismatch") do |root|
        replace(root, "examples/closeout.md", "- Resolution path: merged\n", "")
      end

      expect_failure("worktree closeout field omission", "worktree closeout example field mismatch") do |root|
        replace(root, "examples/closeout.md", "- Owner/category: orchestrator/phase-execution\n", "")
      end

      expect_failure("worktree closeout field order", "worktree closeout example field mismatch") do |root|
        replace(
          root,
          "examples/closeout.md",
          "- Checkout kind: named branch\n- Remote subject: bound\n",
          "- Remote subject: bound\n- Checkout kind: named branch\n"
        )
      end

      expect_failure("worktree closeout trailing field", "worktree closeout example trailing field") do |root|
        replace(root, "examples/closeout.md", "- Blocker: none\n```", "- Blocker: none\n- Path: private/path\n```")
      end

      expect_failure("worktree closeout path-state mismatch", "worktree closeout path state mismatch: merged") do |root|
        replace(root, "examples/closeout.md", "- Checkout kind: named branch\n", "- Checkout kind: detached\n")
      end

      expect_failure("private worktree evidence in public closeout", "private worktree evidence exposed in public closeout") do |root|
        replace(
          root,
          "examples/closeout.md",
          "## Private Lifecycle Evidence Example\n",
          "- Clean status: clean\n\n## Private Lifecycle Evidence Example\n"
        )
      end

      expect_failure("private worktree path in public closeout", "private worktree evidence exposed in public closeout") do |root|
        replace(
          root,
          "examples/closeout.md",
          "## Private Lifecycle Evidence Example\n",
          "- Canonical path: /private/path\n\n## Private Lifecycle Evidence Example\n"
        )
      end

      expect_failure("private worktree evidence template omission", "private worktree evidence template mismatch") do |root|
        full_block = "#{Checker::PRIVATE_WORKTREE_EVIDENCE_LINES.join("\n")}\n"
        short_block = "#{Checker::PRIVATE_WORKTREE_EVIDENCE_LINES[0...-1].join("\n")}\n"
        replace(root, "docs/templates.md", full_block, short_block)
      end

      expect_failure("private worktree evidence template trailing field", "private worktree evidence template mismatch") do |root|
        replace(
          root,
          "docs/templates.md",
          "- Blocker: <none | exact blocker>\n```",
          "- Blocker: <none | exact blocker>\n- Extra: <not allowed>\n```"
        )
      end

      expect_failure("private worktree evidence example omission", "private worktree evidence example mismatch") do |root|
        replace(root, "examples/closeout.md", "- Per-worktree Git directory: <private canonical per-worktree Git directory>\n", "")
      end

      expect_failure("private worktree evidence example path mismatch", "private worktree evidence state mismatch: reviewer detached") do |root|
        replace(
          root,
          "examples/closeout.md",
          "- Canonical path: <private canonical reviewer-worktree path>\n- Owner/category and cleanup owner: Reviewer 2/reviewer-verification | Reviewer 2\n- Checkout kind: detached\n",
          "- Canonical path: <private canonical reviewer-worktree path>\n- Owner/category and cleanup owner: Reviewer 2/reviewer-verification | Reviewer 2\n- Checkout kind: named branch\n"
        )
      end

      [
        [
          "reviewer cleanup owner mismatch",
          "- Owner/category and cleanup owner: Reviewer 2/reviewer-verification | Reviewer 2\n",
          "- Owner/category and cleanup owner: Reviewer 2/reviewer-verification | orchestrator\n",
          "private worktree evidence state mismatch: reviewer detached"
        ],
        [
          "merged abbreviated reviewed head",
          "- Expected branch/ref or reviewed SHA: refs/heads/phase/EXAMPLE-retry-behavior at aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n",
          "- Expected branch/ref or reviewed SHA: refs/heads/phase/EXAMPLE-retry-behavior at abc1234\n",
          "private worktree evidence state mismatch: merged"
        ],
        [
          "merged remote state mismatch",
          "- Expected/live remote state: absent/absent\n",
          "- Expected/live remote state: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n",
          "private worktree evidence state mismatch: merged"
        ],
        [
          "merged local transition mismatch",
          "- Previous/new local expected state: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/absent\n",
          "- Previous/new local expected state: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n",
          "private worktree evidence state mismatch: merged"
        ],
        [
          "merged dirty cleanup mismatch",
          "- Local ref post-delete check: absent\n- Clean status: clean\n- Removal result: removed normally\n",
          "- Local ref post-delete check: absent\n- Clean status: dirty\n- Removal result: removed normally\n",
          "private worktree evidence state mismatch: merged"
        ],
        [
          "reviewer retained-checkout mismatch",
          "- Local ref post-delete check: not applicable\n- Clean status: clean\n- Removal result: removed normally\n- Retained-checkout absence check: passed\n",
          "- Local ref post-delete check: not applicable\n- Clean status: clean\n- Removal result: removed normally\n- Retained-checkout absence check: failed\n",
          "private worktree evidence state mismatch: reviewer detached"
        ]
      ].each do |name, original, replacement, error|
        expect_failure(name, error) do |root|
          replace(root, "examples/closeout.md", original, replacement)
        end
      end

      expect_failure("public worktree record rule omission", "public worktree record rule missing") do |root|
        replace(root, "docs/coordination-records.md", "#{Checker::PUBLIC_WORKTREE_RECORD_RULE}\n", "")
      end

      expect_failure("reviewer worktree cleanup omission", "reviewer worktree cleanup rule missing") do |root|
        replace(root, "examples/reviewer-comment.md", "Dirty state or failed cleanup returns `could-not-review` with `Verdict: not issued`.", "Cleanup failure is recorded.")
      end

      expect_failure("duplicate Default Workflow heading", "README Default Workflow section missing or duplicated") do |root|
        append(root, "README.md", "\n## Default Workflow\n\nDuplicate workflow.\n")
      end

      expect_failure("Markdown-equivalent duplicate section heading", "section missing or duplicated: ## New Orchestrator Prompt") do |root|
        append(root, "docs/templates.md", "\n## New Orchestrator Prompt \n\nDuplicate prompt.\n")
      end

      expect_failure("Setext duplicate section heading", "section missing or duplicated: ## New Orchestrator Prompt") do |root|
        append(root, "docs/templates.md", "\nNew Orchestrator Prompt\n-----------------------\n\nDuplicate prompt.\n")
      end

      expect_failure("Setext H1 does not hide adjacent duplicate H2", "section missing or duplicated: ## New Orchestrator Prompt") do |root|
        append(root, "docs/templates.md", "\nContainer Heading\n===\nNew Orchestrator Prompt\n---\n")
      end

      expect_failure("unordered-list continuation cannot hide duplicate H2", "ambiguous indented heading") do |root|
        append(root, "docs/templates.md", "\n- item\n    ## New Orchestrator Prompt\n")
      end

      expect_failure("ordered-list continuation cannot hide duplicate H2", "ambiguous indented heading") do |root|
        append(root, "docs/templates.md", "\n1. item\n    ## New Orchestrator Prompt\n")
      end

      expect_failure("same-line list item cannot hide duplicate H2", "list-contained headings") do |root|
        append(root, "docs/templates.md", "\n- ## New Orchestrator Prompt\n")
      end

      expect_failure("list-contained Setext H2 is rejected", "indented Setext headings") do |root|
        append(root, "docs/templates.md", "\n- New Orchestrator Prompt\n  ---\n")
      end

      expect_failure("tight unordered-list blockquote cannot hide duplicate H2", "ambiguous indented heading") do |root|
        append(root, "docs/templates.md", "\n- item\n    > ## New Orchestrator Prompt\n")
      end

      expect_failure("loose unordered-list blockquote cannot hide duplicate H2", "ambiguous indented heading") do |root|
        append(root, "docs/templates.md", "\n- item\n\n    > ## New Orchestrator Prompt\n")
      end

      expect_failure("ordered-list blockquote cannot hide duplicate H2", "ambiguous indented heading") do |root|
        append(root, "docs/templates.md", "\n1. item\n    > ## New Orchestrator Prompt\n")
      end

      expect_failure("nested ordered-list blockquote cannot hide duplicate H2", "ambiguous indented heading") do |root|
        append(root, "docs/templates.md", "\n1. outer\n    1. inner\n        > ## New Orchestrator Prompt\n")
      end

      expect_failure("list blockquote Setext cannot hide duplicate H2", "ambiguous indented heading") do |root|
        append(root, "docs/templates.md", "\n- item\n    > New Orchestrator Prompt\n    > ---\n")
      end

      expect_failure("list blockquote cannot hide duplicate Default Workflow", "ambiguous indented heading") do |root|
        append(root, "README.md", "\n- item\n    > ## Default Workflow\n")
      end

      expect_failure("bare blockquote cannot hide duplicate H2", "container-prefixed headings") do |root|
        append(root, "docs/templates.md", "\n> ## New Orchestrator Prompt\n")
      end

      expect_failure("repeated blockquote cannot hide duplicate H2", "container-prefixed headings") do |root|
        append(root, "docs/templates.md", "\n> > ## New Orchestrator Prompt\n")
      end

      expect_failure("minimum unordered continuation cannot hide blockquote H2", "container-prefixed headings") do |root|
        append(root, "docs/templates.md", "\n- item\n  > ## New Orchestrator Prompt\n")
      end

      expect_failure("loose minimum unordered continuation cannot hide blockquote H2", "container-prefixed headings") do |root|
        append(root, "docs/templates.md", "\n- item\n\n  > ## New Orchestrator Prompt\n")
      end

      expect_failure("minimum ordered continuation cannot hide blockquote H2", "container-prefixed headings") do |root|
        append(root, "docs/templates.md", "\n1. item\n   > ## New Orchestrator Prompt\n")
      end

      expect_failure("minimum continuation cannot hide blockquote Setext H2", "container-prefixed headings") do |root|
        append(root, "docs/templates.md", "\n- item\n  > New Orchestrator Prompt\n  > ---\n")
      end

      expect_failure("mixed minimum containers cannot hide duplicate H2", "container-prefixed headings") do |root|
        append(root, "docs/templates.md", "\n- item\n  > 1. > ## New Orchestrator Prompt\n")
      end

      expect_failure("minimum continuation cannot hide duplicate Default Workflow", "container-prefixed headings") do |root|
        append(root, "README.md", "\n- item\n  > ## Default Workflow\n")
      end

      expect_failure("unordered continuation cannot hide raw HTML H2", "raw HTML blocks are not allowed") do |root|
        append(root, "docs/templates.md", "\n- item\n    <h2>New Orchestrator Prompt</h2>\n")
      end

      expect_failure("ordered continuation cannot hide raw HTML H2", "raw HTML blocks are not allowed") do |root|
        append(root, "docs/templates.md", "\n1. item\n    <h2>New Orchestrator Prompt</h2>\n")
      end

      expect_failure("nested continuation cannot hide raw HTML H2", "raw HTML blocks are not allowed") do |root|
        append(root, "docs/templates.md", "\n- outer\n    - inner\n        <h2>New Orchestrator Prompt</h2>\n")
      end

      expect_failure("tabbed continuation cannot hide raw HTML H2", "raw HTML blocks are not allowed") do |root|
        append(root, "docs/templates.md", "\n- item\n\t<h2>New Orchestrator Prompt</h2>\n")
      end

      expect_failure("minimum unordered continuation cannot hide raw HTML H2", "raw HTML blocks are not allowed") do |root|
        append(root, "docs/templates.md", "\n- item\n  <h2>New Orchestrator Prompt</h2>\n")
      end

      expect_failure("minimum ordered continuation cannot hide raw HTML H2", "raw HTML blocks are not allowed") do |root|
        append(root, "docs/templates.md", "\n1. item\n   <h2>New Orchestrator Prompt</h2>\n")
      end

      expect_failure("same-line list cannot hide raw HTML H2", "raw HTML blocks are not allowed") do |root|
        append(root, "docs/templates.md", "\n- <h2>New Orchestrator Prompt</h2>\n")
      end

      expect_failure("blockquote cannot hide raw HTML H2", "raw HTML blocks are not allowed") do |root|
        append(root, "docs/templates.md", "\n> <h2>New Orchestrator Prompt</h2>\n")
      end

      expect_failure("mixed containers cannot hide raw HTML H2", "raw HTML blocks are not allowed") do |root|
        append(root, "docs/templates.md", "\n- > <h2>New Orchestrator Prompt</h2>\n")
      end

      expect_failure("list continuation cannot hide raw HTML Default Workflow", "raw HTML blocks are not allowed") do |root|
        append(root, "README.md", "\n- item\n    <h2>Default Workflow</h2>\n")
      end

      expect_failure("list continuation cannot hide generic raw HTML", "raw HTML blocks are not allowed") do |root|
        append(root, "docs/templates.md", "\n- item\n    <div>Visible policy</div>\n")
      end

      with_fixture do |root|
        append(root, "docs/templates.md", "\n> `<h2>New Orchestrator Prompt</h2>`\n")
        Checker.new(root).check!
      end
      pass("blockquoted inline-code HTML remains literal")

      with_fixture do |root|
        append(root, "docs/templates.md", "\n```html\n<h2>New Orchestrator Prompt</h2>\n```\n")
        Checker.new(root).check!
      end
      pass("fenced raw HTML remains literal")

      expect_failure("intervening peer section", "section order mismatch: ## New Orchestrator Prompt") do |root|
        replace(root, "docs/templates.md", "\n## Local Plan Template\n", "\n## Unrelated Peer Section\n\n## Local Plan Template\n")
      end

      expect_failure("empty intervening level-two heading", "section order mismatch: ## New Orchestrator Prompt") do |root|
        replace(root, "docs/templates.md", "\n## Local Plan Template\n", "\n##\n\n## Local Plan Template\n")
      end

      expect_failure("comment-bearing empty level-two heading", "inline HTML comments are not allowed") do |root|
        replace(root, "docs/templates.md", "\n## Local Plan Template\n", "\n## <!-- empty -->\n\n## Local Plan Template\n")
      end

      expect_failure("formatted duplicate level-two heading", "unsupported inline syntax in level-two heading") do |root|
        append(root, "docs/templates.md", "\n## *New Orchestrator Prompt*\n")
      end

      expect_failure("inline-code comment markers cannot hide duplicate heading", "section missing or duplicated: ## New Orchestrator Prompt") do |root|
        append(root, "docs/templates.md", "\n`<!--`\n## New Orchestrator Prompt\n`-->`\n")
      end

      expect_failure("invalid backtick fence hides duplicate section heading", "multiline or unclosed inline code spans are not allowed") do |root|
        append(root, "docs/templates.md", "\n```invalid`info\n## New Orchestrator Prompt\n```\n")
      end

      expect_failure("invalid backtick fence hides duplicate Default Workflow", "multiline or unclosed inline code spans are not allowed") do |root|
        append(root, "README.md", "\n```invalid`info\n## Default Workflow\n```\n")
      end

      expect_failure("commented required section heading", "section missing or duplicated: ## New Orchestrator Prompt") do |root|
        replace(root, "docs/templates.md", "## New Orchestrator Prompt\n", "<!--\n## New Orchestrator Prompt\n-->\n")
      end

      expect_failure("commented Default Workflow heading", "README Default Workflow section missing or duplicated") do |root|
        replace(root, "README.md", "## Default Workflow\n", "<!--\n## Default Workflow\n-->\n")
      end

      with_fixture do |root|
        replace(
          root,
          "docs/templates.md",
          "\n## Private Worktree Lifecycle Evidence\n",
          "\n```text\n## New Orchestrator Prompt ##\n```\n\n## Private Worktree Lifecycle Evidence\n"
        )
        Checker.new(root).check!
      end
      pass("fenced heading lookalike ignored")

      with_fixture do |root|
        append(root, "docs/templates.md", "\n<!--\n## New Orchestrator Prompt\n-->\n")
        Checker.new(root).check!
      end
      pass("commented heading lookalike ignored")

      with_fixture do |root|
        append(root, "docs/templates.md", "\n~~~valid`tilde-info\n## New Orchestrator Prompt\n~~~\n")
        Checker.new(root).check!
      end
      pass("tilde fence with backtick info hides heading")

      with_fixture do |root|
        append(root, "docs/templates.md", "\n~~~text <!-- valid fence info\n## New Orchestrator Prompt\n~~~\n")
        Checker.new(root).check!
      end
      pass("comment-like fence info hides heading")

      with_fixture do |root|
        replace(root, "README.md", "\n## Use It For\n", "\nUnexpected Peer Section\n-----------------------\n\nNot part of Default Workflow.\n\n## Use It For\n")
        source = Checker.new(root).send(:default_workflow_source)
        raise "Setext heading did not bound Default Workflow" if source.include?("Unexpected Peer Section")
      end
      pass("Setext heading bounds Default Workflow")

      with_fixture do |root|
        replacement = "\nContainer Heading\n===\nUnexpected Peer\n---\n\n## Use It For\n"
        replace(root, "README.md", "\n## Use It For\n", replacement)
        readme = read(root, "README.md")
        start = readme.index("## Default Workflow\n") || raise("Default Workflow heading missing")
        finish = readme.index("Unexpected Peer\n---\n", start) || raise("Setext H2 boundary missing")
        expected = readme[start...finish]
        source = Checker.new(root).send(:default_workflow_source)
        raise "Setext H1/H2 boundary bytes differ" unless source == expected
        raise "Setext H1 bytes missing from Default Workflow" unless source.end_with?("Container Heading\n===\n")
      end
      pass("Setext H1 bytes precede adjacent Default Workflow H2 boundary")

      with_fixture do |root|
        baseline_bytes = Checker.new(root).send(:default_workflow_source).bytesize
        replacement = "\nUnexpected Peer\nSection\n-------\n\nNot part of Default Workflow.\n\n## Use It For\n"
        replace(root, "README.md", "\n## Use It For\n", replacement)
        source = Checker.new(root).send(:default_workflow_source)
        raise "multiline Setext heading leaked into Default Workflow" if source.include?("Unexpected Peer") || source.include?("Section\n-------")
        raise "multiline Setext changed Default Workflow byte count" unless source.bytesize == baseline_bytes
      end
      pass("multiline Setext heading preserves Default Workflow bytes")

      with_fixture do |root|
        baseline_bytes = Checker.new(root).send(:default_workflow_source).bytesize
        addition = "    `indented code\n---\nActive policy remains in Default Workflow.\n"
        replace(root, "README.md", "\n## Use It For\n", "\n#{addition}\n## Use It For\n")
        source = Checker.new(root).send(:default_workflow_source)
        raise "indented code thematic break truncated Default Workflow" unless source.include?("Active policy remains in Default Workflow.")
        raise "indented code fixture did not expand Default Workflow bytes" unless source.bytesize > baseline_bytes
      end
      pass("indented code thematic break stays inside Default Workflow")

      with_fixture do |root|
        write(root, "README.md", read(root, "README.md").gsub("\n", "\r\n"))
        Checker.new(root).check!
      end
      pass("CRLF README extraction")

      expect_failure("invalid UTF-8 README", "README.md: invalid UTF-8") do |root|
        write(root, "README.md", read(root, "README.md") + "\xFF".b)
      end

      expect_failure("bare CR README", "README.md: bare CR") do |root|
        write(root, "README.md", read(root, "README.md") + "bare\rcr\n")
      end

      expect_failure("NUL README", "README.md: NUL byte") do |root|
        write(root, "README.md", read(root, "README.md") + "nul\0byte\n")
      end

      canonical = Checker.new(@source_root).canonical_body("caf\xC3\xA9\r\n".b)
      expected_canonical = "caf\xC3\xA9\n".b.force_encoding(Encoding::UTF_8)
      raise "canonical UTF-8/CRLF normalization failed" unless canonical == expected_canonical
      pass("canonical UTF-8 and CRLF")

      with_fixture do |root|
        playbook = read(root, "docs/playbook.md")
        playbook.sub!("# Four Eyes Role Contracts\n", "# Four Eyes Role Contracts\n\nUTF-8 fixture: café 😀\n") || raise("Role Contracts fixture missing")
        write(root, "docs/playbook.md", playbook)
        Checker.new(root).write_derived!
        Checker.new(root).check!
      end
      pass("multibyte Role Contracts extraction")

      expect_failure("broken local link", "broken local Markdown link") do |root|
        append(root, "README.md", "\n[broken](docs/does-not-exist.md)\n")
      end

      expect_failure("retired external coordinator in AGENTS", "retired coordination policy present") do |root|
        append(root, "AGENTS.md", "\nLinear remains required for workflow coordination.\n")
      end

      expect_failure("retired synchronized-document instruction", "retired coordination policy present") do |root|
        append(root, "README.md", "\nLoad a synced workflow document before review.\n")
      end

      Checker::STALE_PHRASES.each do |phrase|
        expect_failure("stale phrase: #{phrase}", "stale phrase present") do |root|
          append(root, "README.md", "\n#{phrase}\n")
        end
      end

      puts "check-docs self-test: #{@checks} checks passed"
    end

    private

    def with_fixture
      Dir.mktmpdir("four-eyes-check-docs-") do |tmp|
        %w[AGENTS.md README.md docs examples].each do |entry|
          FileUtils.cp_r(File.join(@source_root, entry), File.join(tmp, entry))
        end
        yield tmp
      end
    end

    def expect_failure(name, message)
      with_fixture do |root|
        yield root
        assert_failure(name, message) { Checker.new(root).check! }
      end
    end

    def assert_failure(name, message)
      yield
      raise "#{name}: expected failure"
    rescue CheckError => error
      raise "#{name}: wrong failure: #{error.message}" unless error.message.include?(message)

      pass(name)
    end

    def pass(name)
      @checks += 1
      puts "PASS #{name}"
    end

    def read(root, path)
      File.binread(File.join(root, path))
    end

    def write(root, path, content)
      File.binwrite(File.join(root, path), content)
    end

    def append(root, path, content)
      File.open(File.join(root, path), "ab") { |file| file.write(content) }
    end

    def replace(root, path, from, to)
      content = read(root, path)
      content.sub!(from, to) || raise("test fixture text missing in #{path}: #{from.inspect}")
      write(root, path, content)
    end

    def insert_before_role_end(root, content)
      replace(root, "docs/playbook.md", Checker::ROLE_END, "#{content}\n#{Checker::ROLE_END}")
    end
  end
end

root = File.expand_path("..", __dir__)

begin
  case ARGV
  when ["--self-test"]
    FourEyesDocs::SelfTest.new(root).run!
  when ["--write-derived"]
    FourEyesDocs::Checker.new(root).write_derived!
    puts "wrote docs/role-contracts.md"
  when []
    report = FourEyesDocs::Checker.new(root).check!
    puts "check-docs: OK"
    puts "source_bootstrap_before=#{report[:before]}"
    puts "source_bootstrap_after=#{report[:after]}"
    puts "source_bootstrap_saved=#{report[:saved]}"
    puts format("source_bootstrap_reduction=%.2f%%", report[:reduction])
  else
    raise FourEyesDocs::CheckError, "use --self-test, --write-derived, or no arguments"
  end
rescue FourEyesDocs::CheckError => error
  warn "check-docs: FAIL: #{error.message}"
  exit 1
end
