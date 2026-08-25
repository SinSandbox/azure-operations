# Plan Critique: Entra ID Group and PIM Role Assignment Deployment

## Verdict
Revise

## Findings

### PC-001: Group-only access model is not fully planned
* Location: Plan `## Goals`, `## Functional Requirements`, `## Acceptance Criteria`, and `## Phase Checklist` (P01-P04); details P01-P04
* Severity: Blocking
* Description: The plan says the Demo Contributors and Demo Readers groups become the sole mechanism for subscription access, and TR-010 requires contributor/read access to be granted only through those groups rather than direct per-user assignments. However, no phase or task inventories existing direct Reader/Contributor assignments, removes or replaces them, or records evidence that none exist. P04-T01 only checks compatibility with the standing-privileged-access policy, which would not detect direct Reader assignments and does not prove the broader group-only access requirement.
* Owner/disposition: planner-applicable directly
* Resolving evidence or recommended correction: Add an explicit task and acceptance check to query current subscription role assignments, remove or replace any direct per-user Reader/Contributor access that conflicts with TR-010, or record evidence that no such assignments exist. Resolution evidence should be a role-assignment inventory or equivalent proof showing group-based access only for the in-scope reader/contributor paths.

### PC-002: P04 depends on an unconfirmed deployed policy assignment state
* Location: Plan `## Dependencies`; plan P04/P04-T01; details P04 `### Unresolved Items`; details P04-T01 `#### Unresolved Items`
* Severity: Blocking
* Description: The critique boundary includes a runtime compliance check against `deny-standing-privileged-role-assignments`, but the supplied evidence confirms only a policy definition artifact and an assignment template. The phase details explicitly say it is not confirmed whether that policy is already assigned to the demo subscription. No plan task resolves that prerequisite, yet P04-T01 assumes the compliance scan can be run after P02/P03.
* Owner/disposition: planner-applicable directly
* Resolving evidence or recommended correction: Add a prerequisite or task to confirm the deployed initiative/policy assignment, its scope, and the effective `standingAccessEffect` before the compliance scan runs; or split P04-T01 into (a) artifact-level parameter review and (b) runtime compliance validation only when the assignment exists. Resolution evidence should identify the deployed assignment or explicitly add the step needed when it is absent.

### PC-003: The authoritative `allowedOwnerPrincipalIds` update target is described inconsistently
* Location: Plan P04-T01 in `## Phase Checklist`; details P04 `### Likely Targets`; details P04-T01 `#### Likely Targets`
* Severity: Significant
* Description: The plan checklist frames `policy/policyDefinitions/deny-standing-privileged-role-assignments.json` as the relevant parameter target, but the phase details later clarify that `allowedOwnerPrincipalIds` is populated at assignment time in `policy/policyAssignments/demo-environment-cost-governance-assignment.json`. This leaves the authoritative update point ambiguous and could send implementation to the wrong artifact.
* Owner/disposition: planner-applicable directly
* Resolving evidence or recommended correction: Standardize the plan and details so they clearly distinguish between the definition declaring the parameter schema and the policy assignment carrying the effective value. Resolution evidence is consistent wording across P04/P04-T01 that names the assignment artifact or deployed assignment parameter as the authoritative exemption-value source.

### PC-004: Deployment-mechanism acceptance language conflicts with the plan's own Graph/IaC boundary
* Location: Plan `## Non-Functional Requirements` (declarative deployment criterion) and `## Acceptance Criteria`; details P01 `### Likely Targets`; details P03 `### Unresolved Items`
* Severity: Significant
* Description: The plan correctly notes in P01 that Entra ID group creation is a Microsoft Graph operation rather than an Azure Resource Manager resource under `Microsoft.Authorization` or `Microsoft.Resources`. But the plan's non-functional criterion says group creation and role-eligibility assignment should be expressed as Bicep/ARM resources, and the acceptance criteria require the exact mechanism for every task with no unresolved ambiguity even though P03 deliberately defers the PIM-policy mechanism. That creates an internal inconsistency and under-communicates the non-ARM nature of group creation.
* Owner/disposition: planner-applicable directly
* Resolving evidence or recommended correction: Rewrite the deployment-mechanism criterion so it distinguishes ARM-native, Microsoft Graph-based, and documented manual/deferred steps explicitly, and align the acceptance criteria with the caller-accepted P03 decision point. Resolution evidence is a consistent statement across the plan and details that group creation is Graph-based and the P03 mechanism remains an intentional implementation-time decision rather than an unmet blocker.

### PC-005: P03 overstates confirmed PIM policy targeting and mechanism certainty
* Location: Plan `### What You May Not Know`; details P03 `### Intent` and `### Likely Targets`; details P03-T01 `#### Intent` and `#### Likely Targets`
* Severity: Significant
* Description: The P03 language presents the PIM policy as though it can be configured specifically for the Demo Contributors group's eligible assignment and names concrete rule types and implementation paths as effectively confirmed. Based on the supplied repository evidence, the stronger, directly supported claim is narrower: the target APIs/resource types are part of the implementation hypothesis, but the exact policy-assignment granularity and supported mechanism are still being deferred to implementation-time confirmation. The current phrasing risks overstating what has been proven from the available evidence.
* Owner/disposition: planner-applicable directly
* Resolving evidence or recommended correction: Rephrase P03 and P03-T01 so they describe the rule names, assignment granularity, and specific API path as implementation-time confirmation items unless tied to explicit cited evidence. Resolution evidence is wording that preserves the caller's fixed outcome (10-hour cap, no approval) while clearly labeling the exact configuration surface as a confirmed-later implementation detail.

## Summary
The plan is close on intent and phase/task ID consistency, and it correctly preserves the caller's decisions around group-based access, PIM eligibility, and the intentionally deferred PIM-policy deployment mechanism. It still needs revision before it is credible for implementation because it does not yet plan the full transition to a group-only access model, and its policy-validation phase depends on an unconfirmed deployed-policy prerequisite. The remaining issues are planner-fixable consistency and evidence-precision corrections around `allowedOwnerPrincipalIds`, Graph versus ARM deployment boundaries, and how confidently the P03 PIM-policy surface is described.
