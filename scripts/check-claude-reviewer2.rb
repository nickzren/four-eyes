#!/usr/bin/env ruby
# frozen_string_literal: true

require "bigdecimal"
require "digest"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"

module FourEyesClaudeReviewer2Check
  class CheckFailure < StandardError; end

  ROOT = File.expand_path("..", __dir__)
  ADAPTER_PATH = File.join(__dir__, "claude-reviewer2.rb")
  SCHEMA_PATH = File.join(ROOT, "schemas/reviewer-verdict.schema.json")
  EXPECTED_MAGIC = "four-eyes-review-packet-v1\0".b.freeze
  EXPECTED_RECORD_LABELS = [
    "packet-version",
    "reviewer-slot",
    "phase-id",
    "review-round",
    "review-stage",
    "workflow-revision",
    "artifact-kind",
    "identity-json",
    "reviewer-instructions",
    "changed-file-manifest",
    "artifact-bytes",
    "verification-evidence",
    "neutral-prior-summary",
    "own-prior-findings"
  ].freeze
  EXPECTED_SYSTEM_PROMPT = "You are Four Eyes Reviewer 2. Review only the sealed packet on standard input. Do not use tools or outside context. Return only structured output matching the supplied JSON Schema.".freeze

  class SelfTest
    def initialize
      @checks = 0
      @failures = []
      @filter = ENV["FOUR_EYES_TEST_FILTER"]
    end

    def run!
      check("schema has disjoint completed and terminal variants") { check_schema_shape }
      check("JSON parser rejects duplicate keys at every nesting level") { check_duplicate_json }
      check("V1 packet framing and record order round-trip exactly") { check_packet_round_trip }
      check("maximum calls accepts only canonical lexical values 1 through 20") { check_maximum_calls }
      check("maximum dollars accepts only bounded canonical decimals") { check_maximum_dollars }
      check("Claude create and resume argv are exact shell-free arrays") { check_claude_argv }
      check("contract manifest binds all validity keys while candidate revision stays audit-only") { check_contract_manifest }
      check("provider launch environment contains only the reviewed allowlist") { check_provider_environment }
      check("plan pack writes an immutable private V1 packet and binding") { check_plan_pack }
      check("pack produces all four exact artifact identity variants") { check_pack_variants }
      check("Git manifests and uncommitted artifact bind staged unstaged and untracked bytes") { check_git_artifacts }
      check("packet consumer enforces exact identity manifest text and artifact contracts") { check_packet_contract }
      check("private paths and source plans reject link mode and containment violations") { check_path_safety }
      check("provider envelope and structured verdict fail closed on identity cost and schema drift") { check_provider_result }
      check("durable phase state enforces budgets no-re-roll closure and tombstones") { check_state_machine }
      check("close removes phase raw material and preserves a rejecting tombstone") { check_close_cleanup }
      check("pre-launch evidence and contract failures produce one durable no-spend terminal") { check_prelaunch_failures }
      check("missing invocation auth records a pre-launch terminal without spending") { check_missing_auth }
      check("launched provider failures map to sanitized durable terminal records") { check_failure_mapping }
      check("provider spawn failure consumes one attempt without inventing a call or spend") { check_launch_accounting }
      check("fake provider review is isolated budgeted session-bound and atomic") { check_fake_review }
      check("same-phase second call resumes the one trusted provider session") { check_session_resume }
      check("parent adapter loss leaves monitors enforcing termination and blocks relaunch") { check_parent_loss }
      check("wrapper survives TERM grace and unrelated process groups remain untouched") { check_wrapper_authority }
      check("watchdog and supervisor independently enforce the wrapper deadline") { check_monitor_failover }
      check("authenticated controls and overflow termination keep numeric signaling in the wrapper") { check_control_and_overflow }

      if @failures.empty?
        puts "check-claude-reviewer2 self-test: #{@checks} checks passed"
        return
      end

      raise CheckFailure, "#{@checks} checks run, #{@failures.length} failed"
    end

    private

    def adapter
      Object.const_get(:FourEyesClaudeReviewer2)
    rescue NameError
      fail_check("adapter must define FourEyesClaudeReviewer2")
    end

    def check(name)
      return if @filter && !name.include?(@filter)

      yield
      @checks += 1
      puts "PASS #{name}"
    rescue StandardError => error
      @checks += 1
      @failures << [name, error]
      warn "FAIL #{name}: #{error.message}"
    end

    def assert_equal(expected, actual, label)
      return if expected == actual

      fail_check("#{label}: expected #{expected.inspect}, got #{actual.inspect}")
    end

    def assert(condition, message)
      fail_check(message) unless condition
    end

    def expect_failure(error_class = StandardError)
      begin
        yield
      rescue error_class
        return
      end

      fail_check("expected #{error_class} failure")
    end

    def fail_check(message)
      raise CheckFailure, message
    end

    def check_schema_shape
      schema = JSON.parse(File.binread(SCHEMA_PATH))
      variants = schema.fetch("oneOf")
      assert_equal(2, variants.length, "root oneOf count")

      completed = variants.find { |variant| variant.dig("properties", "Review status", "const") == "completed" }
      terminal = variants.find { |variant| variant.dig("properties", "Review status", "enum") == ["error", "timeout", "could-not-review"] }
      assert(completed, "completed variant missing")
      assert(terminal, "terminal variant missing")

      completed_keys = [
        "Review status",
        "Verdict",
        "Blocking findings",
        "Non-blocking findings",
        "Questions",
        "Required changes",
        "Artifact identity"
      ]
      terminal_keys = ["Review status", "Verdict", "Reason", "Artifact identity"]
      assert_equal(completed_keys.sort, completed.fetch("required").sort, "completed required keys")
      assert_equal(completed_keys.sort, completed.fetch("properties").keys.sort, "completed property keys")
      assert_equal(terminal_keys.sort, terminal.fetch("required").sort, "terminal required keys")
      assert_equal(terminal_keys.sort, terminal.fetch("properties").keys.sort, "terminal property keys")
      assert_equal(false, completed.fetch("additionalProperties"), "completed additionalProperties")
      assert_equal(false, terminal.fetch("additionalProperties"), "terminal additionalProperties")
      assert_equal(["Approve", "Approve with nits", "Block"], completed.dig("properties", "Verdict", "enum"), "completed verdicts")
      assert_equal("not issued", terminal.dig("properties", "Verdict", "const"), "terminal verdict")
      assert(!completed.fetch("properties").key?("Reason"), "completed variant permits terminal reason")
      reviewer_fields = ["Blocking findings", "Non-blocking findings", "Questions", "Required changes"]
      assert((reviewer_fields & terminal.fetch("properties").keys).empty?, "terminal variant permits reviewer findings")

      identity_refs = schema.dig("$defs", "artifactIdentity", "oneOf").map { |entry| entry.fetch("$ref") }
      expected_refs = %w[planIdentity manualUncommittedIdentity manualCommittedIdentity prIdentity].map { |name| "#/$defs/#{name}" }
      assert_equal(expected_refs, identity_refs, "artifact identity variants")
      terminal_identity = terminal.dig("properties", "Artifact identity", "oneOf")
      assert(terminal_identity.any? { |entry| entry["$ref"] == "#/$defs/artifactIdentity" }, "terminal safe identity reference missing")
      assert(terminal_identity.any? { |entry| entry["type"] == "null" }, "terminal unavailable identity sentinel missing")
    end

    def check_duplicate_json
      parsed = adapter.parse_json('{"outer":{"cost":0.100000}}')
      assert(parsed.fetch("outer").fetch("cost").is_a?(BigDecimal), "decimal_class must be BigDecimal")
      assert_equal(BigDecimal("0.100000"), parsed.fetch("outer").fetch("cost"), "decimal value")

      expect_failure(JSON::ParserError) { adapter.parse_json('{"key":1,"key":2}') }
      expect_failure(JSON::ParserError) { adapter.parse_json('{"outer":{"key":1,"key":2}}') }
    end

    def check_packet_round_trip
      sha = "a" * 40
      identity = JSON.generate(
        "artifact_bytes" => 4,
        "artifact_kind" => "plan",
        "artifact_sha256" => "b" * 64,
        "base" => "none",
        "prior_reviewed_head" => "none",
        "review_round" => 1,
        "review_stage" => "plan",
        "reviewed_head" => "uncommitted at HEAD #{sha}",
        "workflow_revision" => sha
      )
      values = [
        "1",
        "2",
        "phase-1",
        "1",
        "plan",
        sha,
        "plan",
        identity,
        "Review exactly these bytes.",
        "[]",
        "plan",
        "verified",
        "",
        ""
      ]
      records = EXPECTED_RECORD_LABELS.zip(values)
      expected = EXPECTED_MAGIC + records.map do |label, bytes|
        value = bytes.b
        "#{label}\0#{value.bytesize}\0".b + value
      end.join

      assert_equal(EXPECTED_MAGIC, adapter::PACKET_MAGIC, "packet magic")
      assert_equal(EXPECTED_RECORD_LABELS, adapter::PACKET_RECORD_LABELS, "packet record labels")
      packet = adapter.encode_packet(records)
      assert_equal(expected, packet, "encoded packet bytes")
      assert_equal(records, adapter.decode_packet(packet), "decoded packet records")

      reordered = records.dup
      reordered[2], reordered[3] = reordered[3], reordered[2]
      malformed = EXPECTED_MAGIC + reordered.map { |label, bytes| "#{label}\0#{bytes.bytesize}\0#{bytes}".b }.join
      expect_failure { adapter.decode_packet(malformed) }
      expect_failure { adapter.decode_packet(packet + "trailing") }
    end

    def check_maximum_calls
      {"1" => 1, "9" => 9, "10" => 10, "20" => 20}.each do |text, expected|
        assert_equal(expected, adapter.parse_maximum_calls(text), "maximum calls #{text}")
      end
      ["", "0", "21", "01", "1.0", "+1", "-1", " 1", "1 ", "1\n"].each do |text|
        expect_failure(ArgumentError) { adapter.parse_maximum_calls(text) }
      end
    end

    def check_maximum_dollars
      ["0.000001", "1.0", "1.250000", "999.999999"].each do |text|
        assert_equal(BigDecimal(text), adapter.parse_maximum_dollars(text), "maximum dollars #{text}")
      end
      [
        "",
        "0.000000",
        "1000.000000",
        "01.0",
        ".1",
        "1",
        "1.",
        "+1.0",
        "-1.0",
        "1e0",
        " 1.0",
        "1.0 ",
        "1.0000000"
      ].each do |text|
        expect_failure(ArgumentError) { adapter.parse_maximum_dollars(text) }
      end
    end

    def check_claude_argv
      executable = "/private/tmp/four eyes/fake;claude"
      schema_json = JSON.generate(JSON.parse(File.binread(SCHEMA_PATH)))
      model_id = "claude-opus-4-1-20250805"
      mcp_path = "/private/tmp/four eyes/mcp.json"
      settings_path = "/private/tmp/four eyes/settings.json"
      session_id = "123e4567-e89b-42d3-a456-426614174000"
      common = [
        executable,
        "--bare",
        "--print",
        "--input-format",
        "text",
        "--output-format",
        "json",
        "--json-schema",
        schema_json,
        "--model",
        model_id,
        "--effort",
        "max",
        "--tools",
        "",
        "--disable-slash-commands",
        "--strict-mcp-config",
        "--mcp-config",
        mcp_path,
        "--settings",
        settings_path,
        "--no-chrome",
        "--permission-mode",
        "dontAsk",
        "--system-prompt",
        EXPECTED_SYSTEM_PROMPT,
        "--max-budget-usd",
        "1.25"
      ]
      arguments = {
        claude_executable: executable,
        schema_json: schema_json,
        model_id: model_id,
        mcp_config_path: mcp_path,
        settings_path: settings_path,
        remaining_budget: BigDecimal("1.250000"),
        session_id: session_id
      }

      assert_equal(EXPECTED_SYSTEM_PROMPT, adapter::SYSTEM_PROMPT, "fixed system prompt")
      assert_equal(common + ["--session-id", session_id], adapter.build_claude_argv(**arguments, resume: false), "session-create argv")
      assert_equal(common + ["--resume", session_id], adapter.build_claude_argv(**arguments, resume: true), "session-resume argv")
    end

    def check_provider_environment
      Dir.mktmpdir("four-eyes-claude-environment-") do |tmp|
        runtime = {
          root: File.join(tmp, "runtime"),
          home: File.join(tmp, "runtime", "home"),
          tmp: File.join(tmp, "runtime", "tmp"),
          work: File.join(tmp, "runtime", "home", "work")
        }
        runtime.values.each { |path| Dir.mkdir(path, 0o700) }
        provider = adapter.run_provider(
          argv: ["/usr/bin/env"],
          packet: "".b,
          api_key: "fake-contract-key",
          runtime: runtime,
          deadline_seconds: 5,
          on_spawn: ->(_pid) {}
        )
        environment = provider.fetch(:stdout).lines(chomp: true).to_h { |line| line.split("=", 2) }
        expected = {
          "ANTHROPIC_API_KEY" => "fake-contract-key",
          "HOME" => runtime.fetch(:home),
          "TMPDIR" => runtime.fetch(:tmp),
          "LANG" => "C.UTF-8",
          "LC_ALL" => "C"
        }
        assert_equal(expected, environment, "provider launch environment")
      end
    end

    def check_contract_manifest
      Dir.mktmpdir("four-eyes-contract-manifest-") do |tmp|
        fake = File.join(tmp, "fake-claude")
        write_fake_claude(fake)
        model = "claude-opus-4-1-20250805"
        first = adapter.contract_manifest(
          candidate_revision: "a" * 40, claude_executable: fake,
          model_id: model, checker_path: __FILE__, schema_path: SCHEMA_PATH
        )
        second = adapter.contract_manifest(
          candidate_revision: "b" * 40, claude_executable: fake,
          model_id: model, checker_path: __FILE__, schema_path: SCHEMA_PATH
        )
        expected_keys = %w[
          adapter_sha256 argv_template_sha256 candidate_revision canonical_diff_arguments
          checker_sha256 claude_executable_realpath claude_executable_sha256
          claude_help_sha256 claude_version fixed_flags limits model_id
          packet_magic_sha256 packet_record_labels process_contract review_stages
          schema_sha256 system_prompt system_prompt_sha256 version
        ]
        assert_equal(expected_keys, first.keys.sort, "contract manifest keys")
        assert_equal(adapter::FIXED_CLAUDE_FLAGS, first.fetch("fixed_flags"), "contract fixed flags")
        assert_equal(adapter::CANONICAL_DIFF_ARGUMENTS, first.fetch("canonical_diff_arguments"), "contract canonical diff")
        assert_equal(adapter::PACKET_RECORD_LABELS, first.fetch("packet_record_labels"), "contract packet labels")
        assert_equal(adapter::SYSTEM_PROMPT, first.fetch("system_prompt"), "contract system prompt")
        assert_equal(adapter.contract_limits, first.fetch("limits"), "contract limits")
        assert_equal(
          adapter.canonical_json(adapter.contract_validity_keys(first)),
          adapter.canonical_json(adapter.contract_validity_keys(second)),
          "candidate revision changed validity keys"
        )
        serialized = adapter.canonical_json(first)
        %w[fake-contract-key ambient-api-key-canary session_id account_identifier org_identifier].each do |forbidden|
          assert(!serialized.include?(forbidden), "contract manifest leaked #{forbidden}")
        end
      end
    end

    def check_plan_pack
      with_plan_fixture do |fixture|
        packet = File.join(fixture.fetch(:evidence), "round-1.packet")
        output, error, status = Open3.capture3(
          "ruby", ADAPTER_PATH, "pack",
          "--repo", fixture.fetch(:repo),
          "--evidence-root", fixture.fetch(:evidence),
          "--state-root", fixture.fetch(:state),
          "--phase-id", "TEST-1",
          "--review-round", "1",
          "--review-stage", "plan",
          "--workflow-revision", fixture.fetch(:head),
          "--artifact-kind", "plan",
          "--source-plan", fixture.fetch(:plan),
          "--reviewer-instructions", fixture.fetch(:instructions),
          "--verification-evidence", fixture.fetch(:verification),
          "--neutral-prior-summary", fixture.fetch(:neutral),
          "--own-prior-findings", fixture.fetch(:prior),
          "--packet", packet
        )
        assert(status.success?, "pack failed: #{error}")
        digest = output.strip
        assert(digest.match?(/\A[0-9a-f]{64}\z/), "pack did not return a bare digest")
        assert_equal(digest, Digest::SHA256.file(packet).hexdigest, "packet digest")
        assert_equal("#{digest}\n", File.binread("#{packet}.sha256"), "packet sidecar")
        assert_equal(0o600, File.stat(packet).mode & 0o777, "packet mode")
        assert_equal(0o600, File.stat("#{packet}.sha256").mode & 0o777, "sidecar mode")
        assert_equal(0o700, File.stat(fixture.fetch(:evidence)).mode & 0o777, "evidence root mode")
        assert_equal(0o700, File.stat(fixture.fetch(:state)).mode & 0o777, "state root mode")

        records = adapter.decode_packet(File.binread(packet)).to_h
        assert_equal("1", records.fetch("packet-version"), "packet version")
        assert_equal("2", records.fetch("reviewer-slot"), "reviewer slot")
        assert_equal("TEST-1", records.fetch("phase-id"), "phase ID")
        assert_equal(File.binread(fixture.fetch(:plan)), records.fetch("artifact-bytes"), "plan artifact bytes")
        assert_equal("[]", records.fetch("changed-file-manifest"), "plan manifest")

        identity = adapter.parse_json(records.fetch("identity-json"))
        assert_equal("plan", identity.fetch("artifact_kind"), "plan identity kind")
        assert_equal(File.size(fixture.fetch(:plan)), identity.fetch("artifact_bytes"), "plan identity bytes")
        assert_equal(Digest::SHA256.file(fixture.fetch(:plan)).hexdigest, identity.fetch("artifact_sha256"), "plan identity digest")
        assert_equal("uncommitted at HEAD #{fixture.fetch(:head)}", identity.fetch("reviewed_head"), "plan reviewed head")

        phase_digest = Digest::SHA256.hexdigest("TEST-1")
        binding = File.join(fixture.fetch(:state), "bindings", phase_digest, "1.json")
        assert(File.file?(binding), "binding record missing")
        assert_equal(0o600, File.stat(binding).mode & 0o777, "binding mode")
        binding_json = adapter.parse_json(File.binread(binding))
        expected_keys = %w[artifact_kind packet_sha256 phase_id repository_identity_sha256 review_round source_plan_bytes source_plan_realpath source_plan_sha256 workflow_revision]
        assert_equal(expected_keys, binding_json.keys.sort, "binding keys")
        assert_equal(File.realpath(fixture.fetch(:plan)), binding_json.fetch("source_plan_realpath"), "bound plan realpath")
        assert_equal(digest, binding_json.fetch("packet_sha256"), "bound packet digest")

        _repeat_output, repeat_error, repeat_status = Open3.capture3(
          "ruby", ADAPTER_PATH, "pack",
          "--repo", fixture.fetch(:repo), "--evidence-root", fixture.fetch(:evidence),
          "--state-root", fixture.fetch(:state), "--phase-id", "TEST-1",
          "--review-round", "1", "--review-stage", "plan",
          "--workflow-revision", fixture.fetch(:head), "--artifact-kind", "plan",
          "--source-plan", fixture.fetch(:plan), "--reviewer-instructions", fixture.fetch(:instructions),
          "--verification-evidence", fixture.fetch(:verification),
          "--neutral-prior-summary", fixture.fetch(:neutral), "--own-prior-findings", fixture.fetch(:prior),
          "--packet", packet
        )
        assert(!repeat_status.success?, "duplicate pack unexpectedly succeeded")
        assert(repeat_error.include?("already exists"), "duplicate pack failure was not fail-closed")
      end
    end

    def check_pack_variants
      with_plan_fixture do |fixture|
        repo = File.realpath(fixture.fetch(:repo))
        File.write(File.join(repo, "tracked.txt"), "base\n")
        git!(repo, "add", "tracked.txt")
        git!(repo, "commit", "-q", "-m", "base")
        base = git!(repo, "rev-parse", "HEAD")
        File.write(File.join(repo, "tracked.txt"), "base\ncommitted\n")
        git!(repo, "add", "tracked.txt")
        git!(repo, "commit", "-q", "-m", "reviewed")
        reviewed = git!(repo, "rev-parse", "HEAD")

        %w[manual-committed pr].each_with_index do |kind, index|
          packet = pack_fixture_artifact(
            fixture,
            phase_id: "TEST-VARIANTS",
            review_round: index + 1,
            artifact_kind: kind,
            base: base,
            reviewed_head: reviewed
          )
          records = adapter.decode_packet(File.binread(packet)).to_h
          identity = adapter.parse_json(records.fetch("identity-json"))
          assert_equal(kind, identity.fetch("artifact_kind"), "#{kind} identity kind")
          assert_equal(base, identity.fetch("base"), "#{kind} base")
          assert_equal(reviewed, identity.fetch("reviewed_head"), "#{kind} reviewed head")
          assert_equal(git!(repo, "merge-base", base, reviewed), identity.fetch("merge_base"), "#{kind} merge base")
          assert_equal(adapter.canonical_diff(repo, base, reviewed, "--", "."), records.fetch("artifact-bytes"), "#{kind} artifact")
          assert_equal(adapter.changed_file_manifest(repo, artifact_kind: kind, base: base, reviewed_head: reviewed), records.fetch("changed-file-manifest"), "#{kind} manifest")
          assert(adapter.validate_current_artifact!(repo, identity, records), "#{kind} current artifact rejected")
        end

        File.open(File.join(repo, "tracked.txt"), "a") { |file| file.write("unstaged\n") }
        File.write(File.join(repo, "untracked.txt"), "untracked\n")
        packet = pack_fixture_artifact(
          fixture,
          phase_id: "TEST-VARIANTS",
          review_round: 3,
          artifact_kind: "manual-uncommitted"
        )
        records = adapter.decode_packet(File.binread(packet)).to_h
        identity = adapter.parse_json(records.fetch("identity-json"))
        fingerprint = adapter.repository_fingerprint(repo)
        assert_equal("manual-uncommitted", identity.fetch("artifact_kind"), "manual identity kind")
        assert_equal("none", identity.fetch("base"), "manual base")
        assert_equal("uncommitted at HEAD #{fingerprint.fetch('head')}", identity.fetch("reviewed_head"), "manual reviewed head")
        assert_equal(fingerprint.fetch("staged_sha256"), identity.fetch("staged_sha256"), "manual staged digest")
        assert_equal(fingerprint.fetch("unstaged_sha256"), identity.fetch("unstaged_sha256"), "manual unstaged digest")
        assert_equal(fingerprint.fetch("untracked_sha256"), identity.fetch("untracked_sha256"), "manual untracked digest")
        assert_equal(adapter.build_uncommitted_artifact(repo), records.fetch("artifact-bytes"), "manual artifact")
        assert_equal(adapter.changed_file_manifest(repo, artifact_kind: "manual-uncommitted"), records.fetch("changed-file-manifest"), "manual manifest")
        assert(adapter.validate_current_artifact!(repo, identity, records), "manual current artifact rejected")
        File.write(File.join(repo, "untracked.txt"), "drifted\n")
        expect_failure { adapter.validate_current_artifact!(repo, identity, records) }
      end
    end

    def check_git_artifacts
      with_git_artifact_fixture do |fixture|
        repo = File.realpath(fixture.fetch(:repo))
        manifest_json = adapter.changed_file_manifest(repo, artifact_kind: "manual-uncommitted")
        manifest = adapter.parse_json(manifest_json)
        expected = [
          {
            "committed_status" => "none",
            "path" => "tracked.txt",
            "staged_status" => "M",
            "unstaged_status" => "M",
            "untracked" => false
          },
          {
            "committed_status" => "none",
            "path" => "untracked.txt",
            "staged_status" => "none",
            "unstaged_status" => "none",
            "untracked" => true
          }
        ]
        assert_equal(expected, manifest, "manual changed-file manifest")
        assert_equal(adapter.canonical_json(expected), manifest_json, "canonical manifest JSON")

        body = adapter.build_uncommitted_artifact(repo)
        labels = []
        offset = 0
        while offset < body.bytesize
          label, length, value, offset = decode_body_record(body, offset)
          labels << label
          assert_equal(length, value.bytesize, "manual body record length")
        end
        assert_equal(%w[staged-diff unstaged-diff untracked-manifest untracked-content], labels, "manual body labels")
        assert(body.include?("staged\n"), "staged bytes absent from artifact")
        assert(body.include?("unstaged\n"), "unstaged bytes absent from artifact")
        assert(body.include?("untracked fixture\n"), "untracked bytes absent from artifact")

        first_fingerprint = adapter.repository_fingerprint(repo)
        File.write(File.join(repo, "untracked.txt"), "changed untracked fixture\n")
        second_fingerprint = adapter.repository_fingerprint(repo)
        assert(first_fingerprint.fetch("untracked_sha256") != second_fingerprint.fetch("untracked_sha256"), "untracked content mutation was not detected")

        git!(repo, "add", ".")
        git!(repo, "commit", "-q", "-m", "candidate")
        reviewed_head = git!(repo, "rev-parse", "HEAD")
        committed = adapter.parse_json(adapter.changed_file_manifest(repo, artifact_kind: "manual-committed", base: fixture.fetch(:base), reviewed_head: reviewed_head))
        assert_equal(%w[tracked.txt untracked.txt], committed.map { |entry| entry.fetch("path") }, "committed manifest paths")
        assert(committed.all? { |entry| entry.fetch("committed_status") != "none" }, "committed statuses missing")
      end

      with_clean_git_artifact_fixture do |repo, _base|
        File.rename(File.join(repo, "tracked.txt"), File.join(repo, "renamed.txt"))
        git!(repo, "add", "-A")
        expect_failure { adapter.changed_file_manifest(repo, artifact_kind: "manual-uncommitted") }
      end

      with_clean_git_artifact_fixture do |repo, _base|
        FileUtils.cp(File.join(repo, "tracked.txt"), File.join(repo, "copied.txt"))
        git!(repo, "add", "copied.txt")
        expect_failure { adapter.changed_file_manifest(repo, artifact_kind: "manual-uncommitted") }
      end

      with_clean_git_artifact_fixture do |repo, _base|
        File.unlink(File.join(repo, "tracked.txt"))
        File.symlink("target.txt", File.join(repo, "tracked.txt"))
        git!(repo, "add", "tracked.txt")
        expect_failure { adapter.changed_file_manifest(repo, artifact_kind: "manual-uncommitted") }
      end

      with_clean_git_artifact_fixture do |repo, _base|
        head = git!(repo, "rev-parse", "HEAD")
        git!(repo, "update-index", "--add", "--cacheinfo", "160000,#{head},nested-module")
        expect_failure { adapter.changed_file_manifest(repo, artifact_kind: "manual-uncommitted") }
      end

      with_clean_git_artifact_fixture do |repo, base|
        original_branch = git!(repo, "branch", "--show-current")
        git!(repo, "checkout", "-q", "-b", "other")
        File.write(File.join(repo, "tracked.txt"), "other\n")
        git!(repo, "commit", "-qam", "other")
        git!(repo, "checkout", "-q", original_branch)
        File.write(File.join(repo, "tracked.txt"), "master\n")
        git!(repo, "commit", "-qam", "master")
        _output, _error, status = Open3.capture3("git", "-C", repo, "merge", "--no-edit", "other")
        raise CheckFailure, "unmerged fixture did not conflict" if status.success?
        expect_failure { adapter.changed_file_manifest(repo, artifact_kind: "manual-uncommitted") }
        git!(repo, "merge", "--abort")
        assert_equal(base, git!(repo, "merge-base", base, "HEAD"), "fixture base changed unexpectedly")
      end
    end

    def check_packet_contract
      head = "a" * 40
      artifact = "# Exact plan\n".b
      identity = {
        "artifact_bytes" => artifact.bytesize,
        "artifact_kind" => "plan",
        "artifact_sha256" => Digest::SHA256.hexdigest(artifact),
        "base" => "none",
        "prior_reviewed_head" => "none",
        "review_round" => 1,
        "review_stage" => "plan",
        "reviewed_head" => "uncommitted at HEAD #{head}",
        "workflow_revision" => head
      }
      records = {
        "packet-version" => "1",
        "reviewer-slot" => "2",
        "phase-id" => "PER-TEST",
        "review-round" => "1",
        "review-stage" => "plan",
        "workflow-revision" => head,
        "artifact-kind" => "plan",
        "identity-json" => adapter.canonical_json(identity),
        "reviewer-instructions" => "Review independently.\n",
        "changed-file-manifest" => "[]",
        "artifact-bytes" => artifact,
        "verification-evidence" => "",
        "neutral-prior-summary" => "",
        "own-prior-findings" => ""
      }
      assert(adapter.validate_packet_records!(records, phase_id: "PER-TEST", review_round: 1), "valid packet records rejected")

      invalid_identities = [
        identity.merge("artifact_bytes" => 0),
        identity.merge("artifact_bytes" => "#{artifact.bytesize}"),
        identity.merge("base" => head),
        identity.merge("prior_reviewed_head" => "NONE"),
        identity.merge("reviewed_head" => head),
        identity.merge("artifact_sha256" => "A" * 64),
        identity.merge("workflow_revision" => "a" * 39),
        identity.merge("review_round" => BigDecimal("1")),
        identity.merge("review_stage" => "review")
      ]
      invalid_identities.each { |value| expect_failure { adapter.validate_identity!(value) } }

      expect_failure { adapter.validate_packet_records!(records.merge("packet-version" => "2"), phase_id: "PER-TEST", review_round: 1) }
      expect_failure { adapter.validate_packet_records!(records.merge("identity-json" => JSON.pretty_generate(identity)), phase_id: "PER-TEST", review_round: 1) }
      expect_failure { adapter.validate_packet_records!(records.merge("artifact-bytes" => artifact + "drift"), phase_id: "PER-TEST", review_round: 1) }
      expect_failure { adapter.validate_packet_records!(records.merge("reviewer-instructions" => "bad\0instruction"), phase_id: "PER-TEST", review_round: 1) }
      expect_failure { adapter.validate_packet_records!(records.merge("verification-evidence" => "x" * 65_537), phase_id: "PER-TEST", review_round: 1) }
      invalid_utf8 = "\xFF".b
      expect_failure { adapter.validate_packet_records!(records.merge("neutral-prior-summary" => invalid_utf8), phase_id: "PER-TEST", review_round: 1) }

      uncommitted_identity = identity.merge(
        "artifact_kind" => "manual-uncommitted",
        "staged_sha256" => "b" * 64,
        "unstaged_sha256" => "c" * 64,
        "untracked_sha256" => "d" * 64
      )
      manifest_entry = {
        "committed_status" => "none",
        "path" => "docs/example.md",
        "staged_status" => "M",
        "unstaged_status" => "none",
        "untracked" => false
      }
      uncommitted_records = records.merge(
        "artifact-kind" => "manual-uncommitted",
        "identity-json" => adapter.canonical_json(uncommitted_identity),
        "changed-file-manifest" => adapter.canonical_json([manifest_entry])
      )
      assert(adapter.validate_packet_records!(uncommitted_records, phase_id: "PER-TEST", review_round: 1), "valid manifest rejected")
      malformed_manifests = [
        [manifest_entry.merge("staged_status" => "R")],
        [manifest_entry.merge("path" => "../escape")],
        [manifest_entry.merge("path" => "bad\0path")],
        [manifest_entry, manifest_entry],
        [manifest_entry.merge("extra" => true)],
        [manifest_entry.merge("untracked" => "false")]
      ]
      malformed_manifests.each do |value|
        expect_failure do
          adapter.validate_packet_records!(uncommitted_records.merge("changed-file-manifest" => adapter.canonical_json(value)), phase_id: "PER-TEST", review_round: 1)
        end
      end
    end

    def check_path_safety
      with_plan_fixture do |fixture|
        evidence = File.realpath(fixture.fetch(:evidence))
        state = File.realpath(fixture.fetch(:state))
        repo = File.realpath(fixture.fetch(:repo))
        assert_equal(File.realpath(evidence), adapter.validate_private_root(evidence, repo, "evidence root"), "valid private root")
        assert_equal(File.realpath(fixture.fetch(:plan)), adapter.validate_source_plan(fixture.fetch(:plan), repo), "valid source plan")

        File.chmod(0o755, evidence)
        expect_failure { adapter.validate_private_root(evidence, repo, "evidence root") }
        File.chmod(0o700, evidence)

        root_link = File.join(File.dirname(evidence), "evidence-link")
        File.symlink(evidence, root_link)
        expect_failure { adapter.validate_private_root(root_link, repo, "evidence root") }

        private_file = fixture.fetch(:instructions)
        assert_equal(File.realpath(private_file), adapter.validate_private_file(private_file, evidence), "valid private file")
        private_link = File.join(evidence, "input-link")
        File.symlink(private_file, private_link)
        expect_failure { adapter.validate_private_file(private_link, evidence) }
        private_hardlink = File.join(evidence, "input-hardlink")
        File.link(private_file, private_hardlink)
        expect_failure { adapter.validate_private_file(private_file, evidence) }
        File.unlink(private_hardlink)
        File.chmod(0o644, private_file)
        expect_failure { adapter.validate_private_file(private_file, evidence) }
        File.chmod(0o600, private_file)
        expect_failure { adapter.validate_private_file(fixture.fetch(:plan), evidence) }

        plan_link = File.join(repo, "tmp", "plan-link.md")
        File.symlink(fixture.fetch(:plan), plan_link)
        expect_failure { adapter.validate_source_plan(plan_link, repo) }
        plan_hardlink = File.join(repo, "tmp", "plan-hardlink.md")
        File.link(fixture.fetch(:plan), plan_hardlink)
        expect_failure { adapter.validate_source_plan(fixture.fetch(:plan), repo) }
        File.unlink(plan_hardlink)
        expect_failure { adapter.validate_source_plan(File.join(repo, ".gitignore"), repo) }
        outside_plan = File.join(File.dirname(repo), "outside-plan.md")
        File.write(outside_plan, "outside\n")
        expect_failure { adapter.validate_source_plan(outside_plan, repo) }

        expect_failure { adapter.validate_new_output("relative.result", evidence, "review result") }
        nested = File.join(evidence, "nested")
        Dir.mkdir(nested, 0o700)
        expect_failure { adapter.validate_new_output(File.join(nested, "result.json"), evidence, "review result") }
        existing = File.join(evidence, "existing.result")
        write_private(existing, "existing\n")
        expect_failure { adapter.validate_new_output(existing, evidence, "review result") }

        source = File.binread(ADAPTER_PATH)
        assert(source.include?("stat.uid == Process.uid"), "ownership check missing")
        assert_equal(File.realpath(state), adapter.validate_private_root(state, repo, "state root"), "valid state root")
      end
    end

    def check_provider_result
      sha = "a" * 40
      identity = {
        "artifact_bytes" => 4,
        "artifact_kind" => "plan",
        "artifact_sha256" => "b" * 64,
        "base" => "none",
        "prior_reviewed_head" => "none",
        "review_round" => 1,
        "review_stage" => "plan",
        "reviewed_head" => "uncommitted at HEAD #{sha}",
        "workflow_revision" => sha
      }
      completed = {
        "Review status" => "completed",
        "Verdict" => "Approve",
        "Blocking findings" => [],
        "Non-blocking findings" => [],
        "Questions" => [],
        "Required changes" => [],
        "Artifact identity" => identity
      }
      session_id = "123e4567-e89b-42d3-a456-426614174000"
      envelope = {
        "type" => "result",
        "subtype" => "success",
        "is_error" => false,
        "session_id" => session_id,
        "total_cost_usd" => nil,
        "structured_output" => completed
      }
      envelope_json = adapter.canonical_json(envelope).sub('"total_cost_usd":null', '"total_cost_usd":0.100001')
      structured, cost = adapter.parse_provider_envelope(
        envelope_json,
        expected_session_id: session_id,
        expected_identity: identity,
        reservation: BigDecimal("1.000000")
      )
      assert_equal(completed, structured, "structured output")
      assert_equal(BigDecimal("0.100001"), cost, "trusted provider cost")

      expect_failure { adapter.parse_provider_envelope(envelope_json.sub(session_id, "00000000-0000-4000-8000-000000000000"), expected_session_id: session_id, expected_identity: identity, reservation: BigDecimal("1")) }
      expect_failure { adapter.parse_provider_envelope(envelope_json.sub("0.100001", "1.000001"), expected_session_id: session_id, expected_identity: identity, reservation: BigDecimal("1")) }
      expect_failure { adapter.parse_provider_envelope(envelope_json.sub('"is_error":false', '"is_error":true'), expected_session_id: session_id, expected_identity: identity, reservation: BigDecimal("1")) }
      wrong_identity = adapter.canonical_json(envelope.merge("structured_output" => completed.merge("Artifact identity" => identity.merge("review_round" => 2)))).sub('"total_cost_usd":null', '"total_cost_usd":0.100001')
      expect_failure { adapter.parse_provider_envelope(wrong_identity, expected_session_id: session_id, expected_identity: identity, reservation: BigDecimal("1")) }
      expect_failure { adapter.parse_provider_envelope(envelope_json + "junk", expected_session_id: session_id, expected_identity: identity, reservation: BigDecimal("1")) }
      duplicate = envelope_json.sub('"type":"result"', '"type":"result","type":"result"')
      expect_failure(JSON::ParserError) { adapter.parse_provider_envelope(duplicate, expected_session_id: session_id, expected_identity: identity, reservation: BigDecimal("1")) }

      terminal = {
        "Review status" => "timeout",
        "Verdict" => "not issued",
        "Reason" => "deadline expired",
        "Artifact identity" => identity
      }
      adapter.validate_structured_result!(terminal, expected_identity: identity)
      expect_failure { adapter.validate_structured_result!(terminal.merge("Blocking findings" => []), expected_identity: identity) }
      expect_failure { adapter.validate_structured_result!(completed.merge("Reason" => "not allowed"), expected_identity: identity) }
    end

    def check_state_machine
      Dir.mktmpdir("four-eyes-claude-state-") do |tmp|
        root = File.join(tmp, "state")
        Dir.mkdir(root, 0o700)
        store = adapter::StateStore.new(root)
        state = store.create!(
          phase_id: "STATE-1",
          model_id: "claude-opus-4-1-20250805",
          contract_digest: "c" * 64,
          maximum_calls: 2,
          maximum_dollars: BigDecimal("2.000000")
        )
        assert_equal(1, state.fetch("next_round"), "initial next round")
        assert_equal("open", state.fetch("direct_mode"), "initial direct mode")
        assert_equal(0o600, File.stat(store.state_path("STATE-1")).mode & 0o777, "state mode")

        dispatch = store.begin_dispatch!(phase_id: "STATE-1", review_round: 1, model_id: "claude-opus-4-1-20250805", contract_digest: "c" * 64, maximum_calls: 2, maximum_dollars: BigDecimal("2"), deadline: Time.now.to_i + 60)
        assert(dispatch.fetch("dispatch_nonce").match?(/\A[0-9a-f]{64}\z/), "dispatch nonce")
        assert(dispatch.fetch("candidate_session_uuid").match?(/\A[0-9a-f-]{36}\z/), "candidate session UUID")
        expect_failure { store.begin_dispatch!(phase_id: "STATE-1", review_round: 1, model_id: "claude-opus-4-1-20250805", contract_digest: "c" * 64, maximum_calls: 2, maximum_dollars: BigDecimal("2"), deadline: Time.now.to_i + 60) }

        launched = store.record_launch_attempt!(phase_id: "STATE-1", nonce: dispatch.fetch("dispatch_nonce"))
        assert_equal(1, launched.fetch("launch_attempts"), "launch attempts")
        assert_equal("2.0", launched.fetch("reserved_dollars"), "full reservation")
        acknowledged = store.record_provider_ack!(phase_id: "STATE-1", nonce: dispatch.fetch("dispatch_nonce"), provider_pid: Process.pid)
        assert_equal(1, acknowledged.fetch("confirmed_calls_launched"), "confirmed calls")
        assert_equal("confirmed-launched", acknowledged.fetch("provider_launch_state"), "launch state")

        completed = store.complete_round!(phase_id: "STATE-1", nonce: dispatch.fetch("dispatch_nonce"), outcome_digest: "d" * 64, cost: BigDecimal("0.500001"), trusted_session: true)
        assert_equal(2, completed.fetch("next_round"), "next round after completion")
        assert_equal(true, completed.fetch("session_established"), "session established")
        assert_equal("0.500001", completed.fetch("settled_dollars"), "settled cost")
        assert_equal("0.0", completed.fetch("reserved_dollars"), "released reservation")

        second = store.begin_dispatch!(phase_id: "STATE-1", review_round: 2, model_id: "claude-opus-4-1-20250805", contract_digest: "c" * 64, maximum_calls: 2, maximum_dollars: BigDecimal("2"), deadline: Time.now.to_i + 60)
        store.record_launch_attempt!(phase_id: "STATE-1", nonce: second.fetch("dispatch_nonce"))
        terminal = store.terminal_round!(phase_id: "STATE-1", nonce: second.fetch("dispatch_nonce"), outcome_digest: "e" * 64, launched_uncertain: true)
        assert_equal(3, terminal.fetch("next_round"), "next round after terminal")
        assert_equal("closed", terminal.fetch("direct_mode"), "uncertain launch closes direct mode")
        assert_equal("possibly-launched", terminal.fetch("provider_launch_state"), "uncertain launch state")
        expect_failure { store.begin_dispatch!(phase_id: "STATE-1", review_round: 3, model_id: "claude-opus-4-1-20250805", contract_digest: "c" * 64, maximum_calls: 2, maximum_dollars: BigDecimal("2"), deadline: Time.now.to_i + 60) }

        tombstone = store.close!(phase_id: "STATE-1", close_result_digest: "f" * 64)
        assert_equal(true, tombstone.fetch("closed"), "tombstone closed")
        assert(!tombstone.key?("candidate_session_uuid"), "session leaked into tombstone")
        assert(!File.exist?(store.state_path("STATE-1")), "open state retained after close")
        assert_equal(0o600, File.stat(store.tombstone_path("STATE-1")).mode & 0o777, "tombstone mode")
        expect_failure { store.create!(phase_id: "STATE-1", model_id: "claude-opus-4-1-20250805", contract_digest: "c" * 64, maximum_calls: 2, maximum_dollars: BigDecimal("2")) }
      end
    end

    def check_fake_review
      with_plan_fixture do |fixture|
        packet, packet_digest = pack_fixture_plan(fixture)
        schema_copy = File.join(fixture.fetch(:evidence), "schema.json")
        write_private(schema_copy, File.binread(SCHEMA_PATH))
        fake = File.join(File.dirname(fixture.fetch(:repo)), "fake-claude")
        write_fake_claude(fake)
        model = "claude-opus-4-1-20250805"
        manifest = adapter.contract_manifest(
          candidate_revision: fixture.fetch(:head),
          claude_executable: fake,
          model_id: model,
          checker_path: __FILE__,
          schema_path: SCHEMA_PATH
        )
        manifest_path = File.join(fixture.fetch(:state), "contract.json")
        write_private(manifest_path, adapter.canonical_json(manifest))
        contract_digest = Digest::SHA256.file(manifest_path).hexdigest
        output_path = File.join(fixture.fetch(:evidence), "round-1.result.json")
        output, error, status = Open3.capture3(
          {"FOUR_EYES_CLAUDE_API_KEY" => "fake-contract-key"},
          "ruby", ADAPTER_PATH, "review",
          "--repo", fixture.fetch(:repo),
          "--evidence-root", fixture.fetch(:evidence),
          "--state-root", fixture.fetch(:state),
          "--phase-id", "TEST-1",
          "--review-round", "1",
          "--expected-packet-sha256", packet_digest,
          "--packet", packet,
          "--schema", schema_copy,
          "--output", output_path,
          "--contract-manifest", manifest_path,
          "--contract-sha256", contract_digest,
          "--claude-executable", fake,
          "--model-id", model,
          "--maximum-calls", "2",
          "--maximum-dollars", "2.000000",
          "--deadline-seconds", "60"
        )
        unless status.success?
          private_stderr = Dir.glob(File.join(fixture.fetch(:evidence), "runtime", "**", "process.stderr")).map { |path| File.binread(path) }.join
          monitor_errors = Dir.glob(File.join(fixture.fetch(:evidence), "runtime", "**", "*.error")).map { |path| File.binread(path) }.join
          state_debug = Dir.glob(File.join(fixture.fetch(:state), "open", "*.json")).map { |path| File.binread(path) }.join
          runtime_files = Dir.glob(File.join(fixture.fetch(:evidence), "runtime", "**", "*"), File::FNM_DOTMATCH).sort
          fail_check("fake review failed: #{error} private stderr: #{private_stderr} monitor errors: #{monitor_errors} state: #{state_debug} runtime: #{runtime_files.inspect}")
        end
        result_digest = output.strip
        assert_equal(Digest::SHA256.file(output_path).hexdigest, result_digest, "review result digest")
        assert_equal(0o600, File.stat(output_path).mode & 0o777, "review result mode")
        result = adapter.parse_json(File.binread(output_path))
        assert_equal("completed", result.fetch("Review status"), "review status")
        assert_equal("Approve", result.fetch("Verdict"), "review verdict")

        state = adapter::StateStore.new(fixture.fetch(:state)).load("TEST-1")
        assert_equal(2, state.fetch("next_round"), "review next round")
        assert_equal(1, state.fetch("launch_attempts"), "review launch attempts")
        assert_equal(1, state.fetch("confirmed_calls_launched"), "review confirmed calls")
        assert_equal(true, state.fetch("session_established"), "review session established")
        assert_equal("0.100001", state.fetch("settled_dollars"), "review settled cost")
        assert_equal("open", state.fetch("direct_mode"), "review direct mode")
      end
    end

    def check_missing_auth
      with_plan_fixture do |fixture|
        packet, packet_digest = pack_fixture_plan(fixture)
        schema_copy = File.join(fixture.fetch(:evidence), "schema.json")
        write_private(schema_copy, File.binread(SCHEMA_PATH))
        fake = File.join(File.dirname(fixture.fetch(:repo)), "fake-claude")
        provider_marker = File.join(File.dirname(fixture.fetch(:repo)), "provider-launched")
        invocation_log = File.join(File.dirname(fixture.fetch(:repo)), "provider-invocations.log")
        write_fake_claude(fake, provider_marker: provider_marker, invocation_log: invocation_log)
        model = "claude-opus-4-1-20250805"
        manifest = adapter.contract_manifest(
          candidate_revision: fixture.fetch(:head),
          claude_executable: fake,
          model_id: model,
          checker_path: __FILE__,
          schema_path: SCHEMA_PATH
        )
        manifest_path = File.join(fixture.fetch(:state), "contract.json")
        write_private(manifest_path, adapter.canonical_json(manifest))
        output_path = File.join(fixture.fetch(:evidence), "round-1.result.json")
        ambient_home = File.join(File.dirname(fixture.fetch(:repo)), "ambient-home")
        FileUtils.mkdir_p(File.join(ambient_home, ".claude", "plugins"))
        canaries = {
          File.join(ambient_home, ".claude", "settings.json") => "apiKeyHelper: ambient-auth-canary\n",
          File.join(ambient_home, ".claude", "CLAUDE.md") => "ambient-claude-md-canary\n",
          File.join(ambient_home, ".claude", "memory.md") => "ambient-memory-canary\n",
          File.join(ambient_home, ".claude", "plugins", "canary") => "ambient-plugin-canary\n"
        }
        canaries.each { |path, content| File.write(path, content) }
        output, error, status = Open3.capture3(
          {
            "HOME" => ambient_home,
            "CLAUDE_CONFIG_DIR" => File.join(ambient_home, ".claude"),
            "ANTHROPIC_API_KEY" => "ambient-api-key-canary",
            "ANTHROPIC_AUTH_TOKEN" => "ambient-oauth-canary"
          },
          "ruby", ADAPTER_PATH, "review",
          "--repo", fixture.fetch(:repo),
          "--evidence-root", fixture.fetch(:evidence),
          "--state-root", fixture.fetch(:state),
          "--phase-id", "TEST-1",
          "--review-round", "1",
          "--expected-packet-sha256", packet_digest,
          "--packet", packet,
          "--schema", schema_copy,
          "--output", output_path,
          "--contract-manifest", manifest_path,
          "--contract-sha256", Digest::SHA256.file(manifest_path).hexdigest,
          "--claude-executable", fake,
          "--model-id", model,
          "--maximum-calls", "2",
          "--maximum-dollars", "2.000000",
          "--deadline-seconds", "60"
        )
        fail_check("missing-auth terminal failed: #{error}") unless status.success?
        result = adapter.parse_json(File.binread(output_path))
        assert_equal("error", result.fetch("Review status"), "missing-auth status")
        assert_equal("not issued", result.fetch("Verdict"), "missing-auth verdict")
        assert_equal("Invocation-only Claude API key is unavailable.", result.fetch("Reason"), "missing-auth reason")
        assert_equal(Digest::SHA256.file(output_path).hexdigest, output.strip, "missing-auth digest")
        assert(!File.exist?(provider_marker), "provider launched without invocation auth")

        state = adapter::StateStore.new(fixture.fetch(:state)).load("TEST-1")
        assert_equal(2, state.fetch("next_round"), "missing-auth next round")
        assert_equal(0, state.fetch("launch_attempts"), "missing-auth launch attempts")
        assert_equal(0, state.fetch("confirmed_calls_launched"), "missing-auth confirmed calls")
        assert_equal("0.0", state.fetch("settled_dollars"), "missing-auth settled dollars")
        assert_equal("open", state.fetch("direct_mode"), "missing-auth direct mode")
        assert_equal(false, state.fetch("session_established"), "missing-auth session state")
        canaries.each do |path, content|
          assert_equal(content, File.binread(path), "ambient auth/startup canary changed")
        end
        public_bytes = File.binread(output_path) + output + error
        %w[ambient-auth-canary ambient-claude-md-canary ambient-memory-canary ambient-plugin-canary ambient-api-key-canary ambient-oauth-canary].each do |canary|
          assert(!public_bytes.include?(canary), "ambient auth/startup canary leaked")
        end

        packet, packet_digest = pack_fixture_plan(fixture, review_round: 2, review_stage: "plan delta")
        second_output = File.join(fixture.fetch(:evidence), "round-2.result.json")
        _digest, second_error, second_status = Open3.capture3(
          {"FOUR_EYES_CLAUDE_API_KEY" => "fake-contract-key"},
          "ruby", ADAPTER_PATH, "review",
          "--repo", fixture.fetch(:repo), "--evidence-root", fixture.fetch(:evidence),
          "--state-root", fixture.fetch(:state), "--phase-id", "TEST-1",
          "--review-round", "2", "--expected-packet-sha256", packet_digest,
          "--packet", packet, "--schema", schema_copy, "--output", second_output,
          "--contract-manifest", manifest_path,
          "--contract-sha256", Digest::SHA256.file(manifest_path).hexdigest,
          "--claude-executable", fake, "--model-id", model,
          "--maximum-calls", "2", "--maximum-dollars", "2.000000", "--deadline-seconds", "60"
        )
        assert(second_status.success?, "post-auth first launch failed: #{second_error}")
        selector, = File.readlines(invocation_log, chomp: true).fetch(0).split(":", 2)
        assert_equal("session-id", selector, "pre-launch terminal incorrectly established a session")
      end
    end

    def check_prelaunch_failures
      %i[packet_drift stale_contract].each do |failure|
        with_plan_fixture do |fixture|
          packet, packet_digest = pack_fixture_plan(fixture)
          schema_copy = File.join(fixture.fetch(:evidence), "schema.json")
          write_private(schema_copy, File.binread(SCHEMA_PATH))
          fake = File.join(File.dirname(fixture.fetch(:repo)), "fake-claude")
          provider_marker = File.join(File.dirname(fixture.fetch(:repo)), "provider-launched")
          write_fake_claude(fake, provider_marker: provider_marker)
          model = "claude-opus-4-1-20250805"
          manifest = adapter.contract_manifest(
            candidate_revision: fixture.fetch(:head), claude_executable: fake,
            model_id: model, checker_path: __FILE__, schema_path: SCHEMA_PATH
          )
          manifest_path = File.join(fixture.fetch(:state), "contract.json")
          write_private(manifest_path, adapter.canonical_json(manifest))
          contract_digest = Digest::SHA256.file(manifest_path).hexdigest
          if failure == :packet_drift
            File.open(packet, "ab") { |file| file.write("drift") }
          else
            File.open(manifest_path, "ab") { |file| file.write("\n") }
          end
          output_path = File.join(fixture.fetch(:evidence), "round-1.result.json")
          output, error, status = Open3.capture3(
            {"FOUR_EYES_CLAUDE_API_KEY" => "fake-contract-key"},
            "ruby", ADAPTER_PATH, "review",
            "--repo", fixture.fetch(:repo), "--evidence-root", fixture.fetch(:evidence),
            "--state-root", fixture.fetch(:state), "--phase-id", "TEST-1",
            "--review-round", "1", "--expected-packet-sha256", packet_digest,
            "--packet", packet, "--schema", schema_copy, "--output", output_path,
            "--contract-manifest", manifest_path, "--contract-sha256", contract_digest,
            "--claude-executable", fake, "--model-id", model,
            "--maximum-calls", "2", "--maximum-dollars", "2.000000", "--deadline-seconds", "60"
          )
          assert(status.success?, "#{failure} did not record a terminal: #{error}")
          result = adapter.parse_json(File.binread(output_path))
          assert_equal("could-not-review", result.fetch("Review status"), "#{failure} status")
          assert_equal("not issued", result.fetch("Verdict"), "#{failure} verdict")
          assert_equal(Digest::SHA256.file(output_path).hexdigest, output.strip, "#{failure} result digest")
          assert_equal("", error, "#{failure} public stderr")
          assert(!File.exist?(provider_marker), "#{failure} launched provider")
          state = adapter::StateStore.new(fixture.fetch(:state)).load("TEST-1")
          assert_equal(2, state.fetch("next_round"), "#{failure} next round")
          assert_equal(0, state.fetch("launch_attempts"), "#{failure} launch attempts")
          assert_equal(0, state.fetch("confirmed_calls_launched"), "#{failure} confirmed calls")
          assert_equal("0.0", state.fetch("reserved_dollars"), "#{failure} reserved dollars")
        end
      end
    end

    def check_close_cleanup
      with_plan_fixture do |fixture|
        _packet, _packet_digest = pack_fixture_plan(fixture)
        result_path = File.join(fixture.fetch(:evidence), "round-1.result.json")
        result_bytes = adapter.canonical_json(
          "Review status" => "error",
          "Verdict" => "not issued",
          "Reason" => "Fixture terminal.",
          "Artifact identity" => nil
        )
        write_private(result_path, result_bytes)
        close_result_digest = Digest::SHA256.hexdigest(result_bytes)
        model = "claude-opus-4-1-20250805"
        contract_digest = "c" * 64
        store = adapter::StateStore.new(fixture.fetch(:state))
        store.create!(
          phase_id: "TEST-1",
          model_id: model,
          contract_digest: contract_digest,
          maximum_calls: 2,
          maximum_dollars: BigDecimal("2.000000")
        )
        store.prelaunch_terminal!(
          phase_id: "TEST-1",
          review_round: 1,
          model_id: model,
          contract_digest: contract_digest,
          maximum_calls: 2,
          maximum_dollars: BigDecimal("2.000000"),
          outcome_digest: close_result_digest
        )

        output, error, status = Open3.capture3(
          "ruby", ADAPTER_PATH, "close",
          "--repo", fixture.fetch(:repo),
          "--evidence-root", fixture.fetch(:evidence),
          "--state-root", fixture.fetch(:state),
          "--phase-id", "TEST-1",
          "--close-result-sha256", close_result_digest
        )
        fail_check("close failed: #{error}") unless status.success?
        tombstone_path = store.tombstone_path("TEST-1")
        tombstone = adapter.parse_json(File.binread(tombstone_path))
        assert_equal(Digest::SHA256.file(tombstone_path).hexdigest, output.strip, "close tombstone digest")
        assert_equal(
          %w[close_result_digest closed contract_digest final_round phase_id version],
          tombstone.keys.sort,
          "tombstone fields"
        )
        assert_equal([], Dir.children(fixture.fetch(:evidence)), "closed evidence root")
        assert(!File.exist?(store.state_path("TEST-1")), "open phase state retained")
        binding_directory = File.join(fixture.fetch(:state), "bindings", Digest::SHA256.hexdigest("TEST-1"))
        assert(!File.exist?(binding_directory), "phase bindings retained")
        expect_failure(adapter::AdapterError) { store.load("TEST-1") }

        output, _error, status = Open3.capture3(
          "ruby", ADAPTER_PATH, "pack",
          "--repo", fixture.fetch(:repo), "--evidence-root", fixture.fetch(:evidence),
          "--state-root", fixture.fetch(:state), "--phase-id", "TEST-1",
          "--review-round", "2", "--review-stage", "plan delta",
          "--workflow-revision", fixture.fetch(:head), "--artifact-kind", "plan",
          "--source-plan", fixture.fetch(:plan), "--reviewer-instructions", fixture.fetch(:instructions),
          "--verification-evidence", fixture.fetch(:verification),
          "--neutral-prior-summary", fixture.fetch(:neutral), "--own-prior-findings", fixture.fetch(:prior),
          "--packet", File.join(fixture.fetch(:evidence), "round-2.packet")
        )
        assert(!status.success?, "closed phase accepted another packet")
        assert_equal("", output, "closed phase emitted packet digest")
      end
    end

    def check_failure_mapping
      {nonzero: "error", malformed: "could-not-review"}.each do |behavior, expected_status|
        with_plan_fixture do |fixture|
          invocation = invoke_fixture_review(fixture, behavior: behavior)
          fail_check("#{behavior} terminal invocation failed: #{invocation.fetch(:error)}") unless invocation.fetch(:status).success?
          result = adapter.parse_json(File.binread(invocation.fetch(:output_path)))
          assert_equal(expected_status, result.fetch("Review status"), "#{behavior} status")
          assert_equal("not issued", result.fetch("Verdict"), "#{behavior} verdict")
          assert(!adapter.canonical_json(result).include?("private-provider-canary"), "#{behavior} leaked private output")
          assert_equal("", invocation.fetch(:error), "#{behavior} public stderr")
          state = adapter::StateStore.new(fixture.fetch(:state)).load("TEST-1")
          assert_equal(2, state.fetch("next_round"), "#{behavior} next round")
          assert_equal(1, state.fetch("launch_attempts"), "#{behavior} launch attempts")
          assert_equal(1, state.fetch("confirmed_calls_launched"), "#{behavior} confirmed calls")
          assert_equal("closed", state.fetch("direct_mode"), "#{behavior} direct mode")
          assert_equal("confirmed-launched", state.fetch("provider_launch_state"), "#{behavior} launch state")
          assert_equal("2.0", state.fetch("reserved_dollars"), "#{behavior} retained reservation")
        end
      end
    end

    def check_launch_accounting
      with_supervision_fixture(behavior: :spawn_error, deadline_offset: 20) do |fixture|
        event = adapter.await_supervision(fixture.fetch(:handle))
        assert_equal("error", event.fetch("event"), "spawn-failure supervision event")
        assert_equal(false, event.fetch("launched_uncertain"), "spawn failure launch certainty")
        state = fixture.fetch(:store).load(fixture.fetch(:phase_id))
        assert_equal(1, state.fetch("launch_attempts"), "spawn failure attempt count")
        assert_equal(0, state.fetch("confirmed_calls_launched"), "spawn failure confirmed calls")
        assert_equal("not-launched", state.fetch("provider_launch_state"), "spawn failure launch state")
        assert_equal("2.0", state.fetch("reserved_dollars"), "spawn failure initial reservation")
        terminal = fixture.fetch(:store).terminal_round!(
          phase_id: fixture.fetch(:phase_id),
          nonce: fixture.fetch(:nonce),
          outcome_digest: "b" * 64,
          launched_uncertain: false
        )
        assert_equal("0.0", terminal.fetch("reserved_dollars"), "spawn failure released reservation")
        assert_equal("open", terminal.fetch("direct_mode"), "disproved launch closed direct mode")
        assert_equal(0, terminal.fetch("confirmed_calls_launched"), "spawn failure invented confirmed call")
      end
    end

    def invoke_fixture_review(fixture, behavior: :success)
      packet, packet_digest = pack_fixture_plan(fixture)
      schema_copy = File.join(fixture.fetch(:evidence), "schema.json")
      write_private(schema_copy, File.binread(SCHEMA_PATH))
      fake = File.join(File.dirname(fixture.fetch(:repo)), "fake-claude")
      write_fake_claude(fake, behavior: behavior)
      model = "claude-opus-4-1-20250805"
      manifest = adapter.contract_manifest(
        candidate_revision: fixture.fetch(:head),
        claude_executable: fake,
        model_id: model,
        checker_path: __FILE__,
        schema_path: SCHEMA_PATH
      )
      manifest_path = File.join(fixture.fetch(:state), "contract.json")
      write_private(manifest_path, adapter.canonical_json(manifest))
      output_path = File.join(fixture.fetch(:evidence), "round-1.result.json")
      output, error, status = Open3.capture3(
        {"FOUR_EYES_CLAUDE_API_KEY" => "fake-contract-key"},
        "ruby", ADAPTER_PATH, "review",
        "--repo", fixture.fetch(:repo),
        "--evidence-root", fixture.fetch(:evidence),
        "--state-root", fixture.fetch(:state),
        "--phase-id", "TEST-1",
        "--review-round", "1",
        "--expected-packet-sha256", packet_digest,
        "--packet", packet,
        "--schema", schema_copy,
        "--output", output_path,
        "--contract-manifest", manifest_path,
        "--contract-sha256", Digest::SHA256.file(manifest_path).hexdigest,
        "--claude-executable", fake,
        "--model-id", model,
        "--maximum-calls", "2",
        "--maximum-dollars", "2.000000",
        "--deadline-seconds", "60"
      )
      {output: output, error: error, status: status, output_path: output_path}
    end

    def check_session_resume
      with_plan_fixture do |fixture|
        invocation_log = File.join(File.dirname(fixture.fetch(:repo)), "provider-invocations.log")
        packet, packet_digest = pack_fixture_plan(fixture, review_round: 1)
        schema_copy = File.join(fixture.fetch(:evidence), "schema.json")
        write_private(schema_copy, File.binread(SCHEMA_PATH))
        fake = File.join(File.dirname(fixture.fetch(:repo)), "fake-claude")
        write_fake_claude(fake, invocation_log: invocation_log)
        model = "claude-opus-4-1-20250805"
        manifest = adapter.contract_manifest(
          candidate_revision: fixture.fetch(:head),
          claude_executable: fake,
          model_id: model,
          checker_path: __FILE__,
          schema_path: SCHEMA_PATH
        )
        manifest_path = File.join(fixture.fetch(:state), "contract.json")
        write_private(manifest_path, adapter.canonical_json(manifest))
        contract_digest = Digest::SHA256.file(manifest_path).hexdigest

        [1, 2].each do |round|
          if round == 2
            packet, packet_digest = pack_fixture_plan(fixture, review_round: round, review_stage: "plan delta")
          end
          output_path = File.join(fixture.fetch(:evidence), "round-#{round}.result.json")
          _output, error, status = Open3.capture3(
            {"FOUR_EYES_CLAUDE_API_KEY" => "fake-contract-key"},
            "ruby", ADAPTER_PATH, "review",
            "--repo", fixture.fetch(:repo), "--evidence-root", fixture.fetch(:evidence),
            "--state-root", fixture.fetch(:state), "--phase-id", "TEST-1",
            "--review-round", round.to_s, "--expected-packet-sha256", packet_digest,
            "--packet", packet, "--schema", schema_copy, "--output", output_path,
            "--contract-manifest", manifest_path, "--contract-sha256", contract_digest,
            "--claude-executable", fake, "--model-id", model,
            "--maximum-calls", "2", "--maximum-dollars", "2.000000", "--deadline-seconds", "60"
          )
          fail_check("resume round #{round} failed: #{error}") unless status.success?
        end

        invocations = File.readlines(invocation_log, chomp: true)
        assert_equal(2, invocations.length, "provider invocation count")
        first_selector, first_session = invocations.fetch(0).split(":", 2)
        second_selector, second_session = invocations.fetch(1).split(":", 2)
        assert_equal("session-id", first_selector, "first session selector")
        assert_equal("resume", second_selector, "second session selector")
        assert_equal(first_session, second_session, "resumed session identity")
        state = adapter::StateStore.new(fixture.fetch(:state)).load("TEST-1")
        assert_equal(3, state.fetch("next_round"), "resume next round")
        assert_equal(2, state.fetch("launch_attempts"), "resume launch attempts")
        assert_equal(2, state.fetch("confirmed_calls_launched"), "resume confirmed calls")
        assert_equal("0.200002", state.fetch("settled_dollars"), "resume settled dollars")
        assert_equal(true, state.fetch("session_established"), "resume trusted session")
      end
    end

    def check_monitor_failover
      %w[watchdog_pid supervisor_pid].each do |failed_monitor|
        with_supervision_fixture(behavior: :hang, deadline_offset: 4) do |fixture|
          state = wait_for_state(fixture.fetch(:store), fixture.fetch(:phase_id)) { |value| value["current_transition"] == "in_flight" }
          wrapper_pid = state.fetch("wrapper_pid")
          failed_pid = state.fetch(failed_monitor)
          assert(failed_pid != Process.pid, "#{failed_monitor} aliases test process")
          assert(wrapper_pid != Process.pid, "wrapper aliases test process")
          assert_equal(wrapper_pid, Process.getpgid(wrapper_pid), "wrapper process group")
          assert(Process.getpgrp != wrapper_pid, "test process joined wrapper group")
          Process.kill("KILL", failed_pid)
          event = begin
            adapter.await_supervision(fixture.fetch(:handle))
          rescue adapter::AdapterError
            nil
          end
          if failed_monitor == "supervisor_pid"
            assert_equal("timeout", event&.fetch("event"), "surviving watchdog outcome")
          else
            assert_equal(nil, event, "dead watchdog outcome")
          end
          wait_until(10, "wrapper survived failed #{failed_monitor}") { !process_alive?(wrapper_pid) }
          assert(!process_alive?(wrapper_pid), "wrapper remains after #{failed_monitor} failure")
          terminalize_supervision_fixture(fixture)
        end
      end
    end

    def check_parent_loss
      with_supervision_fixture(behavior: :hang, deadline_offset: 4) do |fixture|
        state = wait_for_state(fixture.fetch(:store), fixture.fetch(:phase_id)) { |value| value["current_transition"] == "in_flight" }
        wrapper_pid = state.fetch("wrapper_pid")
        watchdog_pid = fixture.fetch(:handle).fetch(:pid)
        fixture.fetch(:handle).fetch(:io).close
        wait_until(10, "wrapper survived parent loss and monitor deadline") { !process_alive?(wrapper_pid) }
        Process.waitpid(watchdog_pid)
        assert(!process_alive?(watchdog_pid), "watchdog survived completed parent-loss cleanup")
        blocked = fixture.fetch(:store).load(fixture.fetch(:phase_id))
        assert_equal("in_flight", blocked.fetch("current_transition"), "parent loss silently reopened transition")
        expect_failure do
          fixture.fetch(:store).begin_dispatch!(
            phase_id: fixture.fetch(:phase_id), review_round: 1,
            model_id: "claude-opus-4-1-20250805", contract_digest: "d" * 64,
            maximum_calls: 2, maximum_dollars: BigDecimal("2.000000"),
            deadline: Time.now.to_i + 60
          )
        end
        terminalize_supervision_fixture(fixture)
      end
    end

    def check_wrapper_authority
      unrelated_pid = Process.spawn("/bin/sleep", "20", pgroup: true)
      with_supervision_fixture(behavior: :success, deadline_offset: 5) do |fixture|
        completed = adapter.await_supervision(fixture.fetch(:handle))
        unless completed["event"] == "completed"
          errors = Dir.glob(File.join(fixture.fetch(:runtime_root), "*.error")).map { |path| File.binread(path) }.join
          state_debug = adapter.canonical_json(fixture.fetch(:store).load(fixture.fetch(:phase_id)))
          progress = File.exist?(fixture.fetch(:provider_progress)) ? File.binread(fixture.fetch(:provider_progress)) : "missing"
          fail_check("wrapper completion event: #{completed.inspect}; errors: #{errors}; provider progress: #{progress}; state: #{state_debug}")
        end
        state = fixture.fetch(:store).load(fixture.fetch(:phase_id))
        wrapper_pid = state.fetch("wrapper_pid")
        assert(process_alive?(wrapper_pid), "wrapper exited before durable release")
        sleep_for = fixture.fetch(:deadline) + 1 - Time.now.to_f
        sleep(sleep_for) if sleep_for.positive?
        assert(process_alive?(wrapper_pid), "wrapper did not survive TERM grace")
        timeout = adapter.await_supervision(fixture.fetch(:handle))
        assert_equal("timeout", timeout.fetch("event"), "unreleased wrapper timeout")
        wait_until(3, "wrapper remained after KILL") { !process_alive?(wrapper_pid) }
        assert(process_alive?(unrelated_pid), "unrelated process group was signaled")
        terminalize_supervision_fixture(fixture)
      end
    ensure
      if unrelated_pid && process_alive?(unrelated_pid)
        Process.kill("TERM", unrelated_pid)
        Process.waitpid(unrelated_pid) rescue nil
      end
    end

    def check_control_and_overflow
      nonce = "a" * 64
      writer, reader = Socket.pair(:UNIX, :STREAM, 0)
      adapter.send_control(writer, nonce, "TERM")
      adapter.send_control(writer, nonce, "TERM")
      assert_equal("TERM", adapter.read_control(reader, nonce), "first idempotent TERM")
      assert_equal("TERM", adapter.read_control(reader, nonce), "second idempotent TERM")
      writer.close
      reader.close

      writer, reader = Socket.pair(:UNIX, :STREAM, 0)
      writer.write("#{'b' * 64}\0KILL\n")
      expect_failure(adapter::AdapterError) { adapter.read_control(reader, nonce) }
      writer.close
      reader.close

      source = File.binread(ADAPTER_PATH)
      watchdog = source.byteslice(source.index("  def watchdog_event_loop"), source.index("  def internal_supervisor") - source.index("  def watchdog_event_loop"))
      supervisor = source.byteslice(source.index("  def supervisor_event_loop"), source.index("  def internal_wrapper") - source.index("  def supervisor_event_loop"))
      wrapper = source.byteslice(source.index("  def run_provider_wrapper"), source.index("  def capture_stream") - source.index("  def run_provider_wrapper"))
      assert(!watchdog.include?("Process.kill"), "watchdog uses numeric signaling")
      assert(!supervisor.include?("Process.kill"), "supervisor uses numeric signaling")
      assert(wrapper.include?("Process.kill"), "wrapper lacks self-group signaling")

      with_supervision_fixture(behavior: :overflow, deadline_offset: 20) do |fixture|
        state = wait_for_state(fixture.fetch(:store), fixture.fetch(:phase_id)) { |value| value["current_transition"] == "in_flight" }
        wrapper_pid = state.fetch("wrapper_pid")
        event = adapter.await_supervision(fixture.fetch(:handle))
        assert_equal("error", event.fetch("event"), "overflow outcome")
        wait_until(3, "overflow wrapper remained") { !process_alive?(wrapper_pid) }
        terminalize_supervision_fixture(fixture)
      end
    end

    def with_supervision_fixture(behavior:, deadline_offset:)
      with_plan_fixture do |fixture|
        packet, packet_digest = pack_fixture_plan(fixture)
        fake = File.join(File.dirname(fixture.fetch(:repo)), "fake-claude")
        provider_progress = File.join(File.dirname(fixture.fetch(:repo)), "provider-progress.log")
        write_supervision_fake(fake, behavior: behavior, provider_progress: provider_progress)
        runtime = adapter.create_runtime(fixture.fetch(:evidence), "TEST-1", 1)
        settings_path = File.join(runtime.fetch(:home), "settings.json")
        mcp_path = File.join(runtime.fetch(:home), "mcp.json")
        write_private(settings_path, "{}\n")
        write_private(mcp_path, "{}\n")
        schema_json = adapter.canonical_json(adapter.plain_json_value(adapter.parse_json(File.binread(SCHEMA_PATH))))
        store = adapter::StateStore.new(fixture.fetch(:state))
        model = "claude-opus-4-1-20250805"
        contract_digest = "d" * 64
        state = store.create!(
          phase_id: "TEST-1",
          model_id: model,
          contract_digest: contract_digest,
          maximum_calls: 2,
          maximum_dollars: BigDecimal("2.000000")
        )
        deadline = Time.now.to_i + deadline_offset
        dispatch = store.begin_dispatch!(
          phase_id: "TEST-1",
          review_round: 1,
          model_id: model,
          contract_digest: contract_digest,
          maximum_calls: 2,
          maximum_dollars: BigDecimal("2.000000"),
          deadline: deadline
        )
        argv = adapter.build_claude_argv(
          claude_executable: fake,
          schema_json: schema_json,
          model_id: model,
          mcp_config_path: mcp_path,
          settings_path: settings_path,
          remaining_budget: BigDecimal("2.000000"),
          session_id: state.fetch("candidate_session_uuid"),
          resume: false
        )
        runtime_config = runtime.transform_keys(&:to_s)
        config = {
          "absolute_deadline" => deadline,
          "argv" => argv,
          "nonce" => dispatch.fetch("dispatch_nonce"),
          "packet_path" => packet,
          "packet_sha256" => packet_digest,
          "phase_id" => "TEST-1",
          "phase_sha256" => Digest::SHA256.hexdigest("TEST-1"),
          "review_round" => 1,
          "runtime" => runtime_config,
          "state_root" => fixture.fetch(:state)
        }
        config_path = File.join(runtime.fetch(:root), "supervision.json")
        write_private(config_path, adapter.canonical_json(config))
        handle = adapter.start_supervision(config_path, "fake-contract-key", runtime_config)
        yield fixture.merge(
          store: store,
          phase_id: "TEST-1",
          nonce: dispatch.fetch("dispatch_nonce"),
          handle: handle,
          deadline: deadline,
          runtime_root: runtime.fetch(:root),
          provider_progress: provider_progress
        )
      ensure
        handle&.fetch(:io)&.close rescue nil
        Process.waitpid(handle.fetch(:pid), Process::WNOHANG) rescue nil if handle
      end
    end

    def terminalize_supervision_fixture(fixture)
      state = fixture.fetch(:store).load(fixture.fetch(:phase_id))
      return if state["current_transition"] == "idle"

      fixture.fetch(:store).terminal_round!(
        phase_id: fixture.fetch(:phase_id),
        nonce: fixture.fetch(:nonce),
        outcome_digest: "e" * 64,
        launched_uncertain: true
      )
    end

    def wait_for_state(store, phase_id, &condition)
      value = nil
      wait_until(5, "state transition did not arrive") do
        value = store.load(phase_id)
        condition.call(value)
      rescue adapter::AdapterError
        false
      end
      value
    end

    def wait_until(seconds, message)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
      until yield
        fail_check(message) if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        sleep 0.05
      end
      true
    end

    def process_alive?(pid)
      Process.kill(0, pid)
      true
    rescue Errno::ESRCH
      false
    end

    def pack_fixture_plan(fixture, review_round: 1, review_stage: "plan")
      packet = File.join(fixture.fetch(:evidence), "round-#{review_round}.packet")
      output, error, status = Open3.capture3(
        "ruby", ADAPTER_PATH, "pack",
        "--repo", fixture.fetch(:repo), "--evidence-root", fixture.fetch(:evidence),
        "--state-root", fixture.fetch(:state), "--phase-id", "TEST-1",
        "--review-round", review_round.to_s, "--review-stage", review_stage,
        "--workflow-revision", fixture.fetch(:head), "--artifact-kind", "plan",
        "--source-plan", fixture.fetch(:plan), "--reviewer-instructions", fixture.fetch(:instructions),
        "--verification-evidence", fixture.fetch(:verification),
        "--neutral-prior-summary", fixture.fetch(:neutral), "--own-prior-findings", fixture.fetch(:prior),
        "--packet", packet
      )
      fail_check("fixture pack failed: #{error}") unless status.success?
      [packet, output.strip]
    end

    def pack_fixture_artifact(fixture, phase_id:, review_round:, artifact_kind:, base: nil, reviewed_head: nil)
      packet = File.join(fixture.fetch(:evidence), "#{phase_id}-round-#{review_round}.packet")
      arguments = [
        "ruby", ADAPTER_PATH, "pack",
        "--repo", fixture.fetch(:repo), "--evidence-root", fixture.fetch(:evidence),
        "--state-root", fixture.fetch(:state), "--phase-id", phase_id,
        "--review-round", review_round.to_s, "--review-stage", "implementation",
        "--workflow-revision", fixture.fetch(:head), "--artifact-kind", artifact_kind,
        "--reviewer-instructions", fixture.fetch(:instructions),
        "--verification-evidence", fixture.fetch(:verification),
        "--neutral-prior-summary", fixture.fetch(:neutral), "--own-prior-findings", fixture.fetch(:prior),
        "--packet", packet
      ]
      arguments.concat(["--base", base, "--reviewed-head", reviewed_head]) if base && reviewed_head
      output, error, status = Open3.capture3(*arguments)
      fail_check("#{artifact_kind} fixture pack failed: #{error}") unless status.success?
      assert_equal(Digest::SHA256.file(packet).hexdigest, output.strip, "#{artifact_kind} packet digest")
      packet
    end

    def write_private(path, content)
      File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(content) }
    end

    def write_fake_claude(path, provider_marker: nil, behavior: :success, invocation_log: nil)
      marker_line = provider_marker ? "File.write(#{provider_marker.inspect}, \"launched\\n\")" : ""
      log_line = invocation_log ? "File.open(#{invocation_log.inspect}, \"a\", 0o600) { |file| file.puts(\"\#{selector}:\#{session}\") }" : ""
      behavior_line = case behavior
                      when :success then ""
                      when :nonzero then 'warn "private-provider-canary"; exit 17'
                      when :malformed then 'STDOUT.write("{malformed"); exit 0'
                      when :hang then 'sleep 120'
                      else fail_check("unsupported fake behavior: #{behavior}")
                      end
      source = <<~RUBY
        #!#{RbConfig.ruby}
        require "json"

        if ARGV == ["--version"]
          puts "fake-claude 1.0"
          exit 0
        end
        if ARGV == ["--help"]
          puts "fake help: bare json-schema effort tools mcp settings session resume budget"
          exit 0
        end

        #{marker_line}

        required_env = %w[ANTHROPIC_API_KEY HOME LANG LC_ALL TMPDIR]
        ENV.delete("__CF_USER_TEXT_ENCODING") if RUBY_PLATFORM.include?("darwin")
        abort "environment leak: \#{ENV.keys.sort.inspect}" unless ENV.keys.sort == required_env.sort
        abort "key missing" unless ENV["ANTHROPIC_API_KEY"] == "fake-contract-key"
        abort "locale mismatch" unless ENV["LANG"] == "C.UTF-8" && ENV["LC_ALL"] == "C"
        abort "cwd not private" unless Dir.pwd.start_with?(ENV.fetch("HOME"))
        abort "HOME mode" unless (File.stat(ENV.fetch("HOME")).mode & 0o777) == 0o700
        abort "TMPDIR mode" unless (File.stat(ENV.fetch("TMPDIR")).mode & 0o777) == 0o700

        value_after = ->(flag) { index = ARGV.index(flag) or abort "missing flag: \#{flag}"; ARGV.fetch(index + 1) }
        abort "effort" unless value_after.call("--effort") == "max"
        abort "tools" unless value_after.call("--tools") == ""
        abort "settings bytes" unless File.binread(value_after.call("--settings")) == "{}\\n"
        abort "mcp bytes" unless File.binread(value_after.call("--mcp-config")) == "{}\\n"
        selector = ARGV.include?("--session-id") ? "session-id" : "resume"
        session = value_after.call("--\#{selector}")
        #{log_line}

        packet = STDIN.read.b
        magic = "four-eyes-review-packet-v1\\0".b
        abort "packet magic" unless packet.start_with?(magic)
        offset = magic.bytesize
        identity = nil
        14.times do
          label_end = packet.index("\\0", offset) or abort "label"
          label = packet.byteslice(offset, label_end - offset)
          length_end = packet.index("\\0", label_end + 1) or abort "length"
          length = Integer(packet.byteslice(label_end + 1, length_end - label_end - 1), 10)
          value = packet.byteslice(length_end + 1, length)
          identity = JSON.parse(value) if label == "identity-json"
          offset = length_end + 1 + length
        end
        #{behavior_line}
        result = {
          "type" => "result",
          "subtype" => "success",
          "is_error" => false,
          "session_id" => session,
          "total_cost_usd" => 0.100001,
          "structured_output" => {
            "Review status" => "completed",
            "Verdict" => "Approve",
            "Blocking findings" => [],
            "Non-blocking findings" => [],
            "Questions" => [],
            "Required changes" => [],
            "Artifact identity" => identity
          }
        }
        STDOUT.write(JSON.generate(result))
      RUBY
      File.write(path, source)
      File.chmod(0o700, path)
    end

    def write_supervision_fake(path, behavior:, provider_progress:)
      if behavior == :spawn_error
        File.write(path, "#!/definitely/missing/four-eyes-interpreter\n")
        File.chmod(0o700, path)
        return
      end
      quoted_progress = "'#{provider_progress.gsub("'", %q('\\''))}'"
      action = case behavior
               when :hang then "/bin/sleep 120"
               when :overflow then "/usr/bin/head -c 1100000 /dev/zero; /bin/sleep 120"
               else "exit 0"
               end
      source = <<~SH
        #!/bin/sh
        printf 'started\\n' > #{quoted_progress}
        #{action}
      SH
      File.write(path, source)
      File.chmod(0o700, path)
    end

    def decode_body_record(bytes, offset)
      label_end = bytes.index("\0", offset) || fail_check("manual body label truncated")
      label = bytes.byteslice(offset, label_end - offset)
      length_end = bytes.index("\0", label_end + 1) || fail_check("manual body length truncated")
      length_text = bytes.byteslice(label_end + 1, length_end - label_end - 1)
      assert(length_text.match?(/\A(?:0|[1-9][0-9]*)\z/), "manual body length not canonical")
      length = Integer(length_text, 10)
      value_start = length_end + 1
      value = bytes.byteslice(value_start, length) || fail_check("manual body value truncated")
      [label, length, value, value_start + length]
    end

    def with_plan_fixture
      Dir.mktmpdir("four-eyes-claude-pack-") do |tmp|
        repo = File.join(tmp, "repo")
        evidence = File.join(tmp, "evidence")
        state = File.join(tmp, "state")
        FileUtils.mkdir_p(File.join(repo, "tmp"))
        File.write(File.join(repo, ".gitignore"), "/tmp/\n")
        plan = File.join(repo, "tmp", "plan.md")
        File.write(plan, "# Test Plan\n\nReview these exact bytes.\n")
        git!(repo, "init", "-q")
        git!(repo, "config", "user.name", "Four Eyes Self Test")
        git!(repo, "config", "user.email", "self-test@example.invalid")
        git!(repo, "add", ".gitignore")
        git!(repo, "commit", "-q", "-m", "fixture")
        head = git!(repo, "rev-parse", "HEAD")
        Dir.mkdir(evidence, 0o700)
        Dir.mkdir(state, 0o700)
        inputs = {
          instructions: "Review independently.\n",
          verification: "fixture verification passed\n",
          neutral: "",
          prior: ""
        }.transform_values.with_index do |content, index|
          path = File.join(evidence, "input-#{index}.txt")
          File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(content) }
          path
        end
        yield({repo: repo, evidence: evidence, state: state, plan: plan, head: head}.merge(inputs))
      end
    end

    def with_git_artifact_fixture
      Dir.mktmpdir("four-eyes-claude-artifact-") do |tmp|
        repo = File.join(tmp, "repo")
        FileUtils.mkdir_p(repo)
        git!(repo, "init", "-q")
        git!(repo, "config", "user.name", "Four Eyes Self Test")
        git!(repo, "config", "user.email", "self-test@example.invalid")
        File.write(File.join(repo, "tracked.txt"), "base\n")
        git!(repo, "add", "tracked.txt")
        git!(repo, "commit", "-q", "-m", "base")
        base = git!(repo, "rev-parse", "HEAD")
        File.write(File.join(repo, "tracked.txt"), "base\nstaged\n")
        git!(repo, "add", "tracked.txt")
        File.open(File.join(repo, "tracked.txt"), "a") { |file| file.write("unstaged\n") }
        File.write(File.join(repo, "untracked.txt"), "untracked fixture\n")
        yield repo: repo, base: base
      end
    end

    def with_clean_git_artifact_fixture
      Dir.mktmpdir("four-eyes-claude-artifact-negative-") do |tmp|
        repo = File.join(tmp, "repo")
        FileUtils.mkdir_p(repo)
        git!(repo, "init", "-q")
        git!(repo, "config", "user.name", "Four Eyes Self Test")
        git!(repo, "config", "user.email", "self-test@example.invalid")
        File.write(File.join(repo, "tracked.txt"), "base\n")
        git!(repo, "add", "tracked.txt")
        git!(repo, "commit", "-q", "-m", "base")
        yield repo, git!(repo, "rev-parse", "HEAD")
      end
    end

    def git!(repo, *arguments)
      output, error, status = Open3.capture3("git", "-C", repo, *arguments)
      fail_check("git fixture failed: #{error}") unless status.success?

      output.strip
    end
  end

  def self.load_adapter!
    require ADAPTER_PATH
  rescue LoadError
    raise CheckFailure, "required adapter missing: scripts/claude-reviewer2.rb" unless File.file?(ADAPTER_PATH)

    raise
  end
end

begin
  unless ARGV == ["--self-test"]
    raise FourEyesClaudeReviewer2Check::CheckFailure, "usage: ruby scripts/check-claude-reviewer2.rb --self-test"
  end

  FourEyesClaudeReviewer2Check.load_adapter!
  FourEyesClaudeReviewer2Check::SelfTest.new.run!
rescue FourEyesClaudeReviewer2Check::CheckFailure => error
  warn "check-claude-reviewer2: FAIL: #{error.message}"
  exit 1
end
