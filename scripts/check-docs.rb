#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "digest"
require "json"
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
    CANONICAL_BODY_RULE = "Canonical source-body bytes are defined once here: require valid UTF-8; convert CRLF to LF; reject any remaining bare CR or NUL; remove every trailing LF; append exactly one LF. `Source body SHA-256` hashes those canonical body bytes, including the one final LF."
    MARKER_RULE = "Each synced document starts with exactly `Workflow revision: <full-sha>`, then `Source body SHA-256: <digest>`, then one blank line, followed by the canonical source body."
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
      ["Four Eyes Default Workflow", "README.md#Default Workflow", "01-default-workflow.md"],
      ["Four Eyes Playbook", "docs/playbook.md", "02-playbook.md"],
      ["Four Eyes Templates", "docs/templates.md", "03-templates.md"],
      ["Four Eyes Issue Tracker Setup", "docs/issue-tracker-setup.md", "04-issue-tracker-setup.md"],
      ["Four Eyes Role Contracts", "docs/role-contracts.md", "05-role-contracts.md"],
      ["Four Eyes Linear Setup", "docs/linear-setup.md", "06-linear-setup.md"]
    ].freeze
    SOURCE_MAP_LINES = [
      "- `Four Eyes Default Workflow` <- `README.md` from the `## Default Workflow` heading through the byte before the next level-two heading",
      "- `Four Eyes Playbook` <- complete `docs/playbook.md`",
      "- `Four Eyes Templates` <- complete `docs/templates.md`",
      "- `Four Eyes Issue Tracker Setup` <- complete `docs/issue-tracker-setup.md`",
      "- `Four Eyes Role Contracts` <- complete generated `docs/role-contracts.md`",
      "- `Four Eyes Linear Setup` <- complete `docs/linear-setup.md`"
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
      "five documents total"
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
      check_sync_contract!
      check_links!
      check_stale_phrases!
      report
    end

    def write_derived!
      File.binwrite(path("docs/role-contracts.md"), role_contracts_source)
    end

    def write_sync_dir!(directory, revision)
      fail_check("workflow revision must be a full lowercase commit SHA") unless revision.match?(/\A[0-9a-f]{40}\z/)

      destination = safe_outside_repo_path(directory)
      fail_check("sync directory must not be a symlink") if File.symlink?(destination)
      FileUtils.mkdir_p(destination, mode: 0o700)
      File.chmod(0o700, destination)

      entries = SYNC_SOURCES.map do |title, source, filename|
        body = canonical_body(source_bytes(source), source)
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
      value = bytes.dup.force_encoding(Encoding::UTF_8)
      fail_check("#{label}: invalid UTF-8") unless value.valid_encoding?
      fail_check("#{label}: NUL byte") if value.include?("\0")

      value = value.gsub("\r\n", "\n")
      fail_check("#{label}: bare CR") if value.include?("\r")
      value.sub(/\n*\z/, "") + "\n"
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

    def role_contracts_source
      playbook = read("docs/playbook.md")
      start = playbook.index(ROLE_BEGIN)
      finish = start && playbook.index(ROLE_END, start + ROLE_BEGIN.bytesize)
      fail_check("marked Role Contracts source missing or malformed") unless start && finish

      body = playbook.byteslice((start + ROLE_BEGIN.bytesize)...finish)
      fail_check("marked Role Contracts source is not canonical") unless canonical_body(body, "Role Contracts source") == body
      body
    end

    def default_workflow_source
      readme = read("README.md")
      start_match = /^## Default Workflow\n/.match(readme)
      fail_check("README Default Workflow section missing") unless start_match
      finish_match = /^## /m.match(readme, start_match.end(0))
      finish = finish_match ? finish_match.begin(0) : readme.bytesize
      readme.byteslice(start_match.begin(0)...finish)
    end

    def source_bytes(source)
      source == "README.md#Default Workflow" ? default_workflow_source : read(source)
    end

    def check_derived!
      expected = role_contracts_source
      actual = read("docs/role-contracts.md")
      fail_check("generated Role Contracts differ from marked Playbook source") unless actual == expected
    end

    def check_rule_groups!
      contract = read("docs/role-contracts.md")
      RULE_GROUPS.each do |group|
        fail_check("missing role-contract rule group: #{group}") unless contract.include?("## #{group}\n")
      end
    end

    def check_bootstrap!
      fail_check("bootstrap membership mismatch") unless @bootstrap_members == POST_BOOTSTRAP_MEMBERS
      fail_check("pre-change bootstrap total mismatch") unless PRE_BOOTSTRAP_COMPONENTS.values.sum == PRE_BOOTSTRAP_TOTAL

      linear_setup = read("docs/linear-setup.md")
      PRE_BOOTSTRAP_COMPONENTS.each do |name, bytes|
        display_name = name == "README.md#Default Workflow" ? "README Default Workflow section" : "complete #{File.basename(name, ".md").split("-").map(&:capitalize).join(" ")}"
        fail_check("pre-change bootstrap record missing: #{name}") unless linear_setup.include?("#{display_name}: #{bytes.to_s.reverse.scan(/.{1,3}/).join(",").reverse} bytes")
      end
      fail_check("pre-change bootstrap total record missing") unless linear_setup.include?("92,036 UTF-8 bytes")
      fail_check("live Linear readback record missing") unless linear_setup.include?("92,059 bytes")

      post_bytes = default_workflow_source.bytesize + read("docs/role-contracts.md").bytesize
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
      ["README.md", "docs/templates.md"].each do |relative|
        count = read(relative).scan(Regexp.new(Regexp.escape(LOADING_SENTENCE))).length
        fail_check("orchestrator loading prompt mismatch in #{relative}") unless count == 1
      end
    end

    def check_field_order!
      templates = read("docs/templates.md")
      new_prompt = section(templates, "## New Orchestrator Prompt", "## Local Plan Template")
      task_issue = section(templates, "## Task Issue Template", "## Reviewer Prompt")
      expected_lines = workflow_field_lines(new_prompt)
      actual_lines = workflow_field_lines(task_issue)
      fail_check("workflow field order mismatch") unless expected_lines == actual_lines
    end

    def workflow_field_lines(content)
      positions = FIELD_PREFIXES.map do |prefix|
        match = /^#{Regexp.escape(prefix)}.*$/.match(content)
        fail_check("workflow field missing: #{prefix}") unless match
        [match.begin(0), match[0]]
      end
      fail_check("workflow field order mismatch") unless positions.map(&:first) == positions.map(&:first).sort
      positions.map(&:last)
    end

    def section(content, start_heading, end_heading)
      start = content.index(start_heading)
      finish = start && content.index(end_heading, start + start_heading.bytesize)
      fail_check("section missing: #{start_heading}") unless start && finish
      content.byteslice(start...finish)
    end

    def check_sync_contract!
      linear_setup = read("docs/linear-setup.md")
      positions = SOURCE_MAP_LINES.map do |line|
        fail_check("sync source map incomplete: #{line}") unless linear_setup.scan(line).length == 1
        linear_setup.index(line)
      end
      fail_check("sync source map order mismatch") unless positions == positions.sort
      fail_check("canonical source-body rule missing") unless linear_setup.include?(CANONICAL_BODY_RULE)
      fail_check("sync marker rule missing") unless linear_setup.include?(MARKER_RULE)
      fail_check("five runtime document rule missing") unless linear_setup.scan("five runtime documents").length == 1
      fail_check("six-document readback rule missing") unless linear_setup.include?("Read all six documents back")
    end

    def check_links!
      markdown_paths.each do |relative|
        content = read(relative)
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
      corpus = markdown_paths.map { |relative| read(relative) }.join("\n")
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

    def write_private(destination, bytes)
      File.open(destination, File::WRONLY | File::CREAT | File::TRUNC, 0o600) { |file| file.write(bytes) }
      File.chmod(0o600, destination)
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

      Checker::RULE_GROUPS.each do |group|
        expect_failure("missing #{group} rule group", "missing role-contract rule group: #{group}") do |root|
          replace(root, "docs/playbook.md", "\n## #{group}\n", "\n## Removed #{group}\n")
          Checker.new(root).write_derived!
        end
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

      expect_failure("field-order drift", "workflow field order mismatch") do |root|
        path = "docs/templates.md"
        content = read(root, path)
        first = "Review tier: skip | light | full\n"
        second = "Handoff mode: reviewer1-subagent + manual reviewer2 | manual human relay\n"
        content.sub!(second + first, first + second) || raise("test fixture field pair missing")
        write(root, path, content)
      end

      expect_failure("incomplete source map", "sync source map incomplete") do |root|
        replace(root, "docs/linear-setup.md", "#{Checker::SOURCE_MAP_LINES[4]}\n", "")
      end

      expect_failure("source-map order drift", "sync source map order mismatch") do |root|
        first = "#{Checker::SOURCE_MAP_LINES[0]}\n"
        second = "#{Checker::SOURCE_MAP_LINES[1]}\n"
        replace(root, "docs/linear-setup.md", first + second, second + first)
      end

      expect_failure("canonical-body rule omission", "canonical source-body rule missing") do |root|
        replace(root, "docs/linear-setup.md", Checker::CANONICAL_BODY_RULE, "")
      end

      expect_failure("marker rule omission", "sync marker rule missing") do |root|
        replace(root, "docs/linear-setup.md", Checker::MARKER_RULE, "")
      end

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
