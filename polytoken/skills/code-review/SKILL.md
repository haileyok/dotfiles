---
description: Run a model-independent, iterative code review with two alternate models and classify findings by severity.
polytoken:
  tags: [review, engineering]
---

# Code review

Use this skill when the requesting agent wants an independent review of the current change. The requesting agent remains the decision-maker: reviewer output is evidence to evaluate, not an automatic verdict.

## Select the two review models

The only review model choices are:

- `router/gpt-5.6-sol:api(low)`
- `router/glm-5.2:api(high)`
- `router/kimi-k3:api(high)`

The two reviewers **must be different model types from the requesting agent's current model type**. Use the current model identity exposed in this skill's template context (`model_name`; also consider `model_variant` if the name is abbreviated) to exclude the matching choice:

{% if "gpt-5.6-sol" in model_name | lower or "gpt-5.6-sol" in model_variant | lower %}
- Current type is GPT-5.6-Sol: use `router/glm-5.2:api(high)` and `router/kimi-k3:api(high)`.
{% elif "glm-5.2" in model_name | lower or "glm-5.2" in model_variant | lower %}
- Current type is GLM-5.2: use `router/gpt-5.6-sol:api(low)` and `router/kimi-k3:api(high)`.
{% elif "kimi-k3" in model_name | lower or "kimi-k3" in model_variant | lower %}
- Current type is Kimi-K3: use `router/gpt-5.6-sol:api(low)` and `router/glm-5.2:api(high)`.
{% else %}
- The current type is not one of the three named choices: use `router/gpt-5.6-sol:api(low)` and `router/glm-5.2:api(high)`. Do not use a reviewer that is actually the current type if the runtime identifies it more precisely.
{% endif %}

Never select the current model type as a reviewer. Never use the same model twice. Launch both reviewers in parallel when the subagent tool permits it.

## Review loop

Repeat this complete cycle until the stopping rule below is satisfied:

1. Establish the review scope. Inspect the current repository diff, changed files, relevant surrounding code, tests, and project guidance. Do not review only the patch in isolation when surrounding behavior is needed to determine correctness. Note the base and head commits when useful.
2. Send the same self-contained review brief to each selected model using the `subagent` tool and its `model_override` field. The brief must include the repository/change context, the exact review scope, and these instructions:
   - look for real bugs, regressions, security issues, data loss, compatibility problems, and missing tests;
   - do not make edits;
   - report only actionable findings supported by specific file/line evidence;
   - distinguish definite bugs from questions or style preferences;
   - assign one of `severe`, `high`, `medium`, `low`, or `informational` severity;
   - return: severity, concise title, file and line, explanation, impact, and a concrete fix/test suggestion;
   - explicitly say when no actionable findings exist.
3. Read both responses completely. As the requesting agent, independently verify every finding against the code and requirements. Deduplicate overlapping findings, reject speculative/style-only items, and record disagreements rather than treating model consensus as proof.
4. Present the consolidated findings in descending severity order: severe, high, medium, low, informational. Include the source model(s), exact location, why it is valid or rejected, and the disposition (fix, defer only when the task explicitly permits it, or reject with rationale). Do not hide a valid finding merely because the other model missed it.
5. For each valid finding that the task calls for addressing, make the fix and add or update focused tests where appropriate. If a valid finding is outside the requested scope, state that explicitly; do not silently ignore it.
6. After any code change, rerun the review cycle with both selected models against the updated diff. Tell reviewers which prior findings were addressed and ask them to check for regressions and newly exposed issues. A later cycle must not reuse stale line numbers or an old diff.

## Mandatory continuation and stopping rule

- A `severe` or `high` finding requires continued review iteration. Do not declare the review complete while one remains valid and unaddressed; fix it (or obtain an explicit task-level decision that it is out of scope), then run both reviewers again.
- An unaddressed `medium` finding also cannot be silently left in the final result: address it and rerun, or explicitly determine and document that it is incorrect/out of scope under the task's constraints.
- If a finding is judged incorrect, the requesting agent may stop iterating for that finding, but must give a concrete technical reason. Do not stop just because the models disagree.
- Stop only when the consolidated result has no actionable findings, or contains low/informational findings only, or the requesting agent has explicitly determined the remaining findings are incorrect. Before stopping, make the final severity-ordered report clear and state what was fixed, rejected, or left as a documented low-risk item.

Do not claim that tests, commands, or model reviews ran unless you actually ran or received them. If a reviewer fails or times out, retry that reviewer or clearly report the incomplete review rather than treating the missing response as approval.
