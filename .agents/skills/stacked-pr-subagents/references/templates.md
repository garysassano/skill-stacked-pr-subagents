# Templates

## Ledger

Keep it at `.stack-ledger.md` in the stack's worktree and add that name to the repository's `.git/info/exclude`.

```markdown
# Stack ledger

- Plan: <path or link>
- Harness: <omp | Claude Code | OpenCode | Codex>, orchestrator session <id>
- Worktree: <path>, trunk <main>, stack #<number>

| #   | Branch             | PR  | Tasks      | Owner      | Status       | Head    |
| --- | ------------------ | --- | ---------- | ---------- | ------------ | ------- |
| 1   | checkout/01-schema | #41 | T-01, T-02 | <agent id> | approved     | 1a2b3c4 |
| 2   | checkout/02-api    | #42 | T-03       | <agent id> | fixing: F-2  | 5d6e7f8 |
| 3   | checkout/03-ui     |     | T-04, T-05 | <agent id> | implementing |         |

## Findings

| ID  | Layer | Source     | Finding                               | State            |
| --- | ----- | ---------- | ------------------------------------- | ---------------- |
| F-1 | 1     | review     | Index missing on `orders.user_id`     | fixed in 9a8b7c6 |
| F-2 | 2     | CI run 123 | `api::tests::refund` fails on Windows | sent to owner    |
```

Statuses: `implementing`, `pr-open`, `in-review`, `fixing: F-n`, `blocked-on: <layer>`, `approved`. When a layer gets a new owner, keep the old id in a note beside the row.

## Layer brief

Fill in every field. The agent starts with no knowledge of the conversation.

```text
You are the owner of layer <N> of a stack of pull requests that implements <plan>. Other agents own the layers below and above yours. You may be resumed later to change this layer, so keep what you learn about it.

Worktree: <path>. Work only there, and only on your branch.
Trunk: <main>. Your branch: <branch>. It goes on top of <parent branch> (layer <N-1>), or on the trunk for layer 1.
Tasks: <the plan's text for these tasks, or the plan's path and section>.
Context from the layers below: <their PR numbers and one line each; read their PR bodies with gh pr view>.
Repository rules: <instruction files to read, checks to run, tool wrappers such as a gh wrapper, constraints>.

Do:
1. Create the branch: gh stack init --base <trunk> <branch> (layer 1), or gh stack top, then gh stack add <branch>.
2. Implement the tasks. Run the narrowest local checks that prove them. Don't wait for CI.
3. Commit with messages that follow the repository's conventions.
4. Run gh stack submit --auto, then gh pr edit <number> --title "<title>" --body-file <file>. The body says what changed, why, how you verified it, where you deviated from the plan, and what later layers must know.
5. Report and end your turn.

Never run gh stack commands without their non-interactive arguments (view --json, submit --auto, merge <PR> --yes), never merge, and never push with --force outside gh stack.
If a lower layer is wrong, commit your work in progress, report "blocked-on: layer <K>" with the evidence, and stop.
If a task needs a decision the plan doesn't make, report it as a question and stop.

Report: PR number and URL, head SHA, checks run and their results, deviations, open questions.
```

## Fix message to an owner

```text
Layer <N> (<branch>, PR #<n>) needs changes.
Findings: <F-ids, each with its evidence: review text, failing test, CI log excerpt>.
Since your last turn: <for example "layer 2 changed the Order type in 4e5f6a7">.

Do: gh stack checkout <branch>, fix and commit, run the checks that prove the fix, gh stack rebase --upstack, gh stack push, gh stack top.
If the rebase stops on a conflict in a higher layer's code: resolve it if the resolution is obvious; otherwise run gh stack rebase --abort and report the conflict.
Update the PR body if the change affects what later layers rely on.
Report: new head SHA, checks run, anything still open.
```

## Review brief

```text
Review layer <N> of a stack of pull requests, read-only. Don't edit files and don't check out branches.
Diff: git diff <parent branch>..<branch>, in the worktree <path>. PR: #<n>; read its body with gh pr view <n>.
Tasks it must implement: <the plan's text>.
Check correctness against the tasks, tests that would catch a plausible regression, and the repository's rules in <files>.
Report each finding with file, line and evidence, and a severity: must-fix or optional. Say "no findings" if there are none.
```

For the final review over the whole stack, use `git diff <trunk>..<top branch>` and ask about the seams: interfaces one layer defines and another uses, code an earlier layer added that a later one made obsolete, and docs or changelog entries that disagree.
