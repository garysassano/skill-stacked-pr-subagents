# Harness notes

How each coding-agent harness spawns a subagent with a fresh context, which id identifies it, and how to resume it once it has finished. Checked on 2026-11-11 against Claude Code 2.1.322, OpenCode 2.2.7, Codex CLI 0.167.1, and the omp documentation of that date. These details change often, so check the linked sources when a step fails.

To find out which harness you are in, look at your own tools: `task` with `agent://` addresses is omp, `Agent` with `SendMessage` is Claude Code, `subagent` is OpenCode, and `spawn_agent` with `followup_task` is Codex.

## At a glance

|                                      | omp                                          | Claude Code                                                                          | OpenCode                                                  | Codex CLI                                                              |
| ------------------------------------ | -------------------------------------------- | ------------------------------------------------------------------------------------ | --------------------------------------------------------- | ---------------------------------------------------------------------- |
| Spawn                                | `task` tool                                  | `Agent` tool, custom `subagent_type`                                                 | `subagent` tool, agent with `mode: subagent`              | `spawn_agent` with `fork_turns: "none"`                                |
| Fresh context                        | by default                                   | by default, except forks                                                             | by default                                                | **only with `fork_turns: "none"`**                                     |
| Id to record                         | agent id (`agent://<id>`)                    | `agentId` from the result                                                            | child `sessionID` (`ses_…`)                               | `task_name` path (`/root/<name>`) and the root session id              |
| Resume a finished subagent           | `write agent://<id>`                         | `SendMessage({to: "<agentId>"})`                                                     | `subagent` again with `sessionID`                         | `followup_task(target: "/root/<name>")`                                |
| After a restart                      | resume the main session, then message the id | `claude --resume <session>`, then message the id                                     | reopen the parent session, then call with `sessionID`     | `codex exec resume <root id>`, then `followup_task`                    |
| Default cache lifetime of a subagent | provider default                             | 5 minutes                                                                            | provider default (5 minutes on Anthropic)                 | 30 minutes or more (OpenAI)                                            |
| Main trap                            | isolated workers can't be revived            | Explore and Plan can't be resumed; isolation worktrees start from the default branch | `general` can't spawn; some models send `"ses"` as the id | completed children keep their thread slots; sandbox blocks the network |

## omp

- **Spawn.** The `task` tool. A child starts with only its assignment and the shared context, not the main conversation. Results arrive in the main session as they finish; block with the `wait` tool when there is nothing else to do. Use the `task` agent for layer agents and `reviewer` for reviews.
- **Record** the agent id the spawn returns. `agent://<id>` holds its final output and `history://<id>` its transcript.
- **Resume** with `write agent://<id>` and the message. A finished worker is `idle` for `task.agentIdleTtlMs` (7 minutes by default), then `parked` to disk. Messaging a parked worker revives it with its full history. After a restart, resume the same main session; Agent Hub (`Alt+A`) finds the parked workers again.
- **Isolation.** Leave `isolated` off. Isolated workers can't be revived once they finish, because their workspace is torn down.
- **Limits.** `task.softRequestBudget` (200 requests by default) asks a long-running worker to wrap up, then forces a partial result at 1.5 times the budget. A layer that hits it reports partial work; resume it to continue. `task.maxRecursionDepth` is 2.
- **Cache.** omp warms only the main session's prompt cache, not subagents' (`providers.cacheWarming`). Retention follows `providers.cacheRetention`.
- Sources: [Subagents](https://omp.sh/docs/subagents), [task tool](https://github.com/can1357/oh-my-pi/blob/main/docs/tools/task.md).

## Claude Code

- **Spawn.** The `Agent` tool with a custom `subagent_type` defined in `.claude/agents/<name>.md` or `~/.claude/agents/<name>.md`, or `general-purpose`. Don't use Explore or Plan for anything you may resume: they are one-shot and return no agent id. Don't fork for a layer: a fork inherits the whole conversation, which defeats the point.
- **Settings.** Set `CLAUDE_CODE_FORK_SUBAGENT=0` in `settings.json` `env`. Fork mode is on by default since 2.1.302; turning it off stops Claude from forking on its own and lets it wait for a subagent. Leave agent teams off, so a named spawn stays a plain subagent.
- **Record** the `agentId` from the Agent tool result, plus the main session id. Use the id, not the name: names from before the main session's last compaction don't survive a restart.
- **Resume** with `SendMessage({to: "<agentId>", ...})`. The subagent resumes in the background with its full history and the tool set it first ran with. A subagent you stopped yourself (`x` in `/tasks`) refuses messages. Use 2.1.304 or later; it fixed resumed subagents forgetting their most recent work. After a restart, run `claude --resume <session id>` and send by id. Lost ids are in `~/.claude/projects/<project>/<session>/subagents/agent-<id>.meta.json`.
- **Retention.** Subagent transcripts are deleted after `cleanupPeriodDays` (30 days by default). Raise it if a stack can live longer.
- **Isolation.** Don't set `isolation: worktree` on layer agents. Those worktrees branch from the repository's default branch, unless `worktree.baseRef` is `"head"`, and are swept later. Start `claude` inside the stack's worktree instead.
- **Cache.** Subagents get the 5-minute cache by default, even on a subscription. `subagentPromptCacheTtl: "1h"` (2.1.242 or later) keeps an owner warm through an hour of waiting, at a higher write price. A resumed subagent reads the cache its earlier run warmed while that cache lives.
- **Headless.** `claude -p --output-format json` returns the `session_id`; `claude -p "<message>" --resume <session id>` continues it.
- Sources: [Subagents](https://code.claude.com/docs/en/sub-agents) (Resume subagents, Turn fork mode off), [Prompt caching](https://code.claude.com/docs/en/prompt-caching) (Which TTL each request gets), [Worktrees](https://code.claude.com/docs/en/worktrees) (Choose the base branch), [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md) 2.1.304.

## OpenCode 2

These notes are for OpenCode 2 and don't cover OpenCode 1, where the tool and its permission action were called `task`. V2 renamed both to `subagent` and uses ordered `permissions` rules instead of V1's `permission` map.

- **Spawn.** The `subagent` tool, with an agent whose `mode` is `subagent` or `all`, defined in `.opencode/agents/<name>.md`, `~/.config/opencode/agents/<name>.md` or under `agents` in `opencode.jsonc`. Give the layer agent V2 `permissions` rules that allow `edit` and `shell`, and allow the orchestrator to launch it with `{ "action": "subagent", "resource": "<agent>", "effect": "allow" }`. In 2.2.7 a call blocks until the child finishes unless you pass `background: true`; blocking suits this workflow. On the `dev` branch after 2.2.7, every call runs in the background and reports back when the child goes idle ([#63382](https://github.com/anomalyco/opencode/pull/63382)). The default nesting depth is 1, so layer agents can't start their own reviewers. The orchestrator starts reviewers.
- **Record** the child `sessionID` from the `<subagent sessionID="ses_…">` result, plus the orchestrator's own session id.
- **Resume** by calling `subagent` again with the same `agent`, that `sessionID` and a new `prompt`. A finished child starts a new run on top of its history. Only the parent session may continue its children. Keep the same agent and model, because a switch costs the cache. Leaving out `sessionID` silently starts a new child ([#62793](https://github.com/anomalyco/opencode/issues/62793)). Some models send the literal string `ses` as the id and fail with "Subagent session not found: ses" ([#59293](https://github.com/anomalyco/opencode/issues/59293)); none of the reported models are Claude or GPT.
- **After a restart**, reopen the same parent session (`opencode run --session <parent id>` or `/sessions` in the TUI), then continue the child by `sessionID`.
- **Isolation.** A child works in its parent's directory. Start the orchestrator in the stack's worktree.
- **Cache.** OpenCode sends no cache lifetime by default, so Anthropic's 5 minutes applies. Set `settings.cache.ttl` (for example `"1h"`) on the provider or model. Warming never applies to subagent sessions.
- Sources: [Tools: Subagent](https://opencode.ai/docs/tools/), [Agents](https://opencode.ai/docs/agents/), [Migrate from V1](https://opencode.ai/docs/migrate-v1/), [Models: Cache lifetime](https://opencode.ai/docs/models/), [Warming](https://opencode.ai/docs/warming/), [PR #43172](https://github.com/anomalyco/opencode/pull/43172).

## Codex CLI

- **Runtime.** Current models use multi-agent V2, chosen by the model catalog. The notes below are for V2.
- **Spawn** with `spawn_agent` and always pass `fork_turns: "none"`. In V2 the default is `"all"`, which copies the orchestrator's whole history into the child. Define layer agents in `.codex/agents/<name>.toml` (`name`, `description`, `developer_instructions`, optionally `model`) and pass the name as `agent_type`. Wait with `wait_agent`.
- **Record** the child's `task_name` path (`/root/<task_name>`) and the root session id (`thread_id` of the `thread.started` event in `codex exec --json`).
- **Resume** with `followup_task(target: "/root/<task_name>", message: ...)`. It starts a new turn in the same child thread with its history. Children can only be reached through their root: resume the root with `codex exec resume <root id>` (fixed in 0.145.0, [#33002](https://github.com/openai/codex/issues/33002)), then follow up. A child's own session id is rejected.
- **Thread cap.** Completed V2 children keep their thread slots, and V2 has no `close_agent` ([#22779](https://github.com/openai/codex/issues/22779), open). The V2 default cap is 4. Set `[agents] max_concurrent_threads_per_session` to at least the number of layers plus reviewers, with a margin, or reuse one reviewer thread with `followup_task` for every layer.
- **Network.** The `workspace-write` sandbox blocks network access by default, so `git push` and `gh` fail. Allow it with `sandbox_workspace_write.network_access = true`, or allow `git` and `gh` through [rules](https://learn.chatgpt.com/docs/agent-configuration/rules). Non-interactive children can't ask for approvals.
- **Isolation.** Children share the root's working directory. Start the root in the stack's worktree.
- **Cache.** On GPT-5.6 and later, OpenAI keeps cache entries for at least 30 minutes by default. Codex doesn't set a lifetime.
- **V1 models.** Record `agent_id`, resume with `resume_agent(id)`, then `send_input` and `wait_agent`. `resume_agent` doesn't restore the child's model and reasoning effort ([#26718](https://github.com/openai/codex/issues/26718)), so state them again.
- Sources: [Subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents), [Sandbox](https://learn.chatgpt.com/docs/sandboxing), [Prompt caching](https://developers.openai.com/api/docs/guides/prompt-caching), source `codex-rs/core/src/tools/handlers/multi_agents_v2/spawn.rs` and `codex-rs/core/src/config/mod.rs` at `rust-v0.167.1`.
