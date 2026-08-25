<!-- markdownlint-disable-file -->
# RPI Plan: Entra ID Group and PIM Role Assignment Deployment

## Task Metadata

* Task ID: entra-pim-group-role-deployment
* Task slug: entra-pim-group-role-deployment
* Planning status: revised
* Plan date: 2026-08-24
* Phase details: .copilot-tracking/details/2026-08-24/entra-pim-group-role-deployment-phase-details.md
* Plan critique: .copilot-tracking/reviews/plans/2026-08-24/entra-pim-group-role-deployment-plan-critique.md

## Executive Summary

This plan implements TR-010 (Entra ID group-based role assignment model) and the PIM portion of TR-006 (access restriction and least privilege) from the demo subscription technical requirements. It creates two Entra ID security groups — **Demo Contributors** and **Demo Readers** — and configures the Azure RBAC role assignments each group needs, with the Contributor assignment made PIM-eligible (not standing) and capped at a 10-hour maximum activation with no owner/admin approval required to activate.

### User Decisions and Requirements Highlights

* Only the subscription owner may hold standing Owner/Contributor/Administrator access; all other privileged access must be least-privilege, PIM-activated, and capped at 10 hours with no approval gate — this plan is the deployment vehicle for that rule via group-based PIM eligibility rather than per-user assignments.
* Two groups are required: Demo Contributors (create/manage resources such as networking, VMs, Key Vault) and Demo Readers (query/read only) — see [Entra ID group-based role assignment model (TR-010)](../../../docs/project-planning/azure-demo-subscription-technical-requirements.md).

### What You May Not Know

* Azure Resource Manager/Bicep can declaratively grant **PIM eligibility** (`Microsoft.Authorization/roleEligibilityScheduleRequests`), but the **PIM policy** that sets the 10-hour maximum activation duration and removes the approval requirement (`Microsoft.Authorization/roleManagementPolicies`) has limited native Bicep/ARM template support as of the latest published schema (`2024-09-01-preview` exposes only the resource name, not the `rules` payload). Configuring that policy is expected to require a direct Azure REST API call (for example through an ARM `deploymentScript` resource, Azure CLI/PowerShell, or Microsoft Graph) rather than pure declarative Bicep properties. This plan accounts for that gap as a phase boundary rather than treating it as a blocker.
* The existing `policy/policyDefinitions/deny-standing-privileged-role-assignments.json` custom Azure Policy already denies standing Owner/Contributor/User Access Administrator role assignments except for principals listed in its `allowedOwnerPrincipalIds` parameter. This plan's Demo Contributors group must receive an **eligible** (PIM) assignment, not a **standing/active** assignment, or it will trip that existing policy once its effect is set to `Deny`.

### Unresolved Decisions or Blockers

* None currently blocking. One assumption is recorded under Unresolved Items in phase details P03: the exact deployment mechanism for the PIM policy update (deployment script vs. manual one-time portal/PowerShell configuration) is deferred to implementation-time evidence gathering, since evidence confirms the target API exists but not a single canonical IaC pattern.
* This plan was revised once against a completed critique (verdict: Revise); all 5 findings (PC-001–PC-005) were planner-applicable directly and have been resolved in this revision — see Critique Disposition.

For current user input, see [User Decisions and Requirements](#user-decisions-and-requirements). The planner keeps the synthesized sections below current as evidence and user direction evolve.

## User Decisions and Requirements

* Only the subscription owner may have standing Owner/Contributor/Administrator access to the demo subscription; all other privileged access must be least-privilege and time-bound (source: BRD business rules BR-006–BR-008, technical requirement TR-006).
* Privileged access must be granted through Azure PIM just-in-time activation, active for no more than 10 hours per activation request, with no owner/admin approval required to activate — only a time limit is enforced (source: user input, "The PIM account can be active for 10 hours at each request. No owner or admin approval needed to activate a privileged role, only a time limit is set.").
* Access must be managed through two Entra ID security groups rather than individual user role assignments (source: user input, "a group should be used for users who will be contributors to the subscription... There should be another group of users who can query and read resources").
* The Demo Contributors group is for users who create Azure resources such as network, VMs, and Key Vault, and needs the role assignment(s) required for that (source: user input; synthesized as TR-010 in docs/project-planning/azure-demo-subscription-technical-requirements.md).
* The Demo Readers group is for users who query and read resources in the subscription, and needs the role assignment(s) required for that (source: user input; synthesized as TR-010).
* This task is scoped to producing an implementation plan for deploying the Entra ID groups and their role assignments, including the PIM requirement for the roles (source: user input, rpi-plan invocation arguments: "Create an implementation plan for the deployment of Entra ID group and role assignments. Include the PIM requirement for the roles").

## Goals

* Stand up the Demo Contributors and Demo Readers Entra ID security groups as the sole mechanism for granting subscription access, replacing any direct per-user role assignment approach.
* Assign the Demo Contributors group the Contributor role at subscription scope as a PIM-eligible (not standing) assignment.
* Assign the Demo Readers group the Reader role at subscription scope as a standing assignment, since Reader carries no write/delete capability and is not subject to the standing-access restriction.
* Configure the PIM role settings for the Demo Contributors group's Contributor eligibility so that activation is capped at a 10-hour maximum duration and does not require owner/admin approval.
* Keep the deployed groups and role assignments consistent with the existing `policy/policyDefinitions/deny-standing-privileged-role-assignments.json` custom policy so the demo subscription's Azure Policy guardrails and its access model do not conflict.

## Scope and Non-Goals

### In Scope

* Creating the Demo Contributors and Demo Readers Entra ID security groups (definition of required attributes: name, description, group type, membership type).
* Inventorying existing direct (per-user) Reader and Contributor role assignments at subscription scope and remediating or documenting any that conflict with the group-only access model.
* Defining and deploying the Azure RBAC role assignment(s) for each group at subscription scope (Contributor for Demo Contributors; Reader for Demo Readers).
* Defining and deploying the Demo Contributors group's role assignment as a PIM-eligible assignment rather than a standing/active assignment.
* Configuring the PIM role management policy governing that eligible assignment: maximum activation duration of 10 hours, no required approval to activate.
* Confirming whether the `deny-standing-privileged-role-assignments` policy is currently assigned to the demo subscription and reconciling this access model with the `allowedOwnerPrincipalIds` parameter carried by that deployed assignment so the subscription owner's standing access remains the only exempted principal.
* Producing evidence-based phase detail for the above so implementation can proceed without re-deriving the access model from scratch.

### Non-Goals

* Deploying or modifying the Azure Policy artifacts under `policy/` beyond what is needed to keep them consistent with this access model (no new policy definitions are introduced by this plan).
* Configuring group membership (adding specific named users to Demo Contributors or Demo Readers) — this plan defines the groups and their role assignments, not ongoing membership management.
* Implementing the budget alerting (TR-003), auto-shutdown/cleanup automation (TR-004/TR-005), or governance workbook (TR-008/TR-009) requirements — those remain separate, unplanned technical requirements.
* Extending PIM eligibility or custom activation policy to any role other than the Demo Contributors group's Contributor role and the Demo Readers group's Reader role.
* Production or non-demo subscription rollout.

## Functional Requirements

* The solution creates two Entra ID security groups, Demo Contributors and Demo Readers, that are usable as Azure RBAC role-assignment principals.
  * Observable acceptance criteria: Both groups exist in Entra ID with a security-enabled group type and are visible as assignable principals when creating an Azure role assignment at the subscription scope.
* The Demo Contributors group receives the built-in Contributor role at subscription scope as a PIM-eligible assignment.
  * Observable acceptance criteria: The subscription's PIM "Eligible assignments" (or equivalent `roleEligibilityScheduleRequests`/`roleEligibilityScheduleInstances`) list shows the Demo Contributors group eligible for Contributor at subscription scope, and no corresponding standing/active Contributor assignment exists for that group outside of an activated PIM session.
* The Demo Readers group receives the built-in Reader role at subscription scope as a standing (active) assignment.
  * Observable acceptance criteria: A `Microsoft.Authorization/roleAssignments` resource exists granting the Demo Readers group the Reader role at subscription scope, visible immediately without a PIM activation step.
* A member of the Demo Contributors group can activate their eligible Contributor role for up to 10 hours without requiring approval from the subscription owner or another administrator.
  * Observable acceptance criteria: The PIM role settings (role management policy) for the Contributor role assignment tied to the Demo Contributors group show `Activation: maximum duration = 10 hours` and `Require approval to activate = No`.
* Deployed role assignments for both groups remain compatible with the existing `deny-standing-privileged-role-assignments` custom Azure Policy definition in `policy/policyDefinitions/deny-standing-privileged-role-assignments.json`.
  * Observable acceptance criteria: A policy compliance scan against the demo subscription shows no non-compliant resource for the Demo Contributors or Demo Readers role assignments when that policy's effect is set to `Deny` or `Audit`, once the policy's assignment/deployment status has been confirmed.
* No direct (per-user) Reader or Contributor role assignment remains at subscription scope outside the Demo Contributors and Demo Readers group assignments, so contributor and reader access is granted exclusively through the two groups.
  * Observable acceptance criteria: An inventory of subscription-scope role assignments shows only the Demo Contributors group (PIM-eligible Contributor), the Demo Readers group (standing Reader), and the subscription owner as holders of Reader/Contributor/Owner-tier access; any prior direct per-user assignment has been removed or explicitly documented as an approved, time-limited exception.

## Non-Functional Requirements

* Group-based access management must reduce ongoing operational effort compared to per-user role assignments.
  * Objective threshold or evaluation condition: Adding or removing a user's subscription access is achievable by changing only Entra ID group membership, without creating or deleting an Azure role assignment.
  * Observable acceptance criteria: A test user added to the Demo Contributors or Demo Readers group inherits the group's role assignment without any additional role-assignment operation at the subscription scope.
* The PIM eligibility and policy configuration must be auditable.
  * Objective threshold or evaluation condition: PIM eligibility and activation history for the Demo Contributors group's Contributor role is visible in Entra ID PIM audit history or Azure Activity Log.
  * Observable acceptance criteria: An activation event for the Demo Contributors group's Contributor role appears in the PIM audit log with a timestamped start and a 10-hour-or-less expiration.
* The deployment approach should use the correct mechanism for each Azure/Entra ID surface, favoring declarative infrastructure-as-code where the current API supports it, and clearly documenting any step that cannot be expressed declaratively.
  * Objective threshold or evaluation condition: Role assignment and role-eligibility configuration (`Microsoft.Authorization/roleAssignments`, `Microsoft.Authorization/roleEligibilityScheduleRequests`) are expressed as ARM/Bicep resources; Entra ID group creation is expressed through the Microsoft Graph API surface (for example the Microsoft Graph Bicep extension or an equivalent Graph-based deployment) since Entra ID groups are not Azure Resource Manager resources; any PIM policy step (10-hour maximum duration, no-approval rule) that cannot currently be expressed declaratively is explicitly documented as a deployment-time decision between a scripted and a manual/PowerShell mechanism.
  * Observable acceptance criteria: Phase details name the exact mechanism used for group creation (Graph-based) and role assignment/eligibility (ARM/Bicep-based); the PIM policy configuration step (P03) is recorded as an explicit implementation-time decision point rather than left silently unspecified.

## Acceptance Criteria

* Demo Contributors and Demo Readers Entra ID security groups exist and are documented with their intended membership purpose.
* No direct per-user Reader or Contributor role assignment remains at subscription scope outside the two group assignments and the subscription owner; any pre-existing direct assignment has been inventoried and either removed or explicitly documented as an approved exception.
* Demo Contributors group holds a PIM-eligible Contributor role assignment at subscription scope; no standing Contributor assignment exists for that group.
* Demo Readers group holds a standing Reader role assignment at subscription scope.
* The Demo Contributors group's PIM role policy enforces a 10-hour maximum activation duration and does not require approval to activate.
* The demo subscription's deployed policy assignment status for `deny-standing-privileged-role-assignments` (or the initiative that contains it) is confirmed, and once confirmed, the access model is reconciled with the `allowedOwnerPrincipalIds` parameter carried by that deployed assignment so the subscription owner remains the only principal exempt from the standing-access restriction.
* Phase details record the exact deployment mechanism for every task (ARM/Bicep resource, Microsoft Graph-based resource, or an explicitly flagged deployment-time decision between a scripted and a manual/PowerShell mechanism for the PIM policy step), with no task left silently unspecified.

## Implementation Context Record

| Context item                     | Current artifact or record                                                                                                               |
|-----------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------|
| Plan                              | .copilot-tracking/plans/2026-08-24/entra-pim-group-role-deployment-plan.md                                                                |
| Phase details                     | .copilot-tracking/details/2026-08-24/entra-pim-group-role-deployment-phase-details.md                                                    |
| Latest critique                   | .copilot-tracking/reviews/plans/2026-08-24/entra-pim-group-role-deployment-plan-critique.md — Revise verdict; all 5 findings resolved directly by the planner |
| Relevant research                 | Not applicable — evidence gap closed with two targeted lookups (Microsoft Learn: roleManagementPolicies, roleEligibilityScheduleRequests) recorded directly in this plan; no separate research artifact was required |
| Changes-record role               | .copilot-tracking/changes/2026-08-24/entra-pim-group-role-deployment-changes.md is created or continued by implementation as its evidence record |
| Planning execution and readiness  | Revised after one critique run (Revise verdict, all 5 findings resolved directly) — implementation-ready                                    |
| Continuation context               | Standalone invocation — advise `/rpi-implement` only once this plan reaches an implementation-ready, critiqued state                       |

## Sources

* docs/project-planning/azure-demo-subscription-cost-control-brd.md: Source of BR-006–BR-009 (no standing non-owner access, PIM JIT, 10-hour activation, no-approval activation) and BG-006/NFR-001 ($0-cost-after-cleanup context for the broader environment).
* docs/project-planning/azure-demo-subscription-technical-requirements.md: Source of TR-006 (access restriction and least privilege) and TR-010 (Entra ID group-based role assignment model), which this plan directly implements.
* policy/policyDefinitions/deny-standing-privileged-role-assignments.json: Existing custom Azure Policy that declares the `allowedOwnerPrincipalIds` parameter schema and denies standing Owner/Contributor/User Access Administrator assignments except for principals listed in that parameter; this plan's group-based PIM-eligible assignment must remain compliant with it.
* policy/policyAssignments/demo-environment-cost-governance-assignment.json: Authoritative source for the deployed `allowedOwnerPrincipalIds` parameter value and the policy's assigned effect/scope; P04-T01 confirms this deployment state before the P04-T02 compliance scan.
* policy/README.md: Notes that "the actual just-in-time activation duration, approval requirements, and eligible-role configuration are set in Microsoft Entra Privileged Identity Management (PIM) role settings, which is an Entra ID configuration, not an Azure Resource Manager policy" — confirms this plan's scope is the correct location for that configuration.
* Microsoft Learn, Microsoft.Authorization/roleManagementPolicies template reference (https://learn.microsoft.com/en-us/azure/templates/microsoft.authorization/rolemanagementpolicies): Confirms the resource type exists but the published Bicep/ARM schema (2024-09-01-preview) exposes only `name`, not a `rules` property, informing the P03 boundary and assumption about needing a non-declarative or scripted mechanism for the activation-duration/approval policy.
* Web search evidence (Microsoft Q&A and Microsoft Learn PIM API concepts): Confirms `Microsoft.Authorization/roleEligibilityScheduleRequests` is usable in Bicep/ARM to grant PIM eligibility, while maximum activation duration and approval-requirement policy settings are commonly configured via PowerShell/Microsoft Graph or the Portal rather than plain Bicep properties.

## Phase Checklist

<!-- rpi:phase id=P01 -->
### [ ] P01: Define and provision the Entra ID security groups

* Intent: Create the Demo Contributors and Demo Readers Entra ID security groups that will serve as the sole principals for subscription role assignments.
* Dependencies: None

<!-- rpi:task id=P01-T01 -->
#### [ ] P01-T01: Define and create the Demo Contributors group

* Requirement and evidence: TR-010 Demo Contributors group definition in docs/project-planning/azure-demo-subscription-technical-requirements.md
* Expected result: A security-enabled Entra ID group named to reflect its Demo Contributors purpose exists and is ready to receive a role assignment.
* Detail section: P01-T01 in .copilot-tracking/details/2026-08-24/entra-pim-group-role-deployment-phase-details.md

<!-- rpi:task id=P01-T02 -->
#### [ ] P01-T02: Define and create the Demo Readers group

* Requirement and evidence: TR-010 Demo Readers group definition in docs/project-planning/azure-demo-subscription-technical-requirements.md
* Expected result: A security-enabled Entra ID group named to reflect its Demo Readers purpose exists and is ready to receive a role assignment.
* Detail section: P01-T02 in .copilot-tracking/details/2026-08-24/entra-pim-group-role-deployment-phase-details.md

<!-- rpi:phase id=P02 -->
### [ ] P02: Deploy the group role assignments

* Intent: Grant each group the Azure RBAC role(s) needed for its purpose, with the Demo Contributors assignment expressed as a PIM-eligible assignment and the Demo Readers assignment expressed as a standing assignment.
* Dependencies: P01 (both groups must exist before a role can be assigned to them)

<!-- rpi:task id=P02-T01 -->
#### [ ] P02-T01: Assign the Demo Readers group a standing Reader role at subscription scope

* Requirement and evidence: TR-010 Demo Readers group required role assignment in docs/project-planning/azure-demo-subscription-technical-requirements.md
* Expected result: A `Microsoft.Authorization/roleAssignments` resource grants the Demo Readers group the built-in Reader role at subscription scope, active immediately without PIM activation.
* Detail section: P02-T01 in .copilot-tracking/details/2026-08-24/entra-pim-group-role-deployment-phase-details.md

<!-- rpi:task id=P02-T02 -->
#### [ ] P02-T02: Assign the Demo Contributors group a PIM-eligible Contributor role at subscription scope

* Requirement and evidence: TR-010 Demo Contributors group required role assignment, TR-006 (privileged access is PIM-eligible, not standing) in docs/project-planning/azure-demo-subscription-technical-requirements.md
* Expected result: A `Microsoft.Authorization/roleEligibilityScheduleRequests` resource (or equivalent) makes the Demo Contributors group eligible for the built-in Contributor role at subscription scope; no standing Contributor assignment is created for that group.
* Detail section: P02-T02 in .copilot-tracking/details/2026-08-24/entra-pim-group-role-deployment-phase-details.md

<!-- rpi:task id=P02-T03 -->
#### [ ] P02-T03: Inventory and remediate existing direct Reader/Contributor role assignments

* Requirement and evidence: TR-010 (contributor/reader access granted only through the two groups, never through direct per-user role assignments) in docs/project-planning/azure-demo-subscription-technical-requirements.md
* Expected result: A recorded inventory of subscription-scope Reader/Contributor/Owner-tier role assignments confirms that, aside from the subscription owner, only the Demo Contributors group (PIM-eligible Contributor) and the Demo Readers group (standing Reader) hold access; any pre-existing direct per-user assignment is removed or documented as an approved, time-limited exception.
* Detail section: P02-T03 in .copilot-tracking/details/2026-08-24/entra-pim-group-role-deployment-phase-details.md

<!-- rpi:phase id=P03 -->
### [ ] P03: Configure the PIM activation policy for the Demo Contributors role

* Intent: Ensure the Demo Contributors group's eligible Contributor assignment activates for a maximum of 10 hours and does not require owner/admin approval.
* Dependencies: P02-T02 (the eligible assignment must exist before its activation policy is meaningfully scoped)

<!-- rpi:task id=P03-T01 -->
#### [ ] P03-T01: Set the 10-hour maximum activation duration and remove the approval requirement

* Requirement and evidence: User input ("The PIM account can be active for 10 hours at each request. No owner or admin approval needed to activate a privileged role, only a time limit is set."); TR-006 in docs/project-planning/azure-demo-subscription-technical-requirements.md
* Expected result: The role management policy governing the Demo Contributors group's Contributor eligibility shows a 10-hour maximum activation duration and no required approval step. The exact configuration surface (specific rule identifiers and whether it is set via a declarative resource, a deployment script, or a documented manual/PowerShell step) is an implementation-time confirmation item, not a proven detail; only the functional outcome (10-hour cap, no approval) is a fixed requirement.
* Detail section: P03-T01 in .copilot-tracking/details/2026-08-24/entra-pim-group-role-deployment-phase-details.md

<!-- rpi:phase id=P04 -->
### [ ] P04: Reconcile with existing policy guardrails and document the access model

* Intent: Confirm the deployed groups and role assignments remain compliant with the existing `deny-standing-privileged-role-assignments` custom policy and leave a clear record of the final access model for future reference.
* Dependencies: P02, P03

<!-- rpi:task id=P04-T01 -->
#### [ ] P04-T01: Confirm the deployed policy assignment state and the authoritative owner-exemption value

* Requirement and evidence: policy/policyAssignments/demo-environment-cost-governance-assignment.json `allowedOwnerPrincipalIds` parameter (the deployed value; the policy definition only declares the parameter's schema); TR-006 in docs/project-planning/azure-demo-subscription-technical-requirements.md
* Expected result: It is confirmed whether the `deny-standing-privileged-role-assignments` policy (via the `demo-environment-cost-governance` initiative) is currently assigned to the demo subscription and, if so, at what `standingAccessEffect`. If assigned, the assignment's `allowedOwnerPrincipalIds` parameter is confirmed or corrected to list only the current subscription owner. If not yet assigned, this is documented so P04-T02's compliance scan is not assumed to run against a non-existent assignment.
* Detail section: P04-T01 in .copilot-tracking/details/2026-08-24/entra-pim-group-role-deployment-phase-details.md

<!-- rpi:task id=P04-T02 -->
#### [ ] P04-T02: Run the policy compliance scan and document the final access model

* Requirement and evidence: policy/policyDefinitions/deny-standing-privileged-role-assignments.json; TR-006, TR-010 in docs/project-planning/azure-demo-subscription-technical-requirements.md
* Expected result: Once P04-T01 confirms the policy assignment exists, an on-demand compliance scan confirms the Demo Contributors (PIM-eligible) and Demo Readers (standing Reader) assignments are compliant; a short documentation update records the final group/role/PIM state for future reference.
* Detail section: P04-T02 in .copilot-tracking/details/2026-08-24/entra-pim-group-role-deployment-phase-details.md

## Dependencies

* Entra ID tenant administrative access sufficient to create security groups: required before P01 can complete.
* Azure RBAC administrative access (or a temporary elevated/owner assignment) sufficient to create role assignments and PIM eligibility/policy configuration at subscription scope: required before P02 and P03 can complete.
* Read access to the subscription's current role assignments: required before P02-T03 can inventory existing direct assignments.
* Existing `policy/policyDefinitions/deny-standing-privileged-role-assignments.json` custom policy definition and its deployed assignment status: P04-T01 confirms whether and how it is assigned before P04-T02's compliance check is evaluated.
* Confirmed mechanism for configuring PIM role management policy (declarative resource, deployment script, or manual/PowerShell step): needed before P03-T01 can be executed; the exact mechanism is an implementation-time confirmation per the P03 boundary noted in Sources.

## Critique Disposition

Record the latest critique findings, their disposition, and any explicitly accepted residual risk. Keep this section outside user decisions and current planning synthesis.

| Critique run and finding | Disposition | Plan response or residual risk |
|--------------------------|--------------|---------------------------------|
| 2026-08-24 critique, PC-001 (Blocking) | Resolved | Added P02-T03 to inventory existing direct Reader/Contributor role assignments and remediate or document any that conflict with the group-only access model; added a matching functional requirement and acceptance criterion. |
| 2026-08-24 critique, PC-002 (Blocking) | Resolved | Split P04-T01 into a policy-assignment-confirmation task (does the deployment exist, at what effect) and a new P04-T02 for the actual compliance scan, which now explicitly depends on P04-T01's confirmation. |
| 2026-08-24 critique, PC-003 (Significant) | Resolved | Standardized wording so `policy/policyAssignments/demo-environment-cost-governance-assignment.json` is named as the authoritative source for the deployed `allowedOwnerPrincipalIds` value; the policy definition file is now described only as declaring the parameter's schema. |
| 2026-08-24 critique, PC-004 (Significant) | Resolved | Rewrote the declarative-deployment NFR and acceptance criteria to explicitly separate ARM/Bicep-native role assignment and eligibility resources from Microsoft Graph-based group creation and from the PIM policy step, which remains an explicit implementation-time decision rather than an assumed-declarative step. |
| 2026-08-24 critique, PC-005 (Significant) | Resolved | Softened P03/P03-T01 language so exact PIM policy rule identifiers and configuration surface are framed as an implementation-time confirmation item, while keeping the 10-hour maximum duration and no-approval outcome as the fixed, settled requirement. |

## Follow-Up Items

* Ongoing Demo Contributors/Demo Readers group membership management (adding/removing specific users) is out of scope for this plan and is a follow-up operational task for the subscription owner once the groups exist.
* Reconciling the remaining unimplemented technical requirements (TR-003 budget alerts, TR-004/TR-005 auto-shutdown and cleanup automation, TR-008/TR-009 governance workbook) remains a separate follow-up planning task not covered here.

## Handoff

* Implementation artifact: .copilot-tracking/changes/2026-08-24/entra-pim-group-role-deployment-changes.md
* Ready phase or task: P01-T01 (plan is critiqued and revised; implementation may proceed with `/rpi-implement`)
* Remaining provisional question or blocker: None — the P03 PIM-policy deployment mechanism (declarative resource vs. deployment script vs. manual/PowerShell step) remains an explicit implementation-time confirmation item, not a blocker.
