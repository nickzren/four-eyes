#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "tmpdir"
require "uri"

module FourEyesDocs
  class CheckError < StandardError; end

  class Checker
    ROLE_BEGIN = "<!-- BEGIN FOUR EYES ROLE CONTRACTS SOURCE -->\n"
    ROLE_END = "<!-- END FOUR EYES ROLE CONTRACTS SOURCE -->"
    RULE_GROUPS = ["Authority", "Orchestrator", "Reviewer", "Tier", "Human Gate", "Artifact", "Tracker", "Branch", "Loading"].freeze
    LOADING_SENTENCE = "Load the task issue, Four Eyes Default Workflow, and Four Eyes Role Contracts first. Load Four Eyes Playbook, Templates, Issue Tracker Setup, or Linear Setup only when the task needs their exact rule, template, tracker behavior, or sync procedure."
    DEFAULT_LOADING_BLOCK = "Default orchestrator bootstrap is:\n\n- the task issue\n- Four Eyes Default Workflow\n- Four Eyes Role Contracts\n\n"
    DEFAULT_LOADING_BULLETS = ["- the task issue", "- Four Eyes Default Workflow", "- Four Eyes Role Contracts"].freeze
    LOAD_ON_DEMAND_RULE = "Load Four Eyes Playbook only for exact policy detail or canonical commands, Templates only to fill an artifact, Issue Tracker Setup only for tracker-neutral behavior, and Linear Setup only for creation or sync. Reviewers receive a filled immutable packet and exact task evidence; they do not need the workflow-document set unless a disputed rule itself is under review."
    ROLE_LOADING_RULE = "- Default orchestrator bootstrap is the task issue, Four Eyes Default Workflow, and Four Eyes Role Contracts."
    TRACKER_LOADING_RULE = "Load the task issue, Four Eyes Default Workflow, and Four Eyes Role Contracts by default. Load the Playbook, Templates, Issue Tracker Setup, or Linear Setup only when their exact policy, template, tracker behavior, or sync procedure is needed. Reviewers receive filled immutable packets and do not need the workflow-document set."
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
      "docs/issue-tracker-setup.md" => 1,
      "docs/linear-setup.md" => 1,
      "examples/task-issue.md" => 1,
      "examples/multi-slice-issues.md" => 3
    }.freeze
    REVIEWER2_OPTION_OCCURRENCES = {
      "README.md" => 1,
      "docs/playbook.md" => 1,
      "docs/templates.md" => 2,
      "docs/issue-tracker-setup.md" => 1,
      "docs/linear-setup.md" => 1
    }.freeze
    AUTOMATION_LADDER_LINES = [
      "1. Current baseline: PR transport with human-invoked external reviewers.",
      "2. Current Codex-led default: reused named internal Reviewer 1, human-relayed external Reviewer 2.",
      "3. Optional where the orchestrator platform provides native isolated invocation and the human records the exact phase, full model identity, maximum calls, and maximum cost amount and currency: orchestrator invokes only Reviewer 2 directly.",
      "4. Future: CI-triggered reviewers.",
      "Rung 3 is never globally or orchestrator-authorized; each task or phase requires the recorded human decision and enforceable bounds. Rung 4 is not implemented or pre-authorized."
    ].freeze
    SOURCE_MAP_INTRO = "Use this fixed title order:"
    CANONICAL_BODY_RULE = "Canonical source-body bytes are defined once here: require valid UTF-8; convert CRLF to LF; reject any remaining bare CR or NUL; remove every trailing LF; append exactly one LF. `Source body SHA-256` hashes those canonical body bytes, including the one final LF."
    MARKER_RULE = "Each synced document starts with exactly `Workflow revision: <full-sha>`, then `Source body SHA-256: <digest>`, then one blank line, followed by the canonical source body."
    LINEAR_SERIALIZATION_RULE = "Linear may reserialize Markdown because documents are stored as rich text. The source-body digest attests to canonical committed source bytes; it is not a digest of Linear's serialized body. The repo remains the byte-exact source of truth."
    RUNTIME_DOCUMENT_RULE = "- five runtime documents named Four Eyes Default Workflow, Four Eyes Playbook, Four Eyes Templates, Four Eyes Issue Tracker Setup, and Four Eyes Role Contracts"
    READBACK_RULE = "5. Read all six documents back once. For each document, require the exact expected title, exact workflow revision and source-body digest marker block, the expected first Markdown heading, and non-empty content after that heading."
    READBACK_STABILITY_RULE = "6. Write each first readback content back unchanged, read the document a second time, and require the exact title again plus byte-identical first and second content. This confirms stable Linear serialization for that write/read cycle; it does not prove source-body byte preservation."
    READBACK_FAILURE_RULE = "7. Any missing document, title mismatch, abbreviated or mixed revision, wrong source-body digest, malformed marker block, missing expected heading, empty content after the heading, or unstable second readback leaves the sync gate open."
    READBACK_RECORD_RULE = "8. Record the full pushed revision, generated manifest digest, each stable readback content SHA-256, and six successful marker, heading/content, and stability checks in the standing workflow-doc review issue."
    STANDING_READBACK_RULE = "- Readback: all six marker and heading/content checks passed; titles exact and first/second content byte-identical"
    STANDING_READBACK_DIGEST_RULE = "- Stable readback content SHA-256: <one bare digest per title>"
    STANDING_DESCRIPTION_INTRO = "Use this issue for reviews and sync evidence for the Four Eyes workflow documents."
    PRE_BOOTSTRAP_COMPONENTS = {
      "README.md#Default Workflow" => 2_630,
      "docs/playbook.md" => 54_802,
      "docs/templates.md" => 25_609,
      "docs/issue-tracker-setup.md" => 8_995
    }.freeze
    PRE_BOOTSTRAP_TOTAL = 92_036
    PRE_BOOTSTRAP_RECORD_RULE = "The reproducible pre-change source bootstrap at revision `225430672fad342d693137254c256ca44f2bd8ef` was 92,036 UTF-8 bytes:"
    LIVE_LINEAR_READBACK_RULE = "The separate live Linear readback was 92,059 bytes. Do not use that readback or maintainer-document bytes in the source-savings denominator. `ruby scripts/check-docs.rb` reports the current source bootstrap, bytes saved, and percentage reduction; the post-change source bootstrap must not exceed 12,000 bytes."
    POST_BOOTSTRAP_MEMBERS = ["README.md#Default Workflow", "docs/role-contracts.md"].freeze
    POST_BOOTSTRAP_BUDGET = 12_000
    WORKTREE_MODE_LINE = "Worktree mode: on | off"
    WORKTREE_REFERENCE_LINE = "Worktree reference: none | <ownership-category>/<opaque worktree reference>"
    WORKTREE_FIELD_PREFIXES = ["Worktree mode:", "Worktree reference:"].freeze
    WORKTREE_OPTION_LINES = [WORKTREE_MODE_LINE, WORKTREE_REFERENCE_LINE].freeze
    WORKTREE_FIELD_OCCURRENCES = {
      "docs/playbook.md" => 1,
      "docs/templates.md" => 2,
      "docs/issue-tracker-setup.md" => 1,
      "examples/task-issue.md" => 1,
      "examples/multi-slice-issues.md" => 3
    }.freeze
    WORKTREE_OPTION_OCCURRENCES = {
      "docs/playbook.md" => 1,
      "docs/templates.md" => 2,
      "docs/issue-tracker-setup.md" => 1
    }.freeze
    WORKTREE_DEFAULT_LINES = [
      "Worktree mode default: on | off",
      "Worktree reference default: none"
    ].freeze
    WORKTREE_SLICE_LINES = [
      "   - worktree mode: inherit | on | off",
      "   - worktree reference: none | <ownership-category>/<opaque worktree reference>"
    ].freeze
    DEFAULT_WORKTREE_RULE = "4. For each phase, the orchestrator creates a phase branch and dedicated worktree from the base while the primary checkout stays coordination-only."
    ROLE_WORKTREE_RULE = "- With phase branch mode on, default to one owned phase worktree, keep the primary checkout fixed, verify baseline, and remove it before branch deletion; the packet remains the review artifact, only a repo-backed reviewer that creates a detached worktree must remove it before verdict, and the contract has no named integration dependency."
    WORKTREE_REQUIRED_RULES = [
      "The worktree lifecycle requires no named plugin, skill, marketplace product, or vendor-specific integration.",
      "- `(Phase branch mode: on, Worktree mode: on)` is the default phase-branch path: use one dedicated named-branch worktree and keep the primary checkout coordination-only.",
      "- `(Phase branch mode: off, Worktree mode: off)` preserves the existing primary-checkout execution and uncommitted-review path.",
      "- `(Phase branch mode: on, Worktree mode: off)` requires explicit human approval because it disables collision protection.",
      "- `(Phase branch mode: off, Worktree mode: on)` is invalid.",
      "- Never use force to create or remove a worktree. Never remove a worktree automatically before its lifecycle record is complete.",
      "- Prefer a worktree path outside the repository root. A project-local root is allowed only when `git check-ignore -v` exits zero for it and identifies an existing positive repository-specific rule in a tracked repository ignore file or that repository's own Git metadata; a negation or host-global rule is insufficient.",
      "- After creation, recompute the primary-checkout fingerprint. If the fingerprint command fails or its untracked digest changes, the worktree location is non-compliant.",
      "- Before fresh creation, require the primary checkout on the recorded base branch at the stored base SHA, clean under `git status --porcelain=v1 --untracked-files=all`, and equal to its canonical stored fingerprint.",
      "- Before fresh creation, require `git worktree list --porcelain` to show no conflicting path or checkout, require the full local phase ref absent, and require an authoritative live query of the bound remote subject to report the full remote phase ref absent.",
      "- Create the named phase branch and worktree together from the exact base without force. The primary checkout stays on the base branch and performs no phase implementation.",
      "- Before sealing ownership, require the primary branch, HEAD, cleanliness, and fingerprint to remain exactly unchanged.",
      "- Before sealing ownership, require the phase worktree at the canonical recorded path, on the exact named phase branch, at the base SHA, clean, fingerprintable, and bound to the expected Git common directory and distinct per-worktree Git directory.",
      "- Repeat the authoritative live remote-absence query after local creation. Only when every primary, phase, local-ref, Git-identity, fingerprint, and remote postcondition matches may the orchestrator seal the immutable creation record and record local `absent -> <base SHA>` and remote `absent` expected states.",
      "- A failed creation postcondition creates only a recovery record from observed facts and a human handoff. Never adopt, remove, retry, or advance expected state automatically.",
      "- Before edits, run only the repository's documented setup and verification commands in the phase worktree and record exact results. Never run a generic dependency installer automatically.",
      "- If the repository documents no verification command, the reviewed plan must define one or explicitly record that no baseline is available.",
      "- A failing baseline proceeds only after the human accepts the exact command, bounded failure signature, and impact. A plan-authored acceptance alone is insufficient.",
      "- Immediately before every authorized commit, require the exact full phase ref and expected local SHA. Afterward, require the same branch, a different new SHA that descends from both the previous expected SHA and immutable base, then record previous/new values and advance expected local state.",
      "- A missing, premature, unauthorized, unchanged, or non-descendant local-ref transition hands off and is never absorbed.",
      "- Obtain authoritative remote state from a live query to the exact remote or forge subject, never from remote-tracking refs alone.",
      "- Before every authorized push or remote deletion, require authoritative live state to equal expected state. Freeze the expected local tip as a push's intended remote SHA.",
      "- After every authorized push or remote deletion, query the same subject again and require the intended exact new state before recording previous/new values or advancing expected remote state.",
      "- Reviewer worktrees are optional and apply only to a repo-backed reviewer of a commit-bound `(Phase branch mode: on, Worktree mode: on)` implementation artifact that needs local execution.",
      "- A plan, packet-only, forge-only, no-repo, or `(off, off)` uncommitted reviewer has no worktree obligation and inspects the immutable supplied artifact directly.",
      "- The immutable packet or forge artifact, never a mutable worktree, is the source of reviewed bytes.",
      "- A reviewer-created worktree follows the same compliant-location and ownership rules as a phase worktree.",
      "- Dirty reviewer state or failed cleanup returns `Review status: could-not-review` with `Verdict: not issued`; any drafted judgment is non-counting evidence. A reviewer that created no worktree has no cleanup obligation. Only the orchestrator records `error` or `timeout` when no response can be obtained.",
      "- Worktree removal and branch resolution are separate. Resolve every phase worktree as merged, abandoned, intentionally kept branch, or human handoff. Remove the owned worktree before deleting its branch.",
      "- Before requesting merge approval, bind the credential-free target repository identity, full target ref, exact live target tip, exact reviewed phase head, canonical reviewed-artifact digest, intended target, and merge strategy.",
      "- Immediately before an approved forge merge, re-query the exact target and artifact and require all bound identities and approvals unchanged. Also require the primary checkout still on its stored base branch and SHA, clean, at its stored fingerprint, with that base an ancestor of the live target tip.",
      "- Only exact closeout authorization permits a fast-forward-only move of the primary target branch directly to the verified merge commit. Never create another merge, rebase, reset, force, or move to a later target tip.",
      "- After the primary fast-forward, require the exact target branch and merge-commit HEAD, clean state, and successful new fingerprint before recording the new coordination base and running post-merge verification there.",
      "- For merged cleanup, record state; exit the worktree; remove it normally without force; verify its exact path absent from `git worktree list --porcelain` from a retained checkout; then apply the existing merged branch cleanup rule.",
      "- Before authorized local phase-ref deletion, require the worktree absent and the full local ref equal to expected local state. After deletion, require the ref absent before recording previous/new state and advancing expected local state to `absent`.",
      "- Before authorized remote branch deletion, require authoritative live state equal to the expected exact SHA. Afterward, require the exact ref absent before recording previous/new state and advancing expected remote state to `absent`.",
      "- Abandoned cleanup requires complete ownership, applicable expected state, authoritative local and remote state, PR state, cleanliness, and preservation need. Dirty, divergent, changed, unowned, or preservation-needed state hands off.",
      "- An intentionally kept branch still requires complete ownership, exact retained local expected SHA, authoritative remote state, clean status, branch tips, reason, next owner, and revisit trigger. Remove and verify the worktree while leaving branch, expected local SHA, remote state, and PR unchanged.",
      "- Never run `git worktree prune` in the normal lifecycle. A stale entry is an out-of-band, human-gated repair.",
      "- Cleanup removes only the exact path in the ownership record and only when its live branch or detached SHA matches that record. Never remove another agent's worktree."
    ].freeze
    FIELD_PREFIXES = [
      "Handoff mode:",
      "Review tier:",
      "Autonomy mode:",
      "Phase branch mode:",
      "Phase branch flow:",
      "Review transport:",
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
    SYNC_SOURCES = [
      {
        title: "Four Eyes Default Workflow",
        source: "README.md#Default Workflow",
        filename: "01-default-workflow.md",
        map_line: "- `Four Eyes Default Workflow` <- `README.md` from the `## Default Workflow` heading through the byte before the next level-two heading"
      },
      {
        title: "Four Eyes Playbook",
        source: "docs/playbook.md",
        filename: "02-playbook.md",
        map_line: "- `Four Eyes Playbook` <- complete `docs/playbook.md`"
      },
      {
        title: "Four Eyes Templates",
        source: "docs/templates.md",
        filename: "03-templates.md",
        map_line: "- `Four Eyes Templates` <- complete `docs/templates.md`"
      },
      {
        title: "Four Eyes Issue Tracker Setup",
        source: "docs/issue-tracker-setup.md",
        filename: "04-issue-tracker-setup.md",
        map_line: "- `Four Eyes Issue Tracker Setup` <- complete `docs/issue-tracker-setup.md`"
      },
      {
        title: "Four Eyes Role Contracts",
        source: "docs/role-contracts.md",
        filename: "05-role-contracts.md",
        map_line: "- `Four Eyes Role Contracts` <- complete generated `docs/role-contracts.md`"
      },
      {
        title: "Four Eyes Linear Setup",
        source: "docs/linear-setup.md",
        filename: "06-linear-setup.md",
        map_line: "- `Four Eyes Linear Setup` <- complete `docs/linear-setup.md`"
      }
    ].map(&:freeze).freeze
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

    attr_reader :root

    def self.source_map_lines(sync_sources = SYNC_SOURCES)
      sync_sources.map { |entry| entry.fetch(:map_line) }
    end

    def initialize(root, bootstrap_members: POST_BOOTSTRAP_MEMBERS, sync_sources: SYNC_SOURCES)
      @root = File.expand_path(root)
      @bootstrap_members = bootstrap_members
      @sync_sources = sync_sources
    end

    def check!
      check_derived!
      check_rule_groups!
      report = check_bootstrap!
      check_loading_prompts!
      check_field_order!
      check_reviewer2_handoff!
      check_worktree_contract!
      check_sync_contract!
      check_links!
      check_stale_phrases!
      report
    end

    def write_derived!
      File.binwrite(path("docs/role-contracts.md"), role_contracts_source)
    end

    def write_sync_dir!(directory, revision)
      verify_sync_revision!(revision)
      check!

      expanded = File.expand_path(directory)
      fail_check("sync directory must not already exist") if path_entry_exists?(expanded)
      destination = safe_outside_repo_path(expanded)
      fail_check("sync directory parent must exist") unless File.directory?(File.dirname(destination))
      begin
        Dir.mkdir(destination, 0o700)
      rescue Errno::EEXIST
        fail_check("sync directory must not already exist")
      rescue SystemCallError => error
        fail_check("cannot create sync directory: #{error.message}")
      end
      File.chmod(0o700, destination)
      fail_check("sync directory mode must be 0700") unless (File.stat(destination).mode & 0o777) == 0o700

      entries = @sync_sources.map do |entry|
        title = entry.fetch(:title)
        source = entry.fetch(:source)
        filename = entry.fetch(:filename)
        body = canonical_body(committed_source_bytes(revision, source), "#{source} at revision")
        body_digest = Digest::SHA256.hexdigest(body)
        payload = "Workflow revision: #{revision}\nSource body SHA-256: #{body_digest}\n\n#{body}"
        write_private(File.join(destination, filename), payload)
        {
          "title" => title,
          "source" => source,
          "filename" => filename,
          "source_body_sha256" => body_digest,
          "payload_sha256" => Digest::SHA256.hexdigest(payload),
          "payload_bytes" => payload.bytesize
        }
      end

      manifest = {
        "workflow_revision" => revision,
        "documents" => entries
      }
      manifest_bytes = JSON.pretty_generate(manifest) + "\n"
      write_private(File.join(destination, "manifest.json"), manifest_bytes)
      Digest::SHA256.hexdigest(manifest_bytes)
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

    def source_bytes(source)
      source == "README.md#Default Workflow" ? default_workflow_source : read(source)
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

      linear_setup = normalized_read("docs/linear-setup.md")
      loading_rule = section(linear_setup, "## Loading Rule", "## Canonical Sync Source Map")
      PRE_BOOTSTRAP_COMPONENTS.each do |name, bytes|
        display_name = name == "README.md#Default Workflow" ? "README Default Workflow section" : "complete #{File.basename(name, ".md").split("-").map(&:capitalize).join(" ")}"
        expected = "- #{display_name}: #{bytes.to_s.reverse.scan(/.{1,3}/).join(",").reverse} bytes"
        require_unique_operative_line_in_section!(linear_setup, loading_rule, expected, "pre-change bootstrap record missing: #{name}")
      end
      require_unique_operative_line_in_section!(linear_setup, loading_rule, PRE_BOOTSTRAP_RECORD_RULE, "pre-change bootstrap total record missing")
      require_unique_operative_line_in_section!(linear_setup, loading_rule, LIVE_LINEAR_READBACK_RULE, "live Linear readback record missing")

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

      linear_setup = normalized_read("docs/linear-setup.md")
      linear_loading = section(linear_setup, "## Loading Rule", "## Canonical Sync Source Map")
      load_rule_starts = operative_line_positions(linear_loading, "Default orchestrator bootstrap is:")
      load_rule_finishes = operative_line_positions(linear_loading, LOAD_ON_DEMAND_RULE)
      fail_check("default loading instructions mismatch") unless load_rule_starts.length == 1 && load_rule_finishes.length == 1
      bootstrap_region = linear_loading[load_rule_starts.first...load_rule_finishes.first]
      loading_bullets = bootstrap_region.lines.map(&:chomp).select { |line| line.start_with?("- ") }
      fail_check("default loading instructions mismatch") unless bootstrap_region == DEFAULT_LOADING_BLOCK && loading_bullets == DEFAULT_LOADING_BULLETS
      require_unique_operative_line_in_section!(linear_setup, linear_loading, LOAD_ON_DEMAND_RULE, "default loading instructions mismatch")

      role_contracts = normalized_read("docs/role-contracts.md")
      role_loading = section(role_contracts, "## Loading")
      require_unique_operative_line_in_section!(role_contracts, role_loading, ROLE_LOADING_RULE, "role-contract loading instructions mismatch")

      tracker_setup = normalized_read("docs/issue-tracker-setup.md")
      tracker_loading = section(tracker_setup, "## Recommended Issue Shape", "## Autonomy Mode")
      require_unique_operative_line_in_section!(tracker_setup, tracker_loading, TRACKER_LOADING_RULE, "tracker loading instructions mismatch")
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

    def check_worktree_contract!
      occurrences = Hash.new(0)
      option_occurrences = Hash.new(0)
      markdown_paths.each do |relative|
        lines = normalized_read(relative).lines.map(&:chomp)
        lines.each_with_index do |line, index|
          next unless line.start_with?(WORKTREE_FIELD_PREFIXES.first)

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
      lifecycle = section(playbook, "## Worktree Lifecycle", "## Authority")
      WORKTREE_REQUIRED_RULES.each do |line|
        require_unique_operative_line_in_section!(playbook, lifecycle, line, "worktree lifecycle rule missing")
      end

      readme = normalized_read("README.md")
      default_workflow = default_workflow_source
      require_unique_operative_line_in_section!(readme, default_workflow, DEFAULT_WORKTREE_RULE, "default workflow worktree rule missing")

      role_contracts = normalized_read("docs/role-contracts.md")
      branch = section(role_contracts, "## Branch", "## Loading")
      require_unique_operative_line_in_section!(role_contracts, branch, ROLE_WORKTREE_RULE, "role-contract worktree rule missing")

      closeout = normalized_read("examples/closeout.md")
      ["merged", "abandoned", "intentionally kept branch", "reviewer detached"].each do |path|
        fail_check("worktree closeout path missing: #{path}") unless closeout.include?("- Resolution path: #{path}")
      end

      reviewer = normalized_read("examples/reviewer-comment.md")
      fail_check("reviewer worktree cleanup rule missing") unless reviewer.include?("Dirty state or failed cleanup returns `could-not-review` with `Verdict: not issued`.")
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

    def check_sync_contract!
      linear_setup = normalized_read("docs/linear-setup.md")
      fail_check("canonical sync source map mismatch") unless @sync_sources == SYNC_SOURCES
      agent_prompt = section(linear_setup, "## Agent Prompt", "## Loading Rule")
      source_map = section(linear_setup, "## Canonical Sync Source Map", "## Sync Rule")
      sync_rule = section(linear_setup, "## Sync Rule", "## Standing Review Issue")
      standing_review = section(linear_setup, "## Standing Review Issue")
      standing_descriptions = fenced_code_blocks(standing_review).select do |block|
        block[:info] == "text" && block[:body].start_with?("#{STANDING_DESCRIPTION_INTRO}\n")
      end
      fail_check("standing review issue Description missing") unless standing_descriptions.length == 1
      standing_description = standing_descriptions.first[:body]

      expected_entries = self.class.source_map_lines(@sync_sources)
      require_unique_operative_line_in_section!(linear_setup, source_map, CANONICAL_BODY_RULE, "canonical source-body rule missing")
      require_unique_operative_line_in_section!(linear_setup, source_map, MARKER_RULE, "sync marker rule missing")
      require_unique_operative_line_in_section!(linear_setup, source_map, LINEAR_SERIALIZATION_RULE, "Linear serialization trust boundary missing")
      intro_positions = operative_line_positions(source_map, SOURCE_MAP_INTRO)
      body_rule_positions = operative_line_positions(source_map, CANONICAL_BODY_RULE)
      fail_check("canonical sync source map entries mismatch") unless intro_positions.length == 1 && body_rule_positions.length == 1

      map_block = source_map[(intro_positions.first + SOURCE_MAP_INTRO.length)...body_rule_positions.first]
      actual_entries = map_block.lines.map(&:chomp).reject(&:empty?)
      missing_entry = expected_entries.find { |line| actual_entries.count(line) != 1 }
      fail_check("sync source map incomplete: #{missing_entry}") if missing_entry
      fail_check("canonical sync source map entries mismatch") unless actual_entries.length == expected_entries.length
      fail_check("sync source map order mismatch") unless actual_entries == expected_entries
      expected_block = "\n\n#{expected_entries.join("\n")}\n\n"
      fail_check("canonical sync source map entries mismatch") unless map_block == expected_block
      source_map_lines = markdown_lines(source_map).select { |entry| entry[:context] == :prose }
      section_list_entries = source_map_lines.map { |entry| entry[:line] }.select { |line| markdown_list_line?(line) }
      fail_check("canonical sync source map entries mismatch") unless section_list_entries == expected_entries
      map_arrow_count = source_map_lines.sum { |entry| entry[:line].scan("<-").length }
      fail_check("canonical sync source map entries mismatch") unless map_arrow_count == expected_entries.length

      agent_prompt_body = unique_text_prompt(agent_prompt, "five runtime document rule missing")
      require_unique_line_in_section!(linear_setup, agent_prompt_body, RUNTIME_DOCUMENT_RULE, "five runtime document rule missing")
      require_unique_operative_line_in_section!(linear_setup, sync_rule, READBACK_RULE, "sync readback procedure missing")
      require_unique_operative_line_in_section!(linear_setup, sync_rule, READBACK_STABILITY_RULE, "sync readback stability procedure missing")
      require_unique_operative_line_in_section!(linear_setup, sync_rule, READBACK_FAILURE_RULE, "sync readback failure rule missing")
      require_unique_operative_line_in_section!(linear_setup, sync_rule, READBACK_RECORD_RULE, "sync readback record rule missing")
      require_unique_line_in_section!(linear_setup, standing_description, STANDING_READBACK_RULE, "standing readback record missing")
      require_unique_line_in_section!(linear_setup, standing_description, STANDING_READBACK_DIGEST_RULE, "standing readback digest record missing")
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

    def verify_sync_revision!(revision)
      fail_check("workflow revision must be a full lowercase commit SHA") unless revision.match?(/\A[0-9a-f]{40}\z/)

      resolved, _error, status = git_capture("rev-parse", "--verify", "#{revision}^{commit}")
      fail_check("workflow revision does not identify a commit") unless status.success?
      fail_check("workflow revision does not identify the exact commit") unless resolved.strip == revision

      head = git_text("rev-parse", "HEAD")
      fail_check("workflow revision must equal HEAD") unless head == revision
      fail_check("repository must be clean before sync generation") unless git_text("status", "--porcelain=v1", "--untracked-files=all").empty?

      remote_refs = git_text("for-each-ref", "--format=%(refname)", "--contains=#{revision}", "refs/remotes")
      fail_check("workflow revision must be pushed before sync generation") if remote_refs.empty?

      @sync_sources.each do |entry|
        source = entry.fetch(:source)
        committed = committed_source_bytes(revision, source)
        working = source_bytes(source)
        unless canonical_body(committed, "#{source} at revision") == canonical_body(working, source)
          fail_check("workflow source does not match revision: #{source}")
        end
      end
    end

    def committed_source_bytes(revision, source)
      if source == "README.md#Default Workflow"
        default_workflow_source_from(git_bytes("show", "#{revision}:README.md"), "README.md at revision")
      else
        git_bytes("show", "#{revision}:#{source}")
      end
    end

    def git_capture(*arguments)
      Open3.capture3("git", "-C", root, *arguments)
    end

    def git_text(*arguments)
      output, error, status = git_capture(*arguments)
      fail_check("git command failed: #{error.strip}") unless status.success?
      output.strip
    end

    def git_bytes(*arguments)
      output, error, status = git_capture(*arguments)
      fail_check("git command failed: #{error.strip}") unless status.success?
      output.b
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

    def markdown_paths
      ["README.md"] + Dir.chdir(root) { Dir.glob("{docs,examples}/**/*.md").sort }
    end

    def safe_outside_repo_path(directory)
      expanded = File.expand_path(directory)
      resolved = resolve_with_existing_parent(expanded)
      root_real = File.realpath(root)
      if resolved == root_real || resolved.start_with?(root_real + File::SEPARATOR)
        fail_check("sync directory must resolve outside the repository")
      end
      expanded
    end

    def resolve_with_existing_parent(target)
      suffix = []
      current = target
      until File.exist?(current) || File.symlink?(current)
        suffix.unshift(File.basename(current))
        parent = File.dirname(current)
        fail_check("cannot resolve sync directory") if parent == current
        current = parent
      end
      File.join(File.realpath(current), *suffix)
    end

    def path_entry_exists?(target)
      File.lstat(target)
      true
    rescue Errno::ENOENT
      false
    end

    def write_private(destination, bytes)
      flags = File::WRONLY | File::CREAT | File::EXCL
      flags |= File::NOFOLLOW if defined?(File::NOFOLLOW)
      File.open(destination, flags, 0o600) do |file|
        file.chmod(0o600)
        file.write(bytes)
        file.flush
      end
    rescue Errno::EEXIST, Errno::ELOOP
      fail_check("sync output path already exists")
    rescue SystemCallError => error
      fail_check("cannot create sync output: #{error.message}")
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
        replace(root, "docs/linear-setup.md", Checker::PRE_BOOTSTRAP_RECORD_RULE, "<!--\n#{Checker::PRE_BOOTSTRAP_RECORD_RULE}\n-->")
      end

      expect_failure("extended live readback record", "live Linear readback record missing") do |root|
        replace(root, "docs/linear-setup.md", Checker::LIVE_LINEAR_READBACK_RULE, "#{Checker::LIVE_LINEAR_READBACK_RULE} Approximate values are acceptable.")
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
        replace(root, "docs/linear-setup.md", block, "#{block.chomp}\n- Four Eyes Playbook\n\n")
      end

      expect_failure("commented default loading block", "default loading instructions mismatch") do |root|
        block = "#{Checker::DEFAULT_LOADING_BLOCK}#{Checker::LOAD_ON_DEMAND_RULE}"
        replace(root, "docs/linear-setup.md", block, "<!--\n#{block}\n-->")
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

      expect_failure("Linear Setup Reviewer 2 fields omission", "Reviewer 2 field occurrence mismatch in docs/linear-setup.md") do |root|
        replace(root, "docs/linear-setup.md", "#{Checker::REVIEWER2_OPTION_LINES.join("\n")}\n", "")
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
        replace(root, "docs/issue-tracker-setup.md", block, "Remote note: local only\n#{block}")
      end

      expect_failure("worktree option drift", "worktree option block mismatch") do |root|
        replace(root, "docs/issue-tracker-setup.md", Checker::WORKTREE_MODE_LINE, "Worktree mode: off | on")
      end

      expect_failure("invalid selected worktree mode", "invalid selected worktree mode") do |root|
        replace(root, "examples/task-issue.md", "Worktree mode: on", "Worktree mode: maybe")
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

      expect_failure("default workflow worktree omission", "default workflow worktree rule missing") do |root|
        replace(root, "README.md", "#{Checker::DEFAULT_WORKTREE_RULE}\n", "")
      end

      expect_failure("role-contract worktree omission", "role-contract worktree rule missing") do |root|
        replace(root, "docs/playbook.md", "#{Checker::ROLE_WORKTREE_RULE}\n", "")
        Checker.new(root).write_derived!
      end

      expect_failure("merged worktree closeout omission", "worktree closeout path missing: merged") do |root|
        replace(root, "examples/closeout.md", "- Resolution path: merged\n", "")
      end

      expect_failure("reviewer worktree cleanup omission", "reviewer worktree cleanup rule missing") do |root|
        replace(root, "examples/reviewer-comment.md", "Dirty state or failed cleanup returns `could-not-review` with `Verdict: not issued`.", "Cleanup failure is recorded.")
      end

      with_fixture do |root|
        reduced = Checker::SYNC_SOURCES.reject { |entry| entry.fetch(:title) == "Four Eyes Role Contracts" }
        checker = Checker.new(root, sync_sources: reduced)
        assert_failure("canonical source-map shrinkage", "canonical sync source map mismatch") { checker.check! }
      end
      expect_failure("incomplete source map", "sync source map incomplete") do |root|
        replace(root, "docs/linear-setup.md", "#{Checker.source_map_lines[4]}\n", "")
      end

      expect_failure("source-map order drift", "sync source map order mismatch") do |root|
        first = "#{Checker.source_map_lines[0]}\n"
        second = "#{Checker.source_map_lines[1]}\n"
        replace(root, "docs/linear-setup.md", first + second, second + first)
      end

      expect_failure("source-map expansion", "canonical sync source map entries mismatch") do |root|
        extra = "- `Four Eyes Runtime` <- complete `docs/runtime.md`\n"
        replace(root, "docs/linear-setup.md", "#{Checker.source_map_lines.last}\n", "#{Checker.source_map_lines.last}\n#{extra}")
      end

      expect_failure("malformed source-map expansion", "canonical sync source map entries mismatch") do |root|
        extra = "- Four Eyes Runtime <- complete docs/runtime.md\n"
        replace(root, "docs/linear-setup.md", "#{Checker.source_map_lines.last}\n", "#{Checker.source_map_lines.last}\n#{extra}")
      end

      expect_failure("indented source-map expansion", "canonical sync source map entries mismatch") do |root|
        extra = "  - `Four Eyes Runtime` <- complete `docs/runtime.md`\n"
        replace(root, "docs/linear-setup.md", "#{Checker.source_map_lines.last}\n", "#{Checker.source_map_lines.last}\n#{extra}")
      end

      expect_failure("misplaced source-map expansion", "canonical sync source map entries mismatch") do |root|
        extra = "- Four Eyes Runtime <- complete docs/runtime.md"
        replace(root, "docs/linear-setup.md", Checker::MARKER_RULE, "#{Checker::MARKER_RULE}\n\n#{extra}")
      end

      {
        "asterisk" => "* Four Eyes Runtime <- complete docs/runtime.md",
        "plus" => "+ Four Eyes Runtime <- complete docs/runtime.md",
        "ordered" => "1. Four Eyes Runtime <- complete docs/runtime.md"
      }.each do |name, extra|
        expect_failure("#{name} source-map expansion", "canonical sync source map entries mismatch") do |root|
          replace(root, "docs/linear-setup.md", Checker::MARKER_RULE, "#{Checker::MARKER_RULE}\n\n#{extra}")
        end
      end

      expect_failure("inline-code comment markers cannot hide source-map expansion", "canonical sync source map entries mismatch") do |root|
        extra = "- `<!--` Four Eyes Runtime <- complete docs/runtime.md `-->`\n"
        replace(root, "docs/linear-setup.md", "#{Checker.source_map_lines.last}\n", "#{Checker.source_map_lines.last}\n#{extra}")
      end

      expect_failure("mixed raw HTML and comment", "raw HTML blocks are not allowed") do |root|
        replace(root, "docs/linear-setup.md", Checker::MARKER_RULE, "#{Checker::MARKER_RULE}\n\n<div><!-- harmless --></div>")
      end

      expect_failure("commented source-map block", "canonical") do |root|
        block = "#{Checker::SOURCE_MAP_INTRO}\n\n#{Checker.source_map_lines.join("\n")}\n\n#{Checker::CANONICAL_BODY_RULE}"
        replace(root, "docs/linear-setup.md", block, "<!--\n#{block}\n-->")
      end

      expect_failure("canonical-body rule omission", "canonical source-body rule missing") do |root|
        replace(root, "docs/linear-setup.md", Checker::CANONICAL_BODY_RULE, "")
      end

      expect_failure("relocated canonical-body rule", "canonical source-body rule missing") do |root|
        replace(root, "docs/linear-setup.md", Checker::CANONICAL_BODY_RULE, "Canonical source bodies are normalized before sync.")
        append(root, "docs/linear-setup.md", "\n#{Checker::CANONICAL_BODY_RULE}\n")
      end

      expect_failure("extended canonical-body rule", "canonical source-body rule missing") do |root|
        replace(root, "docs/linear-setup.md", Checker::CANONICAL_BODY_RULE, "#{Checker::CANONICAL_BODY_RULE} A summary digest is sufficient.")
      end

      expect_failure("marker rule omission", "sync marker rule missing") do |root|
        replace(root, "docs/linear-setup.md", Checker::MARKER_RULE, "")
      end

      expect_failure("relocated marker rule", "sync marker rule missing") do |root|
        replace(root, "docs/linear-setup.md", Checker::MARKER_RULE, "Each synced document starts with revision markers.")
        append(root, "docs/linear-setup.md", "\n#{Checker::MARKER_RULE}\n")
      end

      expect_failure("prefixed marker rule", "sync marker rule missing") do |root|
        replace(root, "docs/linear-setup.md", Checker::MARKER_RULE, "Optional: #{Checker::MARKER_RULE}")
      end

      expect_failure("commented marker rule", "sync marker rule missing") do |root|
        replace(root, "docs/linear-setup.md", Checker::MARKER_RULE, "<!--\n#{Checker::MARKER_RULE}\n-->")
      end

      expect_failure("Linear serialization trust boundary omission", "Linear serialization trust boundary missing") do |root|
        replace(root, "docs/linear-setup.md", Checker::LINEAR_SERIALIZATION_RULE, "")
      end

      expect_failure("relocated Linear serialization trust boundary", "Linear serialization trust boundary missing") do |root|
        replace(root, "docs/linear-setup.md", Checker::LINEAR_SERIALIZATION_RULE, "Linear is a rich-text system.")
        append(root, "docs/linear-setup.md", "\n#{Checker::LINEAR_SERIALIZATION_RULE}\n")
      end

      expect_failure("readback procedure omission", "sync readback procedure missing") do |root|
        replace(root, "docs/linear-setup.md", Checker::READBACK_RULE, "5. Read all six documents back.")
      end

      expect_failure("relocated readback procedure", "sync readback procedure missing") do |root|
        replace(root, "docs/linear-setup.md", Checker::READBACK_RULE, "5. Read all six documents back.")
        append(root, "docs/linear-setup.md", "\n#{Checker::READBACK_RULE}\n")
      end

      expect_failure("extended readback procedure", "sync readback procedure missing") do |root|
        replace(root, "docs/linear-setup.md", Checker::READBACK_RULE, "#{Checker::READBACK_RULE} A summary comparison is sufficient.")
      end

      expect_failure("fenced readback procedure", "sync readback procedure missing") do |root|
        replace(root, "docs/linear-setup.md", Checker::READBACK_RULE, "```text\n#{Checker::READBACK_RULE}\n```")
      end

      expect_failure("readback stability omission", "sync readback stability procedure missing") do |root|
        replace(root, "docs/linear-setup.md", Checker::READBACK_STABILITY_RULE, "6. Read every document again.")
      end

      expect_failure("readback failure rule omission", "sync readback failure rule missing") do |root|
        replace(root, "docs/linear-setup.md", Checker::READBACK_FAILURE_RULE, "7. Fail when verification fails.")
      end

      expect_failure("readback record rule omission", "sync readback record rule missing") do |root|
        replace(root, "docs/linear-setup.md", Checker::READBACK_RECORD_RULE, "8. Record the sync result.")
      end

      expect_failure("standing readback record omission", "standing readback record missing") do |root|
        replace(root, "docs/linear-setup.md", Checker::STANDING_READBACK_RULE, "- Readback: passed")
      end

      expect_failure("standing readback digest omission", "standing readback digest record missing") do |root|
        replace(root, "docs/linear-setup.md", Checker::STANDING_READBACK_DIGEST_RULE, "- Stable readback SHA-256: omitted")
      end

      expect_failure("standing readback records moved outside Description", "standing readback record missing") do |root|
        replace(root, "docs/linear-setup.md", Checker::STANDING_READBACK_RULE, "- Readback: omitted")
        replace(root, "docs/linear-setup.md", Checker::STANDING_READBACK_DIGEST_RULE, "- Stable readback content SHA-256: omitted")
        append(root, "docs/linear-setup.md", "\n#{Checker::STANDING_READBACK_RULE}\n#{Checker::STANDING_READBACK_DIGEST_RULE}\n")
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
        append(root, "docs/templates.md", "\n```text\n## New Orchestrator Prompt ##\n```\n")
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

      with_git_fixture do |root, _revision|
        readme = read(root, "README.md")
        readme.sub!("## Default Workflow\n", "## Default Workflow\n\nUTF-8 fixture: \xF0\x9F\x98\x80\n") || raise("Default Workflow fixture missing")
        write(root, "README.md", readme)

        playbook = read(root, "docs/playbook.md")
        playbook.sub!("# Four Eyes Role Contracts\n", "# Four Eyes Role Contracts\n\nUTF-8 fixture: caf\xC3\xA9 \xF0\x9F\x98\x80\n") || raise("Role Contracts fixture missing")
        write(root, "docs/playbook.md", playbook)
        Checker.new(root).write_derived!

        git!(root, "add", "README.md", "docs/playbook.md", "docs/role-contracts.md")
        git!(root, "commit", "-q", "-m", "multibyte fixture")
        revision = git!(root, "rev-parse", "HEAD")
        git!(root, "push", "-q", "origin", "HEAD:refs/heads/main")

        checker = Checker.new(root)
        checker.check!
        destination = File.join(File.dirname(root), "multibyte-sync")
        checker.write_sync_dir!(destination, revision)

        expected_default = expected_default_workflow(checker.normalize_text(read(root, "README.md"), "README.md"))
        default_payload = read(root, File.join("..", "multibyte-sync", "01-default-workflow.md"))
        actual_default = default_payload.split("\n\n", 2).fetch(1)
        expected_default = checker.canonical_body(expected_default)
        unless actual_default.b == expected_default.b
          raise "multibyte Default Workflow payload mismatch: expected #{expected_default.bytesize}/#{Digest::SHA256.hexdigest(expected_default)}, actual #{actual_default.bytesize}/#{Digest::SHA256.hexdigest(actual_default)}"
        end

        normalized_playbook = checker.normalize_text(read(root, "docs/playbook.md"), "docs/playbook.md")
        role_start = normalized_playbook.index(Checker::ROLE_BEGIN) + Checker::ROLE_BEGIN.length
        role_finish = normalized_playbook.index(Checker::ROLE_END, role_start)
        expected_role = normalized_playbook[role_start...role_finish]
        actual_role = checker.normalize_text(read(root, "docs/role-contracts.md"), "docs/role-contracts.md")
        raise "multibyte Role Contracts mismatch" unless actual_role == expected_role
      end
      pass("multibyte source extraction and payload")

      with_git_fixture do |root, revision|
        checker = Checker.new(root)
        destination = File.join(File.dirname(root), "valid-sync")
        checker.write_sync_dir!(destination, revision)
        pass("revision-bound sync")

        assert_failure("existing sync directory", "sync directory must not already exist") do
          checker.write_sync_dir!(destination, revision)
        end

        attack_dir = File.join(File.dirname(root), "symlink-attack")
        Dir.mkdir(attack_dir, 0o700)
        target = File.join(root, "README.md")
        target_before = File.binread(target)
        target_mode = File.stat(target).mode & 0o777
        payload_link = File.join(attack_dir, "01-default-workflow.md")
        File.symlink(target, payload_link)
        assert_failure("symlinked sync payload", "sync output path already exists") do
          checker.send(:write_private, payload_link, "mutated\n")
        end
        raise "symlink target bytes changed" unless File.binread(target) == target_before
        raise "symlink target mode changed" unless (File.stat(target).mode & 0o777) == target_mode
        raise "repository changed during symlink test" unless git!(root, "status", "--porcelain=v1", "--untracked-files=all").empty?
        pass("symlink target and repository unchanged")

        assert_failure("nonexistent workflow revision", "workflow revision does not identify a commit") do
          checker.write_sync_dir!(File.join(File.dirname(root), "nonexistent-sync"), "a" * 40)
        end

        append(root, "examples/task-issue.md", "\nrevision fixture\n")
        git!(root, "add", "examples/task-issue.md")
        git!(root, "commit", "-q", "-m", "fixture second revision")
        second_revision = git!(root, "rev-parse", "HEAD")

        assert_failure("unpushed workflow revision", "workflow revision must be pushed before sync generation") do
          checker.write_sync_dir!(File.join(File.dirname(root), "unpushed-sync"), second_revision)
        end

        git!(root, "push", "-q", "origin", "HEAD:refs/heads/main")

        assert_failure("mismatched workflow revision", "workflow revision must equal HEAD") do
          checker.write_sync_dir!(File.join(File.dirname(root), "mismatched-sync"), revision)
        end

        append(root, "README.md", "\ndirty fixture\n")
        assert_failure("dirty revision source", "repository must be clean before sync generation") do
          checker.write_sync_dir!(File.join(File.dirname(root), "dirty-sync"), second_revision)
        end
      end

      with_crlf_git_fixture do |root, revision|
        source_paths = ["README.md"] + Checker::SYNC_SOURCES.map { |entry| entry.fetch(:source) }.reject { |source| source == "README.md#Default Workflow" }
        missing_crlf = source_paths.reject { |source| read(root, source).include?("\r\n") }
        raise "CRLF fixture did not convert: #{missing_crlf.join(', ')}" unless missing_crlf.empty?
        raise "CRLF fixture is not clean" unless git!(root, "status", "--porcelain=v1", "--untracked-files=all").empty?

        checker = Checker.new(root)
        checker.check!
        checker.write_sync_dir!(File.join(File.dirname(root), "crlf-sync"), revision)
      end
      pass("clean CRLF check and revision-bound sync")

      expect_failure("broken local link", "broken local Markdown link") do |root|
        append(root, "README.md", "\n[broken](docs/does-not-exist.md)\n")
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
        %w[README.md docs examples].each do |entry|
          FileUtils.cp_r(File.join(@source_root, entry), File.join(tmp, entry))
        end
        yield tmp
      end
    end

    def with_git_fixture
      Dir.mktmpdir("four-eyes-check-docs-git-") do |tmp|
        root = File.join(tmp, "repo")
        remote = File.join(tmp, "remote.git")
        FileUtils.mkdir_p(root)
        %w[README.md docs examples].each do |entry|
          FileUtils.cp_r(File.join(@source_root, entry), File.join(root, entry))
        end
        git!(root, "init", "-q")
        git!(root, "config", "user.name", "Four Eyes Self Test")
        git!(root, "config", "user.email", "self-test@example.invalid")
        git!(root, "add", ".")
        git!(root, "commit", "-q", "-m", "fixture revision")
        git!(tmp, "init", "--bare", "-q", remote)
        git!(root, "remote", "add", "origin", remote)
        git!(root, "push", "-q", "-u", "origin", "HEAD:refs/heads/main")
        yield root, git!(root, "rev-parse", "HEAD")
      end
    end

    def with_crlf_git_fixture
      Dir.mktmpdir("four-eyes-check-docs-crlf-") do |tmp|
        source = File.join(tmp, "source")
        root = File.join(tmp, "clone")
        remote = File.join(tmp, "remote.git")
        FileUtils.mkdir_p(source)
        %w[README.md docs examples].each do |entry|
          FileUtils.cp_r(File.join(@source_root, entry), File.join(source, entry))
        end
        git!(source, "init", "-q")
        git!(source, "config", "user.name", "Four Eyes Self Test")
        git!(source, "config", "user.email", "self-test@example.invalid")
        git!(source, "add", ".")
        git!(source, "commit", "-q", "-m", "fixture revision")
        git!(tmp, "init", "--bare", "-q", remote)
        git!(source, "remote", "add", "origin", remote)
        git!(source, "push", "-q", "origin", "HEAD:refs/heads/main")
        git!(remote, "symbolic-ref", "HEAD", "refs/heads/main")
        git!(tmp, "-c", "core.autocrlf=true", "clone", "-q", remote, root)
        git!(root, "config", "core.autocrlf", "true")
        yield root, git!(root, "rev-parse", "HEAD")
      end
    end

    def git!(root, *arguments)
      output, error, status = Open3.capture3("git", "-C", root, *arguments)
      raise "git fixture failed: #{error}" unless status.success?

      output.strip
    end

    def expected_default_workflow(readme)
      start_match = /^## Default Workflow\n/.match(readme) || raise("Default Workflow heading missing")
      finish_match = /^## /m.match(readme, start_match.end(0))
      finish = finish_match ? finish_match.begin(0) : readme.length
      readme[start_match.begin(0)...finish]
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
    options = {}
    parser = OptionParser.new do |opts|
      opts.on("--sync-dir PATH") { |value| options[:sync_dir] = value }
      opts.on("--revision SHA") { |value| options[:revision] = value }
    end
    parser.parse!(ARGV)
    unless ARGV.empty? && options[:sync_dir] && options[:revision]
      raise FourEyesDocs::CheckError, "use --sync-dir PATH with --revision FULL_SHA"
    end

    checker = FourEyesDocs::Checker.new(root)
    checker.check!
    digest = checker.write_sync_dir!(options[:sync_dir], options[:revision])
    puts "wrote six sync payloads and manifest"
    puts "manifest_sha256=#{digest}"
  end
rescue FourEyesDocs::CheckError, OptionParser::ParseError => error
  warn "check-docs: FAIL: #{error.message}"
  exit 1
end
