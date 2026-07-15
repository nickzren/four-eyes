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
    CANONICAL_BODY_RULE = "Canonical source-body bytes are defined once here: require valid UTF-8; convert CRLF to LF; reject any remaining bare CR or NUL; remove every trailing LF; append exactly one LF. `Source body SHA-256` hashes those canonical body bytes, including the one final LF."
    MARKER_RULE = "Each synced document starts with exactly `Workflow revision: <full-sha>`, then `Source body SHA-256: <digest>`, then one blank line, followed by the canonical source body."
    READBACK_RULE = "5. Read all six documents back. Parse the two exact marker lines and required blank line, apply the canonical source-body algorithm to the remaining bytes, rebuild the payload, and compare every byte with the generated expected payload."
    PRE_BOOTSTRAP_COMPONENTS = {
      "README.md#Default Workflow" => 2_630,
      "docs/playbook.md" => 54_802,
      "docs/templates.md" => 25_609,
      "docs/issue-tracker-setup.md" => 8_995
    }.freeze
    PRE_BOOTSTRAP_TOTAL = 92_036
    POST_BOOTSTRAP_MEMBERS = ["README.md#Default Workflow", "docs/role-contracts.md"].freeze
    POST_BOOTSTRAP_BUDGET = 12_000
    FIELD_PREFIXES = [
      "Handoff mode:",
      "Review tier:",
      "Autonomy mode:",
      "Phase branch mode:",
      "Phase branch flow:",
      "Review transport:",
      "Reviewer 1 handoff:",
      "Reviewer 2 handoff:",
      "Base branch:",
      "Phase branch:",
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
      "five documents total"
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
      start_match = /^## Default Workflow\n/.match(readme)
      fail_check("README Default Workflow section missing") unless start_match
      finish_match = /^## /m.match(readme, start_match.end(0))
      finish = finish_match ? finish_match.begin(0) : readme.length
      readme[start_match.begin(0)...finish]
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
      RULE_GROUPS.each do |group|
        heading = "## #{group}\n"
        fail_check("missing role-contract rule group: #{group}") unless contract.scan(heading).length == 1
        body_start = contract.index(heading) + heading.length
        next_heading = contract.index("\n## ", body_start)
        body = contract[body_start...(next_heading || contract.length)]
        fail_check("empty role-contract rule group: #{group}") unless body.lines.any? { |line| line.start_with?("- ") }
      end
    end

    def check_bootstrap!
      fail_check("bootstrap membership mismatch") unless @bootstrap_members == POST_BOOTSTRAP_MEMBERS
      fail_check("pre-change bootstrap total mismatch") unless PRE_BOOTSTRAP_COMPONENTS.values.sum == PRE_BOOTSTRAP_TOTAL

      linear_setup = normalized_read("docs/linear-setup.md")
      PRE_BOOTSTRAP_COMPONENTS.each do |name, bytes|
        display_name = name == "README.md#Default Workflow" ? "README Default Workflow section" : "complete #{File.basename(name, ".md").split("-").map(&:capitalize).join(" ")}"
        fail_check("pre-change bootstrap record missing: #{name}") unless linear_setup.include?("#{display_name}: #{bytes.to_s.reverse.scan(/.{1,3}/).join(",").reverse} bytes")
      end
      fail_check("pre-change bootstrap total record missing") unless linear_setup.include?("92,036 UTF-8 bytes")
      fail_check("live Linear readback record missing") unless linear_setup.include?("92,059 bytes")

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
      readme_prompt = section(readme, "## Run Your First Review", "## Example Agent Mix")
      require_unique_text_in_section!(readme, readme_prompt, LOADING_SENTENCE, "orchestrator loading prompt mismatch in README.md")

      templates = normalized_read("docs/templates.md")
      orchestrator_prompt = section(templates, "## New Orchestrator Prompt", "## Local Plan Template")
      require_unique_text_in_section!(templates, orchestrator_prompt, LOADING_SENTENCE, "orchestrator loading prompt mismatch in docs/templates.md")

      linear_setup = normalized_read("docs/linear-setup.md")
      linear_loading = section(linear_setup, "## Loading Rule", "## Canonical Sync Source Map")
      load_rule_start = linear_loading.index("Default orchestrator bootstrap is:")
      load_rule_finish = linear_loading.index(LOAD_ON_DEMAND_RULE)
      fail_check("default loading instructions mismatch") unless load_rule_start && load_rule_finish
      bootstrap_region = linear_loading[load_rule_start...load_rule_finish]
      loading_bullets = bootstrap_region.lines.map(&:chomp).select { |line| line.start_with?("- ") }
      fail_check("default loading instructions mismatch") unless bootstrap_region == DEFAULT_LOADING_BLOCK && loading_bullets == DEFAULT_LOADING_BULLETS
      require_unique_text_in_section!(linear_setup, linear_loading, LOAD_ON_DEMAND_RULE, "default loading instructions mismatch")

      role_contracts = normalized_read("docs/role-contracts.md")
      role_loading = section(role_contracts, "## Loading")
      require_unique_text_in_section!(role_contracts, role_loading, ROLE_LOADING_RULE, "role-contract loading instructions mismatch")

      tracker_setup = normalized_read("docs/issue-tracker-setup.md")
      tracker_loading = section(tracker_setup, "## Recommended Issue Shape", "## Autonomy Mode")
      require_unique_text_in_section!(tracker_setup, tracker_loading, TRACKER_LOADING_RULE, "tracker loading instructions mismatch")
    end

    def check_field_order!
      templates = normalized_read("docs/templates.md")
      new_prompt = section(templates, "## New Orchestrator Prompt", "## Local Plan Template")
      task_issue = section(templates, "## Task Issue Template", "## Reviewer Prompt")
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

    def section(content, start_heading, end_heading = nil)
      starts = exact_line_positions(content, start_heading)
      fail_check("section missing or duplicated: #{start_heading}") unless starts.length == 1
      start = starts.first

      if end_heading
        finishes = exact_line_positions(content, end_heading)
        fail_check("section missing or duplicated: #{end_heading}") unless finishes.length == 1
        finish = finishes.first
        fail_check("section order mismatch: #{start_heading}") unless start < finish
      else
        finish = content.length
      end
      content[start...finish]
    end

    def check_sync_contract!
      linear_setup = normalized_read("docs/linear-setup.md")
      fail_check("canonical sync source map mismatch") unless @sync_sources == SYNC_SOURCES
      agent_prompt = section(linear_setup, "## Agent Prompt", "## Loading Rule")
      source_map = section(linear_setup, "## Canonical Sync Source Map", "## Sync Rule")
      sync_rule = section(linear_setup, "## Sync Rule", "## Standing Review Issue")

      expected_entries = self.class.source_map_lines(@sync_sources)
      actual_entries = source_map.lines.map(&:chomp).select { |line| line.match?(/\A- `[^`]+` <- /) }
      missing_entry = expected_entries.find { |line| actual_entries.count(line) != 1 }
      fail_check("sync source map incomplete: #{missing_entry}") if missing_entry
      fail_check("canonical sync source map entries mismatch") unless actual_entries.length == expected_entries.length
      fail_check("sync source map order mismatch") unless actual_entries == expected_entries

      require_unique_text_in_section!(linear_setup, source_map, CANONICAL_BODY_RULE, "canonical source-body rule missing")
      require_unique_text_in_section!(linear_setup, source_map, MARKER_RULE, "sync marker rule missing")
      require_unique_text_in_section!(linear_setup, agent_prompt, "five runtime documents", "five runtime document rule missing")
      require_unique_text_in_section!(linear_setup, sync_rule, READBACK_RULE, "sync readback procedure missing")
    end

    def exact_line_positions(content, expected)
      offset = 0
      content.each_line.with_object([]) do |line, positions|
        positions << offset if line.delete_suffix("\n") == expected
        offset += line.length
      end
    end

    def require_unique_text_in_section!(content, bounded_section, expected, message)
      pattern = Regexp.new(Regexp.escape(expected))
      scoped_count = bounded_section.scan(pattern).length
      total_count = content.scan(pattern).length
      fail_check(message) unless scoped_count == 1 && total_count == 1
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

      with_fixture do |root|
        checker = Checker.new(root, bootstrap_members: ["README.md#Default Workflow"])
        assert_failure("wrong bootstrap membership", "bootstrap membership mismatch") { checker.check! }
      end

      expect_failure("bootstrap budget overflow", "bootstrap byte budget exceeded") do |root|
        insert_before_role_end(root, "x" * Checker::POST_BOOTSTRAP_BUDGET)
        Checker.new(root).write_derived!
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

      expect_failure("operative loading expansion", "default loading instructions mismatch") do |root|
        block = Checker::DEFAULT_LOADING_BLOCK
        replace(root, "docs/linear-setup.md", block, "#{block.chomp}\n- Four Eyes Playbook\n\n")
      end

      expect_failure("field-order drift", "workflow field order mismatch") do |root|
        path = "docs/templates.md"
        content = read(root, path)
        first = "Review tier: skip | light | full\n"
        second = "Handoff mode: reviewer1-subagent + manual reviewer2 | manual human relay\n"
        content.sub!(second + first, first + second) || raise("test fixture field pair missing")
        write(root, path, content)
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

      expect_failure("canonical-body rule omission", "canonical source-body rule missing") do |root|
        replace(root, "docs/linear-setup.md", Checker::CANONICAL_BODY_RULE, "")
      end

      expect_failure("relocated canonical-body rule", "canonical source-body rule missing") do |root|
        replace(root, "docs/linear-setup.md", Checker::CANONICAL_BODY_RULE, "Canonical source bodies are normalized before sync.")
        append(root, "docs/linear-setup.md", "\n#{Checker::CANONICAL_BODY_RULE}\n")
      end

      expect_failure("marker rule omission", "sync marker rule missing") do |root|
        replace(root, "docs/linear-setup.md", Checker::MARKER_RULE, "")
      end

      expect_failure("relocated marker rule", "sync marker rule missing") do |root|
        replace(root, "docs/linear-setup.md", Checker::MARKER_RULE, "Each synced document starts with revision markers.")
        append(root, "docs/linear-setup.md", "\n#{Checker::MARKER_RULE}\n")
      end

      expect_failure("readback procedure omission", "sync readback procedure missing") do |root|
        replace(root, "docs/linear-setup.md", Checker::READBACK_RULE, "5. Read all six documents back.")
      end

      expect_failure("relocated readback procedure", "sync readback procedure missing") do |root|
        replace(root, "docs/linear-setup.md", Checker::READBACK_RULE, "5. Read all six documents back.")
        append(root, "docs/linear-setup.md", "\n#{Checker::READBACK_RULE}\n")
      end

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
