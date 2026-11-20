---
description: Deploy Attie to production through the bluesky-social/deploy GitHub Actions workflow, keeping all active POP1 Attie services on one SHA.
polytoken:
  tags: [deploy, attie, production, github, argocd]
---

# Deploy Attie

Use this skill when asked to deploy Attie to production. This is a live production operation: execute it deliberately, report the exact SHA and workflow run, and do not call it complete until both the GitHub workflow and the GitOps rollout have been checked.

## Default deployment policy

Deploy one Attie SHA to **every active POP1 Attie service** so their images remain aligned:

- `attie-api`
- `attie-embed`
- `attie-ingest-v2`
- `attie-ui`
- `attie-worker`

The default SHA is the latest `origin/main` from `~/bluesky/attie`. Accept a specific full commit SHA or release tag only when the requester explicitly asks for it. Record which source was used.

The production `deploy-attie.yaml` workflow on `bluesky-social/deploy` main enables all five update flags by default. Its ingest input updates the active `attie-ingest-v2` POP1 live tail. The suspended backfill workload is intentionally outside the routine image deployment; that is not a reason to omit `attie-ingest-v2` itself.

Do not selectively omit any of these five services unless there is a concrete, stated reason (for example, an emergency rollback limited to one component, an unavailable image, or an explicit requester instruction). Say which service is excluded and why before dispatching.

## 1. Start by synchronizing the deploy workflow from `main`

The workflow definition itself must be current before using it.

1. Inspect `~/bluesky/deploy` status and current branch. Do not discard or overwrite someone else's work.
2. Fetch the latest remote main:

   ```bash
   git -C ~/bluesky/deploy fetch origin main
   ```

3. If the deploy checkout is clean and already on `main`, fast-forward it:

   ```bash
   git -C ~/bluesky/deploy pull --ff-only origin main
   ```

   If it is on another branch, dirty, or cannot be safely switched, leave it untouched. Create a temporary detached worktree from the freshly fetched main revision instead, inspect the workflow there, and remove the worktree after the deployment. The GitHub dispatch must use `--ref main`, so the remote main workflow definition is what runs.
4. Read `.github/workflows/deploy-attie.yaml` from that current main revision. Confirm it still has a `workflow_dispatch` trigger; the `tag` input; all five update inputs; `update_ingest` defaulting to `true`; the `apps/attie-ingest-v2/values-pop1.yaml` path; and the `validate-overlays` job. If the workflow or its safety behavior changed, stop and explain the discrepancy rather than guessing its inputs.

## 2. Resolve and verify the Attie source SHA

For the default deployment, fetch Attie main and use its exact SHA:

```bash
git -C ~/bluesky/attie fetch origin main
tag="$(git -C ~/bluesky/attie rev-parse origin/main)"
printf 'Deploying Attie SHA: %s\n' "$tag"
```

For an explicitly requested SHA or tag, resolve it to the exact commit and report both the supplied value and resolved SHA. Do not silently substitute the current local HEAD, which may contain unpushed work. Check that GitHub Actions can access the target image or source revision; if it cannot, do not begin a partial deployment.

## 3. Dispatch the deploy workflow with the aligned service set

Run this from the current deploy-main checkout (or use `--repo` explicitly). Dispatch the workflow on remote `main` and set every active service flag explicitly:

```bash
gh workflow run deploy-attie.yaml \
  --repo bluesky-social/deploy \
  --ref main \
  -f tag="$tag" \
  -f update_api=true \
  -f update_embed=true \
  -f update_ingest=true \
  -f update_ui=true \
  -f update_worker=true
```

Capture the workflow-run URL or ID returned by `gh`. Then identify the exact run and wait for it to finish successfully, for example with `gh run watch <run-id-or-url> --exit-status`. Verify the final run details with `gh run view`, including the workflow name, ref, status/conclusion, the successful `validate-overlays` job, and the resulting commit to `bluesky-social/deploy`.

A dispatched workflow, an accepted event, or a green `compute-paths` job is **not** a completed deployment. If the run fails, fetch the failed-job logs with `gh run view <run> --log-failed`, report the failure, and do not claim any component deployed unless the job output proves it.

## 4. Verify GitOps reconciliation and runtime health

The workflow changes POP1 overlay paths in the deploy repository. After the workflow succeeds, verify the real cluster state before declaring success.

1. Use the Argo CD MCP to inspect each updated POP1 Attie application (`attie-api`, `attie-embed`, `attie-ingest-v2`, `attie-ui`, and `attie-worker`):
   - application sync and health status;
   - resource tree and rollout health;
   - relevant events; and
   - workload logs for any Degraded, Progressing, CrashLoopBackOff, or otherwise unhealthy resource.
2. Use `gcx` to inspect the relevant Grafana logs, metrics, and traces after the rollout. Look for new application errors, elevated 5xx/latency, restart loops, ingest lag/failures, or missing traffic compared with the pre-deploy baseline. Kubernetes health alone is insufficient.
3. If reconciliation has not caught up, wait and continue monitoring rather than declaring success. If a component is degraded or runtime signals regress, report the affected service and evidence, then ask before triggering any rollback or another deployment.

## Final report

Report:

- the resolved Attie SHA and whether it was latest `origin/main` or an explicit request;
- each service updated (`api`, `embed`, `ingest-v2`, `ui`, and `worker`) and the reason for any exclusion;
- the GitHub Actions run URL/ID, conclusion, and overlay-validation result;
- Argo sync/health and rollout results per updated application; and
- the `gcx` logs/metrics/traces results, plus any remaining risk.

Do not say the deployment completed when only the GitHub workflow has passed. A successful deployment means the workflow is green, the affected Argo applications are Synced and Healthy, and the post-rollout Grafana signals show no material regression.
