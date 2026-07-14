# Linear Setup

Use this when a human already has:

- a Linear workspace
- an agent with Linear access
- permission to create documents and issues

## Agent Prompt

```text
Set up Four Eyes in Linear.

Source repo: https://github.com/nickzren/four-eyes

If the repo is not available locally, clone or read the source repo first. Then use it as the source:
- README.md
- docs/playbook.md
- docs/templates.md
- docs/issue-tracker-setup.md
- docs/linear-setup.md
- docs/role-contracts.md
- scripts/check-docs.rb

Create:
- a project or workspace area named Four Eyes
- five runtime documents named Four Eyes Default Workflow, Four Eyes Playbook, Four Eyes Templates, Four Eyes Issue Tracker Setup, and Four Eyes Role Contracts
- one maintainer document named Four Eyes Linear Setup
- one standing issue for future workflow-doc reviews

Generate Role Contracts and all six revision-marked sync payloads with scripts/check-docs.rb. Do not hand-edit the derived document, workflow revision markers, source-body digests, or payload bodies.

If custom workflow states are available, use:
- Backlog
- Todo
- In Progress
- Review
- Approval
- Blocked
- Waiting External Eval
- Done

If custom states are not available, use labels:
- gate:review
- gate:approval
- waiting:external-eval
- state:applied-awaiting-verification
- blocked:<reason>

Make phase branch mode with implementation-first flow the default high-throughput path. Make review transport default to `pr` when the repo has a remote and CI or branch protection, otherwise `manual-relay`. Make post-merge branch cleanup default to `yes` and abandoned branch cleanup default to `ask`. Make the Codex-led default use the named isolated Reviewer 1 subagent `reviewer1`, reused across phases and review rounds for the same parent workflow. The orchestrator launches only internal Reviewer 1 and never launches an external reviewer. The human relays every external prompt, including every Reviewer 2 prompt. Require a fresh external Reviewer 2 session for the parent workflow unless the human explicitly chooses otherwise. Require each task issue and verdict to record the current review round, exact transport-specific artifact identity, and the full workflow revision from matching loaded document markers. Hold orchestrator-carried verdicts until all expected slots have returned or have a terminal record, then post them verbatim before synthesis. If the task input is not clear enough to execute safely, have the orchestrator write a temporary local executable plan, have reviewers confirm it when it defines the work, keep it uncommitted, and remove it after closeout.

Keep everything brief, generic, and public-safe. Do not include company names, secrets, internal links, or real task history. If repo or Linear access is missing, stop and say exactly what access is needed.
```

## Loading Rule

Default orchestrator bootstrap is:

- the task issue
- Four Eyes Default Workflow
- Four Eyes Role Contracts

Load Four Eyes Playbook only for exact policy detail or canonical commands, Templates only to fill an artifact, Issue Tracker Setup only for tracker-neutral behavior, and Linear Setup only for creation or sync. Reviewers receive a filled immutable packet and exact task evidence; they do not need the workflow-document set unless a disputed rule itself is under review.

The reproducible pre-change source bootstrap at revision `225430672fad342d693137254c256ca44f2bd8ef` was 92,036 UTF-8 bytes:

- README Default Workflow section: 2,630 bytes
- complete Playbook: 54,802 bytes
- complete Templates: 25,609 bytes
- complete Issue Tracker Setup: 8,995 bytes

The separate live Linear readback was 92,059 bytes. Do not use that readback or maintainer-document bytes in the source-savings denominator. `ruby scripts/check-docs.rb` reports the current source bootstrap, bytes saved, and percentage reduction; the post-change source bootstrap must not exceed 12,000 bytes.

## Canonical Sync Source Map

Use this fixed title order:

- `Four Eyes Default Workflow` <- `README.md` from the `## Default Workflow` heading through the byte before the next level-two heading
- `Four Eyes Playbook` <- complete `docs/playbook.md`
- `Four Eyes Templates` <- complete `docs/templates.md`
- `Four Eyes Issue Tracker Setup` <- complete `docs/issue-tracker-setup.md`
- `Four Eyes Role Contracts` <- complete generated `docs/role-contracts.md`
- `Four Eyes Linear Setup` <- complete `docs/linear-setup.md`

Canonical source-body bytes are defined once here: require valid UTF-8; convert CRLF to LF; reject any remaining bare CR or NUL; remove every trailing LF; append exactly one LF. `Source body SHA-256` hashes those canonical body bytes, including the one final LF.

Each synced document starts with exactly `Workflow revision: <full-sha>`, then `Source body SHA-256: <digest>`, then one blank line, followed by the canonical source body.

Repository source files never hard-code the current revision or source-body digest.

This phase introduces the repo's first checked-in helper convention: documentation helpers use only the Ruby standard library. This is a new owner decision, not a pre-existing implementation pattern.

## Sync Rule

Treat this repo as the source of truth.

Runtime docs:

- Four Eyes Default Workflow
- Four Eyes Playbook
- Four Eyes Templates
- Four Eyes Issue Tracker Setup
- Four Eyes Role Contracts

Maintainer doc:

- Four Eyes Linear Setup

When updating the workflow:

1. Update this repo and run `ruby scripts/check-docs.rb --self-test`, `ruby scripts/check-docs.rb`, and `git diff --check`.
2. Commit and push the repo change.
3. From the pushed revision, generate expected payloads in a new outside-repo directory:

   ```bash
   ruby scripts/check-docs.rb --sync-dir /tmp/four-eyes-sync-<full-sha> --revision <full-sha>
   ```

4. Create or update all six Linear documents from those payload bytes unless the human explicitly requested a repo-only change.
5. Read all six documents back. Parse the two exact marker lines and required blank line, apply the canonical source-body algorithm to the remaining bytes, rebuild the payload, and compare every byte with the generated expected payload.
6. Any missing document, abbreviated or mixed revision, wrong source-body digest, malformed marker block, or byte mismatch leaves the sync gate open.
7. Record the full pushed revision, six successful byte comparisons, and manifest digest in the standing workflow-doc review issue.

If Linear is edited first, backport the change into this repo and regenerate all affected payloads before treating it as durable.

## Standing Review Issue

Title:

```text
Review: Four Eyes workflow docs
```

Description:

```text
Use this issue for reviews and sync evidence for the Four Eyes workflow documents.

Runtime documents:
- Four Eyes Default Workflow
- Four Eyes Playbook
- Four Eyes Templates
- Four Eyes Issue Tracker Setup
- Four Eyes Role Contracts

Maintainer document:
- Four Eyes Linear Setup

Boundary:
- Workflow-doc review and sync only
- Brief, simple, necessary comments
- No private task history or sensitive data

Latest successful sync:
- Workflow revision: <full pushed repo commit SHA>
- Manifest SHA-256: <bare digest>
- Readback: all six payloads byte-exact
```
