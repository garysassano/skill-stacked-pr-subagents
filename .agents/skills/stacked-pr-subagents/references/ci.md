# CI for a stack

GitHub runs a workflow that triggers on `pull_request` for every PR in a stack, as if each PR targeted the stack's base branch. Merging a PR also requires every PR below it to pass the base branch's required checks. Left as it is, a stack of eight layers runs the full suite eight times on every push that moves the stack.

The top PR contains every layer, so the full suite only needs to run there. GitHub exposes stack metadata in workflow expressions as `github.event.pull_request.stack`: `position` (1 is the bottom) and `size`. The property is `null` for a PR that isn't in a stack.

## Gate the expensive jobs

Run a job when the event isn't a pull request, when the PR isn't stacked, or when it is the top of its stack:

```yaml
jobs:
  test:
    if: >-
      github.event_name != 'pull_request' ||
      github.event.pull_request.stack == null ||
      github.event.pull_request.stack.position == github.event.pull_request.stack.size
```

The PRs below the top then show `test` as skipped. A skipped check counts as passing for required status checks, so they can still merge as part of the stack.

Keep fast checks such as format and lint ungated, so each layer still gets quick feedback.

## Matrix jobs

A job-level `if` is evaluated before a matrix expands. A skipped matrix job therefore posts one check under its unexpanded name, such as `check (${{ matrix.os }})`, and the per-leg checks a ruleset requires, such as `check (ubuntu-latest)`, never appear. The PR then waits on "Expected" forever.

Before gating a matrix job, look at which checks the base branch requires:

```sh
gh api repos/OWNER/REPO/rules/branches/main --jq '.[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context'
gh api repos/OWNER/REPO/branches/main/protection/required_status_checks --jq '.contexts[]'
```

The second command fails with 404 when the branch has no classic protection; that is fine.

- If no matrix leg is required, gate the job as above.
- If legs are required, either move the condition onto each step so the matrix still expands and every leg posts a fast green check, or require one aggregator job instead of the legs: a job with `needs: [test]` and `if: always()` that fails when any leg failed.

## Order of work

A PR's runs use the workflow files on its own branch. Put the gate in the first layer of the first stack that uses it, or in a separate PR merged before the stack starts. Changing a repository's CI needs the user's approval.

## Sources

- [Stacked pull requests: GitHub Actions](https://docs.github.com/en/pull-requests/reference/stacked-pull-requests#github-actions)
- [Optimizing CI for stacked pull requests](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/optimizing-ci-for-stacked-pull-requests)
- [Troubleshooting required status checks](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks): "Successful check statuses are success, skipped, and neutral."
- [A skipped matrix job never posts the checks you required](https://x-gis.github.io/X-GIS/blog/2026-07-08-required-check-never-ran/)
