# Claude Reviewer 2 Adapter

This optional adapter removes the human copy/paste step for Claude Reviewer 2 while preserving the Four Eyes policy. Manual external Reviewer 2 remains the default and fallback.

The adapter is transport, not orchestration. It does not implement, synthesize, update the tracker, merge, retry, choose a review tier, or cross a human gate.

## Status And Authorization

Record these fields on the task or phase:

```text
Reviewer 2 handoff: manual external reviewer | direct Claude adapter
Claude adapter status: unavailable | verified | stale
Claude model ID: <full immutable model ID or none>
Claude maximum calls: <positive integer or none>
Claude maximum dollars: <positive decimal or none>
Claude contract manifest SHA-256: <bare digest or none>
```

Use direct mode only when:

- status is `verified`
- the checked-in adapter, checker, schema, fixed constants, Claude executable/version/help, and full model ID match the private contract manifest
- the human authorized the exact task or phase, model, call limit, and dollar limit
- the selected panel still provides the required model-family independence

A new task or phase, budget increase, model change, contract-identity change, or manual fallback requires a new human decision. An unrelated repository revision alone does not invalidate a byte-identical contract.

## Operations

`scripts/claude-reviewer2.rb` has three public operations:

- `pack`: create one immutable private review packet, digest sidecar, and round binding
- `review`: validate that packet and invoke exactly one authorized Reviewer 2 call
- `close`: write a minimal closed-phase tombstone and remove the phase's raw local material

Run `ruby scripts/claude-reviewer2.rb <operation> --help` for the exact options. Use absolute paths.

The orchestrator resolves live PR base/head identities before `pack` and again after the verdict. The adapter makes no forge or tracker call.

## Private Roots

Provide one evidence root and one durable state root outside the repository. Both must be owned by the current user and mode `0700`. Adapter-owned files are mode `0600`.

The adapter rejects relative paths, traversal, symlinks, hard-linked adapter-owned files, wrong ownership, wrong modes, and evidence/state roots inside the repository. The Claude child receives no repository path and runs in an empty private working directory with private `HOME` and `TMPDIR`.

Do not place credentials, auth output, account identifiers, or private tracker data in packets, manifests, PRs, Linear, or public evidence.

## Sealed Packet

V1 is a length-framed binary packet beginning with `four-eyes-review-packet-v1` plus NUL. It contains only:

- phase, round, stage, workflow revision, and exact artifact identity
- reviewer instructions
- canonical changed-file manifest
- exact plan, uncommitted artifact, or committed/PR diff bytes
- bounded verification evidence
- optional neutral prior summary
- Reviewer 2's own prior findings

It excludes peer verdicts, synthesis, parent transcripts, hidden reasoning, credentials, and unrelated files. The adapter validates canonical JSON, exact record order, byte counts, digests, Git identities, repository fingerprint, packet binding, and artifact continuity before and after the provider call.

## Bare Claude Contract

The provider process uses:

- one verified executable invoked as an argument array without a shell
- `--bare`, JSON output, the checked-in JSON Schema, full immutable model ID, and `--effort max`
- no tools, no slash commands, strict empty MCP config, empty settings, no Chrome, and `dontAsk`
- one private phase session created with `--session-id`, then reused only with `--resume`
- a provider-side `--max-budget-usd` bounded by remaining authorized dollars

The child environment is replaced. Only private `HOME`, private `TMPDIR`, fixed locale variables, and `ANTHROPIC_API_KEY` mapped from invocation-only `FOUR_EYES_CLAUDE_API_KEY` are supplied. Normal OAuth, keychain state, Claude settings, project instructions, memory, hooks, plugins, skills, tools, browser, and implicit MCP are not copied.

Never pass the key as an argument or write it to evidence. Missing invocation auth is a pre-launch terminal `error` with zero provider attempts and zero spend.

## Budgets And No Re-roll

One human authorization sets immutable phase/model/contract identities plus maximum calls and dollars. State records launch attempts separately from confirmed provider children.

One numbered round produces exactly one completed verdict or one terminal record. There is no automatic retry, fallback, resampling, or same-round manual replacement. Only the human may authorize a later numbered round.

The direct phase session closes on an uncertain launch, untrusted session identity, timeout, provider/process failure, overflow, or lost process authority. Manual relay then remains available only after a new human decision.

## Process Boundary

A private watchdog and supervisor independently enforce the same deadline. A persistent provider-group wrapper is the only component allowed to signal its own process group. Authenticated private control channels carry `TERM`, then the fixed grace, then `KILL`, or `RELEASE` after a durable result.

Monitors never reconstruct signaling authority from a PID or PGID. Lost wrapper/control authority fails closed and requires human process inspection. Simultaneous monitor or kernel failure remains a documented residual; the provider-side dollar cap is the final spend bound.

## Outcomes

Completed Reviewer 2 judgment:

- `Review status: completed`
- `Verdict: Approve | Approve with nits | Block`
- findings, questions, required changes, and exact echoed artifact identity

Adapter terminal outcome:

- `Review status: error | timeout | could-not-review`
- `Verdict: not issued`
- one sanitized reason and safe identity when available

Terminal outcomes stand for the round and hold the gate. Raw stdout, stderr, environment, auth state, session IDs, private paths, and provider metadata stay private and are removed at phase close.

## Verification And Real-Call Gate

The complete fake suite is local, no-network, and quota-free:

```bash
ruby -w -c scripts/claude-reviewer2.rb
ruby -w -c scripts/check-claude-reviewer2.rb
ruby scripts/check-claude-reviewer2.rb --self-test
```

Generate the private contract manifest only from a clean pushed candidate. Public evidence may include its SHA-256 plus sanitized model/version/capability facts, never the executable path or full manifest.

Before any real call, stop for explicit human approval naming:

- the full immutable model ID
- maximum calls, exactly `2` for the contract test
- one positive maximum-dollar total

The contract test creates one session, resumes it once, verifies isolation and cleanup, then closes the test phase. A changed validity key makes status `stale` and requires a new fake suite, manifest, and separately approved two-call contract.

## Close

Close only an idle phase and provide the final result digest. `close` verifies phase ownership, writes and reads back the minimal tombstone, then removes packets, bindings, process captures, private Claude home/session material, settings/MCP files, and open state for that phase.

The tombstone retains only phase ID, closed state, final round, contract digest, and close-result digest. Removing the tombstone is a separate human retention decision.
