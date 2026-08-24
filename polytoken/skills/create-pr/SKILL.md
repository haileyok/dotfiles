---
description: Create a consistently structured draft GitHub pull request for the current repository with gh.
polytoken:
  tags: [git, github, release]
---

# Create a draft PR

Use this skill when the requesting agent wants the current repository changes opened as a **draft** GitHub pull request. Use the `gh` command-line tool for GitHub operations; do not substitute a browser workflow or claim success without verifying the created PR.

## Preconditions and repository inspection

1. Confirm the working directory is the intended project repository. Inspect `git status --short --branch`, the current branch, the remote, the commit range, and the diff. Also inspect relevant test/build results and project guidance so the PR description is factual.
2. Refuse to create a PR from a detached HEAD, an empty change set, or a branch that is the repository's default branch. Do not include secrets, credentials, generated local state, or unrelated changes; stop and ask for clarification when the change set is mixed or unsafe.
3. Check for an existing PR for the current head branch before creating another one, for example with `gh pr list --head <branch> --state all`. If one exists, report it rather than creating a duplicate.
4. Confirm GitHub access and repository identity with `gh repo view`. If authentication, repository permissions, or the remote configuration prevents the operation, report the exact blocker and do not pretend that a PR was created.

## Prepare the branch

- Determine the base branch from the repository rather than assuming `main` (for example, `gh repo view --json defaultBranchRef --jq .defaultBranchRef.name`).
- Ensure all intended commits are present on the current branch and push it to its configured remote with `git push -u origin HEAD` when needed. Never force-push as part of this skill. If pushing would overwrite someone else's work or the remote is not `origin`, stop and ask before proceeding.
- Recheck the final remote commit and diff after pushing. The PR head must be the current branch, not a temporary or unrelated local ref.

## Stable PR structure

Write the body using this exact section order on every PR:

```markdown
## Summary
- <What changed and why, in one to three bullets.>

## Changes
- <Important implementation or behavior changes.>
- <Include notable API, migration, configuration, or compatibility details.>

## Validation
- <Commands/tests actually run and their results.>
- <If not run, write: `Not run — <specific reason>`.>

## Review notes
- <Known limitations, follow-ups, risks, or reviewer focus areas.>
- <If none, write: `None known.`>
```

Keep the title concise, imperative or outcome-oriented, and specific to the change. Derive every bullet from inspected repository state. Never invent test results, reviewer approvals, issue links, or behavior that was not verified. Keep unrelated discussion out of the body.

## Create and verify the draft

1. Create the PR with `gh pr create` and the `--draft` flag, supplying the explicit base, current head, title, and body (a temporary `--body-file` is preferred for Markdown fidelity). Do not use a command that omits `--draft`.
2. Capture the URL printed by `gh`.
3. Verify it with `gh pr view <url-or-number> --json isDraft,url,title,baseRefName,headRefName,state`. Confirm that `isDraft` is `true`, the base/head are correct, and the PR is open. If verification fails, report the failure and its output.
4. Return the PR URL plus the final title, base/head, draft status, and a short summary of the validation recorded in the body.

A successful result means the PR was actually created and verified as a draft. A push or `gh pr create` error is not success; preserve the error details and leave the repository in its existing non-destructive state.
