#!/usr/bin/env ruby
# frozen_string_literal: true

require "bigdecimal"
require "digest"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "pathname"
require "rbconfig"
require "securerandom"
require "socket"
require "timeout"

module FourEyesClaudeReviewer2
  class AdapterError < StandardError; end
  class ProviderSpawnError < AdapterError; end
  class PostCompletionReleaseError < AdapterError; end

  class DuplicateRejectingHash < Hash
    def []=(key, value)
      raise JSON::ParserError, "duplicate JSON key: #{key}" if key?(key)

      super
    end
  end

  PACKET_MAGIC = "four-eyes-review-packet-v1\0".b.freeze
  PACKET_RECORD_LABELS = [
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
  SYSTEM_PROMPT = "You are Four Eyes Reviewer 2. Review only the sealed packet on standard input. Do not use tools or outside context. Return only structured output matching the supplied JSON Schema.".freeze

  MAXIMUM_CALLS_PATTERN = /\A(?:[1-9]|1[0-9]|20)\z/.freeze
  MAXIMUM_DOLLARS_PATTERN = /\A(?:0|[1-9][0-9]{0,2})\.[0-9]{1,6}\z/.freeze
  GIT_SHA_PATTERN = /\A[0-9a-f]{40}\z/.freeze
  SHA256_PATTERN = /\A[0-9a-f]{64}\z/.freeze
  REVIEW_STAGES = ["plan", "plan delta", "implementation", "implementation delta", "post-execution"].freeze
  PACKET_LIMIT = 524_288
  ARTIFACT_LIMIT = 307_200
  IDENTITY_LIMIT = 16_384
  MANIFEST_LIMIT = 32_768
  SCHEMA_LIMIT = 131_072
  CONTRACT_MANIFEST_LIMIT = 131_072
  STATE_LIMIT = 65_536
  RESULT_LIMIT = 524_288
  STDOUT_LIMIT = 1_048_576
  STDERR_LIMIT = 262_144
  PHASE_MARKER = ".four-eyes-phase.json"
  TERMINATION_GRACE = 5
  IPC_LIMIT = 1_048_576
  ACTIVE_PROCESS_KEYS = %w[
    watchdog_pid supervisor_pid wrapper_pid wrapper_pgid wrapper_start_token
    wrapper_command wrapper_command_sha256 provider_pid
  ].freeze
  TEXT_LIMITS = {
    "reviewer-instructions" => 32_768,
    "verification-evidence" => 65_536,
    "neutral-prior-summary" => 16_384,
    "own-prior-findings" => 32_768
  }.freeze
  CANONICAL_DIFF_ARGUMENTS = [
    "-c", "core.attributesFile=/dev/null",
    "-c", "core.quotePath=true",
    "-c", "diff.mnemonicPrefix=false",
    "-c", "diff.suppressBlankEmpty=false",
    "diff",
    "--diff-algorithm=myers",
    "--no-indent-heuristic",
    "--inter-hunk-context=0",
    "--src-prefix=a/",
    "--dst-prefix=b/",
    "--unified=3",
    "--no-ext-diff",
    "--no-textconv",
    "--no-color",
    "--no-renames",
    "--no-relative",
    "--ignore-submodules=none",
    "--submodule=short",
    "--full-index",
    "--binary",
    "-O/dev/null"
  ].freeze
  FIXED_CLAUDE_FLAGS = [
    "--bare", "--print", "--input-format", "text", "--output-format", "json",
    "--json-schema", "<schema>", "--model", "<model>", "--effort", "max",
    "--tools", "", "--disable-slash-commands", "--strict-mcp-config",
    "--mcp-config", "<mcp-config>", "--settings", "<settings>", "--no-chrome",
    "--permission-mode", "dontAsk", "--system-prompt", SYSTEM_PROMPT,
    "--max-budget-usd", "<remaining-budget>", "<session-selector>", "<session-id>"
  ].freeze

  class StateStore
    attr_reader :root

    def initialize(root)
      @root = File.realpath(root)
      stat = File.lstat(@root)
      unless stat.directory? && !stat.symlink? && stat.uid == Process.uid && (stat.mode & 0o777) == 0o700
        raise AdapterError, "state root must be an owned 0700 directory"
      end
      %w[open tombstones locks].each { |name| ensure_directory(File.join(@root, name)) }
    end

    def state_path(phase_id)
      File.join(root, "open", "#{phase_digest(phase_id)}.json")
    end

    def tombstone_path(phase_id)
      File.join(root, "tombstones", "#{phase_digest(phase_id)}.json")
    end

    def create!(phase_id:, model_id:, contract_digest:, maximum_calls:, maximum_dollars:)
      validate_identity_arguments(phase_id, model_id, contract_digest, maximum_calls, maximum_dollars)
      with_lock(phase_id) do
        raise AdapterError, "phase is closed" if path_entry?(tombstone_path(phase_id))
        raise AdapterError, "phase state already exists" if path_entry?(state_path(phase_id))
        state = {
          "candidate_session_uuid" => SecureRandom.uuid,
          "confirmed_calls_launched" => 0,
          "contract_digest" => contract_digest,
          "current_transition" => "idle",
          "direct_mode" => "open",
          "dispatch_nonce" => nil,
          "absolute_deadline" => nil,
          "last_outcome_digest" => nil,
          "launch_attempts" => 0,
          "maximum_calls" => maximum_calls,
          "maximum_dollars" => decimal_state(maximum_dollars),
          "model_id" => model_id,
          "next_round" => 1,
          "phase_id" => phase_id,
          "provider_launch_state" => "not-launched",
          "reserved_dollars" => "0.0",
          "session_established" => false,
          "settled_dollars" => "0.0",
          "version" => 1
        }
        write_new(state_path(phase_id), state)
        state
      end
    end

    def reject_closed!(phase_id)
      with_lock(phase_id) do
        raise AdapterError, "phase is closed" if path_entry?(tombstone_path(phase_id))
      end
    end

    def begin_dispatch!(phase_id:, review_round:, model_id:, contract_digest:, maximum_calls:, maximum_dollars:, deadline:)
      with_lock(phase_id) do
        state = load_open(phase_id)
        require_round_ready(state, review_round, model_id, contract_digest, maximum_calls, maximum_dollars)
        raise AdapterError, "deadline is invalid" unless deadline.is_a?(Integer) && deadline > Time.now.to_i
        state["dispatch_nonce"] = SecureRandom.hex(32)
        state["absolute_deadline"] = deadline
        state["current_transition"] = "dispatch_pending"
        replace(state_path(phase_id), state)
        state
      end
    end

    def validate_round!(phase_id:, review_round:, model_id:, contract_digest:, maximum_calls:, maximum_dollars:)
      with_lock(phase_id) do
        state = load_open(phase_id)
        require_round_ready(state, review_round, model_id, contract_digest, maximum_calls, maximum_dollars)
        state
      end
    end

    def prelaunch_terminal!(phase_id:, review_round:, model_id:, contract_digest:, maximum_calls:, maximum_dollars:, outcome_digest:)
      with_lock(phase_id) do
        state = load_open(phase_id)
        require_configuration(state, model_id, contract_digest, maximum_calls, maximum_dollars)
        raise AdapterError, "direct mode is closed" unless state["direct_mode"] == "open"
        raise AdapterError, "another transition is active" unless state["current_transition"] == "idle"
        raise AdapterError, "review round is not next" unless state["next_round"] == review_round
        validate_digest(outcome_digest, "outcome digest")
        finish_round(state, outcome_digest)
        replace(state_path(phase_id), state)
        state
      end
    end

    def record_launch_attempt!(phase_id:, nonce:)
      with_lock(phase_id) do
        state = load_active(phase_id, nonce, "dispatch_pending")
        raise AdapterError, "maximum calls exhausted" if state["launch_attempts"] >= state["maximum_calls"]
        available = BigDecimal(state["maximum_dollars"]) - BigDecimal(state["settled_dollars"])
        raise AdapterError, "dollar budget exhausted" unless available.positive?
        state["launch_attempts"] += 1
        state["reserved_dollars"] = decimal_state(available)
        state["provider_launch_state"] = "not-launched"
        state["current_transition"] = "launching"
        replace(state_path(phase_id), state)
        state
      end
    end

    def record_provider_ack!(phase_id:, nonce:, provider_pid:)
      with_lock(phase_id) do
        state = load_active(phase_id, nonce, "launching")
        raise AdapterError, "provider PID is invalid" unless provider_pid.is_a?(Integer) && provider_pid.positive?
        raise AdapterError, "maximum confirmed calls exhausted" if state["confirmed_calls_launched"] >= state["maximum_calls"]
        state["confirmed_calls_launched"] += 1
        state["provider_launch_state"] = "confirmed-launched"
        state["provider_pid"] = provider_pid
        state["current_transition"] = "in_flight"
        replace(state_path(phase_id), state)
        state
      end
    end

    def record_supervision!(phase_id:, nonce:, watchdog_pid:, supervisor_pid:, wrapper_pid:, wrapper_pgid:, wrapper_start_token:, wrapper_command:)
      with_lock(phase_id) do
        state = load_active(phase_id, nonce, "launching")
        [watchdog_pid, supervisor_pid, wrapper_pid, wrapper_pgid].each do |value|
          raise AdapterError, "supervision PID is invalid" unless value.is_a?(Integer) && value.positive?
        end
        raise AdapterError, "wrapper process group mismatch" unless wrapper_pid == wrapper_pgid
        token = FourEyesClaudeReviewer2.validate_single_line(wrapper_start_token, "wrapper start token")
        command = Array(wrapper_command).map { |entry| FourEyesClaudeReviewer2.validate_single_line(entry, "wrapper command") }
        raise AdapterError, "wrapper command is empty" if command.empty?
        state["watchdog_pid"] = watchdog_pid
        state["supervisor_pid"] = supervisor_pid
        state["wrapper_pid"] = wrapper_pid
        state["wrapper_pgid"] = wrapper_pgid
        state["wrapper_start_token"] = token
        state["wrapper_command"] = command
        state["wrapper_command_sha256"] = Digest::SHA256.hexdigest(FourEyesClaudeReviewer2.canonical_json(command))
        replace(state_path(phase_id), state)
        state
      end
    end

    def close_direct_mode!(phase_id:, expected_outcome_digest:)
      with_lock(phase_id) do
        state = load_open(phase_id)
        raise AdapterError, "outcome digest mismatch" unless state["last_outcome_digest"] == expected_outcome_digest
        state["direct_mode"] = "closed"
        replace(state_path(phase_id), state)
        state
      end
    end

    def complete_round!(phase_id:, nonce:, outcome_digest:, cost:, trusted_session:)
      with_lock(phase_id) do
        state = load_active(phase_id, nonce, "in_flight")
        validate_digest(outcome_digest, "outcome digest")
        amount = cost.is_a?(BigDecimal) ? cost : BigDecimal(cost.to_s)
        reservation = BigDecimal(state["reserved_dollars"])
        raise AdapterError, "cost exceeds reservation" if amount.negative? || amount > reservation
        state["settled_dollars"] = decimal_state(BigDecimal(state["settled_dollars"]) + amount)
        state["reserved_dollars"] = "0.0"
        state["session_established"] = true if trusted_session
        finish_round(state, outcome_digest)
        replace(state_path(phase_id), state)
        state
      end
    end

    def terminal_round!(phase_id:, nonce:, outcome_digest:, launched_uncertain:)
      with_lock(phase_id) do
        state = load_open(phase_id)
        raise AdapterError, "dispatch nonce mismatch" unless state["dispatch_nonce"] == nonce
        validate_digest(outcome_digest, "outcome digest")
        if state["provider_launch_state"] == "confirmed-launched"
          state["direct_mode"] = "closed"
        elsif launched_uncertain
          state["provider_launch_state"] = "possibly-launched"
          state["direct_mode"] = "closed"
        else
          state["reserved_dollars"] = "0.0"
        end
        finish_round(state, outcome_digest)
        replace(state_path(phase_id), state)
        state
      end
    end

    def close!(phase_id:, close_result_digest:)
      with_lock(phase_id) do
        if path_entry?(tombstone_path(phase_id))
          tombstone = load_record(tombstone_path(phase_id), "phase tombstone")
          unless tombstone["phase_id"] == phase_id && tombstone["close_result_digest"] == close_result_digest
            raise AdapterError, "closed phase identity mismatch"
          end
          return tombstone
        end
        state = load_open(phase_id)
        raise AdapterError, "cannot close active transition" unless state["current_transition"] == "idle"
        validate_digest(close_result_digest, "close result digest")
        tombstone = {
          "close_result_digest" => close_result_digest,
          "closed" => true,
          "contract_digest" => state.fetch("contract_digest"),
          "final_round" => state.fetch("next_round") - 1,
          "phase_id" => phase_id,
          "version" => 1
        }
        write_new(tombstone_path(phase_id), tombstone)
        File.unlink(state_path(phase_id))
        fsync_directory(File.dirname(state_path(phase_id)))
        tombstone
      end
    end

    def load(phase_id)
      with_lock(phase_id) { load_open(phase_id) }
    end

    private

    def finish_round(state, outcome_digest)
      state["last_outcome_digest"] = outcome_digest
      state["next_round"] += 1
      state["current_transition"] = "idle"
      state["dispatch_nonce"] = nil
      state["absolute_deadline"] = nil
      ACTIVE_PROCESS_KEYS.each { |key| state.delete(key) }
    end

    def load_active(phase_id, nonce, transition)
      state = load_open(phase_id)
      raise AdapterError, "dispatch nonce mismatch" unless state["dispatch_nonce"] == nonce
      raise AdapterError, "transition mismatch" unless state["current_transition"] == transition
      state
    end

    def require_configuration(state, model_id, contract_digest, maximum_calls, maximum_dollars)
      expected = [model_id, contract_digest, maximum_calls, decimal_state(maximum_dollars)]
      actual = [state["model_id"], state["contract_digest"], state["maximum_calls"], state["maximum_dollars"]]
      raise AdapterError, "phase configuration mismatch" unless actual == expected
    end

    def require_round_ready(state, review_round, model_id, contract_digest, maximum_calls, maximum_dollars)
      require_configuration(state, model_id, contract_digest, maximum_calls, maximum_dollars)
      raise AdapterError, "direct mode is closed" unless state["direct_mode"] == "open"
      raise AdapterError, "another transition is active" unless state["current_transition"] == "idle"
      raise AdapterError, "review round is not next" unless state["next_round"] == review_round
    end

    def validate_identity_arguments(phase_id, model_id, contract_digest, maximum_calls, maximum_dollars)
      FourEyesClaudeReviewer2.validate_text(phase_id, "phase ID", 256, empty: false)
      FourEyesClaudeReviewer2.validate_text(model_id, "model ID", 256, empty: false)
      validate_digest(contract_digest, "contract digest")
      raise ArgumentError, "maximum calls is invalid" unless maximum_calls.is_a?(Integer) && maximum_calls.between?(1, 20)
      amount = maximum_dollars.is_a?(BigDecimal) ? maximum_dollars : BigDecimal(maximum_dollars.to_s)
      raise ArgumentError, "maximum dollars is invalid" unless amount.positive? && amount < 1000
    end

    def validate_digest(value, label)
      raise ArgumentError, "#{label} is invalid" unless String(value).match?(SHA256_PATTERN)
    end

    def phase_digest(phase_id)
      Digest::SHA256.hexdigest(FourEyesClaudeReviewer2.validate_text(phase_id, "phase ID", 256, empty: false))
    end

    def load_open(phase_id)
      raise AdapterError, "phase is closed" if path_entry?(tombstone_path(phase_id))
      path = state_path(phase_id)
      raise AdapterError, "phase state is missing" unless path_entry?(path)
      state = load_record(path, "phase state")
      raise AdapterError, "phase identity mismatch" unless state["phase_id"] == phase_id
      state
    end

    def with_lock(phase_id)
      path = File.join(root, "locks", "#{phase_digest(phase_id)}.lock")
      File.open(path, File::RDWR | File::CREAT, 0o600) do |file|
        file.flock(File::LOCK_EX)
        yield
      ensure
        file.flock(File::LOCK_UN) rescue nil
      end
    end

    def load_record(path, label)
      stat = File.lstat(path)
      unless stat.file? && !stat.symlink? && stat.nlink == 1 && stat.uid == Process.uid && (stat.mode & 0o777) == 0o600
        raise AdapterError, "#{label} is unsafe"
      end
      raise AdapterError, "#{label} exceeds limit" if stat.size > STATE_LIMIT
      bytes = FourEyesClaudeReviewer2.read_bounded_file(path, STATE_LIMIT, label)
      FourEyesClaudeReviewer2.plain_json_value(FourEyesClaudeReviewer2.parse_json(bytes))
    rescue Errno::ENOENT
      raise AdapterError, "#{label} is missing"
    end

    def write_new(path, value)
      raise AdapterError, "state record already exists" if path_entry?(path)
      bytes = FourEyesClaudeReviewer2.canonical_json(value)
      File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(bytes)
        file.flush
        file.fsync
      end
      fsync_directory(File.dirname(path))
      verify_readback(path, value)
    end

    def replace(path, value)
      bytes = FourEyesClaudeReviewer2.canonical_json(value)
      temporary = "#{path}.tmp-#{SecureRandom.hex(16)}"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(bytes)
        file.flush
        file.fsync
      end
      File.rename(temporary, path)
      fsync_directory(File.dirname(path))
      verify_readback(path, value)
    ensure
      File.unlink(temporary) if temporary && File.exist?(temporary)
    end

    def verify_readback(path, value)
      stat = File.lstat(path)
      unless stat.file? && !stat.symlink? && stat.nlink == 1 && stat.uid == Process.uid && (stat.mode & 0o777) == 0o600
        raise AdapterError, "state record is unsafe"
      end
      parsed = FourEyesClaudeReviewer2.parse_json(FourEyesClaudeReviewer2.read_bounded_file(path, STATE_LIMIT, "state record"))
      raise AdapterError, "state readback mismatch" unless parsed == value
    end

    def ensure_directory(path)
      if path_entry?(path)
        stat = File.lstat(path)
        unless stat.directory? && !stat.symlink? && stat.uid == Process.uid && (stat.mode & 0o777) == 0o700
          raise AdapterError, "state directory is unsafe"
        end
      else
        Dir.mkdir(path, 0o700)
        fsync_directory(File.dirname(path))
      end
    end

    def decimal_state(value)
      amount = value.is_a?(BigDecimal) ? value : BigDecimal(value.to_s)
      amount.to_s("F")
    end

    def fsync_directory(path)
      File.open(path, File::RDONLY) { |directory| directory.fsync }
    end

    def path_entry?(path)
      File.exist?(path) || File.symlink?(path)
    end
  end

  module_function

  def parse_json(bytes)
    JSON.parse(bytes, object_class: DuplicateRejectingHash, decimal_class: BigDecimal)
  end

  def encode_packet(records)
    unless records.is_a?(Array) && records.map(&:first) == PACKET_RECORD_LABELS
      raise AdapterError, "packet record order mismatch"
    end

    body = records.map do |label, value|
      bytes = String(value).b
      "#{label}\0#{bytes.bytesize}\0".b + bytes
    end.join
    PACKET_MAGIC + body
  end

  def decode_packet(packet)
    bytes = String(packet).b
    raise AdapterError, "packet magic mismatch" unless bytes.start_with?(PACKET_MAGIC)

    offset = PACKET_MAGIC.bytesize
    records = PACKET_RECORD_LABELS.map do |expected_label|
      label, offset = read_packet_token(bytes, offset)
      raise AdapterError, "packet record order mismatch" unless label == expected_label

      length_text, offset = read_packet_token(bytes, offset)
      unless length_text.match?(/\A(?:0|[1-9][0-9]*)\z/)
        raise AdapterError, "packet record length is not canonical"
      end
      length = Integer(length_text, 10)
      raise AdapterError, "packet record truncated" if offset + length > bytes.bytesize

      value = bytes.byteslice(offset, length)
      offset += length
      [label, value]
    end
    raise AdapterError, "packet has trailing bytes" unless offset == bytes.bytesize

    records
  end

  def read_packet_token(bytes, offset)
    finish = bytes.index("\0", offset)
    raise AdapterError, "packet token is truncated" unless finish

    [bytes.byteslice(offset, finish - offset), finish + 1]
  end
  private_class_method :read_packet_token

  def parse_maximum_calls(text)
    value = String(text)
    raise ArgumentError, "maximum calls must be 1 through 20" unless value.match?(MAXIMUM_CALLS_PATTERN)

    Integer(value, 10)
  end

  def parse_maximum_dollars(text)
    value = String(text)
    unless value.match?(MAXIMUM_DOLLARS_PATTERN)
      raise ArgumentError, "maximum dollars must be a canonical decimal below 1000"
    end

    amount = BigDecimal(value)
    unless amount.positive? && amount < BigDecimal("1000")
      raise ArgumentError, "maximum dollars must be greater than zero and below 1000"
    end

    amount
  end

  def canonical_decimal(amount)
    text = amount.to_s("F")
    text.sub!(/0+\z/, "")
    text.sub!(/\.\z/, "")
    text
  end

  def build_claude_argv(claude_executable:, schema_json:, model_id:, mcp_config_path:, settings_path:, remaining_budget:, session_id:, resume:)
    arguments = [
      claude_executable,
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
      mcp_config_path,
      "--settings",
      settings_path,
      "--no-chrome",
      "--permission-mode",
      "dontAsk",
      "--system-prompt",
      SYSTEM_PROMPT,
      "--max-budget-usd",
      canonical_decimal(remaining_budget)
    ]
    arguments.concat(resume ? ["--resume", session_id] : ["--session-id", session_id])
  end

  def contract_manifest(candidate_revision:, claude_executable:, model_id:, checker_path:, schema_path:)
    validate_git_sha(candidate_revision, "candidate revision")
    validate_model_id(model_id)
    executable = validate_executable(claude_executable)
    version_output, version_error, version_status = Open3.capture3(executable, "--version")
    raise AdapterError, "cannot read Claude version" unless version_status.success? && version_error.empty?
    help_output, _help_error, help_status = Open3.capture3(executable, "--help")
    raise AdapterError, "cannot read Claude help" unless help_status.success?
    {
      "adapter_sha256" => Digest::SHA256.file(__FILE__).hexdigest,
      "argv_template_sha256" => Digest::SHA256.hexdigest(canonical_json(FIXED_CLAUDE_FLAGS)),
      "candidate_revision" => candidate_revision,
      "canonical_diff_arguments" => CANONICAL_DIFF_ARGUMENTS,
      "checker_sha256" => Digest::SHA256.file(checker_path).hexdigest,
      "claude_executable_realpath" => executable,
      "claude_executable_sha256" => Digest::SHA256.file(executable).hexdigest,
      "claude_help_sha256" => Digest::SHA256.hexdigest(help_output.b),
      "claude_version" => validate_single_line(version_output, "Claude version"),
      "fixed_flags" => FIXED_CLAUDE_FLAGS,
      "limits" => contract_limits,
      "model_id" => model_id,
      "packet_magic_sha256" => Digest::SHA256.hexdigest(PACKET_MAGIC),
      "packet_record_labels" => PACKET_RECORD_LABELS,
      "process_contract" => {
        "allowed_environment_keys" => %w[ANTHROPIC_API_KEY HOME LANG LC_ALL TMPDIR],
        "control_commands" => %w[TERM KILL RELEASE],
        "control_record" => "64-lowercase-hex-nonce NUL command LF",
        "empty_mcp_settings_sha256" => Digest::SHA256.hexdigest("{}\n"),
        "ipc_limit" => IPC_LIMIT,
        "termination_grace_seconds" => TERMINATION_GRACE
      },
      "review_stages" => REVIEW_STAGES,
      "schema_sha256" => Digest::SHA256.file(schema_path).hexdigest,
      "system_prompt" => SYSTEM_PROMPT,
      "system_prompt_sha256" => Digest::SHA256.hexdigest(SYSTEM_PROMPT),
      "version" => 1
    }
  end

  def contract_limits
    {
      "artifact" => ARTIFACT_LIMIT,
      "contract_manifest" => CONTRACT_MANIFEST_LIMIT,
      "identity_json" => IDENTITY_LIMIT,
      "manifest" => MANIFEST_LIMIT,
      "maximum_model_id" => 256,
      "maximum_phase_id" => 256,
      "packet" => PACKET_LIMIT,
      "result" => RESULT_LIMIT,
      "schema" => SCHEMA_LIMIT,
      "state" => STATE_LIMIT,
      "stderr" => STDERR_LIMIT,
      "stdout" => STDOUT_LIMIT,
      "text_records" => TEXT_LIMITS
    }
  end

  def contract_validity_keys(manifest)
    value = plain_json_value(manifest)
    raise AdapterError, "contract manifest must be an object" unless value.is_a?(Hash)
    value.reject { |key, _entry| key == "candidate_revision" }
  end

  def parse_provider_envelope(bytes, expected_session_id:, expected_identity:, reservation:)
    value = String(bytes)
    raise AdapterError, "provider stdout exceeds limit" if value.bytesize > STDOUT_LIMIT
    envelope = parse_json(value)
    raise AdapterError, "provider envelope must be an object" unless envelope.is_a?(Hash)
    raise AdapterError, "provider type mismatch" unless envelope["type"] == "result"
    raise AdapterError, "provider subtype mismatch" unless envelope["subtype"] == "success"
    raise AdapterError, "provider returned an error" unless envelope["is_error"] == false
    raise AdapterError, "provider session mismatch" unless envelope["session_id"] == expected_session_id

    cost = decimal_number(envelope["total_cost_usd"])
    raise AdapterError, "provider cost is invalid" unless cost.finite? && cost >= 0
    cost = round_cost_up(cost)
    raise AdapterError, "provider cost exceeds reservation" if cost > reservation

    structured = envelope["structured_output"]
    validate_structured_result!(structured, expected_identity: expected_identity)
    [plain_json_value(structured), cost]
  end

  def validate_structured_result!(result, expected_identity:)
    raise AdapterError, "structured output must be an object" unless result.is_a?(Hash)
    status = result["Review status"]
    case status
    when "completed"
      required = ["Review status", "Verdict", "Blocking findings", "Non-blocking findings", "Questions", "Required changes", "Artifact identity"]
      require_exact_keys(result, required)
      raise AdapterError, "completed verdict is invalid" unless ["Approve", "Approve with nits", "Block"].include?(result["Verdict"])
      ["Blocking findings", "Non-blocking findings", "Questions", "Required changes"].each do |field|
        validate_review_text_list(result[field], field)
      end
      require_identity(result["Artifact identity"], expected_identity)
    when "error", "timeout", "could-not-review"
      require_exact_keys(result, ["Review status", "Verdict", "Reason", "Artifact identity"])
      raise AdapterError, "terminal verdict must not be issued" unless result["Verdict"] == "not issued"
      reason = result["Reason"]
      unless reason.is_a?(String) && reason.bytesize.between?(1, 1024) && !reason.include?("\0") && !reason.match?(/[\r\n]/)
        raise AdapterError, "terminal reason is invalid"
      end
      require_identity(result["Artifact identity"], expected_identity) unless result["Artifact identity"].nil?
    else
      raise AdapterError, "review status is invalid"
    end
    true
  end

  def decimal_number(value)
    case value
    when BigDecimal then value
    when Integer then BigDecimal(value.to_s)
    else raise AdapterError, "provider cost must be a JSON number"
    end
  end
  private_class_method :decimal_number

  def round_cost_up(value)
    BigDecimal((value * 1_000_000).ceil.to_s) / 1_000_000
  end
  private_class_method :round_cost_up

  def require_exact_keys(value, expected)
    raise AdapterError, "structured output keys mismatch" unless value.keys.sort == expected.sort
  end
  private_class_method :require_exact_keys

  def validate_review_text_list(value, label)
    unless value.is_a?(Array) && value.length <= 256 && value.all? { |entry| entry.is_a?(String) && entry.bytesize.between?(1, 32_768) && !entry.include?("\0") }
      raise AdapterError, "#{label} is invalid"
    end
  end
  private_class_method :validate_review_text_list

  def require_identity(actual, expected)
    unless actual.is_a?(Hash) && canonical_json(actual) == canonical_json(expected)
      raise AdapterError, "structured artifact identity mismatch"
    end
  end
  private_class_method :require_identity

  def plain_json_value(value)
    case value
    when Hash
      value.each_with_object({}) { |(key, entry), output| output[key] = plain_json_value(entry) }
    when Array
      value.map { |entry| plain_json_value(entry) }
    else
      value
    end
  end

  def canonical_json(value)
    JSON.generate(sort_json(value))
  end

  def sort_json(value)
    case value
    when Hash
      value.keys.sort.each_with_object({}) { |key, sorted| sorted[key] = sort_json(value.fetch(key)) }
    when Array
      value.map { |entry| sort_json(entry) }
    else
      value
    end
  end
  private_class_method :sort_json

  def run_git(repo, *arguments)
    environment = {"LC_ALL" => "C", "GIT_ATTR_NOSYSTEM" => "1"}
    output, _error, status = Open3.capture3(environment, "git", "-C", repo, *arguments)
    raise AdapterError, "git command failed" unless status.success?

    output.b
  end

  def canonical_diff(repo, *arguments)
    run_git(repo, *CANONICAL_DIFF_ARGUMENTS, *arguments)
  end

  def repository_fingerprint(repo)
    head = run_git(repo, "rev-parse", "--verify", "HEAD^{commit}").strip
    staged = Digest::SHA256.hexdigest(canonical_diff(repo, "--cached", head, "--", "."))
    unstaged = Digest::SHA256.hexdigest(canonical_diff(repo, "--", "."))
    names = run_git(repo, "ls-files", "--others", "--exclude-standard", "-z", "--", ".").split("\0", -1)
    names.pop if names.last == ""
    manifest = names.sort.map do |relative|
      path = File.join(repo, relative)
      digest = if File.symlink?(path)
                 Digest::SHA256.hexdigest(File.readlink(path))
               elsif File.file?(path)
                 Digest::SHA256.file(path).hexdigest
               else
                 raise AdapterError, "unsupported untracked path"
               end
      "#{digest}\0#{relative}\0".b
    end.join
    {
      "head" => head,
      "staged_sha256" => staged,
      "unstaged_sha256" => unstaged,
      "untracked_sha256" => Digest::SHA256.hexdigest(manifest)
    }
  end

  def changed_file_manifest(repo, artifact_kind:, base: nil, reviewed_head: nil)
    entries = case artifact_kind
              when "manual-uncommitted"
                manual_manifest_entries(repo)
              when "manual-committed", "pr"
                raise ArgumentError, "base and reviewed head are required" unless base && reviewed_head
                committed_manifest_entries(repo, base, reviewed_head)
              when "plan"
                []
              else
                raise ArgumentError, "unsupported artifact kind"
              end
    canonical_json(entries.sort_by { |entry| entry.fetch("path").b })
  end

  def build_uncommitted_artifact(repo)
    head = run_git(repo, "rev-parse", "--verify", "HEAD^{commit}").strip
    staged = canonical_diff(repo, "--cached", head, "--", ".")
    unstaged = canonical_diff(repo, "--", ".")
    untracked = untracked_entries(repo)
    manifest = untracked.map { |entry| "#{entry.fetch(:digest)}\0#{entry.fetch(:path)}\0".b }.join
    body = manual_record("staged-diff", staged)
    body << manual_record("unstaged-diff", unstaged)
    body << manual_record("untracked-manifest", manifest)
    untracked.each { |entry| body << manual_record("untracked-content", entry.fetch(:content)) }
    body
  end

  def manual_record(label, value)
    bytes = String(value).b
    "#{label}\0#{bytes.bytesize}\0".b + bytes
  end
  private_class_method :manual_record

  def manual_manifest_entries(repo)
    reject_renames_and_copies!(repo, "--cached", "HEAD", "--", ".")
    reject_renames_and_copies!(repo, "--", ".")
    raise AdapterError, "unmerged entries are unsupported" unless run_git(repo, "ls-files", "--unmerged", "-z", "--", ".").empty?

    by_path = {}
    parse_name_status(run_git(repo, "diff", "--name-status", "-z", "--no-renames", "--cached", "HEAD", "--", ".")).each do |status, path|
      by_path[path] = empty_manifest_entry(path).merge("staged_status" => status)
    end
    parse_name_status(run_git(repo, "diff", "--name-status", "-z", "--no-renames", "--", ".")).each do |status, path|
      entry = by_path[path] ||= empty_manifest_entry(path)
      entry["unstaged_status"] = status
    end
    untracked_entries(repo).each do |untracked|
      path = untracked.fetch(:path)
      entry = by_path[path] ||= empty_manifest_entry(path)
      entry["untracked"] = true
    end
    reject_special_index_entries!(repo, by_path.keys)
    reject_special_tree_entries!(repo, "HEAD", by_path.keys)
    reject_special_worktree_entries!(repo, by_path.keys)
    by_path.values.sort_by { |entry| entry.fetch("path").b }
  end
  private_class_method :manual_manifest_entries

  def committed_manifest_entries(repo, base, reviewed_head)
    validate_git_sha(base, "base")
    validate_git_sha(reviewed_head, "reviewed head")
    reject_renames_and_copies!(repo, base, reviewed_head, "--", ".")
    entries = parse_name_status(run_git(repo, "diff", "--name-status", "-z", "--no-renames", base, reviewed_head, "--", ".")).map do |status, path|
      empty_manifest_entry(path).merge("committed_status" => status)
    end
    paths = entries.map { |entry| entry.fetch("path") }
    reject_special_tree_entries!(repo, base, paths)
    reject_special_tree_entries!(repo, reviewed_head, paths)
    entries.sort_by { |entry| entry.fetch("path").b }
  end
  private_class_method :committed_manifest_entries

  def parse_name_status(bytes)
    tokens = bytes.split("\0", -1)
    tokens.pop if tokens.last == ""
    raise AdapterError, "malformed Git name-status output" unless tokens.length.even?
    tokens.each_slice(2).map do |status, path|
      raise AdapterError, "unsupported Git status" unless %w[A M D T].include?(status)
      [status, validate_manifest_path(path)]
    end
  end
  private_class_method :parse_name_status

  def empty_manifest_entry(path)
    {
      "committed_status" => "none",
      "path" => path,
      "staged_status" => "none",
      "unstaged_status" => "none",
      "untracked" => false
    }
  end
  private_class_method :empty_manifest_entry

  def validate_manifest_path(path)
    text = String(path).dup.force_encoding(Encoding::UTF_8)
    raise AdapterError, "manifest path is invalid UTF-8" unless text.valid_encoding?
    raise AdapterError, "manifest path contains NUL" if text.include?("\0")
    pathname = Pathname.new(text)
    if text.empty? || pathname.absolute? || text == "." || pathname.each_filename.any? { |part| part == ".." }
      raise AdapterError, "unsafe manifest path"
    end
    text.tr("\\", "/")
  end
  private_class_method :validate_manifest_path

  def reject_renames_and_copies!(repo, *arguments)
    tokens = run_git(
      repo, "diff", "--name-status", "-z", "--find-renames", "--find-copies-harder", *arguments
    ).split("\0", -1)
    tokens.pop if tokens.last == ""
    index = 0
    while index < tokens.length
      status = tokens.fetch(index)
      index += 1
      if status.start_with?("R", "C")
        raise AdapterError, "renames and copies are unsupported"
      end
      raise AdapterError, "malformed Git name-status output" if index >= tokens.length
      validate_manifest_path(tokens.fetch(index))
      index += 1
    end
  end
  private_class_method :reject_renames_and_copies!

  def reject_special_index_entries!(repo, paths)
    return if paths.empty?

    records = run_git(repo, "ls-files", "--stage", "-z", "--", *paths).split("\0", -1)
    records.pop if records.last == ""
    records.each do |record|
      match = record.match(/\A([0-9]{6}) [0-9a-f]+ ([0-3])\t(.*)\z/m)
      raise AdapterError, "malformed Git index entry" unless match
      raise AdapterError, "unmerged entries are unsupported" unless match[2] == "0"
      reject_special_git_mode!(match[1])
      validate_manifest_path(match[3])
    end
  end
  private_class_method :reject_special_index_entries!

  def reject_special_tree_entries!(repo, treeish, paths)
    return if paths.empty?

    records = run_git(repo, "ls-tree", "-r", "-z", treeish, "--", *paths).split("\0", -1)
    records.pop if records.last == ""
    records.each do |record|
      match = record.match(/\A([0-9]{6}) (?:blob|commit|tree) [0-9a-f]+\t(.*)\z/m)
      raise AdapterError, "malformed Git tree entry" unless match
      reject_special_git_mode!(match[1])
      validate_manifest_path(match[2])
    end
  end
  private_class_method :reject_special_tree_entries!

  def reject_special_worktree_entries!(repo, paths)
    paths.each do |relative|
      absolute = File.join(repo, relative)
      next unless File.exist?(absolute) || File.symlink?(absolute)

      stat = File.lstat(absolute)
      raise AdapterError, "changed paths must not be symlinks" if stat.symlink?
    end
  end
  private_class_method :reject_special_worktree_entries!

  def reject_special_git_mode!(mode)
    raise AdapterError, "changed paths must not be symlinks" if mode == "120000"
    raise AdapterError, "submodules are unsupported" if mode == "160000"
  end
  private_class_method :reject_special_git_mode!

  def untracked_entries(repo)
    names = run_git(repo, "ls-files", "--others", "--exclude-standard", "-z", "--", ".").split("\0", -1)
    names.pop if names.last == ""
    names.map { |path| validate_manifest_path(path) }.sort_by(&:b).map do |relative|
      absolute = File.join(repo, relative)
      stat = File.lstat(absolute)
      raise AdapterError, "untracked path must be a regular non-symlink file" unless stat.file? && !stat.symlink?
      raise AdapterError, "untracked path has multiple links" unless stat.nlink == 1
      content = File.binread(absolute)
      {path: relative, digest: Digest::SHA256.hexdigest(content), content: content}
    end
  rescue Errno::ENOENT
    raise AdapterError, "untracked path changed during capture"
  end
  private_class_method :untracked_entries

  def run_cli(arguments, stdout: $stdout)
    operation = arguments.shift
    case operation
    when "pack"
      stdout.puts(pack(parse_pack_options(arguments)))
    when "review"
      stdout.puts(review(parse_review_options(arguments)))
    when "close"
      stdout.puts(close(parse_close_options(arguments)))
    when "__watchdog"
      internal_watchdog(arguments)
    when "__supervisor"
      internal_supervisor(arguments)
    when "__wrapper"
      internal_wrapper(arguments)
    else
      raise ArgumentError, "operation must be pack, review, or close"
    end
  end

  def parse_close_options(arguments)
    options = {}
    parser = OptionParser.new do |opts|
      opts.on("--repo PATH") { |value| options[:repo] = value }
      opts.on("--evidence-root PATH") { |value| options[:evidence_root] = value }
      opts.on("--state-root PATH") { |value| options[:state_root] = value }
      opts.on("--phase-id ID") { |value| options[:phase_id] = value }
      opts.on("--close-result-sha256 SHA") { |value| options[:close_result_sha256] = value }
    end
    parser.parse!(arguments)
    raise ArgumentError, "unexpected arguments" unless arguments.empty?
    required = %i[repo evidence_root state_root phase_id close_result_sha256]
    missing = required.reject { |key| options.key?(key) }
    raise ArgumentError, "missing option: #{missing.first}" unless missing.empty?
    options
  end

  def parse_review_options(arguments)
    options = {}
    parser = OptionParser.new do |opts|
      opts.on("--repo PATH") { |value| options[:repo] = value }
      opts.on("--evidence-root PATH") { |value| options[:evidence_root] = value }
      opts.on("--state-root PATH") { |value| options[:state_root] = value }
      opts.on("--phase-id ID") { |value| options[:phase_id] = value }
      opts.on("--review-round N") { |value| options[:review_round] = value }
      opts.on("--expected-packet-sha256 SHA") { |value| options[:expected_packet_sha256] = value }
      opts.on("--packet PATH") { |value| options[:packet] = value }
      opts.on("--schema PATH") { |value| options[:schema] = value }
      opts.on("--output PATH") { |value| options[:output] = value }
      opts.on("--contract-manifest PATH") { |value| options[:contract_manifest] = value }
      opts.on("--contract-sha256 SHA") { |value| options[:contract_sha256] = value }
      opts.on("--claude-executable PATH") { |value| options[:claude_executable] = value }
      opts.on("--model-id ID") { |value| options[:model_id] = value }
      opts.on("--maximum-calls N") { |value| options[:maximum_calls] = value }
      opts.on("--maximum-dollars USD") { |value| options[:maximum_dollars] = value }
      opts.on("--deadline-seconds N") { |value| options[:deadline_seconds] = value }
    end
    parser.parse!(arguments)
    raise ArgumentError, "unexpected arguments" unless arguments.empty?
    required = %i[repo evidence_root state_root phase_id review_round expected_packet_sha256 packet schema output contract_manifest contract_sha256 claude_executable model_id maximum_calls maximum_dollars deadline_seconds]
    missing = required.reject { |key| options.key?(key) }
    raise ArgumentError, "missing option: #{missing.first}" unless missing.empty?
    options
  end

  def parse_pack_options(arguments)
    options = {prior_reviewed_head: "none"}
    parser = OptionParser.new do |opts|
      opts.on("--repo PATH") { |value| options[:repo] = value }
      opts.on("--evidence-root PATH") { |value| options[:evidence_root] = value }
      opts.on("--state-root PATH") { |value| options[:state_root] = value }
      opts.on("--phase-id ID") { |value| options[:phase_id] = value }
      opts.on("--review-round N") { |value| options[:review_round] = value }
      opts.on("--review-stage STAGE") { |value| options[:review_stage] = value }
      opts.on("--workflow-revision SHA") { |value| options[:workflow_revision] = value }
      opts.on("--artifact-kind KIND") { |value| options[:artifact_kind] = value }
      opts.on("--source-plan PATH") { |value| options[:source_plan] = value }
      opts.on("--base SHA") { |value| options[:base] = value }
      opts.on("--reviewed-head SHA") { |value| options[:reviewed_head] = value }
      opts.on("--prior-reviewed-head SHA") { |value| options[:prior_reviewed_head] = value }
      opts.on("--reviewer-instructions PATH") { |value| options[:reviewer_instructions] = value }
      opts.on("--verification-evidence PATH") { |value| options[:verification_evidence] = value }
      opts.on("--neutral-prior-summary PATH") { |value| options[:neutral_prior_summary] = value }
      opts.on("--own-prior-findings PATH") { |value| options[:own_prior_findings] = value }
      opts.on("--packet PATH") { |value| options[:packet] = value }
    end
    parser.parse!(arguments)
    raise ArgumentError, "unexpected arguments" unless arguments.empty?

    required = %i[repo evidence_root state_root phase_id review_round review_stage workflow_revision artifact_kind reviewer_instructions verification_evidence neutral_prior_summary own_prior_findings packet]
    missing = required.reject { |key| options.key?(key) }
    raise ArgumentError, "missing option: #{missing.first}" unless missing.empty?

    case options.fetch(:artifact_kind)
    when "plan"
      raise ArgumentError, "missing option: source_plan" unless options.key?(:source_plan)
      raise ArgumentError, "base and reviewed head do not apply to plan" if options.key?(:base) || options.key?(:reviewed_head)
    when "manual-uncommitted"
      raise ArgumentError, "source plan does not apply to manual-uncommitted" if options.key?(:source_plan)
      raise ArgumentError, "base and reviewed head do not apply to manual-uncommitted" if options.key?(:base) || options.key?(:reviewed_head)
    when "manual-committed", "pr"
      raise ArgumentError, "missing option: base" unless options.key?(:base)
      raise ArgumentError, "missing option: reviewed_head" unless options.key?(:reviewed_head)
      raise ArgumentError, "source plan does not apply to committed artifacts" if options.key?(:source_plan)
    else
      raise ArgumentError, "unsupported artifact kind"
    end

    options
  end

  def pack(options)
    repo = validate_repo(options.fetch(:repo))
    evidence_root = validate_private_root(options.fetch(:evidence_root), repo, "evidence root")
    state_root = validate_private_root(options.fetch(:state_root), repo, "state root")
    phase_id = validate_text(options.fetch(:phase_id), "phase ID", 256, empty: false)
    store = StateStore.new(state_root)
    store.reject_closed!(phase_id)
    claim_evidence_root!(evidence_root, phase_id)
    review_round = parse_positive_integer(options.fetch(:review_round), "review round")
    review_stage = options.fetch(:review_stage)
    raise ArgumentError, "unsupported review stage" unless REVIEW_STAGES.include?(review_stage)
    workflow_revision = validate_git_sha(options.fetch(:workflow_revision), "workflow revision")
    prior_head = options.fetch(:prior_reviewed_head)
    validate_git_sha(prior_head, "prior reviewed head") unless prior_head == "none"
    artifact_kind = options.fetch(:artifact_kind)
    run_git(repo, "cat-file", "-e", "#{workflow_revision}^{commit}")

    input_records = {
      "reviewer-instructions" => read_private_input(options.fetch(:reviewer_instructions), evidence_root, TEXT_LIMITS.fetch("reviewer-instructions"), empty: false),
      "verification-evidence" => read_private_input(options.fetch(:verification_evidence), evidence_root, TEXT_LIMITS.fetch("verification-evidence"), empty: true),
      "neutral-prior-summary" => read_private_input(options.fetch(:neutral_prior_summary), evidence_root, TEXT_LIMITS.fetch("neutral-prior-summary"), empty: true),
      "own-prior-findings" => read_private_input(options.fetch(:own_prior_findings), evidence_root, TEXT_LIMITS.fetch("own-prior-findings"), empty: true)
    }
    fingerprint = repository_fingerprint(repo)
    head = fingerprint.fetch("head")
    common_identity = {
      "artifact_kind" => artifact_kind,
      "prior_reviewed_head" => prior_head,
      "review_round" => review_round,
      "review_stage" => review_stage,
      "workflow_revision" => workflow_revision
    }
    source_plan = nil
    artifact, manifest, identity = case artifact_kind
                                   when "plan"
                                     source_plan = validate_source_plan(options.fetch(:source_plan), repo)
                                     bytes = read_bounded_file(source_plan, ARTIFACT_LIMIT, "plan")
                                     value = common_identity.merge(
                                       "artifact_bytes" => bytes.bytesize,
                                       "artifact_sha256" => Digest::SHA256.hexdigest(bytes),
                                       "base" => "none",
                                       "reviewed_head" => "uncommitted at HEAD #{head}"
                                     )
                                     [bytes, "[]", value]
                                   when "manual-uncommitted"
                                     bytes = build_uncommitted_artifact(repo)
                                     value = common_identity.merge(
                                       "artifact_bytes" => bytes.bytesize,
                                       "artifact_sha256" => Digest::SHA256.hexdigest(bytes),
                                       "base" => "none",
                                       "reviewed_head" => "uncommitted at HEAD #{head}",
                                       "staged_sha256" => fingerprint.fetch("staged_sha256"),
                                       "unstaged_sha256" => fingerprint.fetch("unstaged_sha256"),
                                       "untracked_sha256" => fingerprint.fetch("untracked_sha256")
                                     )
                                     [bytes, changed_file_manifest(repo, artifact_kind: artifact_kind), value]
                                   when "manual-committed", "pr"
                                     base = validate_git_sha(options.fetch(:base), "base")
                                     reviewed_head = validate_git_sha(options.fetch(:reviewed_head), "reviewed head")
                                     run_git(repo, "cat-file", "-e", "#{base}^{commit}")
                                     run_git(repo, "cat-file", "-e", "#{reviewed_head}^{commit}")
                                     merge_base = run_git(repo, "merge-base", base, reviewed_head).strip
                                     bytes = canonical_diff(repo, base, reviewed_head, "--", ".")
                                     value = common_identity.merge(
                                       "artifact_bytes" => bytes.bytesize,
                                       "artifact_sha256" => Digest::SHA256.hexdigest(bytes),
                                       "base" => base,
                                       "merge_base" => merge_base,
                                       "reviewed_head" => reviewed_head
                                     )
                                     [bytes, changed_file_manifest(repo, artifact_kind: artifact_kind, base: base, reviewed_head: reviewed_head), value]
                                   end
    raise AdapterError, "artifact exceeds limit" if artifact.bytesize > ARTIFACT_LIMIT
    records = [
      ["packet-version", "1"],
      ["reviewer-slot", "2"],
      ["phase-id", phase_id],
      ["review-round", review_round.to_s],
      ["review-stage", review_stage],
      ["workflow-revision", workflow_revision],
      ["artifact-kind", artifact_kind],
      ["identity-json", canonical_json(identity)],
      ["reviewer-instructions", input_records.fetch("reviewer-instructions")],
      ["changed-file-manifest", manifest],
      ["artifact-bytes", artifact],
      ["verification-evidence", input_records.fetch("verification-evidence")],
      ["neutral-prior-summary", input_records.fetch("neutral-prior-summary")],
      ["own-prior-findings", input_records.fetch("own-prior-findings")]
    ]
    validate_packet_records!(records.to_h, phase_id: phase_id, review_round: review_round)
    packet = encode_packet(records)
    raise AdapterError, "packet exceeds limit" if packet.bytesize > PACKET_LIMIT

    packet_path = validate_new_output(options.fetch(:packet), evidence_root, "packet")
    sidecar_path = validate_new_output("#{packet_path}.sha256", evidence_root, "packet sidecar")
    phase_directory = File.join(state_root, "bindings", Digest::SHA256.hexdigest(phase_id))
    ensure_private_directory(File.join(state_root, "bindings"), state_root)
    ensure_private_directory(phase_directory, File.join(state_root, "bindings"))
    binding_path = File.join(phase_directory, "#{review_round}.json")
    raise AdapterError, "binding already exists" if File.exist?(binding_path) || File.symlink?(binding_path)
    digest = Digest::SHA256.hexdigest(packet)
    binding = {
      "artifact_kind" => artifact_kind,
      "packet_sha256" => digest,
      "phase_id" => phase_id,
      "repository_identity_sha256" => Digest::SHA256.hexdigest(canonical_json(fingerprint)),
      "review_round" => review_round,
      "workflow_revision" => workflow_revision
    }
    if artifact_kind == "plan"
      binding.merge!(
        "source_plan_bytes" => artifact.bytesize,
        "source_plan_realpath" => source_plan,
        "source_plan_sha256" => Digest::SHA256.hexdigest(artifact)
      )
    end
    write_exclusive(packet_path, packet)
    write_exclusive(sidecar_path, "#{digest}\n")
    write_exclusive(binding_path, canonical_json(binding))
    unless File.binread(packet_path) == packet && File.binread(sidecar_path) == "#{digest}\n" && parse_json(File.binread(binding_path)) == binding
      raise AdapterError, "pack readback mismatch"
    end
    digest
  end

  def close(options)
    repo = validate_repo(options.fetch(:repo))
    evidence_root = validate_private_root(options.fetch(:evidence_root), repo, "evidence root")
    state_root = validate_private_root(options.fetch(:state_root), repo, "state root")
    phase_id = validate_text(options.fetch(:phase_id), "phase ID", 256, empty: false)
    close_result_digest = validate_sha256(options.fetch(:close_result_sha256), "close result digest")
    store = StateStore.new(state_root)
    marker_path = File.join(evidence_root, PHASE_MARKER)
    if File.exist?(marker_path) || File.symlink?(marker_path)
      marker = plain_json_value(parse_json(File.binread(validate_private_file(marker_path, evidence_root))))
      expected_marker = {"phase_id" => phase_id, "phase_sha256" => Digest::SHA256.hexdigest(phase_id), "version" => 1}
      raise AdapterError, "evidence root belongs to another phase" unless marker == expected_marker
    elsif !(File.exist?(store.tombstone_path(phase_id)) && Dir.children(evidence_root).empty?)
      raise AdapterError, "evidence root is not bound to phase"
    end

    tombstone = store.close!(phase_id: phase_id, close_result_digest: close_result_digest)
    binding_directory = File.join(state_root, "bindings", Digest::SHA256.hexdigest(phase_id))
    remove_tree(binding_directory, File.join(state_root, "bindings")) if File.exist?(binding_directory) || File.symlink?(binding_directory)
    Dir.children(evidence_root).each { |name| remove_tree(File.join(evidence_root, name), evidence_root) }
    Digest::SHA256.hexdigest(canonical_json(tombstone))
  end

  def review(options)
    repo = validate_repo(options.fetch(:repo))
    evidence_root = validate_private_root(options.fetch(:evidence_root), repo, "evidence root")
    state_root = validate_private_root(options.fetch(:state_root), repo, "state root")
    phase_id = validate_text(options.fetch(:phase_id), "phase ID", 256, empty: false)
    review_round = parse_positive_integer(options.fetch(:review_round), "review round")
    expected_packet_digest = validate_sha256(options.fetch(:expected_packet_sha256), "expected packet digest")
    contract_digest = validate_sha256(options.fetch(:contract_sha256), "contract digest")
    model_id = validate_model_id(options.fetch(:model_id))
    maximum_calls = parse_maximum_calls(options.fetch(:maximum_calls))
    maximum_dollars = parse_maximum_dollars(options.fetch(:maximum_dollars))
    deadline_seconds = parse_deadline(options.fetch(:deadline_seconds))
    output_path = validate_new_output(options.fetch(:output), evidence_root, "review result")
    store = StateStore.new(state_root)
    begin
      state = store.load(phase_id)
    rescue AdapterError => error
      raise unless error.message == "phase state is missing"
      state = store.create!(phase_id: phase_id, model_id: model_id, contract_digest: contract_digest, maximum_calls: maximum_calls, maximum_dollars: maximum_dollars)
    end
    store.validate_round!(
      phase_id: phase_id, review_round: review_round, model_id: model_id,
      contract_digest: contract_digest, maximum_calls: maximum_calls,
      maximum_dollars: maximum_dollars
    )
    round_ready = true

    executable = validate_executable(options.fetch(:claude_executable))
    packet_path = validate_private_file(options.fetch(:packet), evidence_root)
    schema_path = validate_private_file(options.fetch(:schema), evidence_root)
    manifest_path = validate_private_file(options.fetch(:contract_manifest), state_root)
    packet = read_bounded_file(packet_path, PACKET_LIMIT, "packet")
    raise AdapterError, "packet digest mismatch" unless Digest::SHA256.hexdigest(packet) == expected_packet_digest
    records = decode_packet(packet).to_h
    identity = validate_packet_records!(records, phase_id: phase_id, review_round: review_round)

    binding = load_binding(state_root, phase_id, review_round)
    validate_binding!(binding, phase_id: phase_id, review_round: review_round, packet_digest: expected_packet_digest, identity: identity, packet: packet, repo: repo)
    validate_current_artifact!(repo, identity, records)
    _contract, schema_bytes = validate_contract!(manifest_path, contract_digest, executable, model_id, schema_path)

    key = ENV["FOUR_EYES_CLAUDE_API_KEY"]
    if key.nil? || key.empty?
      terminal = {
        "Review status" => "error",
        "Verdict" => "not issued",
        "Reason" => "Invocation-only Claude API key is unavailable.",
        "Artifact identity" => identity
      }
      validate_structured_result!(terminal, expected_identity: identity)
      terminal_bytes = canonical_json(terminal)
      write_exclusive(output_path, terminal_bytes)
      terminal_digest = Digest::SHA256.hexdigest(terminal_bytes)
      store.prelaunch_terminal!(
        phase_id: phase_id,
        review_round: review_round,
        model_id: model_id,
        contract_digest: contract_digest,
        maximum_calls: maximum_calls,
        maximum_dollars: maximum_dollars,
        outcome_digest: terminal_digest
      )
      return terminal_digest
    end

    deadline = Time.now.to_i + deadline_seconds
    dispatch = store.begin_dispatch!(phase_id: phase_id, review_round: review_round, model_id: model_id, contract_digest: contract_digest, maximum_calls: maximum_calls, maximum_dollars: maximum_dollars, deadline: deadline)
    nonce = dispatch.fetch("dispatch_nonce")

    runtime = create_runtime(evidence_root, phase_id, review_round)
    schema_json = canonical_json(plain_json_value(parse_json(schema_bytes)))
    settings_path = File.join(runtime.fetch(:home), "settings.json")
    mcp_path = File.join(runtime.fetch(:home), "mcp.json")
    write_exclusive(settings_path, "{}\n")
    write_exclusive(mcp_path, "{}\n")
    remaining = maximum_dollars - BigDecimal(state.fetch("settled_dollars"))
    argv = build_claude_argv(
      claude_executable: executable,
      schema_json: schema_json,
      model_id: model_id,
      mcp_config_path: mcp_path,
      settings_path: settings_path,
      remaining_budget: remaining,
      session_id: state.fetch("candidate_session_uuid"),
      resume: state.fetch("session_established")
    )
    runtime_config = runtime.transform_keys(&:to_s)
    supervision_config = {
      "absolute_deadline" => deadline,
      "argv" => argv,
      "nonce" => nonce,
      "packet_path" => packet_path,
      "packet_sha256" => expected_packet_digest,
      "phase_id" => phase_id,
      "phase_sha256" => Digest::SHA256.hexdigest(phase_id),
      "review_round" => review_round,
      "runtime" => runtime_config,
      "state_root" => state_root
    }
    supervision_path = File.join(runtime.fetch(:root), "supervision.json")
    write_exclusive(supervision_path, canonical_json(supervision_config))
    supervision = start_supervision(supervision_path, key, runtime_config)
    key = nil
    provider_event = await_supervision(supervision)
    raise AdapterError, "Claude review deadline expired" if provider_event["event"] == "timeout"
    raise AdapterError, "Claude supervision failed" unless provider_event["event"] == "completed"
    provider_completed = true
    stdout_path = validate_private_file(provider_event.fetch("stdout_path"), evidence_root)
    stderr_path = validate_private_file(provider_event.fetch("stderr_path"), evidence_root)
    provider_stdout = read_bounded_file(stdout_path, STDOUT_LIMIT, "Claude stdout")
    provider_stderr = read_bounded_file(stderr_path, STDERR_LIMIT, "Claude stderr")
    raise AdapterError, "Claude process failed" unless provider_event["exitstatus"] == 0 && provider_event["termsig"].nil?
    raise AdapterError, "Claude stderr is not empty" unless provider_stderr.empty?
    structured, cost = parse_provider_envelope(
      provider_stdout,
      expected_session_id: state.fetch("candidate_session_uuid"),
      expected_identity: identity,
      reservation: remaining
    )
    validate_binding!(load_binding(state_root, phase_id, review_round), phase_id: phase_id, review_round: review_round, packet_digest: expected_packet_digest, identity: identity, packet: packet, repo: repo)
    validate_current_artifact!(repo, identity, records)
    result_bytes = canonical_json(structured)
    raise AdapterError, "review result exceeds limit" if result_bytes.bytesize > RESULT_LIMIT
    write_exclusive(output_path, result_bytes)
    parsed_readback = plain_json_value(parse_json(File.binread(output_path)))
    validate_structured_result!(parsed_readback, expected_identity: identity)
    result_digest = Digest::SHA256.hexdigest(result_bytes)
    store.complete_round!(phase_id: phase_id, nonce: nonce, outcome_digest: result_digest, cost: cost, trusted_session: true)
    begin
      finish_supervision(supervision, "release")
    rescue StandardError
      store.close_direct_mode!(phase_id: phase_id, expected_outcome_digest: result_digest)
      raise PostCompletionReleaseError, "durable result exists but provider release failed; human process inspection is required"
    end
    result_digest
  rescue PostCompletionReleaseError
    raise
  rescue StandardError => error
    raise unless defined?(round_ready) && round_ready && defined?(output_path) && output_path && defined?(store) && store

    terminal = terminal_result(error, defined?(identity) ? identity : nil)
    terminal_bytes = canonical_json(terminal)
    if File.exist?(output_path) || File.symlink?(output_path)
      existing = read_bounded_file(output_path, RESULT_LIMIT, "review result")
      raise unless existing == terminal_bytes
    else
      write_exclusive(output_path, terminal_bytes)
    end
    parsed_terminal = plain_json_value(parse_json(File.binread(output_path)))
    validate_structured_result!(parsed_terminal, expected_identity: defined?(identity) ? identity : nil)
    terminal_digest = Digest::SHA256.hexdigest(terminal_bytes)
    if defined?(nonce) && nonce
      current_state = store.load(phase_id)
      launched_uncertain = if current_state["provider_launch_state"] != "not-launched"
                             true
                           elsif current_state["current_transition"] == "launching"
                             !defined?(provider_event) || provider_event.nil? || provider_event["launched_uncertain"] != false
                           else
                             false
                           end
      store.terminal_round!(phase_id: phase_id, nonce: nonce, outcome_digest: terminal_digest, launched_uncertain: launched_uncertain)
    else
      store.prelaunch_terminal!(
        phase_id: phase_id,
        review_round: review_round,
        model_id: model_id,
        contract_digest: contract_digest,
        maximum_calls: maximum_calls,
        maximum_dollars: maximum_dollars,
        outcome_digest: terminal_digest
      )
    end
    if defined?(supervision) && supervision
      finish_supervision(supervision, defined?(provider_completed) && provider_completed ? "release" : "abort") rescue nil
    end
    terminal_digest
  ensure
    key = nil
  end

  def terminal_result(error, identity)
    message = error.message.to_s
    status, reason = if message == "Claude review deadline expired"
                       ["timeout", "Claude review deadline expired."]
                     elsif error.is_a?(JSON::ParserError) || message.match?(/(?:packet|artifact|binding|fingerprint|schema|structured output|identity|contract manifest)/i)
                       ["could-not-review", "Review evidence or structured output could not be validated."]
                     else
                       ["error", "Claude review adapter failed."]
                     end
    {
      "Review status" => status,
      "Verdict" => "not issued",
      "Reason" => reason,
      "Artifact identity" => identity
    }
  end
  private_class_method :terminal_result

  def run_provider(argv:, packet:, api_key:, runtime:, deadline_seconds:, on_spawn:)
    environment = {
      "ANTHROPIC_API_KEY" => api_key,
      "HOME" => runtime.fetch(:home),
      "TMPDIR" => runtime.fetch(:tmp),
      "LANG" => "C.UTF-8",
      "LC_ALL" => "C"
    }
    stdout_bytes = nil
    stderr_bytes = nil
    status = nil
    Open3.popen3(environment, *argv, unsetenv_others: true, chdir: runtime.fetch(:work)) do |stdin, stdout, stderr, wait_thread|
      on_spawn.call(wait_thread.pid)
      stdin.binmode
      stdin.write(packet)
      stdin.close
      stdout_reader = Thread.new { read_limited_stream(stdout, STDOUT_LIMIT, "stdout") }
      stderr_reader = Thread.new { read_limited_stream(stderr, 262_144, "stderr") }
      status = Timeout.timeout(deadline_seconds) { wait_thread.value }
      stdout_bytes = stdout_reader.value
      stderr_bytes = stderr_reader.value
    end
    write_exclusive(File.join(runtime.fetch(:root), "process.stdout"), stdout_bytes)
    write_exclusive(File.join(runtime.fetch(:root), "process.stderr"), stderr_bytes)
    {stdout: stdout_bytes, stderr: stderr_bytes, status: status}
  rescue Timeout::Error
    raise AdapterError, "Claude deadline expired"
  end

  def write_ipc(io, value)
    bytes = canonical_json(value)
    raise AdapterError, "internal message exceeds limit" if bytes.bytesize > IPC_LIMIT
    io.write([bytes.bytesize].pack("N"))
    io.write(bytes)
    io.flush
  end

  def read_ipc(io)
    header = read_exact(io, 4, allow_eof: true)
    return nil if header.nil?

    length = header.unpack1("N")
    raise AdapterError, "internal message length is invalid" if length > IPC_LIMIT
    plain_json_value(parse_json(read_exact(io, length, allow_eof: false)))
  end

  def read_exact(io, length, allow_eof:)
    output = +"".b
    while output.bytesize < length
      chunk = io.read(length - output.bytesize)
      if chunk.nil? || chunk.empty?
        return nil if allow_eof && output.empty?
        raise AdapterError, "internal message is truncated"
      end
      output << chunk
    end
    output
  end
  private_class_method :read_exact

  def write_secret(io, secret)
    bytes = String(secret).b
    raise AdapterError, "internal secret is invalid" if bytes.empty? || bytes.bytesize > 65_536
    io.write([bytes.bytesize].pack("N"))
    io.write(bytes)
    io.flush
  end

  def read_secret(io)
    length = read_exact(io, 4, allow_eof: false).unpack1("N")
    raise AdapterError, "internal secret length is invalid" unless length.between?(1, 65_536)
    read_exact(io, length, allow_eof: false)
  end

  def send_control(io, nonce, command)
    raise AdapterError, "control command is invalid" unless %w[TERM KILL RELEASE].include?(command)
    io.write("#{nonce}\0#{command}\n")
    io.flush
  end

  def read_control(io, nonce)
    line = io.gets
    return nil if line.nil?
    match = line.match(/\A([0-9a-f]{64})\0(TERM|KILL|RELEASE)\n\z/)
    raise AdapterError, "control record is malformed" unless match && match[1] == nonce
    match[2]
  end

  def monitor_environment(runtime)
    {
      "HOME" => runtime.fetch("home"),
      "TMPDIR" => runtime.fetch("tmp"),
      "LANG" => "C.UTF-8",
      "LC_ALL" => "C"
    }
  end
  private_class_method :monitor_environment

  def spawn_internal(mode, arguments, descriptors, runtime, pgroup: false)
    options = {
      unsetenv_others: true,
      close_others: true,
      chdir: runtime.fetch("work"),
      pgroup: pgroup
    }
    descriptors.each { |number, io| options[number] = io }
    command = [RbConfig.ruby, File.realpath(__FILE__), mode, *arguments.map(&:to_s)]
    [Process.spawn(monitor_environment(runtime), *command, options), command]
  end
  private_class_method :spawn_internal

  def start_supervision(config_path, api_key, runtime)
    parent_io, watchdog_io = Socket.pair(:UNIX, :STREAM, 0)
    secret_writer, secret_reader = Socket.pair(:UNIX, :STREAM, 0)
    pid, command = spawn_internal(
      "__watchdog",
      [config_path, "3", "4"],
      {3 => watchdog_io, 4 => secret_reader},
      runtime
    )
    watchdog_io.close
    secret_reader.close
    write_secret(secret_writer, api_key)
    secret_writer.close
    {io: parent_io, pid: pid, command: command}
  rescue StandardError => error
    write_internal_error(config_path, "watchdog", error)
    [parent_io, watchdog_io, secret_writer, secret_reader].compact.each { |io| io.close rescue nil }
    raise
  end

  def await_supervision(handle)
    message = read_ipc(handle.fetch(:io))
    raise AdapterError, "watchdog exited without a result" if message.nil?
    message
  end

  def finish_supervision(handle, command)
    write_ipc(handle.fetch(:io), {"command" => command})
    acknowledgement = read_ipc(handle.fetch(:io))
    expected = command == "release" ? {"event" => "released"} : {"event" => "terminated"}
    raise AdapterError, "watchdog did not acknowledge #{command}" unless acknowledgement == expected
    Process.waitpid(handle.fetch(:pid))
    handle.fetch(:io).close
    true
  rescue Errno::ECHILD
    true
  end

  def internal_watchdog(arguments)
    raise ArgumentError, "internal watchdog arguments are invalid" unless arguments.length == 3
    config_path, parent_fd, secret_fd = arguments
    config = load_supervision_config(config_path)
    parent_io = Socket.for_fd(Integer(parent_fd, 10))
    secret_io = Socket.for_fd(Integer(secret_fd, 10))
    api_key = read_secret(secret_io)
    secret_io.close
    store = StateStore.new(config.fetch("state_root"))
    store.record_launch_attempt!(phase_id: config.fetch("phase_id"), nonce: config.fetch("nonce"))

    supervisor_io, supervisor_child_io = Socket.pair(:UNIX, :STREAM, 0)
    watchdog_control, wrapper_control = Socket.pair(:UNIX, :STREAM, 0)
    watchdog_result, wrapper_result = Socket.pair(:UNIX, :STREAM, 0)
    secret_writer, secret_reader = Socket.pair(:UNIX, :STREAM, 0)
    supervisor_pid, = spawn_internal(
      "__supervisor",
      [config_path, "3", "4", "5", "6"],
      {3 => supervisor_child_io, 4 => secret_reader, 5 => wrapper_control, 6 => wrapper_result},
      config.fetch("runtime")
    )
    supervisor_child_io.close
    secret_reader.close
    wrapper_control.close
    wrapper_result.close
    write_secret(secret_writer, api_key)
    secret_writer.close
    api_key = nil

    prepared = read_ipc(supervisor_io)
    raise AdapterError, "supervisor did not prepare wrapper" unless prepared && prepared["event"] == "prepared"
    store.record_supervision!(
      phase_id: config.fetch("phase_id"),
      nonce: config.fetch("nonce"),
      watchdog_pid: Process.pid,
      supervisor_pid: supervisor_pid,
      wrapper_pid: prepared.fetch("wrapper_pid"),
      wrapper_pgid: prepared.fetch("wrapper_pgid"),
      wrapper_start_token: prepared.fetch("wrapper_start_token"),
      wrapper_command: prepared.fetch("wrapper_command")
    )
    write_ipc(supervisor_io, {"command" => "go"})
    watchdog_event_loop(config, parent_io, supervisor_io, watchdog_control, watchdog_result, supervisor_pid, store)
  rescue StandardError
    begin
      write_ipc(parent_io, {"event" => "monitor-error", "launched_uncertain" => true}) if parent_io
    rescue StandardError
      nil
    end
    exit 1
  ensure
    api_key = nil
  end

  def watchdog_event_loop(config, parent_io, supervisor_io, control_io, result_io, supervisor_pid, store)
    nonce = config.fetch("nonce")
    deadline = config.fetch("absolute_deadline")
    completion_sent = false
    abort_requested = false
    provider_acknowledged = false
    provider_launch_disproved = false
    term_at = nil
    terminal_event = nil
    loop do
      now = Time.now.to_f
      if term_at.nil? && now >= deadline
        send_control(control_io, nonce, "TERM")
        term_at = now
        terminal_event = "timeout"
      elsif term_at && now - term_at >= TERMINATION_GRACE
        send_control(control_io, nonce, "KILL") rescue nil
      end

      readable = IO.select([parent_io, result_io, supervisor_io], nil, nil, 0.1)&.first || []
      if readable.include?(result_io)
        event = read_ipc(result_io)
        if event.nil?
          terminal_event ||= "error"
        elsif event["event"] == "provider-ack"
          provider_acknowledged = true
          store.record_provider_ack!(phase_id: config.fetch("phase_id"), nonce: nonce, provider_pid: event.fetch("provider_pid"))
        elsif event["event"] == "completed"
          if event["termination_requested"] || event["termsig"] || event["exitstatus"] != 0
            terminal_event ||= event["termination_requested"] ? "timeout" : "error"
            term_at ||= Time.now.to_f
          elsif !terminal_event && !term_at
            write_ipc(parent_io, event)
            completion_sent = true
          end
        elsif %w[spawn-error overflow killed].include?(event["event"])
          provider_launch_disproved = true if event["event"] == "spawn-error" && event["provider_launched"] == false
          terminal_event ||= "error"
          unless term_at
            send_control(control_io, nonce, "TERM") rescue nil
            term_at = Time.now.to_f
          end
        end
      end

      if readable.include?(parent_io)
        command = read_ipc(parent_io)
        if command.nil?
          terminal_event ||= "error"
          unless term_at
            send_control(control_io, nonce, "TERM") rescue nil
            term_at = Time.now.to_f
          end
        elsif command == {"command" => "release"}
          send_control(control_io, nonce, "RELEASE")
          Process.waitpid(supervisor_pid)
          write_ipc(parent_io, {"event" => "released"})
          return
        elsif command == {"command" => "abort"}
          abort_requested = true
          terminal_event ||= "error"
          unless term_at
            send_control(control_io, nonce, "TERM")
            term_at = Time.now.to_f
          end
        else
          raise AdapterError, "parent command is invalid"
        end
      end

      if readable.include?(supervisor_io)
        event = read_ipc(supervisor_io)
        if event && event["event"] == "wrapper-exited"
          if abort_requested
            write_ipc(parent_io, {"event" => "terminated"}) rescue nil
          elsif terminal_event
            write_ipc(parent_io, {"event" => terminal_event, "launched_uncertain" => provider_acknowledged || !provider_launch_disproved}) rescue nil
          elsif !completion_sent
            write_ipc(parent_io, {"event" => terminal_event || "error", "launched_uncertain" => provider_acknowledged || !provider_launch_disproved}) rescue nil
          end
          Process.waitpid(supervisor_pid) rescue nil
          return
        end
      end

      if terminal_event && term_at && now - term_at >= TERMINATION_GRACE + 0.5
        event = abort_requested ? {"event" => "terminated"} : {"event" => terminal_event, "launched_uncertain" => provider_acknowledged || !provider_launch_disproved}
        write_ipc(parent_io, event) rescue nil
        Process.waitpid(supervisor_pid) rescue nil
        return
      end
    end
  end
  private_class_method :watchdog_event_loop

  def internal_supervisor(arguments)
    raise ArgumentError, "internal supervisor arguments are invalid" unless arguments.length == 5
    config_path, command_fd, secret_fd, watchdog_control_fd, watchdog_result_fd = arguments
    config = load_supervision_config(config_path)
    command_io = Socket.for_fd(Integer(command_fd, 10))
    secret_io = Socket.for_fd(Integer(secret_fd, 10))
    watchdog_wrapper_control = Socket.for_fd(Integer(watchdog_control_fd, 10))
    watchdog_wrapper_result = Socket.for_fd(Integer(watchdog_result_fd, 10))
    api_key = read_secret(secret_io)
    secret_io.close
    supervisor_control, wrapper_supervisor_control = Socket.pair(:UNIX, :STREAM, 0)
    supervisor_result, wrapper_supervisor_result = Socket.pair(:UNIX, :STREAM, 0)
    launch_reader, launch_writer = IO.pipe
    wrapper_secret_writer, wrapper_secret_reader = Socket.pair(:UNIX, :STREAM, 0)
    wrapper_arguments = [config_path, config.fetch("phase_sha256"), config.fetch("nonce"), "3", "4", "5", "6", "7", "8"]
    wrapper_pid, wrapper_command = spawn_internal(
      "__wrapper",
      wrapper_arguments,
      {
        3 => launch_reader,
        4 => wrapper_secret_reader,
        5 => watchdog_wrapper_control,
        6 => wrapper_supervisor_control,
        7 => watchdog_wrapper_result,
        8 => wrapper_supervisor_result
      },
      config.fetch("runtime"),
      pgroup: true
    )
    [launch_reader, wrapper_secret_reader, watchdog_wrapper_control, wrapper_supervisor_control, watchdog_wrapper_result, wrapper_supervisor_result].each(&:close)
    write_secret(wrapper_secret_writer, api_key)
    wrapper_secret_writer.close
    api_key = nil
    wrapper_pgid = Process.getpgid(wrapper_pid)
    raise AdapterError, "wrapper is not its process-group leader" unless wrapper_pgid == wrapper_pid
    prepared = {
      "event" => "prepared",
      "wrapper_command" => wrapper_command,
      "wrapper_pgid" => wrapper_pgid,
      "wrapper_pid" => wrapper_pid,
      "wrapper_start_token" => process_start_token(wrapper_pid)
    }
    write_ipc(command_io, prepared)
    command = read_ipc(command_io)
    raise AdapterError, "wrapper launch was not authorized" unless command == {"command" => "go"}
    launch_writer.write("GO")
    launch_writer.close
    supervisor_event_loop(config, command_io, supervisor_control, supervisor_result, wrapper_pid)
  rescue StandardError => error
    write_internal_error(config_path, "supervisor", error)
    exit 1
  ensure
    api_key = nil
  end

  def supervisor_event_loop(config, command_io, control_io, result_io, wrapper_pid)
    nonce = config.fetch("nonce")
    deadline = config.fetch("absolute_deadline")
    term_at = nil
    loop do
      waited = Process.waitpid(wrapper_pid, Process::WNOHANG)
      if waited
        write_ipc(command_io, {"event" => "wrapper-exited"}) rescue nil
        return
      end
      now = Time.now.to_f
      if term_at.nil? && now >= deadline
        send_control(control_io, nonce, "TERM") rescue nil
        term_at = now
      elsif term_at && now - term_at >= TERMINATION_GRACE
        send_control(control_io, nonce, "KILL") rescue nil
      end
      readable = IO.select([result_io], nil, nil, 0.1)&.first || []
      event = read_ipc(result_io) if readable.include?(result_io)
      if event && %w[spawn-error overflow].include?(event["event"]) && term_at.nil?
        send_control(control_io, nonce, "TERM") rescue nil
        term_at = Time.now.to_f
      end
    end
  rescue Errno::ECHILD
    write_ipc(command_io, {"event" => "wrapper-exited"}) rescue nil
  end
  private_class_method :supervisor_event_loop

  def internal_wrapper(arguments)
    raise ArgumentError, "internal wrapper arguments are invalid" unless arguments.length == 9
    config_path, phase_sha256, nonce, launch_fd, secret_fd, control_a_fd, control_b_fd, result_a_fd, result_b_fd = arguments
    config = load_supervision_config(config_path)
    raise AdapterError, "wrapper phase identity mismatch" unless config.fetch("phase_sha256") == phase_sha256
    raise AdapterError, "wrapper nonce mismatch" unless config.fetch("nonce") == nonce
    launch_io = IO.for_fd(Integer(launch_fd, 10))
    secret_io = Socket.for_fd(Integer(secret_fd, 10))
    controls = [Socket.for_fd(Integer(control_a_fd, 10)), Socket.for_fd(Integer(control_b_fd, 10))]
    results = [Socket.for_fd(Integer(result_a_fd, 10)), Socket.for_fd(Integer(result_b_fd, 10))]
    api_key = read_secret(secret_io)
    secret_io.close
    raise AdapterError, "wrapper launch token mismatch" unless launch_io.read == "GO"
    launch_io.close
    run_provider_wrapper(config, nonce, api_key, controls, results)
  rescue StandardError => error
    write_internal_error(config_path, "wrapper", error)
    send_wrapper_event(results || [], {"event" => "spawn-error", "provider_launched" => !error.is_a?(ProviderSpawnError)})
    exit 1
  ensure
    api_key = nil
  end

  def run_provider_wrapper(config, nonce, api_key, controls, results)
    runtime = config.fetch("runtime")
    packet = read_bounded_file(config.fetch("packet_path"), PACKET_LIMIT, "packet")
    raise AdapterError, "wrapper packet digest mismatch" unless Digest::SHA256.hexdigest(packet) == config.fetch("packet_sha256")
    environment = {
      "ANTHROPIC_API_KEY" => api_key,
      "HOME" => runtime.fetch("home"),
      "TMPDIR" => runtime.fetch("tmp"),
      "LANG" => "C.UTF-8",
      "LC_ALL" => "C"
    }
    completed = false
    overflow = false
    pending_kill = false
    term_at = nil
    provider_started = false
    trap("TERM") {}
    Open3.popen3(environment, *config.fetch("argv"), unsetenv_others: true, chdir: runtime.fetch("work"), pgroup: Process.getpgrp) do |stdin, stdout, stderr, wait_thread|
      provider_started = true
      api_key = nil
      send_wrapper_event(results, {"event" => "provider-ack", "provider_pid" => wait_thread.pid})
      stdin.binmode
      stdin.write(packet)
      stdin.close
      stdout_reader = Thread.new { capture_stream(stdout, STDOUT_LIMIT, "stdout") }
      stderr_reader = Thread.new { capture_stream(stderr, STDERR_LIMIT, "stderr") }
      loop do
        readable = IO.select(controls, nil, nil, 0.05)&.first || []
        readable.each do |control|
          command = read_control(control, nonce)
          if command.nil?
            controls.delete(control)
            control.close rescue nil
            next
          end
          case command
          when "TERM"
            unless term_at
              term_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              Process.kill("TERM", -Process.getpgrp)
            end
          when "KILL"
            elapsed = term_at && Process.clock_gettime(Process::CLOCK_MONOTONIC) - term_at
            unless overflow || elapsed
              pending_kill = true
              next
            end
            sleep(TERMINATION_GRACE - elapsed) if !overflow && elapsed < TERMINATION_GRACE
            send_wrapper_event(results, {"event" => "killed"})
            Process.kill("KILL", -Process.getpgrp)
          when "RELEASE"
            raise AdapterError, "RELEASE arrived before provider completion" unless completed
            raise AdapterError, "RELEASE arrived before durable outcome" unless release_state_ready?(config)
            return
          end
        end

        if pending_kill && term_at
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - term_at
          if elapsed >= TERMINATION_GRACE
            send_wrapper_event(results, {"event" => "killed"})
            Process.kill("KILL", -Process.getpgrp)
          end
        end

        [stdout_reader, stderr_reader].each do |reader|
          next unless reader.status == false
          value = reader.value
          if value[:error] && !overflow
            overflow = true
            send_wrapper_event(results, {"event" => "overflow"})
          end
        end

        next unless wait_thread.join(0)
        next unless stdout_reader.status == false && stderr_reader.status == false
        unless completed
          stdout_value = stdout_reader.value
          stderr_value = stderr_reader.value
          overflow ||= stdout_value[:error] || stderr_value[:error]
          unless overflow
            stdout_path = File.join(runtime.fetch("root"), "process.stdout")
            stderr_path = File.join(runtime.fetch("root"), "process.stderr")
            write_exclusive(stdout_path, stdout_value.fetch(:bytes))
            write_exclusive(stderr_path, stderr_value.fetch(:bytes))
            status = wait_thread.value
            send_wrapper_event(
              results,
              {
                "event" => "completed",
                "exitstatus" => status.exitstatus,
                "termsig" => status.termsig,
                "termination_requested" => !term_at.nil?,
                "stdout_path" => stdout_path,
                "stderr_path" => stderr_path
              }
            )
          end
          completed = true
        end
        return if completed && controls.empty?
      end
    end
  rescue SystemCallError => error
    raise ProviderSpawnError, "provider process could not be spawned" unless provider_started

    raise error
  ensure
    trap("TERM", "DEFAULT") rescue nil
  end
  private_class_method :run_provider_wrapper

  def capture_stream(io, limit, label)
    {bytes: read_limited_stream(io, limit, label), error: nil}
  rescue StandardError
    {bytes: "".b, error: true}
  end
  private_class_method :capture_stream

  def send_wrapper_event(results, value)
    Array(results).each do |io|
      write_ipc(io, value)
    rescue StandardError
      nil
    end
  end
  private_class_method :send_wrapper_event

  def release_state_ready?(config)
    state = StateStore.new(config.fetch("state_root")).load(config.fetch("phase_id"))
    state["current_transition"] == "idle" && !state["last_outcome_digest"].nil?
  rescue AdapterError
    false
  end
  private_class_method :release_state_ready?

  def process_start_token(pid)
    output, _error, status = Open3.capture3("/bin/ps", "-o", "lstart=", "-p", pid.to_s)
    raise AdapterError, "wrapper start token unavailable" unless status.success?
    validate_single_line(output.strip, "wrapper start token")
  end
  private_class_method :process_start_token

  def load_supervision_config(path)
    raise AdapterError, "supervision config path must be absolute" unless Pathname.new(path).absolute?
    stat = File.lstat(path)
    unless stat.file? && !stat.symlink? && stat.nlink == 1 && stat.uid == Process.uid && (stat.mode & 0o777) == 0o600
      raise AdapterError, "supervision config is unsafe"
    end
    value = plain_json_value(parse_json(read_bounded_file(path, CONTRACT_MANIFEST_LIMIT, "supervision config")))
    required = %w[absolute_deadline argv nonce packet_path packet_sha256 phase_id phase_sha256 review_round runtime state_root]
    raise AdapterError, "supervision config keys mismatch" unless value.is_a?(Hash) && value.keys.sort == required.sort
    raise AdapterError, "supervision deadline is invalid" unless value["absolute_deadline"].is_a?(Integer)
    raise AdapterError, "supervision argv is invalid" unless value["argv"].is_a?(Array) && value["argv"].all? { |entry| entry.is_a?(String) }
    validate_sha256(value.fetch("nonce"), "supervision nonce")
    validate_sha256(value.fetch("packet_sha256"), "supervision packet digest")
    validate_sha256(value.fetch("phase_sha256"), "supervision phase digest")
    raise AdapterError, "supervision phase digest mismatch" unless Digest::SHA256.hexdigest(value.fetch("phase_id")) == value.fetch("phase_sha256")
    value
  rescue Errno::ENOENT
    raise AdapterError, "supervision config is missing"
  end
  private_class_method :load_supervision_config

  def write_internal_error(config_path, role, error)
    config = load_supervision_config(config_path)
    path = File.join(config.fetch("runtime").fetch("root"), "#{role}.error")
    write_exclusive(path, "#{error.class}: #{error.message}\n") unless File.exist?(path) || File.symlink?(path)
  rescue StandardError
    nil
  end
  private_class_method :write_internal_error

  def read_limited_stream(io, limit, label)
    output = +"".b
    loop do
      chunk = io.readpartial([16_384, limit - output.bytesize + 1].min)
      output << chunk
      raise AdapterError, "Claude #{label} exceeds limit" if output.bytesize > limit
    end
  rescue EOFError
    output
  end
  private_class_method :read_limited_stream

  def create_runtime(evidence_root, phase_id, review_round)
    runtime_root = File.join(evidence_root, "runtime")
    ensure_private_directory(runtime_root, evidence_root)
    phase_root = File.join(runtime_root, Digest::SHA256.hexdigest(phase_id))
    ensure_private_directory(phase_root, runtime_root)
    round_root = File.join(phase_root, review_round.to_s)
    ensure_private_directory(round_root, phase_root)
    home = File.join(round_root, "home")
    tmp = File.join(round_root, "tmp")
    work = File.join(home, "work")
    ensure_private_directory(home, round_root)
    ensure_private_directory(tmp, round_root)
    ensure_private_directory(work, home)
    {root: round_root, home: home, tmp: tmp, work: work}
  end

  def validate_contract!(path, expected_digest, executable, model_id, schema_path)
    bytes = read_bounded_file(path, CONTRACT_MANIFEST_LIMIT, "contract manifest")
    raise AdapterError, "contract manifest digest mismatch" unless Digest::SHA256.hexdigest(bytes) == expected_digest
    manifest = plain_json_value(parse_json(bytes))
    expected = contract_manifest(
      candidate_revision: manifest.fetch("candidate_revision"),
      claude_executable: executable,
      model_id: model_id,
      checker_path: File.join(__dir__, "check-claude-reviewer2.rb"),
      schema_path: File.expand_path("../schemas/reviewer-verdict.schema.json", __dir__)
    )
    raise AdapterError, "contract manifest identity mismatch" unless canonical_json(manifest) == canonical_json(expected)
    schema_bytes = read_bounded_file(schema_path, SCHEMA_LIMIT, "schema")
    raise AdapterError, "schema copy differs from contract" unless Digest::SHA256.hexdigest(schema_bytes) == manifest.fetch("schema_sha256")
    [manifest, schema_bytes]
  end
  private_class_method :validate_contract!

  def load_binding(state_root, phase_id, review_round)
    path = File.join(state_root, "bindings", Digest::SHA256.hexdigest(phase_id), "#{review_round}.json")
    validate_private_file(path, state_root)
    plain_json_value(parse_json(read_bounded_file(path, STATE_LIMIT, "packet binding")))
  end
  private_class_method :load_binding

  def validate_binding!(binding, phase_id:, review_round:, packet_digest:, identity:, packet:, repo:)
    raise AdapterError, "binding phase mismatch" unless binding["phase_id"] == phase_id
    raise AdapterError, "binding round mismatch" unless binding["review_round"] == review_round
    raise AdapterError, "binding packet mismatch" unless binding["packet_sha256"] == packet_digest && Digest::SHA256.hexdigest(packet) == packet_digest
    fingerprint_digest = Digest::SHA256.hexdigest(canonical_json(repository_fingerprint(repo)))
    raise AdapterError, "repository fingerprint drift" unless binding["repository_identity_sha256"] == fingerprint_digest
    if binding["artifact_kind"] == "plan"
      path = binding.fetch("source_plan_realpath")
      stat = File.lstat(path)
      raise AdapterError, "bound plan is unsafe" unless stat.file? && !stat.symlink? && stat.nlink == 1
      bytes = read_bounded_file(path, ARTIFACT_LIMIT, "bound plan")
      unless bytes.bytesize == binding["source_plan_bytes"] && Digest::SHA256.hexdigest(bytes) == binding["source_plan_sha256"] && Digest::SHA256.hexdigest(bytes) == identity["artifact_sha256"]
        raise AdapterError, "bound plan drift"
      end
    end
  rescue Errno::ENOENT
    raise AdapterError, "bound source is missing"
  end
  private_class_method :validate_binding!

  def validate_identity!(identity)
    raise AdapterError, "artifact identity must be an object" unless identity.is_a?(Hash)
    kind = identity["artifact_kind"]
    common = %w[artifact_kind base prior_reviewed_head review_round review_stage reviewed_head workflow_revision]
    variants = {
      "plan" => common + %w[artifact_bytes artifact_sha256],
      "manual-uncommitted" => common + %w[artifact_bytes artifact_sha256 staged_sha256 unstaged_sha256 untracked_sha256],
      "manual-committed" => common + %w[artifact_bytes artifact_sha256 merge_base],
      "pr" => common + %w[artifact_bytes artifact_sha256 merge_base]
    }
    expected = variants[kind]
    raise AdapterError, "unsupported artifact identity" unless expected && identity.keys.sort == expected.sort
    raise AdapterError, "identity artifact byte count is invalid" unless identity["artifact_bytes"].is_a?(Integer) && identity["artifact_bytes"].between?(1, ARTIFACT_LIMIT)
    validate_git_sha(identity.fetch("workflow_revision"), "identity workflow revision")
    validate_sha256(identity.fetch("artifact_sha256"), "identity artifact digest")
    raise AdapterError, "identity round is invalid" unless identity["review_round"].is_a?(Integer) && identity["review_round"].positive?
    raise AdapterError, "identity stage is invalid" unless REVIEW_STAGES.include?(identity["review_stage"])
    prior = identity.fetch("prior_reviewed_head")
    validate_git_sha(prior, "identity prior reviewed head") unless prior == "none"
    case kind
    when "plan", "manual-uncommitted"
      raise AdapterError, "identity base must be none" unless identity["base"] == "none"
      unless identity["reviewed_head"].is_a?(String) && identity["reviewed_head"].match?(/\Auncommitted at HEAD [0-9a-f]{40}\z/)
        raise AdapterError, "identity reviewed head is invalid"
      end
      if kind == "manual-uncommitted"
        %w[staged_sha256 unstaged_sha256 untracked_sha256].each do |field|
          validate_sha256(identity.fetch(field), "identity #{field}")
        end
      end
    when "manual-committed", "pr"
      validate_git_sha(identity.fetch("base"), "identity base")
      validate_git_sha(identity.fetch("reviewed_head"), "identity reviewed head")
      validate_git_sha(identity.fetch("merge_base"), "identity merge base")
    end
    true
  end

  def validate_packet_records!(records, phase_id:, review_round:)
    unless records.is_a?(Hash) && records.keys == PACKET_RECORD_LABELS
      raise AdapterError, "packet record set mismatch"
    end
    expected_phase = validate_text(phase_id, "phase ID", 256, empty: false)
    raise AdapterError, "packet version mismatch" unless records["packet-version"] == "1"
    raise AdapterError, "packet reviewer slot mismatch" unless records["reviewer-slot"] == "2"
    raise AdapterError, "packet phase mismatch" unless validate_text(records["phase-id"], "packet phase ID", 256, empty: false) == expected_phase
    raise AdapterError, "packet round mismatch" unless records["review-round"] == review_round.to_s

    identity_json = validate_text(records["identity-json"], "identity JSON", IDENTITY_LIMIT, empty: false)
    identity = plain_json_value(parse_json(identity_json))
    validate_identity!(identity)
    raise AdapterError, "identity JSON is not canonical" unless identity_json == canonical_json(identity)
    raise AdapterError, "packet stage mismatch" unless records["review-stage"] == identity["review_stage"]
    raise AdapterError, "packet workflow revision mismatch" unless records["workflow-revision"] == identity["workflow_revision"]
    raise AdapterError, "packet artifact kind mismatch" unless records["artifact-kind"] == identity["artifact_kind"]
    raise AdapterError, "packet identity round mismatch" unless identity["review_round"] == review_round

    TEXT_LIMITS.each do |label, limit|
      validate_text(records.fetch(label), label, limit, empty: label != "reviewer-instructions" ? true : false)
    end
    artifact = String(records.fetch("artifact-bytes")).b
    raise AdapterError, "artifact is empty" if artifact.empty?
    raise AdapterError, "artifact exceeds limit" if artifact.bytesize > ARTIFACT_LIMIT
    unless identity["artifact_bytes"] == artifact.bytesize && identity["artifact_sha256"] == Digest::SHA256.hexdigest(artifact)
      raise AdapterError, "artifact identity mismatch"
    end
    validate_changed_file_manifest!(records.fetch("changed-file-manifest"), identity.fetch("artifact_kind"))
    identity
  end

  def validate_changed_file_manifest!(bytes, artifact_kind)
    text = validate_text(bytes, "changed-file manifest", MANIFEST_LIMIT, empty: false)
    value = plain_json_value(parse_json(text))
    raise AdapterError, "changed-file manifest is not canonical" unless text == canonical_json(value)
    raise AdapterError, "changed-file manifest must be an array" unless value.is_a?(Array)
    if artifact_kind == "plan"
      raise AdapterError, "plan manifest must be empty" unless value.empty?
      return true
    end

    keys = %w[committed_status path staged_status unstaged_status untracked]
    statuses = %w[A M D T none]
    paths = value.map do |entry|
      raise AdapterError, "changed-file manifest entry must be an object" unless entry.is_a?(Hash) && entry.keys.sort == keys
      %w[committed_status staged_status unstaged_status].each do |field|
        raise AdapterError, "changed-file manifest status is invalid" unless statuses.include?(entry[field])
      end
      raise AdapterError, "changed-file manifest untracked flag is invalid" unless [true, false].include?(entry["untracked"])
      path = validate_manifest_path(entry["path"])
      raise AdapterError, "changed-file manifest path is not normalized" unless path == entry["path"]
      path
    end
    raise AdapterError, "changed-file manifest paths are duplicated" unless paths.uniq.length == paths.length
    raise AdapterError, "changed-file manifest order is invalid" unless paths == paths.sort_by(&:b)
    true
  end

  def validate_current_artifact!(repo, identity, records)
    validate_identity!(identity)
    raise AdapterError, "artifact record set is invalid" unless records.is_a?(Hash)
    kind = identity.fetch("artifact_kind")
    run_git(repo, "cat-file", "-e", "#{identity.fetch('workflow_revision')}^{commit}")
    case kind
    when "plan"
      return true
    when "manual-uncommitted"
      fingerprint = repository_fingerprint(repo)
      expected_head = "uncommitted at HEAD #{fingerprint.fetch('head')}"
      unless identity["reviewed_head"] == expected_head &&
          identity["staged_sha256"] == fingerprint["staged_sha256"] &&
          identity["unstaged_sha256"] == fingerprint["unstaged_sha256"] &&
          identity["untracked_sha256"] == fingerprint["untracked_sha256"]
        raise AdapterError, "uncommitted artifact fingerprint drift"
      end
      artifact = build_uncommitted_artifact(repo)
      manifest = changed_file_manifest(repo, artifact_kind: kind)
    when "manual-committed", "pr"
      base = identity.fetch("base")
      reviewed_head = identity.fetch("reviewed_head")
      run_git(repo, "cat-file", "-e", "#{base}^{commit}")
      run_git(repo, "cat-file", "-e", "#{reviewed_head}^{commit}")
      merge_base = run_git(repo, "merge-base", base, reviewed_head).strip
      raise AdapterError, "committed artifact merge-base drift" unless identity["merge_base"] == merge_base
      artifact = canonical_diff(repo, base, reviewed_head, "--", ".")
      manifest = changed_file_manifest(repo, artifact_kind: kind, base: base, reviewed_head: reviewed_head)
    else
      raise AdapterError, "unsupported artifact identity"
    end
    unless records["artifact-bytes"] == artifact && records["changed-file-manifest"] == manifest
      raise AdapterError, "current artifact bytes drift"
    end
    unless identity["artifact_bytes"] == artifact.bytesize && identity["artifact_sha256"] == Digest::SHA256.hexdigest(artifact)
      raise AdapterError, "current artifact identity drift"
    end
    true
  end

  def validate_executable(path)
    raise ArgumentError, "Claude executable must be absolute" unless Pathname.new(path).absolute?
    real = File.realpath(path)
    stat = File.lstat(real)
    raise AdapterError, "Claude executable must be a regular file" unless stat.file? && !stat.symlink? && stat.nlink == 1
    raise AdapterError, "Claude executable is not executable" unless File.executable?(real)
    real
  rescue Errno::ENOENT
    raise AdapterError, "Claude executable does not exist"
  end

  def validate_model_id(value)
    text = validate_text(value, "model ID", 256, empty: false)
    if %w[opus sonnet haiku claude-opus claude-sonnet claude-haiku].include?(text) || !text.match?(/\Aclaude-[a-z0-9]+(?:-[a-z0-9]+){2,}\z/)
      raise ArgumentError, "model ID must be full and immutable"
    end
    text
  end

  def validate_single_line(value, label)
    text = String(value).strip
    raise AdapterError, "#{label} is invalid" if text.empty? || text.include?("\0") || text.match?(/[\r\n]/)
    text
  end

  def parse_deadline(value)
    seconds = parse_positive_integer(value, "deadline seconds")
    raise ArgumentError, "deadline must be 60 through 1800 seconds" unless seconds.between?(60, 1800)
    seconds
  end

  def validate_sha256(value, label)
    raise ArgumentError, "#{label} must be a lowercase SHA-256" unless String(value).match?(SHA256_PATTERN)
    value
  end

  def validate_repo(path)
    raise ArgumentError, "repo path must be absolute" unless Pathname.new(path).absolute?
    real = File.realpath(path)
    raise AdapterError, "repo must be a directory" unless File.directory?(real)
    run_git(real, "rev-parse", "--show-toplevel")
    real
  rescue Errno::ENOENT
    raise AdapterError, "repo does not exist"
  end

  def validate_private_root(path, repo, label)
    raise ArgumentError, "#{label} must be absolute" unless Pathname.new(path).absolute?
    stat = File.lstat(path)
    raise AdapterError, "#{label} must be a real directory" unless stat.directory? && !stat.symlink?
    real = File.realpath(path)
    raise AdapterError, "#{label} must be outside repo" if within?(real, repo)
    raise AdapterError, "#{label} has unexpected owner" unless stat.uid == Process.uid
    raise AdapterError, "#{label} mode must be 0700" unless (stat.mode & 0o777) == 0o700
    real
  rescue Errno::ENOENT
    raise AdapterError, "#{label} does not exist"
  end

  def claim_evidence_root!(root, phase_id)
    marker_path = File.join(root, PHASE_MARKER)
    marker = {"phase_id" => phase_id, "phase_sha256" => Digest::SHA256.hexdigest(phase_id), "version" => 1}
    if File.exist?(marker_path) || File.symlink?(marker_path)
      actual = plain_json_value(parse_json(File.binread(validate_private_file(marker_path, root))))
      raise AdapterError, "evidence root belongs to another phase" unless actual == marker
    else
      write_exclusive(marker_path, canonical_json(marker))
    end
  end
  private_class_method :claim_evidence_root!

  def remove_tree(path, root)
    expanded = File.expand_path(path)
    raise AdapterError, "cleanup path escapes approved root" unless within?(expanded, File.realpath(root)) && expanded != File.realpath(root)
    stat = File.lstat(expanded)
    if stat.directory? && !stat.symlink?
      Dir.children(expanded).each { |name| remove_tree(File.join(expanded, name), root) }
      Dir.rmdir(expanded)
    else
      File.unlink(expanded)
    end
  rescue Errno::ENOENT
    nil
  end
  private_class_method :remove_tree

  def validate_source_plan(path, repo)
    raise ArgumentError, "source plan must be absolute" unless Pathname.new(path).absolute?
    stat = File.lstat(path)
    raise AdapterError, "source plan must be a regular non-symlink file" unless stat.file? && !stat.symlink?
    raise AdapterError, "source plan must have one link" unless stat.nlink == 1
    raise AdapterError, "source plan has unexpected owner" unless stat.uid == Process.uid
    real = File.realpath(path)
    raise AdapterError, "source plan must be inside repo" unless within?(real, repo)
    relative = Pathname.new(real).relative_path_from(Pathname.new(repo)).to_s
    _output, _error, status = Open3.capture3({"LC_ALL" => "C"}, "git", "-C", repo, "check-ignore", "--quiet", "--", relative)
    raise AdapterError, "source plan must be gitignored" unless status.success?
    real
  rescue Errno::ENOENT
    raise AdapterError, "source plan does not exist"
  end

  def read_private_input(path, root, limit, empty:)
    real = validate_private_file(path, root)
    bytes = read_bounded_file(real, limit, "input")
    validate_text(bytes, "input", limit, empty: empty)
  end

  def validate_private_file(path, root)
    raise ArgumentError, "private input must be absolute" unless Pathname.new(path).absolute?
    stat = File.lstat(path)
    raise AdapterError, "private input must be a regular non-symlink file" unless stat.file? && !stat.symlink?
    raise AdapterError, "private input must have one link" unless stat.nlink == 1
    raise AdapterError, "private input has unexpected owner" unless stat.uid == Process.uid
    raise AdapterError, "private input mode must be 0600" unless (stat.mode & 0o777) == 0o600
    real = File.realpath(path)
    raise AdapterError, "private input must be under approved root" unless within?(real, root)
    real
  rescue Errno::ENOENT
    raise AdapterError, "private input does not exist"
  end

  def read_bounded_file(path, limit, label)
    before = File.lstat(path)
    unless before.file? && !before.symlink? && before.nlink == 1
      raise AdapterError, "#{label} is unsafe"
    end
    raise AdapterError, "#{label} exceeds limit" if before.size > limit

    flags = File::RDONLY
    flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
    File.open(path, flags) do |file|
      opened = file.stat
      unless opened.file? && opened.nlink == 1 && opened.dev == before.dev && opened.ino == before.ino
        raise AdapterError, "#{label} changed before read"
      end
      bytes = file.read(limit + 1) || "".b
      raise AdapterError, "#{label} exceeds limit" if bytes.bytesize > limit
      after = file.stat
      unless after.dev == opened.dev && after.ino == opened.ino && after.size == opened.size && after.mtime == opened.mtime
        raise AdapterError, "#{label} changed during read"
      end
      bytes
    end
  rescue Errno::ELOOP
    raise AdapterError, "#{label} is unsafe"
  rescue Errno::ENOENT
    raise AdapterError, "#{label} is missing"
  end

  def validate_text(value, label, limit, empty:)
    bytes = String(value).dup.force_encoding(Encoding::UTF_8)
    raise AdapterError, "#{label} exceeds limit" if bytes.bytesize > limit
    raise AdapterError, "#{label} is invalid UTF-8" unless bytes.valid_encoding?
    raise AdapterError, "#{label} contains NUL" if bytes.include?("\0")
    raise AdapterError, "#{label} must not be empty" if !empty && bytes.empty?
    bytes
  end

  def validate_new_output(path, root, label)
    raise ArgumentError, "#{label} path must be absolute" unless Pathname.new(path).absolute?
    parent = File.realpath(File.dirname(File.expand_path(path)))
    candidate = File.join(parent, File.basename(path))
    raise AdapterError, "#{label} must be under approved root" unless within?(candidate, root)
    raise AdapterError, "#{label} already exists" if File.exist?(candidate) || File.symlink?(candidate)
    raise AdapterError, "#{label} parent is not approved root" unless parent == root
    candidate
  end

  def ensure_private_directory(path, parent)
    if File.exist?(path) || File.symlink?(path)
      stat = File.lstat(path)
      raise AdapterError, "private directory is unsafe" unless stat.directory? && !stat.symlink? && stat.uid == Process.uid && (stat.mode & 0o777) == 0o700
      return
    end
    raise AdapterError, "private directory parent mismatch" unless File.realpath(File.dirname(path)) == File.realpath(parent)
    Dir.mkdir(path, 0o700)
    File.open(parent, File::RDONLY) { |directory| directory.fsync }
  end

  def write_exclusive(path, bytes)
    created = nil
    File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
      file.write(bytes)
      file.flush
      file.fsync
      stat = file.stat
      created = [stat.dev, stat.ino]
    end
    File.open(File.dirname(path), File::RDONLY) { |directory| directory.fsync }
    stat = File.lstat(path)
    unless stat.file? && !stat.symlink? && stat.nlink == 1 && stat.uid == Process.uid &&
        (stat.mode & 0o777) == 0o600 && [stat.dev, stat.ino] == created
      raise AdapterError, "private output is unsafe"
    end
  end

  def parse_positive_integer(text, label)
    value = String(text)
    raise ArgumentError, "#{label} must be a positive integer" unless value.match?(/\A[1-9][0-9]*\z/)
    Integer(value, 10)
  end

  def validate_git_sha(value, label)
    raise ArgumentError, "#{label} must be a full lowercase SHA" unless String(value).match?(GIT_SHA_PATTERN)
    value
  end

  def within?(path, root)
    path == root || path.start_with?("#{root}#{File::SEPARATOR}")
  end
  private_class_method :within?
end

if $PROGRAM_NAME == __FILE__
  begin
    FourEyesClaudeReviewer2.run_cli(ARGV.dup)
  rescue FourEyesClaudeReviewer2::AdapterError, ArgumentError, OptionParser::ParseError => error
    warn "claude-reviewer2: FAIL: #{error.message}"
    exit 1
  end
end
