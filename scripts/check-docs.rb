#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
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
    DOCUMENTATION_ENFORCEMENT_RULE = "- Use exact mechanical enforcement when silent drift could change authority, a gate, artifact identity, reviewer isolation, terminal or cleanup behavior, a public/private boundary, or canonical generated output."
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
      "examples/coordination-record.md" => 1,
      "examples/multi-slice-issues.md" => 2
    }.freeze
    REVIEWER2_OPTION_OCCURRENCES = {
      "README.md" => 1,
      "docs/playbook.md" => 1,
      "docs/templates.md" => 2,
      "docs/coordination-records.md" => 2
    }.freeze
    DIRECT_REVIEW_LADDER_BOUNDARY = "Rung 3 is never globally or orchestrator-authorized; each task or phase requires the recorded human decision and enforceable bounds. Rung 4 is not implemented or pre-authorized."
    PRE_BOOTSTRAP_COMPONENTS = {
      "README.md#Default Workflow" => 2_630,
      "docs/playbook.md" => 54_802,
      "docs/templates.md" => 25_609,
      "docs/issue-tracker-setup.md" => 8_995
    }.freeze
    PRE_BOOTSTRAP_TOTAL = 92_036
    PRE_BOOTSTRAP_RECORD_RULE = "The reproducible pre-change source bootstrap at revision `225430672fad342d693137254c256ca44f2bd8ef` was 92,036 UTF-8 bytes:"
    POST_BOOTSTRAP_MEMBERS = ["README.md#Default Workflow", "docs/role-contracts.md"].freeze
    POST_BOOTSTRAP_BUDGET = 12_000
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
      "examples/coordination-record.md" => 1,
      "examples/multi-slice-issues.md" => 2
    }.freeze
    WORKTREE_OPTION_OCCURRENCES = {
      "docs/playbook.md" => 1,
      "docs/templates.md" => 2,
      "docs/coordination-records.md" => 1
    }.freeze
    WORKTREE_DEFAULT_LINES = [
      "Worktree mode default: on | off"
    ].freeze
    WORKTREE_SLICE_LINES = [
      "   - worktree mode: inherit | on | off"
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
    PRIVATE_WORKTREE_EXAMPLE_EXPECTATIONS = {
      "merged" => {
        "- Owner/category and cleanup owner" => "orchestrator/phase-execution | orchestrator",
        "- Checkout kind" => "named branch",
        "- Expected/live remote state" => "absent/absent",
        "- Previous/new local expected state" => "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/absent",
        "- Clean status" => "clean",
        "- Removal result" => "removed normally",
        "- Retained-checkout absence check" => "passed",
        "- Local ref pre-delete check" => "exact match",
        "- Local ref post-delete check" => "absent"
      },
      "reviewer detached" => {
        "- Owner/category and cleanup owner" => "Reviewer 2/reviewer-verification | Reviewer 2",
        "- Checkout kind" => "detached",
        "- Base SHA" => "not applicable",
        "- Stored primary fingerprint" => "not applicable",
        "- Remote identity/name/full ref" => "none/none/none",
        "- Expected/live remote state" => "none/none",
        "- Previous/new local expected state" => "none",
        "- Local ref pre-delete check" => "not applicable",
        "- Local ref post-delete check" => "not applicable",
        "- Clean status" => "clean",
        "- Removal result" => "removed normally",
        "- Retained-checkout absence check" => "passed",
        "- Blocker" => "none"
      }
    }.freeze
    PUBLIC_WORKTREE_RECORD_RULE = "Public coordination records never include worktree paths, usernames, host layout, remote URLs, remote names, full refs, local expected-state transitions, or cleanup diagnostics. Record only the opaque reference, ownership category, checkout kind, remote-subject category, expected/live comparison result, lifecycle path, and blocker if any. Detailed ownership and state transitions stay in private local evidence."
    DEFAULT_WORKTREE_RULE = "5. For each implementation phase, the orchestrator creates a phase branch and dedicated worktree while the primary checkout stays fixed and coordination-only."
    ROLE_WORKTREE_RULE = "- With phase branch mode on, default to one owned phase worktree, keep the primary checkout fixed, verify baseline, and remove it before branch deletion; the packet remains the review artifact, only a repo-backed reviewer that creates a detached worktree must remove it before verdict, and the contract has no named integration dependency."
    WORKTREE_LIFECYCLE_SHA256 = "1a899436fe6bc050fff2d8bca6637eb25a4405de46d364ffb42a854884659be3"
    COORDINATION_FIELD_OCCURRENCES = {
      "README.md" => 1,
      "docs/templates.md" => 2,
      "docs/coordination-records.md" => 1,
      "examples/coordination-record.md" => 1,
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
      "2. `pr` is the default for single-phase remote work; authority transfers to the pull request only after rule 6 verification.",
      "3. `github-issue` uses exactly one parent issue carrying a compact phase ledger; each phase's explicitly identified record within that issue is its authority, and phase pull requests reference it.",
      "4. `local` is the no-forge fallback; it provides resumability, not permanent audit. Work needing durable history uses `pr` or `github-issue`.",
      "5. Each phase has one effective permission authority: in `pr` mode, the recorded local execution-state file until verified transfer to its pull request; in `github-issue` mode, its identified parent-issue phase record; in `local` mode, its recorded local file. Parent defaults and plan inputs are not execution authorities.",
      "6. In `pr` mode, prepare the pull request as non-authoritative, copy the local record's public-safe state and effective permissions, and verify content and cross-references before recording and verifying takeover in the old authority. Mark that old record superseded and name its successor. A failure before takeover preserves the old authority; uncertain takeover stops execution and hands off. The candidate never grants permission before verified takeover.",
      "7. Reviewers may submit verdicts through the selected review transport, including pull request reviews. A direct pull request verdict may change forge review status; it never changes the Four Eyes gate, ledger status, or closeout metadata. Reviewers never edit coordination metadata, status, the phase ledger, or closeout. The orchestrator owns every coordination update.",
      "8. Promote `pr` to `github-issue` when a second phase becomes committed, when a dependency or blocker exists outside the current pull request, or when deferred work must survive the current pull request's closeout. Continuing a single-phase pull request across sessions is not a promotion trigger.",
      "9. Promotion is check-act-verify-record: prepare one non-authoritative parent issue with the plan digest, ledger, current pull request, dependencies, gate, and each phase's unchanged effective permissions; verify content and backlinks before recording and verifying takeover in the old authority. Mark superseded records non-authoritative and name the successor. A failure before takeover preserves the old authority; uncertain takeover stops execution and hands off. Transfer grants no new permission.",
      "10. Multi-phase work uses one parent ledger. Do not create a child issue for each committed execution slice.",
      "11. Create child issues only for independently owned, externally blocked, or durable follow-up work.",
      "12. Selecting `Coordination record: github-issue` pre-authorizes creating, updating, and closing exactly one parent coordination issue plus explicitly accepted durable follow-ups. It authorizes no unrelated issue operations.",
      "13. The parent ledger uses the fixed columns `Phase | Depends on | Status | Branch/PR | Gate | Next action`.",
      "14. Ledger status values are `todo`, `ready`, `in progress`, `review`, `waiting external eval`, `blocked`, and one terminal value.",
      "15. `waiting external eval` is not terminal. Independent phases may advance while unrelated work waits; declared dependencies must satisfy rule 16. Readiness does not clear any review, permission, or human gate.",
      "16. A phase becomes `ready` only when every declared dependency has a verified terminal resolution and all its required results are available and verified. Record each required result and its accessible verification evidence in the phase's authority record. A terminal label alone is insufficient. Removing or replacing a dependency requires the existing scope-change and plan-review gates before advancement.",
      "17. Terminal values are `merged`, `completed`, `abandoned`, `retained`, and `handed off`. `blocked` is never terminal, and any failed cleanup remains `blocked`.",
      "18. `merged` requires the pull request merged and the reviewed head ancestral to the target.",
      "19. `completed` is the successful terminal value for work producing no merge, such as `local` mode. It requires the recorded verification evidence present and the working tree clean.",
      "20. `abandoned` requires authoritative local and remote tip equality, closure of any applicable pull request, clean worktree removal, resolved branches, and a recorded reason and tip SHA.",
      "21. `retained` requires resolved branch and worktree state plus recorded tip SHA, owner, and revisit trigger.",
      "22. `handed off` requires a recorded blocker, owner, next action, and recorded human acceptance of ownership. Without recorded acceptance the phase stays `blocked`.",
      "23. Record closeout evidence in the coordination record and verify it landed before removing any temporary plan or local state record.",
      "24. In `pr` mode, post the final closeout record to the pull request before removing the temporary plan and execution-state record.",
      "25. Parent closeout requires every phase terminal, with each claimed resolution verified against real Git or forge state. Record partial or abandoned outcomes as such; never call missing required results successful delivery."
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
    REVIEW_EFFICIENCY_RULES = [
      "1. Review rounds are capped in exactly two buckets: plan and implementation.",
      "2. Each bucket allows at most three panel rounds: one initial review plus two subsequent panel rounds.",
      "3. A round recorded with `Review stage: delta` counts inside the bucket whose artifact it revises and never starts a new cap.",
      "4. A panel round starts when its first reviewer slot is dispatched.",
      "5. Every numbered round counts against its bucket, including rounds ending in error, timeout, or could-not-review.",
      "6. At the cap the orchestrator stops and returns the current findings to the human.",
      "7. At the cap the human chooses exactly one of: authorize a stated positive number of additional rounds; descope and authorize a stated positive number of rounds to review the changed artifact; override a blocker with recorded risk; or abandon.",
      "8. Additional rounds increment the exhausted bucket. They never reset it and never expand model, call, or cost authorization.",
      "9. A round cap never converts a blocker into a nit. Blockers remain blockers at and after the cap.",
      "10. Accepted nits are deferred by default without changing the artifact.",
      "11. Implement an accepted nit immediately only when the human requires it, an acceptance criterion requires it, or an existing gate requires it.",
      "12. Record every deferred no-action nit in the coordination record closeout with its reason.",
      "13. Record every deferred actionable nit as a follow-up in the coordination record closeout.",
      "14. `Review transport: pr` authorizes no issue creation.",
      "15. `Coordination record: github-issue` retains its existing authority to create, update, and close exactly one parent coordination issue plus explicitly accepted durable follow-ups.",
      "16. Any other external follow-up record requires exact human authorization naming the records, normally bundled into merge approval.",
      "17. Both full-tier reviewers bind approval to the complete current artifact identity in every round.",
      "18. A normal delta round inspects the exact delta, its affected context, that reviewer's own prior findings, and the verification relevant to that delta.",
      "19. Require a wider reread when the delta changes scope, risk, authority, gates, identity mechanics, or shared behavior.",
      "20. Review scope is semantic, not filename-based. A validator change is not automatically a low-risk delta.",
      "21. A validator change affecting authority, gates, identity, or cleanup receives focused inspection of the changed code plus its affected call sites and tests."
    ].freeze
    PUSH_AUTHORIZATION_RULES = [
      "1. Remote push has two authorization paths: either `Phase branch mode: on` together with an authoritative `Remote push: allowed`, or exact human approval for a specifically identified push.",
      "2. A missing `Remote push` value, or `Remote push: disallowed`, blocks the pre-authorized path. The exact-human-approval path remains available.",
      "3. Local commits to the recorded phase branch remain pre-authorized by phase branch mode alone. Only remote push authority is narrowed.",
      "4. Reviewing an existing unchanged pull request requires no push authorization. Other bounded pull request operations continue under `Review transport: pr`.",
      "5. Plan and per-phase selections and parent defaults are inputs, never execution authorities. Resolve inheritance into explicit effective values for each phase. A phase selection is approved only when recorded in the review-approved plan whose digest binds that phase's authority, or exact human approval for that phase and value is recorded in that authority. An approved selection overrides an inherited default only for that phase and its recorded scope.",
      "6. The sole effective phase authority is the mode-specific record defined by Coordination Record Contract rule 5. A phase pull request in `github-issue` mode references its parent phase authority and cannot grant permission independently.",
      "7. Before execution, record the resolved phase values in that authority and verify agreement with inputs approved under rule 5. Any authority transfer preserves the existing effective phase permissions, records verified takeover, and marks superseded copies non-authoritative; it creates no grant.",
      "8. A missing effective grant or disagreement between effective phase inputs and their authority blocks push until the human resolves it. A different inherited default is not a disagreement when a phase override approved under rule 5 is recorded. Superseded copies cannot authorize execution.",
      "9. `Remote push default: disallowed` states the value a new record starts from. It is not itself an authorization.",
      "10. Option order in any recorded field carries no meaning and never conveys a default."
    ].freeze
    POLICY_TRANSITION_RULES = [
      "1. A workflow remains governed by the workflow revision it recorded. `main` advancing never rebinds it, and no new approval is required merely because the tip moved.",
      "2. The push authorization rules apply to workflows that bind the revision containing them. A workflow pinned to an earlier revision retains its recorded policy until closeout.",
      "3. Offline and `manual-relay` work remain valid. No rule requires reaching the remote in order to load policy.",
      "4. New policy governs only agents that load it. Four Eyes cannot prevent deliberate operation from an obsolete checkout or an obsolete policy revision, and does not claim to.",
      "5. Revision selection is orchestrator-attested, appears in review evidence, and is open to human challenge at any gate."
    ].freeze
    PHASE_BRANCH_MERGE_RULE = "Every reviewed phase-branch pull request uses a commit-preserving merge. Squash is outside the normal phase-branch workflow and requires an explicitly reviewed alternative closeout procedure."
    REVIEW_TRANSPORT_DEFAULT_RULE = "Default to `pr` for remote phase-branch implementation. Use `manual-relay` for local or no-remote work, or when the plan explicitly records that a pull request adds no useful coordination or audit value."
    REMOTE_PUSH_OPTION_LINE = "Remote push: disallowed | allowed"
    REMOTE_PUSH_DEFAULT_LINE = "Remote push default: disallowed"
    REMOTE_PUSH_SLICE_OPTION_LINE = "   - remote push: disallowed | allowed"
    REMOTE_PUSH_FIELD_OCCURRENCES = {
      "docs/playbook.md" => 1,
      "docs/templates.md" => 2,
      "docs/coordination-records.md" => 1,
      "examples/coordination-record.md" => 1,
      "examples/multi-slice-issues.md" => 2
    }.freeze
    REMOTE_PUSH_OPTION_OCCURRENCES = {
      "docs/playbook.md" => 1,
      "docs/templates.md" => 2,
      "docs/coordination-records.md" => 1
    }.freeze
    PHASE_LOCAL_COMMIT_RULE = "When phase branch mode is `on`, the orchestrator may create the recorded phase branch and commit in-scope work to it without asking the human for every local commit."
    PHASE_PREAUTHORIZED_PUSH_RULE = "The pre-authorized remote-push path permits updates to that exact branch without asking the human for every push only if all of these are true:"
    PHASE_PUSH_CONDITIONS = [
      "- the branch name, base branch, and merge target are recorded in the plan or coordination record",
      "- the work stays inside the approved phase scope",
      "- pushes go only to the named phase branch",
      "- the authoritative coordination record says `Remote push: allowed`",
      "- branch pushes do not deploy, mutate live systems, publish releases, or trigger hard-to-reverse external actions",
      "- verification commands are run before review",
      "- reviewers review the branch diff and verification evidence before merge approval"
    ].freeze
    PHASE_EXACT_HUMAN_PUSH_RULE = "Exact human approval for a specifically identified push remains an independent authorization path under Push Authorization."
    ROLE_REVIEW_EFFICIENCY_RULE = "- Plan and implementation review each stop after three panel rounds unless the human grants more. Defer accepted nits by default; bind approval to the complete artifact and focus normal delta inspection unless semantic risk widens."
    LEDGER_GATE_RULE = "`Status` records lifecycle progress. `Gate` records the condition controlling the next transition, such as `none`, `dependencies`, `review`, `human approval`, `external evaluation`, `blocker resolution`, or `human handoff`; do not use it as a duplicate status field."
    LEDGER_EXAMPLE_RULE = "`Status` records lifecycle progress; `Gate` controls transition. Retry metrics waits for Retry classification's terminal resolution and verified result evidence in its parent phase authority. Vendor evaluation's non-terminal `waiting external eval` does not block independent Retry classification."
    PHASE_AUTHORITY_LINE = "- Effective phase authority: <selected PR, identified parent phase record, or canonical local record>"
    READ_ONLY_NO_DIFF_RULE = "If execution is read-only and creates no material diff, use Status `completed` when verification is complete and no further action remains, Status `waiting external eval` with Gate `external evaluation` when an external result is pending, or Status `ready` with Gate `human approval` when an explicit human action is required."
    LIFECYCLE_STATUS_IDENTIFIERS = [
      "Todo",
      "Ready",
      "In Progress",
      "Review",
      "Blocked",
      "Waiting External Eval",
      "Merged, Completed, Abandoned, Retained, or Handed Off"
    ].freeze
    FORGE_LABEL_IDENTIFIERS = [
      "gate:review",
      "gate:human-approval",
      "waiting:external-eval",
      "gate:blocker-resolution"
    ].freeze
    PRE_CLEANUP_STATUS_LINE = "- <ready | review | blocked>"
    PRE_CLEANUP_GATE_LINE = "- <human approval | review | blocker resolution>"
    SYNTHESIS_BLOCKED_RULE = "- The orchestrator will use Status `review` with Gate `review` while another review is required, or Status `blocked` with Gate `blocker resolution` while an in-scope blocker remains; it will fix the phase branch, push the update, and request the required review."
    PUBLIC_PLAN_REFERENCE_TEMPLATE = "Local plan reference: <repository-relative path, opaque reference, or \"none\">"
    PUBLIC_PLAN_REFERENCE_EXAMPLE = "Local plan reference: tmp/example-execution-plan.md"
    FORGE_RESOLUTION_TEMPLATE_LINES = [
      "- PR final state: <merged | closed | open | none>",
      "- Merge commit: <full SHA or none>",
      "- Reviewed head: <full SHA or none>",
      "- Reviewed head ancestral to target: <yes | no | not applicable>"
    ].freeze
    MERGED_FORGE_RESOLUTION_LINES = [
      "- PR final state: merged",
      "- Merge commit: bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "- Reviewed head: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "- Reviewed head ancestral to target: yes"
    ].freeze
    ABANDONED_FORGE_RESOLUTION_LINES = [
      "- PR final state: closed",
      "- Merge commit: none",
      "- Reviewed head: none",
      "- Reviewed head ancestral to target: not applicable"
    ].freeze
    TWO_STAGE_CLOSEOUT_RULE = "Record and verify pre-cleanup branch and worktree facts first. Perform only the authorized worktree, pull-request, and branch resolution, then record and verify the final closeout results in the authoritative coordination record. Remove temporary plans and local state records only after that final record is verified."
    COORDINATION_TERMINAL_OPTIONS_LINE = "- merged | completed | abandoned | retained | handed off"
    TEMPORARY_ARTIFACT_CLEANUP_RULE = "Temporary artifacts after this final record is recorded and verified:"
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
      "launch only the isolated internal Reviewer 1 subagent. Return every external reviewer prompt to the human for relay.",
      "fresh session for the parent workflow",
      "unless explicitly instructed to comment in the tracker",
      "Do not post to the tracker unless explicitly instructed.",
      "unless explicitly instructed to post to the tracker",
      "Do not post to Linear or another tracker unless explicitly instructed.",
      "Do not post directly to the tracker unless explicitly instructed.",
      "Prefer squash merge for phase branches unless the repo has a different convention or the reviewed plan names commits that must remain reachable. When commit preservation is required, prohibit squash, use a commit-preserving merge, and verify every named commit is an ancestor of the merge target before deleting the branch.",
      "Default to `pr` when the repo has a remote and CI or branch protection. Use `manual-relay` for local, no-remote, or simple work where a PR adds overhead.",
      "Remote push: allowed | disallowed",
      "The orchestrator may commit and push the recorded phase branch without per-commit approval when pushes are side-effect-free. Human approval remains required before merge to a protected branch.",
      "- Phase branch commits and pushes may be pre-authorized only by phase branch mode.",
      "from latest successful sync note",
      "direct Claude adapter",
      "Claude adapter status:",
      "Claude contract manifest SHA-256:"
    ].freeze
    RETIRED_POLICY_PATTERNS = [
      /\bLinear\b/i,
      /synced workflow document/i,
      /sync payload/i,
      /standing workflow-doc/i,
      /(?:Claude Reviewer 2 Adapter|claude-reviewer2|reviewer-verdict\.schema|adapter terminal record)/i,
      /one child issue for every/i,
      /phase child issue/i,
      /\btask issue\b/i
    ].freeze

    attr_reader :root

    def initialize(root, bootstrap_members: POST_BOOTSTRAP_MEMBERS)
      @root = File.expand_path(root)
      @bootstrap_members = bootstrap_members
      @markdown_cache = {}
    end

    def check!
      check_derived!
      check_rule_groups!
      report = check_bootstrap!
      check_loading_prompts!
      check_field_order!
      check_reviewer2_handoff!
      check_coordination_contract!
      check_review_efficiency_and_policy!
      check_worktree_contract!
      check_remote_push_fields!
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
      reduction = saved.to_f * 100 / PRE_BOOTSTRAP_TOTAL

      { before: PRE_BOOTSTRAP_TOTAL, after: post_bytes, saved: saved, reduction: reduction }
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
      coordination_record_section = section(templates, "## Coordination Record Template", "## Reviewer Prompt")
      new_prompt = unique_text_prompt(new_section, "workflow field template mismatch")
      coordination_record = unique_text_prompt(coordination_record_section, "workflow field template mismatch")
      expected_lines = workflow_field_lines(new_prompt)
      actual_lines = workflow_field_lines(coordination_record)
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
      rungs = markdown_lines(ladder).each_with_object([]) do |entry, identifiers|
        match = entry[:context] == :prose && entry[:line].match(/\A(\d+)\. /)
        identifiers << match[1] if match
      end
      fail_check("automation ladder mismatch") unless rungs == %w[1 2 3 4]
      require_unique_operative_line_in_section!(playbook, ladder, DIRECT_REVIEW_LADDER_BOUNDARY, "automation ladder boundary mismatch")
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
      check_exact_rule_body!(playbook, "## Coordination Record Contract", "## Local Coordination Record", COORDINATION_REQUIRED_RULES + ["", LEDGER_GATE_RULE], "coordination record")
      check_exact_rule_body!(playbook, "## Local Coordination Record", "## Repository Revision Loading", LOCAL_RECORD_REQUIRED_RULES, "local coordination record")
      check_exact_rule_body!(playbook, "## Repository Revision Loading", "## Policy Transition And Trust Boundary", REVISION_LOADING_REQUIRED_RULES, "repository revision loading")
      fail_check("ledger gate semantics missing") unless exact_line_positions(playbook, LEDGER_GATE_RULE).length == 1
      standard_flow = section(playbook, "## Standard Task Flow", "## Orchestrator Next-Action Rule")
      require_unique_operative_line_in_section!(playbook, standard_flow, READ_ONLY_NO_DIFF_RULE, "read-only transition semantics mismatch")
      gate_state = section(playbook, "## Gate State", "## Gate Rule")
      status_start = gate_state.index("Lifecycle status values:\n")
      gate_start = gate_state.index("Gate values name the condition controlling the next transition:\n")
      fail_check("lifecycle status vocabulary mismatch") unless status_start && gate_start && status_start < gate_start
      status_block = gate_state[status_start...gate_start]
      statuses = markdown_lines(status_block).each_with_object([]) do |entry, identifiers|
        match = entry[:context] == :prose && entry[:line].match(/\A[-*+] ([^:]+):\s+.+\z/)
        identifiers << match[1] if match
      end
      fail_check("lifecycle status vocabulary mismatch") unless statuses == LIFECYCLE_STATUS_IDENTIFIERS
      forge_labels = markdown_lines(gate_state).each_with_object([]) do |entry, identifiers|
        match = entry[:context] == :prose && entry[:line].match(/\A[-*+] `([^`]+)`\z/)
        identifiers << match[1] if match
      end
      fail_check("forge label vocabulary mismatch") unless forge_labels == FORGE_LABEL_IDENTIFIERS

      coordination = normalized_read("docs/coordination-records.md")
      recommended_fields = section(coordination, "## Recommended Fields", "## Recommended Record Shape")
      require_unique_operative_line_in_section!(coordination, recommended_fields, LEDGER_GATE_RULE, "coordination ledger gate semantics missing")
      github_integration = section(coordination, "## GitHub Integration")
      require_unique_operative_line_in_section!(coordination, github_integration, TWO_STAGE_CLOSEOUT_RULE, "two-stage closeout rule missing")

      multi_phase = normalized_read("examples/multi-slice-issues.md")
      require_unique_operative_line_in_section!(multi_phase, multi_phase, LEDGER_EXAMPLE_RULE, "ledger example semantics missing")

      templates = normalized_read("docs/templates.md")
      pre_cleanup = templates.index("## Pre-Cleanup Resolution Record")
      closeout = templates.index("## Closeout")
      fail_check("pre-cleanup and closeout template order mismatch") unless pre_cleanup && closeout && pre_cleanup < closeout
      pre_cleanup_template = section(templates, "## Pre-Cleanup Resolution Record", "## Closeout")
      require_unique_line_in_section!(templates, pre_cleanup_template, PRE_CLEANUP_STATUS_LINE, "pre-cleanup status vocabulary mismatch")
      require_unique_line_in_section!(templates, pre_cleanup_template, PRE_CLEANUP_GATE_LINE, "pre-cleanup gate vocabulary mismatch")
      closeout_template = section(templates, "## Closeout", "## Private Worktree Lifecycle Evidence")
      require_unique_line_in_section!(templates, closeout_template, COORDINATION_TERMINAL_OPTIONS_LINE, "closeout terminal options mismatch")
      require_unique_line_in_section!(templates, closeout_template, TEMPORARY_ARTIFACT_CLEANUP_RULE, "closeout temporary-artifact order mismatch")
      FORGE_RESOLUTION_TEMPLATE_LINES.each do |line|
        require_unique_line_in_section!(templates, closeout_template, line, "closeout forge resolution fields mismatch")
      end
      fail_check("non-terminal status present in closeout template") if closeout_template.include?("waiting external eval")

      synthesis = normalized_read("examples/orchestrator-synthesis.md")
      require_unique_line_in_section!(synthesis, synthesis, SYNTHESIS_BLOCKED_RULE, "synthesis status and gate semantics mismatch")

      coordination_prompt = unique_text_prompt(section(templates, "## Coordination Record Template", "## Reviewer Prompt"), "coordination record template missing")
      require_unique_line_in_section!(coordination_prompt, coordination_prompt, PUBLIC_PLAN_REFERENCE_TEMPLATE, "public plan reference mismatch")
      require_unique_line_in_section!(coordination_prompt, coordination_prompt, PHASE_AUTHORITY_LINE, "phase authority missing")
      fail_check("private path guidance exposed in public coordination record") if coordination_prompt.include?("Local plan path:") || absolute_local_path?(coordination_prompt)

      coordination_example = normalized_read("examples/coordination-record.md")
      require_unique_line_in_section!(coordination_example, coordination_example, PUBLIC_PLAN_REFERENCE_EXAMPLE, "public plan reference example mismatch")
      fail_check("private path exposed in public coordination example") if absolute_local_path?(coordination_example)

      closeout_example = normalized_read("examples/closeout.md")
      merged_example = section(closeout_example, "## Merged PR And Worktree Example", "## Non-Terminal Waiting Example")
      MERGED_FORGE_RESOLUTION_LINES.each do |line|
        fail_check("merged forge resolution evidence mismatch") unless exact_line_positions(merged_example, line).length == 1
      end
      abandoned_example = section(closeout_example, "## Abandoned Worktree Example", "## Kept Branch Example")
      ABANDONED_FORGE_RESOLUTION_LINES.each do |line|
        fail_check("abandoned forge resolution evidence mismatch") unless exact_line_positions(abandoned_example, line).length == 1
      end
    end

    def check_review_efficiency_and_policy!
      playbook = normalized_read("docs/playbook.md")
      enforcement = section(playbook, "## Documentation Enforcement Boundary", "## Review Efficiency")
      require_unique_operative_line_in_section!(playbook, enforcement, DOCUMENTATION_ENFORCEMENT_RULE, "documentation enforcement boundary missing")
      check_exact_rule_body!(playbook, "## Push Authorization", "## Workflow Revision And Artifact Identity", PUSH_AUTHORIZATION_RULES, "push authorization")
      check_exact_rule_body!(playbook, "## Policy Transition And Trust Boundary", "## Right-Sizing Slices", POLICY_TRANSITION_RULES, "policy transition")
      check_exact_rule_body!(playbook, "## Review Efficiency", "## Phase Review", REVIEW_EFFICIENCY_RULES, "review efficiency")

      github_boundary = section(playbook, "## GitHub Boundary", "## Close Discipline")
      require_unique_operative_line_in_section!(playbook, github_boundary, PHASE_BRANCH_MERGE_RULE, "phase-branch merge rule mismatch")
      review_transport = section(playbook, "## Review Transport", "## Review Tier")
      require_unique_operative_line_in_section!(playbook, review_transport, REVIEW_TRANSPORT_DEFAULT_RULE, "review transport default mismatch")

      local_commit_rule = "This intentionally allows local commits to the named phase branch before review. The review gate is before protected-branch push, merge, apply, deploy, or closeout."
      phase_branch = section(playbook, "## Phase Branch Mode", "## Push Authorization")
      require_unique_operative_line_in_section!(playbook, phase_branch, local_commit_rule, "local commit authority changed")
      require_unique_operative_line_in_section!(playbook, phase_branch, PHASE_LOCAL_COMMIT_RULE, "phase-branch local commit grant mismatch")
      require_unique_operative_line_in_section!(playbook, phase_branch, PHASE_PREAUTHORIZED_PUSH_RULE, "phase-branch pre-authorized push rule mismatch")
      PHASE_PUSH_CONDITIONS.each do |line|
        require_unique_operative_line_in_section!(playbook, phase_branch, line, "phase-branch push condition mismatch")
      end
      require_unique_operative_line_in_section!(playbook, phase_branch, PHASE_EXACT_HUMAN_PUSH_RULE, "phase-branch exact-human push rule mismatch")
      expected_push_block = "#{PHASE_PREAUTHORIZED_PUSH_RULE}\n\n#{PHASE_PUSH_CONDITIONS.join("\n")}\n\n#{PHASE_EXACT_HUMAN_PUSH_RULE}"
      fail_check("phase-branch push authorization block mismatch") unless phase_branch.scan(expected_push_block).length == 1

      consequential = [
        ["## Roles", "## Autonomy Mode", "- local commit when phase branch mode is not enabled; remote push when neither the pre-authorized path nor exact human approval applies"],
        ["## Autonomy Mode", "## Phase Branch Mode", "Auto-execute alone does not authorize commit, push, publish, merge, deploy, apply, live/external mutation, destructive/costly action, closeout unless already authorized, scope change, commands outside the pre-authorized classes or reviewed plan, or work outside the assigned coordination record. Local commit requires phase branch mode or explicit human approval. Remote push follows Push Authorization below, including its independent exact-human-approval path. Bounded PR writes require `Review transport: pr`. Merge and protected-branch push remain separate human gates."],
        ["## Phase Branch Flow", "## Standard Task Flow", "4. Orchestrator commits only the named phase branch and pushes it only when Push Authorization permits it."],
        ["## Phase Branch Flow", "## Standard Task Flow", "8. After the embargo lifts, the orchestrator posts carried verdicts verbatim, recomputes repository and artifact identity, synthesizes feedback, fixes blockers on the same phase branch, commits locally when phase branch mode authorizes it, pushes only when Push Authorization permits it, and requests the required delta review."],
        ["## Safety Boundaries", "## GitHub Boundary", "- Phase branch commits may be pre-authorized by phase branch mode. Remote pushes require Push Authorization."]
      ]
      consequential.each do |start_heading, end_heading, line|
        require_unique_operative_line_in_section!(playbook, section(playbook, start_heading, end_heading), line, "push-authority surface mismatch")
      end

      readme = normalized_read("README.md")
      default_workflow = default_workflow_source
      require_unique_operative_line_in_section!(readme, default_workflow, "6. In that worktree, the orchestrator verifies the baseline, implements the whole phase, commits the phase branch, pushes it only when Push Authorization permits it, and runs verification.", "README push rule mismatch")
      readme_transport = section(readme, "## Review Transport", "## Coordination Records")
      require_unique_operative_line_in_section!(readme, readme_transport, REVIEW_TRANSPORT_DEFAULT_RULE, "README review transport default mismatch")
      readme_prompt = unique_text_prompt(section(readme, "## Run Your First Review", "## Example Agent Mix"), "README orchestrator prompt missing")
      prompt_line = "Act as orchestrator. Use phase branch and worktree mode for implementation phases. Keep the primary checkout fixed and coordination-only. Default to `pr` for remote phase-branch implementation; use `manual-relay` for local or no-remote work, or when the plan explicitly records that a pull request adds no useful coordination or audit value. Infer practical phases when needed and keep their dependencies and gates in one parent ledger."
      require_unique_line_in_section!(readme, readme_prompt, prompt_line, "README fenced review transport default mismatch")

      templates = normalized_read("docs/templates.md")
      orchestrator_prompt = unique_text_prompt(section(templates, "## New Orchestrator Prompt", "## Local Plan Template"), "orchestrator prompt missing")
      template_worktree = "If phase branch mode is on and phase branch flow is `implementation-first`, default worktree mode to `on`. Create the phase branch and its dedicated worktree from the recorded base, keep the primary checkout fixed and coordination-only, validate ownership and baseline, implement only in the phase worktree, commit only the named phase branch, push it only when Push Authorization permits it, run verification, set Status `review` and Gate `review`, then return reviewer prompts for the branch diff. Worktree mode `off` while phase branch mode remains `on` requires explicit human approval; worktree mode `on` with phase branch mode `off` is invalid."
      require_unique_line_in_section!(templates, orchestrator_prompt, template_worktree, "template worktree push authorization mismatch")
      template_transport = "#{REVIEW_TRANSPORT_DEFAULT_RULE} Selecting `pr` pre-authorizes creating or updating only the recorded phase pull request, maintaining its bounded description, requesting expected reviewers, and submitting expected reviewer verdicts. It never authorizes merge, unrelated pull request changes, or repository settings."
      require_unique_line_in_section!(templates, orchestrator_prompt, template_transport, "template review transport default mismatch")
      template_push = "Record phase branch mode. When it is `on`, the orchestrator may create and commit to only the named phase branch without per-commit approval. It may push only when Push Authorization permits it and the push has no gated side effect. Existing human gates remain."
      require_unique_line_in_section!(templates, orchestrator_prompt, template_push, "template push authorization mismatch")
      coordination = normalized_read("docs/coordination-records.md")
      integration = section(coordination, "## GitHub Integration")
      require_unique_operative_line_in_section!(coordination, integration, PHASE_BRANCH_MERGE_RULE, "coordination merge rule mismatch")

      role_contracts = normalized_read("docs/role-contracts.md")
      tier = section(role_contracts, "## Tier", "## Human Gate")
      require_unique_operative_line_in_section!(role_contracts, tier, ROLE_REVIEW_EFFICIENCY_RULE, "role-contract review efficiency rule missing")
      human_gate = section(role_contracts, "## Human Gate", "## Artifact")
      require_unique_operative_line_in_section!(role_contracts, human_gate, "- Phase branch mode may pre-authorize local commits only to the recorded phase branch. Remote push follows Push Authorization: the pre-authorized path requires the authoritative coordination record to say `Remote push: allowed`, and exact human approval remains available.", "role-contract push gate mismatch")
      branch = section(role_contracts, "## Branch", "## Loading")
      require_unique_operative_line_in_section!(role_contracts, branch, "- Use one recorded phase branch per independently mergeable phase. Implementation-first work may be committed there before review when phase branch mode authorizes it, and pushed only when Push Authorization permits it.", "role-contract branch push rule mismatch")
    end

    def check_exact_rule_body!(content, start_heading, end_heading, expected, label)
      bounded = section(content, start_heading, end_heading)
      expected_body = "#{start_heading}\n\n#{expected.join("\n")}\n\n"
      fail_check("#{label} rules mismatch") unless bounded == expected_body
    end

    def check_remote_push_fields!
      occurrences = Hash.new(0)
      option_occurrences = Hash.new(0)
      fields = Hash.new { |hash, key| hash[key] = [] }
      defaults = Hash.new { |hash, key| hash[key] = [] }
      slice_fields = Hash.new { |hash, key| hash[key] = [] }
      allowed_lines = [REMOTE_PUSH_OPTION_LINE, "Remote push: disallowed", "Remote push: allowed"]

      markdown_paths.each do |relative|
        lines = normalized_read(relative).lines.map(&:chomp)
        lines.each_with_index do |line, index|
          next if line == "Remote push: allowed | disallowed"

          fields[relative] << [line, index, lines] if line.start_with?("Remote push:")
          defaults[relative] << line if line.start_with?("Remote push default:")
          slice_fields[relative] << [line, index, lines] if line.start_with?("   - remote push:")
        end
      end

      fields.each do |relative, entries|
        fail_check("unexpected remote push field in #{relative}") unless REMOTE_PUSH_FIELD_OCCURRENCES.key?(relative)
        occurrences[relative] = entries.length
        option_occurrences[relative] = entries.count { |line, _index, _lines| line == REMOTE_PUSH_OPTION_LINE }
      end
      REMOTE_PUSH_FIELD_OCCURRENCES.each do |relative, expected|
        fail_check("remote push field occurrence mismatch in #{relative}") unless occurrences[relative] == expected
        fail_check("remote push option occurrence mismatch in #{relative}") unless option_occurrences[relative] == REMOTE_PUSH_OPTION_OCCURRENCES.fetch(relative, 0)
      end
      unexpected = occurrences.keys - REMOTE_PUSH_FIELD_OCCURRENCES.keys
      fail_check("unexpected remote push field occurrence") unless unexpected.empty?

      fields.each do |relative, entries|
        entries.each do |line, index, lines|
          fail_check("remote push field value mismatch in #{relative}") unless allowed_lines.include?(line)
          fail_check("remote push field order mismatch in #{relative}") unless index.positive? && lines[index - 1]&.start_with?("Worktree reference:")
          fail_check("remote push field order mismatch in #{relative}") unless lines[index + 1]&.start_with?("Merge target:")
        end
      end

      fail_check("remote push default occurrence mismatch") unless defaults.keys == ["docs/templates.md"] && defaults["docs/templates.md"] == [REMOTE_PUSH_DEFAULT_LINE]
      fail_check("remote push slice field occurrence mismatch") unless slice_fields.keys == ["docs/templates.md"] && slice_fields["docs/templates.md"].length == 1
      slice_line, slice_index, slice_lines = slice_fields["docs/templates.md"].first
      fail_check("remote push slice field occurrence mismatch") unless slice_line == REMOTE_PUSH_SLICE_OPTION_LINE
      fail_check("remote push slice field order mismatch") unless slice_index.positive? && slice_lines[slice_index - 1] == "   - worktree mode: inherit | on | off"
      fail_check("remote push slice field order mismatch") unless slice_lines[slice_index + 1] == "   - merge target:"

      templates = normalized_read("docs/templates.md")
      local_plan = section(templates, "## Local Plan Template", "## Coordination Record Template")
      plan_lines = local_plan.lines.map(&:chomp)
      default_index = plan_lines.index(REMOTE_PUSH_DEFAULT_LINE)
      fail_check("remote push default missing") unless default_index
      fail_check("remote push default order mismatch") unless plan_lines[default_index - 1] == "Worktree mode default: on | off"
      fail_check("remote push default order mismatch") unless plan_lines[default_index + 1]&.start_with?("Workflow revision:")
    end

    def absolute_local_path?(content)
      boundary = %r{(?:\A|[^A-Za-z0-9._~/\\-])}
      posix = %r{#{boundary}/(?!/)[A-Za-z0-9._-]}
      windows = %r{#{boundary}[A-Za-z]:[\\/][^\s`"'<>)]}
      home = %r{#{boundary}~[A-Za-z0-9._-]*[\\/][^\s`"'<>)]}
      content.match?(posix) || content.match?(windows) || content.match?(home)
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
      local_plan = section(templates, "## Local Plan Template", "## Coordination Record Template")
      if local_plan.lines.any? { |line| line.strip.match?(/\A(?:- )?(?:current review round|worktree reference(?: default)?):/i) }
        fail_check("runtime state field in local plan")
      end
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
      playbook = normalized_read("docs/playbook.md")
      lifecycle_starts = heading_positions(playbook, "## Worktree Lifecycle")
      fail_check("worktree lifecycle section missing or duplicated") unless lifecycle_starts.length == 1
      lifecycle_start = lifecycle_starts.first
      lifecycle_finish = playbook.index(ROLE_BEGIN, lifecycle_start)
      fail_check("worktree lifecycle section boundary missing") unless lifecycle_finish
      lifecycle = playbook[lifecycle_start...lifecycle_finish]
      fail_check("worktree lifecycle rules mismatch") unless Digest::SHA256.hexdigest(lifecycle) == WORKTREE_LIFECYCLE_SHA256

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
      phase_mode = section(coordination, "## Phase Branch Mode", "## Multi-Phase Ledger And Durable Follow-Ups")
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

      expected_prefixes = PRIVATE_WORKTREE_EVIDENCE_LINES.map { |line| line.split(": ", 2).first }
      paths = []
      blocks.each do |block|
        lines = block[:body].lines.map(&:chomp)
        fields = lines.drop(2)
        prefixes = fields.map { |line| line.split(": ", 2).first }
        fail_check("private worktree evidence example mismatch") unless prefixes == expected_prefixes

        record = fields.to_h { |line| line.split(": ", 2) }
        fail_check("private worktree evidence example mismatch") if record.values.any? { |value| value.nil? || value.empty? }
        path = record.fetch("- Resolution path")
        expected = PRIVATE_WORKTREE_EXAMPLE_EXPECTATIONS[path]
        fail_check("private worktree evidence state mismatch: #{path}") unless expected
        expected.each do |field, value|
          fail_check("private worktree evidence state mismatch: #{path}") unless record.fetch(field) == value
        end
        subject = record.fetch("- Expected branch/ref or reviewed SHA")
        valid_subject = if path == "merged"
                          subject.match?(/\Arefs\/heads\/phase\/\S+ at [0-9a-f]{40}\z/)
                        else
                          subject.match?(/\A[0-9a-f]{40}\z/)
                        end
        fail_check("private worktree evidence state mismatch: #{path}") unless valid_subject
        if path == "merged"
          fields = {
            "- Base SHA" => /\A[0-9a-f]{40}\z/,
            "- Stored primary fingerprint" => /\AHEAD=[0-9a-f]{40}; staged=[0-9a-f]{64}; unstaged=[0-9a-f]{64}; untracked=[0-9a-f]{64}\z/,
            "- Remote identity/name/full ref" => /\A\S+ \| \S+ \| refs\/heads\/phase\/\S+\z/,
            "- Blocker" => /\Anone\z/
          }
          fail_check("private worktree evidence state mismatch: #{path}") unless fields.all? { |field, pattern| record.fetch(field).match?(pattern) }
        end
        paths << path
      end
      fail_check("private worktree evidence example paths mismatch") unless paths.sort == PRIVATE_WORKTREE_EXAMPLE_EXPECTATIONS.keys.sort
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
      cache_key = content.dup.freeze
      @markdown_cache.fetch(cache_key) do
        @markdown_cache[cache_key] = parse_markdown_lines(cache_key)
      end
    end

    def parse_markdown_lines(source)
      entries = []
      offset = 0
      fence = nil
      in_comment = false

      source.each_line do |raw_line|
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
          indented_content = line.lstrip
          if container_prefixed_heading?(indented_content)
            fail_check("ambiguous indented heading is not allowed in checked workflow Markdown")
          elsif raw_html_after_containers?(indented_content)
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

      entries.each(&:freeze).freeze
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
      @source_root = File.realpath(source_root)
      @checks = 0
      @passed_checks = []
    end

    def run!
      setup_fixture
      with_fixture { |root| assert_bootstrap_report(root, Checker.new(root).check!) }
      pass("valid repository")

      assert_failure("source-root mutation refused", "outside the fixture root") do
        write(@source_root, "README.md", "not written")
      end

      with_fixture do |root|
        assert_failure("path traversal refused", "outside the fixture root") do
          write(root, "../outside-fixture", "not written")
        end
      end

      with_fixture do |root|
        outside = Dir.mktmpdir("fe-link-")
        link = File.join(root, "link")
        File.symlink(outside, link)
        begin
          assert_failure("link refused", "contains a symlink") do
            write(root, "link/outside.txt", "changed")
          end
          raise "symlink escaped" if File.exist?(File.join(outside, "outside.txt"))
        ensure
          File.unlink(link) if File.symlink?(link)
          FileUtils.remove_entry(outside) if File.directory?(outside)
        end
      end

      baseline_readme = nil
      begin
        with_fixture do |root|
          baseline_readme = read(root, "README.md")
          append(root, "README.md", "intentional failed-case mutation\n")
          raise "intentional in-fixture failure"
        end
      rescue RuntimeError => error
        raise unless error.message == "intentional in-fixture failure"
      end
      with_fixture do |root|
        raise "failed case was not restored" unless read(root, "README.md") == baseline_readme
      end
      pass("failed case restores shared fixture")

      with_fixture do |root|
        checker = Checker.new(root)
        original = read(root, "docs/templates.md")
        cached = checker.send(:markdown_lines, original)
        raise "Markdown cache miss for identical content" unless checker.send(:markdown_lines, original).equal?(cached)

        append(root, "docs/templates.md", "\nCache mutation.\n")
        changed = read(root, "docs/templates.md")
        reparsed = checker.send(:markdown_lines, changed)
        fresh = Checker.new(root).send(:markdown_lines, changed)
        raise "Markdown cache survived changed content" if reparsed.equal?(cached)
        raise "cached and uncached Markdown parses differ" unless reparsed == fresh
      end
      pass("Markdown cache is content-bound across mutation")

      expect_failure("derived-file drift", "generated Role Contracts differ") do |root|
        append(root, "docs/role-contracts.md", "drift\n")
      end

      expect_failure("duplicate Role Contracts marker pair", "marked Role Contracts source missing or malformed") do |root|
        append(root, "docs/playbook.md", "\n#{Checker::ROLE_BEGIN}# Competing Role Contracts source\n#{Checker::ROLE_END}\n")
      end

      expect_failure("empty role-contract rule group", "empty role-contract rule group: Authority") do |root|
        content = read(root, "docs/playbook.md")
        content.sub!(/\n## Authority\n.*?(?=\n## Orchestrator\n)/m, "\n## Authority\n") || raise("Authority fixture missing")
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

      [["README.md", "README.md", "## Default Workflow\n", "README bootstrap metrics follow changed bytes"],
        ["docs/playbook.md", "docs/role-contracts.md", "\n## Authority\n", "Role Contracts metrics follow changed bytes"]].each do |source, member, anchor, name|
        with_fixture do |root|
          raise "bootstrap fixture anchor changed" unless read(root, source).scan(anchor).size == 1
          before = read(root, member).gsub("\r\n", "\n").bytesize
          replace(root, source, anchor, "#{anchor}\n")
          Checker.new(root).write_derived! if source != member
          raise "bootstrap fixture mutation failed" unless read(root, member).gsub("\r\n", "\n").bytesize == before + 1
          assert_bootstrap_report(root, Checker.new(root).check!)
        end
        pass(name)
      end

      expect_failure("omitted current bootstrap budget", "current bootstrap budget record missing") do |root|
        replace(root, "README.md", "#{Checker::POST_BOOTSTRAP_RECORD_RULE}\n", "")
      end

      expect_failure("orchestrator prompt mismatch", "orchestrator loading prompt mismatch") do |root|
        replace(root, "README.md", Checker::LOADING_SENTENCE, "Load everything first.")
      end

      expect_failure("operative loading expansion", "default loading instructions mismatch") do |root|
        block = Checker::DEFAULT_LOADING_BLOCK
        replace(root, "README.md", block, "#{block.chomp}\n- Four Eyes Playbook\n\n")
      end

      expect_failure("field-order drift", "workflow field order mismatch") do |root|
        path = "docs/templates.md"
        content = read(root, path)
        first = "Review tier: skip | light | full\n"
        second = "#{Checker::HANDOFF_MODE_LINE}\n"
        content.sub!(second + first, first + second) || raise("test fixture field pair missing")
        write(root, path, content)
      end

      expect_failure("Reviewer 2 option drift", "Reviewer 2 option block mismatch") do |root|
        content = read(root, "docs/templates.md")
        content.gsub!(Checker::REVIEWER2_HANDOFF_LINE, "Reviewer 2 handoff: direct Claude reviewer | manual external reviewer")
        write(root, "docs/templates.md", content)
      end

      with_fixture do |root|
        replace(root, "docs/playbook.md", "1. Current baseline: PR transport with human-invoked external reviewers.", "1. Current baseline uses human-invoked external reviewers over PR transport.")
        Checker.new(root).check!
      end
      pass("automation ladder explanation may be reworded")

      expect_failure("automation ladder boundary omission", "automation ladder boundary mismatch") do |root|
        replace(root, "docs/playbook.md", "#{Checker::DIRECT_REVIEW_LADDER_BOUNDARY}\n", "")
      end

      expect_failure("coordination option drift", "invalid selected coordination record in README.md") do |root|
        replace(root, "README.md", "\n#{Checker::COORDINATION_RECORD_LINE}\n", "\nCoordination record: pr | local | github-issue\n")
      end

      [
        ["coordination", Checker::COORDINATION_REQUIRED_RULES.first, "coordination record rules mismatch"],
        ["local coordination", Checker::LOCAL_RECORD_REQUIRED_RULES.first, "local coordination record rules mismatch"],
        ["repository revision", Checker::REVISION_LOADING_REQUIRED_RULES.first, "repository revision loading rules mismatch"],
        ["review efficiency", Checker::REVIEW_EFFICIENCY_RULES.first, "review efficiency rules mismatch"],
        ["push authorization", Checker::PUSH_AUTHORIZATION_RULES.first, "push authorization rules mismatch"],
        ["policy transition", Checker::POLICY_TRANSITION_RULES.first, "policy transition rules mismatch"]
      ].each do |name, line, error|
        expect_omission_failure(name, "docs/playbook.md", line, error)
      end

      [
        ["coordination", "## Coordination Record Contract", "coordination record rules mismatch"],
        ["local record", "## Local Coordination Record", "local coordination record rules mismatch"],
        ["revision loading", "## Repository Revision Loading", "repository revision loading rules mismatch"]
      ].each do |name, heading, error|
        expect_failure("#{name} inserted prose", error) do |root|
          replace(root, "docs/playbook.md", "#{heading}\n\n", "#{heading}\n\nExtra.\n\n")
        end
      end

      [
        [Checker::COORDINATION_REQUIRED_RULES, "coordination record", [
          [16, "terminal only", /\A.+\z/, "16. A phase becomes `ready` only when every phase it depends on is terminal."],
          [16, "unverified result", /available and verified/, "available"],
          [16, "dependency removal", /existing scope-change and plan-review gates/, "no gates"],
          [25, "partial success", /never call/, "call"],
          [6, "early authority", /never grants/, "grants"],
          [9, "lost permissions", /unchanged effective permissions/, "default permissions"],
          [9, "uncertain takeover", /stops execution and hands off/, "activates the candidate"]
        ]],
        [Checker::PUSH_AUTHORIZATION_RULES, "push authorization", [
          [6, "universal PR", /\A.+\z/, "6. The pull request always governs execution."],
          [8, "stale grant", /Superseded copies cannot/, "Superseded copies can"],
          [5, "default grant", /inputs, never execution authorities/, "execution authorities"],
          [8, "mismatch allowed", /blocks push until the human resolves it/, "permits push"],
          [5, "approval missing", /A phase selection [^.]+\. /, ""]
        ]]
      ].each do |rules, error, cases|
        cases.each do |number, name, pattern, value|
          expect_failure(name, "#{error} rules mismatch") do |root|
            line = rules.fetch(number - 1)
            raise "ambiguous mutation" unless read(root, "docs/playbook.md").scan(line).size == 1 && line.scan(pattern).size == 1
            replace(root, "docs/playbook.md", line, line.sub(pattern, value))
          end
        end
      end

      [
        ["docs/templates.md", Checker::PHASE_AUTHORITY_LINE, "phase authority missing"],
        ["examples/multi-slice-issues.md", Checker::LEDGER_EXAMPLE_RULE, "ledger example semantics missing"]
      ].each do |path, line, error|
        expect_failure(error, error) do |root|
          raise "ambiguous guidance" unless read(root, path).scan(line).size == 1
          replace(root, path, line + "\n", "")
          append(root, path, "\n" + line + "\n") if path == "docs/templates.md"
        end
      end

      expect_failure("documentation enforcement boundary omission", "documentation enforcement boundary missing") do |root|
        replace(root, "docs/playbook.md", "#{Checker::DOCUMENTATION_ENFORCEMENT_RULE}\n", "")
      end

      expect_omission_failure("phase-branch merge", "docs/playbook.md", Checker::PHASE_BRANCH_MERGE_RULE, "phase-branch merge rule mismatch")

      [
        ["value", "examples/coordination-record.md", "Remote push: allowed\n", "Remote push: maybe\n", "field value"],
        ["option", "examples/coordination-record.md", "Remote push: allowed\n", "#{Checker::REMOTE_PUSH_OPTION_LINE}\n", "option occurrence"],
        ["count", "examples/coordination-record.md", "Remote push: allowed\n", "Remote push: allowed\nRemote push: allowed\n", "field occurrence"],
        ["default", "docs/templates.md", "#{Checker::REMOTE_PUSH_DEFAULT_LINE}\n", "", "default occurrence"],
        ["slice field", "docs/templates.md", "#{Checker::REMOTE_PUSH_SLICE_OPTION_LINE}\n", "   - remote push: allowed | disallowed\n", "slice field occurrence"]
      ].each do |name, path, from, to, error|
        expect_failure(name, "push #{error} mismatch") do |root|
          replace(root, path, from, to)
        end
      end

      expect_failure("order", "remote push field order mismatch", :check_remote_push_fields!) do |root|
        replace(
          root,
          "examples/coordination-record.md",
          "Worktree reference: phase-execution/EXAMPLE-retry-worktree\nRemote push: allowed\n",
          "Remote push: allowed\nWorktree reference: phase-execution/EXAMPLE-retry-worktree\n"
        )
      end

      expect_failure("local commit authority narrowed", "local commit authority changed") do |root|
        replace(root, "docs/playbook.md", "This intentionally allows local commits to the named phase branch before review.", "Local commits require remote-push approval before review.")
      end

      expect_failure("role-contract exact-human push path removed", "role-contract push gate mismatch", :check_review_efficiency_and_policy!) do |root|
        line = "- Phase branch mode may pre-authorize local commits only to the recorded phase branch. Remote push follows Push Authorization: the pre-authorized path requires the authoritative coordination record to say `Remote push: allowed`, and exact human approval remains available."
        replace(root, "docs/playbook.md", line, "- Phase branch mode may pre-authorize local commits only to the recorded phase branch. Remote push requires `Remote push: allowed`.")
        Checker.new(root).write_derived!
      end

      expect_failure("read-only transition semantics omission", "read-only transition semantics mismatch") do |root|
        replace(root, "docs/playbook.md", "#{Checker::READ_ONLY_NO_DIFF_RULE}\n", "")
      end

      expect_failure("lifecycle ready status omission", "lifecycle status vocabulary mismatch") do |root|
        replace(root, "docs/playbook.md", "- Ready: every dependency has verified terminal resolution and available verified required results; the phase awaits an authorized transition\n", "")
      end

      with_fixture do |root|
        replace(root, "docs/playbook.md", "- Ready: every dependency has verified terminal resolution and available verified required results; the phase awaits an authorized transition", "- Ready: terminal prerequisites have verified available required results; execution still needs its gate")
        Checker.new(root).check!
      end
      pass("lifecycle explanation may be reworded")

      expect_failure("unknown lifecycle status addition", "lifecycle status vocabulary mismatch") do |root|
        replace(root, "docs/playbook.md", "- Merged, Completed, Abandoned, Retained, or Handed Off: verified terminal resolution\n", "- Merged, Completed, Abandoned, Retained, or Handed Off: verified terminal resolution\n- Draft: not a real lifecycle status\n")
      end

      expect_failure("non-contract forge state label", "forge label vocabulary mismatch") do |root|
        replace(root, "docs/playbook.md", "- `waiting:external-eval`\n", "- `waiting:external-eval`\n- `state:applied-awaiting-verification`\n")
      end

      expect_failure("independent absolute path in public coordination template", "private path guidance exposed in public coordination record") do |root|
        replace(root, "docs/templates.md", Checker::PUBLIC_PLAN_REFERENCE_TEMPLATE, "#{Checker::PUBLIC_PLAN_REFERENCE_TEMPLATE}\nPrivate evidence: /srv/four-eyes/evidence")
      end

      expect_failure("Windows absolute path in public coordination example", "private path exposed in public coordination example") do |root|
        replace(root, "examples/coordination-record.md", Checker::PUBLIC_PLAN_REFERENCE_EXAMPLE, "#{Checker::PUBLIC_PLAN_REFERENCE_EXAMPLE}\nPrivate evidence: C:\\four-eyes\\evidence")
      end

      expect_failure("non-terminal closeout option", "closeout terminal options mismatch") do |root|
        replace(root, "docs/templates.md", Checker::COORDINATION_TERMINAL_OPTIONS_LINE, "- completed | waiting external eval | merged")
      end

      expect_failure("two-stage closeout omission", "two-stage closeout rule missing") do |root|
        replace(root, "docs/coordination-records.md", "#{Checker::TWO_STAGE_CLOSEOUT_RULE}\n", "")
      end

      expect_failure("temporary-artifact closeout ordering omission", "closeout temporary-artifact order mismatch") do |root|
        replace(root, "docs/templates.md", "#{Checker::TEMPORARY_ARTIFACT_CLEANUP_RULE}\n", "")
      end

      expect_failure("worktree field omission", "workflow field missing: Worktree mode:") do |root|
        replace(root, "docs/templates.md", "#{Checker::WORKTREE_OPTION_LINES.join("\n")}\n", "")
      end

      expect_failure("invalid selected worktree mode", "invalid selected worktree mode") do |root|
        replace(root, "examples/coordination-record.md", "Worktree mode: on", "Worktree mode: maybe")
      end

      expect_failure("invalid phase/worktree mode combination", "invalid phase/worktree mode combination") do |root|
        replace(root, "examples/coordination-record.md", "Phase branch mode: on", "Phase branch mode: off")
      end

      expect_failure("missing executable worktree reference", "executable worktree reference missing") do |root|
        replace(root, "examples/coordination-record.md", "Worktree reference: phase-execution/EXAMPLE-retry-worktree", "Worktree reference: none")
      end

      ["Worktree reference default: none", "   - current review round: <positive integer>",
        "   - worktree reference: none | <ownership-category>/<opaque worktree reference>"].each do |line|
        expect_failure("retired plan field: #{line.strip}", "runtime state field in local plan") do |root|
          anchor = "Cleanup: remove after closeout\n"
          raise "plan fixture anchor changed" unless read(root, "docs/templates.md").scan(anchor).size == 1
          replace(root, "docs/templates.md", anchor, "#{anchor}#{line}\n")
        end
      end

      [["Worktree mode default: on | off", "default"],
        ["   - worktree mode: inherit | on | off", "slice field"]].each do |line, field|
        expect_failure("plan push #{field} predecessor", "remote push #{field} order mismatch", :check_remote_push_fields!) do |root|
          anchor = "#{line}\n"
          raise "plan fixture anchor changed" unless read(root, "docs/templates.md").scan(anchor).size == 1
          replace(root, "docs/templates.md", anchor, "#{anchor}Unrelated line\n")
        end
      end

      [0, 29, -1].each_with_index do |rule_index, sample|
        expect_failure("worktree lifecycle sample #{sample + 1}", "worktree lifecycle rules mismatch") do |root|
          remove_worktree_rule(root, rule_index)
        end
      end

      expect_failure("unchecked worktree lifecycle addition", "worktree lifecycle rules mismatch") do |root|
        replace(root, "docs/playbook.md", "\n### Mode And Location\n", "\n### Mode And Location\n\n- Unreviewed lifecycle expansion.\n")
      end

      expect_failure("default workflow worktree omission", "default workflow worktree rule missing", :check_worktree_contract!) do |root|
        replace(root, "README.md", "#{Checker::DEFAULT_WORKTREE_RULE}\n", "")
      end

      expect_failure("role-contract worktree omission", "role-contract worktree rule missing", :check_worktree_contract!) do |root|
        replace(root, "docs/playbook.md", "#{Checker::ROLE_WORKTREE_RULE}\n", "")
        Checker.new(root).write_derived!
      end

      expect_failure("worktree closeout field omission", "worktree closeout example field mismatch") do |root|
        replace(root, "examples/closeout.md", "- Owner/category: orchestrator/phase-execution\n", "")
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

      expect_failure("private worktree evidence template omission", "private worktree evidence template mismatch") do |root|
        full_block = "#{Checker::PRIVATE_WORKTREE_EVIDENCE_LINES.join("\n")}\n"
        short_block = "#{Checker::PRIVATE_WORKTREE_EVIDENCE_LINES[0...-1].join("\n")}\n"
        replace(root, "docs/templates.md", full_block, short_block)
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

      expect_failure("reviewer cleanup owner mismatch", "private worktree evidence state mismatch: reviewer detached") do |root|
        replace(root, "examples/closeout.md", "Reviewer 2/reviewer-verification | Reviewer 2", "Reviewer 2/reviewer-verification | orchestrator")
      end

      [
        ["detached base SHA", "- Base SHA: not applicable\n", "- Base SHA: #{'1' * 40}\n", "reviewer detached"],
        ["detached fingerprint", "- Stored primary fingerprint: not applicable\n", "- Stored primary fingerprint: HEAD=#{'1' * 40}\n", "reviewer detached"],
        ["detached local ref", "- Local ref pre-delete check: not applicable\n", "- Local ref pre-delete check: exact match\n", "reviewer detached"],
        ["detached remote tuple", "- Remote identity/name/full ref: none/none/none\n", "- Remote identity/name/full ref: example.invalid/four-eyes | origin | refs/heads/phase/example\n", "reviewer detached"]
      ].each do |name, from, to, path|
        expect_failure("#{name} mismatch", "private worktree evidence state mismatch: #{path}") do |root|
          replace(root, "examples/closeout.md", from, to)
        end
      end

      expect_failure("merged abbreviated reviewed head", "private worktree evidence state mismatch: merged") do |root|
        replace(root, "examples/closeout.md", "refs/heads/phase/EXAMPLE-retry-behavior at aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "refs/heads/phase/EXAMPLE-retry-behavior at abc1234")
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

      expect_failure("Setext duplicate section heading", "section missing or duplicated: ## New Orchestrator Prompt") do |root|
        append(root, "docs/templates.md", "\nNew Orchestrator Prompt\n-----------------------\n\nDuplicate prompt.\n")
      end

      expect_failure("unordered-list continuation cannot hide duplicate H2", "ambiguous indented heading") do |root|
        append(root, "docs/templates.md", "\n- item\n    ## New Orchestrator Prompt\n")
      end

      expect_failure("same-line list item cannot hide duplicate H2", "list-contained headings") do |root|
        append(root, "docs/templates.md", "\n- ## New Orchestrator Prompt\n")
      end

      expect_failure("bare blockquote cannot hide duplicate H2", "container-prefixed headings") do |root|
        append(root, "docs/templates.md", "\n> ## New Orchestrator Prompt\n")
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

      expect_failure("formatted duplicate level-two heading", "unsupported inline syntax in level-two heading") do |root|
        append(root, "docs/templates.md", "\n## *New Orchestrator Prompt*\n")
      end

      expect_failure("invalid backtick fence hides duplicate section heading", "multiline or unclosed inline code spans are not allowed") do |root|
        append(root, "docs/templates.md", "\n```invalid`info\n## New Orchestrator Prompt\n```\n")
      end

      expect_failure("commented required section heading", "section missing or duplicated: ## New Orchestrator Prompt") do |root|
        replace(root, "docs/templates.md", "## New Orchestrator Prompt\n", "<!--\n## New Orchestrator Prompt\n-->\n")
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
        replace(root, "README.md", "\n## Use It For\n", "\nUnexpected Peer Section\n-----------------------\n\nNot part of Default Workflow.\n\n## Use It For\n")
        source = Checker.new(root).send(:default_workflow_source)
        raise "Setext heading did not bound Default Workflow" if source.include?("Unexpected Peer Section")
      end
      pass("Setext heading bounds Default Workflow")

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
        checker = Checker.new(root)
        checker.write_derived!
        checker.send(:check_derived!)
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

      expect_failure("retired task-issue role", "retired coordination policy present") do |root|
        append(root, "README.md", "\nUse a task issue as the required workflow state record.\n")
      end

      expect_failure("retired reviewer adapter", "retired coordination policy present") do |root|
        append(root, "README.md", "\nClaude Reviewer 2 Adapter\n")
      end

      Checker::STALE_PHRASES.each do |phrase|
        expect_failure("stale phrase: #{phrase}", "stale phrase present") do |root|
          append(root, "README.md", "\n#{phrase}\n")
        end
      end

      verify_source_unchanged!
      pass("source checkout remains unchanged")
      puts "check-docs self-test: #{@checks} checks passed"
    rescue StandardError => error
      @passed_checks.each { |name| warn "PASS: #{name}" }
      warn "FAIL: #{error.message}"
      raise
    ensure
      teardown_fixture
    end

    private

    def expect_omission_failure(name, path, line, error)
      expect_failure("#{name} rule omission", error) do |root|
        replace(root, path, "#{line}\n", "")
      end
    end

    def remove_worktree_rule(root, index)
      content = read(root, "docs/playbook.md")
      start = content.index("## Worktree Lifecycle\n") || raise("worktree lifecycle fixture missing")
      finish = content.index(Checker::ROLE_BEGIN, start) || raise("worktree lifecycle boundary missing")
      rules = content[start...finish].lines.reject { |line| line.strip.empty? || line.start_with?("#") }
      replace(root, "docs/playbook.md", rules.fetch(index), "")
    end

    def with_fixture
      restore_fixture!
      yield @fixture_root
    ensure
      restore_fixture! if @fixture_root
    end

    def setup_fixture
      @source_snapshot = source_snapshot
      @fixture_root = File.realpath(Dir.mktmpdir("four-eyes-check-docs-"))
      raise CheckError, "self-test fixture must be outside source checkout" if beneath?(@fixture_root, @source_root)

      %w[AGENTS.md README.md docs examples].each do |entry|
        FileUtils.cp_r(File.join(@source_root, entry), File.join(@fixture_root, entry))
      end
      @fixture_snapshot = fixture_snapshot
    end

    def teardown_fixture
      return unless @fixture_root

      source_error = begin
        verify_source_unchanged!
        nil
      rescue StandardError => error
        error
      end
      FileUtils.remove_entry(@fixture_root) if File.directory?(@fixture_root)
      @fixture_root = nil
      raise source_error if source_error
    end

    def source_snapshot
      source_paths.each_with_object({}) do |relative, snapshot|
        candidate = File.join(@source_root, relative)
        snapshot[relative] = File.symlink?(candidate) ? "L#{File.readlink(candidate)}" : "F#{File.binread(candidate)}"
      end
    end

    def source_paths
      stdout = IO.popen(["git", "-C", @source_root, "ls-files", "-coz", "--exclude-standard"], "rb", &:read)
      raise CheckError, "source list failed" unless $?.success?

      stdout.split("\0").sort
    end

    def fixture_snapshot
      Dir.chdir(@fixture_root) do
        Dir.glob("**/*", File::FNM_DOTMATCH).sort.each_with_object({}) do |relative, snapshot|
          candidate = File.join(@fixture_root, relative)
          raise CheckError, "fixture has a symlink" if File.symlink?(candidate)

          snapshot[relative] = File.binread(candidate) if File.file?(candidate)
        end
      end
    end

    def restore_fixture!
      current = fixture_snapshot
      (current.keys - @fixture_snapshot.keys).each do |relative|
        target = fixture_path(@fixture_root, relative)
        File.delete(target)
      end
      @fixture_snapshot.each do |relative, content|
        target = fixture_path(@fixture_root, relative)
        File.binwrite(target, content) unless File.file?(target) && File.binread(target) == content
      end
      raise CheckError, "self-test fixture restoration failed" unless fixture_snapshot == @fixture_snapshot
    end

    def verify_source_unchanged!
      raise CheckError, "self-test modified the source checkout" unless source_snapshot == @source_snapshot
    end

    def beneath?(path, root)
      path == root || path.start_with?("#{root}#{File::SEPARATOR}")
    end

    def fixture_path(root, relative)
      canonical_root = File.realpath(root)
      raise CheckError, "self-test mutation target is outside the fixture root" unless canonical_root == @fixture_root

      target = File.expand_path(relative, canonical_root)
      raise CheckError, "self-test mutation target is outside the fixture root" unless beneath?(target, canonical_root) && target != canonical_root

      current = canonical_root
      target.delete_prefix("#{canonical_root}#{File::SEPARATOR}").split(File::SEPARATOR).each do |component|
        current = File.join(current, component)
        raise CheckError, "target contains a symlink" if File.symlink?(current)
      end

      parent = File.realpath(File.dirname(target))
      raise CheckError, "self-test mutation target is outside the fixture root" unless beneath?(parent, canonical_root)

      target
    end

    def assert_bootstrap_report(root, actual)
      readme = read(root, "README.md").gsub("\r\n", "\n")
      unless readme.scan(/^## Default Workflow$/).size == 1 && readme.scan(/^## Use It For$/).size == 1
        raise "bootstrap oracle fixture anchors changed"
      end
      body = readme[/^## Default Workflow\n.*?(?=^## Use It For\n)/m] || raise("bootstrap oracle section missing")
      after = body.bytesize + read(root, "docs/role-contracts.md").gsub("\r\n", "\n").bytesize
      before = Checker::PRE_BOOTSTRAP_COMPONENTS.values.sum
      saved = before - after
      unless actual.values_at(:before, :after, :saved) == [before, after, saved] &&
          format("%.2f", actual.fetch(:reduction)) == format("%.2f", 100.0 * saved / before)
        raise "bootstrap arithmetic mismatch"
      end
    end

    def expect_failure(name, message, check = :check!)
      with_fixture do |root|
        yield root
        assert_failure(name, message) { Checker.new(root).send(check) }
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
      @passed_checks << name
    end

    def read(root, path)
      File.binread(fixture_path(root, path))
    end

    def write(root, path, content)
      File.binwrite(fixture_path(root, path), content)
    end

    def append(root, path, content)
      File.open(fixture_path(root, path), "ab") { |file| file.write(content) }
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
