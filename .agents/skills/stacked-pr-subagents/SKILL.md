---
name: stacked-pr-subagents
description: Implement a multi-task plan as a stack of pull requests built by serial subagents. The main session orchestrates and writes no code; one subagent at a time implements one layer on a branch stacked on the previous layer's and opens its PR with gh stack; the orchestrator records which subagent owns which PR and resumes that owner for any later change; full CI runs only on the top PR; the finished stack is reviewed and merged in one operation. Use when asked to implement a plan, a list of batches, or several dependent tasks that would grow one session's context, or when asked to stack PRs with subagents.
---

# Stacked PRs with serial subagents

The main session is the orchestrator. It splits the plan into layers and hands one layer at a time to a fresh subagent. That subagent implements the layer on its own branch, stacked on the previous layer's branch, and opens a pull request with `gh stack`. The orchestrator records which subagent owns which PR, so any later change to a layer goes back to the subagent that wrote it, which still holds its context. When the last layer is done and reviewed, the whole stack merges in one operation.

This keeps every context small. A single session that implements a whole plan re-reads its entire, growing context on every turn. Parallel subagents in separate worktrees stay small, but dependent tasks conflict and their PRs must be rebased onto each other. Serial layers avoid both: each branch starts from the one below, so there is nothing to rebase between siblings.

Use it for a plan with several dependent tasks that each need real implementation work. Don't use it for a change one session finishes comfortably, for independent tasks on disjoint files (parallel worktrees with separate PRs fit those), or for work where most steps wait on the user's decisions.

## Roles

- **Orchestrator** (the main session): splits the plan into layers, writes each brief, keeps the ledger, routes findings to owners, and decides when to merge. It reads final reports, the ledger, `gh stack view --json` and CI states. It never reads full diffs or subagent transcripts, and it never edits the code.
- **Layer agent**: one per layer, spawned with a fresh context. It implements the layer, verifies it locally, commits, opens or updates its PR, and reports. It owns that layer for the rest of the run.
- **Reviewer**: read-only. One per layer, plus one for the whole stack at the end. It reads a layer by git refs (`git diff <parent>..<branch>`), not from the working tree.

One writer at a time: only one agent edits the shared worktree at any moment. Reviewers and CI only read, so they may run while a layer agent works.

## Before the first layer

1. Read [references/harnesses.md](references/harnesses.md) for the harness you run in: how to spawn a subagent with a fresh context, which id to record, how to resume a finished subagent, and the traps. Getting this wrong makes subagents copy the whole orchestrator conversation or makes owners unreachable.
2. Check the tools. `gh stack --help` must work (the `github/gh-stack` extension of GitHub CLI), git must be 2.36 or later, and `git config rerere.enabled` should be `true` so a resolved conflict replays in every layer above. All branches must live in one GitHub repository; stacks don't cross forks. If the extension is missing, stop and tell the user: installing tools is their call. Where the repository's instructions name a `gh` wrapper, use it for every `gh` call.
3. Create one worktree for the whole stack from the trunk, for example `git worktree add --detach ../<repo>-stack origin/main`. Every agent works there, so build caches stay warm across layers and the user's own checkout stays untouched. Don't use a harness's per-subagent isolation: those features branch from the default branch or tear the workspace down when the subagent finishes, which breaks both the stack and resuming its owner.
4. Check whether the repository's CI runs its expensive jobs only on the top PR of a stack ([references/ci.md](references/ci.md)). If it doesn't, propose the change to the user. With their approval it goes into the first layer, since a PR's runs use the workflow files on its own branch.
5. Split the plan into layers (below), write the ledger, and state the layer list in the chat. Proceed unless a layer depends on a decision only the user can make.

## Layers

- One concern per layer, describable in one sentence. Dependencies point only down the stack.
- Size a layer by context, not by the plan's headings. A layer agent should finish its first pass well under half of its context window, so later fix rounds still fit. A large batch in the plan becomes several layers.
- Foundations go first. A layer that needs an open decision waits until the user has made it.
- Name branches `<topic>/<NN>-<slug>`, for example `checkout/01-schema`, unless the repository has its own convention.

## The ledger

The ledger is a file in the worktree root, `.stack-ledger.md`, listed in `.git/info/exclude`. It lives outside the chat so that it survives the orchestrator's compaction and restarts. It holds the harness, the orchestrator's session id, and one row per layer: branch, PR, tasks, owner agent id, status, head SHA. Below the table is a queue of findings, each assigned to the layer that owns the fix. The template is in [references/templates.md](references/templates.md).

Update it right after every spawn, report, review, CI result and fix. When the orchestrator loses track, the ledger and `gh stack view --json` restore it.

## The layer loop

For layer N:

1. **Spawn** a layer agent with the brief from [references/templates.md](references/templates.md). The brief is self-contained, because the agent starts blank. Record its agent id in the ledger before doing anything else, with status `implementing`.
2. **Implement.** The agent creates its branch on top of the stack: `gh stack init --base <trunk> <branch>` for the first layer, `gh stack add <branch>` from the top branch for later ones. It implements its tasks, runs the narrowest local checks that prove them, and commits.
3. **Open the PR.** The agent runs `gh stack submit --auto`, which pushes every branch and opens draft PRs. It then replaces the generated title and body with `gh pr edit`. The body is the handoff for later layers: what changed, why, how it was verified, deviations from the plan, and anything later layers must know. Then it reports and ends its turn.
4. **Record.** The orchestrator adds the PR number and head SHA to the ledger and sets the status to `pr-open`.
5. **Review and move on.** The orchestrator starts a reviewer on layer N and spawns the layer N+1 agent at the same time. Nobody waits for CI.
6. **Route findings.** Review findings, CI failures and blockers reported by later layers go into the ledger queue against the layer that owns the fix. They are applied between writer turns: once the current layer agent has ended its turn, resume each owner in turn (see below).

A layer agent that finds a defect in a lower layer doesn't fix it on its own branch. It commits its work in progress, reports `blocked-on: layer K` with the evidence, and ends its turn. The orchestrator resumes layer K's owner for the fix, then resumes the blocked agent and tells it that layer K changed.

## Changing a layer later

Resume the layer's owner with the findings. It checks out its branch (`gh stack checkout <branch>`), fixes and commits there, replays the layers above with `gh stack rebase --upstack`, pushes with `gh stack push`, returns to the top with `gh stack top`, and reports its new head SHA. If the rebase stops on a conflict in a higher layer's code (exit code 3), it resolves the conflict only if the resolution is obvious. Otherwise it runs `gh stack rebase --abort` and reports the conflict, and the orchestrator resumes that higher layer's owner to run the rebase. After a lower layer changes, tell every higher owner you resume next that the code below it moved and must be re-read.

Resume the owner by default. It already knows the code it wrote, so a fix costs a short message plus its own transcript. That transcript is read from the provider's prompt cache while the cache is still warm (each harness's lifetime is in [references/harnesses.md](references/harnesses.md)), and at the full input price after that. A fresh agent would rebuild the same knowledge by reading the code again. Spawn a fresh agent instead when the owner's context is close to full, its session can't be resumed, or the change has nothing to do with what it built. Give the new agent the layer's PR body and diff, and record it in the ledger as the layer's new owner.

## CI

- Agents never wait for CI.
- Expensive jobs run only on the top PR of the stack, which contains every layer ([references/ci.md](references/ci.md)). The PRs below report those jobs as skipped.
- Between layers, the orchestrator looks at the latest run on the top PR (`gh pr checks <top>`). A red run goes into the queue against the layer that owns the failing code: find it from the failing test or file and `git log`.
- Merge only when the top PR is green on its current head SHA.

## Stop and ask

Stop the run and ask the user when a layer needs a decision the plan doesn't make, such as a trade-off with visible consequences, a new restriction, or anything the repository's rules reserve for the user. Also stop when an agent reports a blocker that no owner can fix. Never pick a default to keep the stack moving. Layers that don't depend on the answer may continue meanwhile.

## Finish

1. Check that every finding in the ledger queue is closed and the top PR is green on its head SHA.
2. Run a final read-only reviewer over the whole stack (`git diff <trunk>..<top branch>`). It looks at the seams between layers: interfaces one layer defines and another uses, code an earlier layer added that a later one made obsolete, and docs and changelog entries that disagree. Its findings go to the owners, as in the loop.
3. Mark every PR ready for review with `gh pr ready <number>`.
4. Merge only if the user asked for merging as part of the run, since merging into the default branch is outward-facing. Run `gh stack merge <top PR> --yes` with the repository's merge method, for example `--squash`. It merges the top PR and every PR below it as one operation: if any of them can't merge, none do. Never use `gh pr merge` on a stacked PR; it can't merge a stack.
5. Remove the worktree (`git worktree remove <path>`) and report to the user: the PRs, what each changed, what was verified, and anything left open. Keep the ledger until then.

## gh stack without a terminal

`gh stack` opens prompts or a full-screen interface when it has a terminal, and those hang an agent. Always pass the non-interactive forms:

| Use                                    | Never run bare                                     |
| -------------------------------------- | -------------------------------------------------- |
| `gh stack view --json`                 | `gh stack view`                                    |
| `gh stack submit --auto`               | `gh stack submit`                                  |
| `gh stack init <branch>`               | `gh stack init`                                    |
| `gh stack add <branch>`                | `gh stack add`                                     |
| `gh stack checkout <branch>`           | `gh stack checkout`                                |
| `gh stack up`, `down`, `top`, `bottom` | `gh stack switch`                                  |
| `gh stack merge <PR> --yes`            | `gh stack modify` (it has no non-interactive form) |

Exit code 3 is a rebase conflict: resolve the files, `git add` them, and run `gh stack rebase --continue`. Exit code 9 means stacked PRs are unavailable in the repository; tell the user. `gh stack <command> --help` is authoritative for flags, and the extension's own skill, [`github/gh-stack`](https://github.com/github/gh-stack/blob/main/skills/gh-stack/SKILL.md), covers recovery in more depth.
