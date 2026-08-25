<!-- markdownlint-disable-file -->
# RPI Phase Details: Entra ID Group and PIM Role Assignment Deployment

## Metadata

* Task ID: entra-pim-group-role-deployment
* Task slug: entra-pim-group-role-deployment
* Related plan: .copilot-tracking/plans/2026-08-24/entra-pim-group-role-deployment-plan.md
* Evidence sources: docs/project-planning/azure-demo-subscription-cost-control-brd.md, docs/project-planning/azure-demo-subscription-technical-requirements.md, policy/policyDefinitions/deny-standing-privileged-role-assignments.json, policy/README.md, Microsoft Learn Microsoft.Authorization/roleManagementPolicies and roleEligibilityScheduleRequests template references

## Phase Index

| Phase ID | Name                                                              | Status      | Detail sections       |
|----------|--------------------------------------------------------------------|-------------|------------------------|
| P01      | Define and provision the Entra ID security groups                  | not_started | P01, P01-T01, P01-T02 |
| P02      | Deploy the group role assignments                                  | not_started | P02, P02-T01, P02-T02, P02-T03 |
| P03      | Configure the PIM activation policy for the Demo Contributors role | not_started | P03, P03-T01          |
| P04      | Reconcile with existing policy guardrails and document the access model | not_started | P04, P04-T01, P04-T02 |

<!-- rpi:phase id=P01 -->
## P01: Define and provision the Entra ID security groups

### Context

TR-010 in docs/project-planning/azure-demo-subscription-technical-requirements.md defines two required Entra ID security groups for the demo subscription: Demo Contributors (resource creators) and Demo Readers (query/read-only users). Both groups must exist as security-enabled groups so they can be used as principals for Azure RBAC role assignments; Microsoft Entra ID supports assigning Azure roles to security groups directly, which is the mechanism this plan relies on to avoid per-user role assignments.

### Intent

Create both groups with clear naming and a description that documents their intended purpose, so that the role assignments in P02 have a stable principal to target and so future administrators understand why each group exists without re-reading the BRD or technical requirements.

### Boundaries

* Included: Defining group name, description, group type (security), and membership type (assigned) for both groups; creating both groups in Entra ID.
* Excluded: Populating group membership with specific named users; configuring group-based licensing or non-RBAC group attributes; creating any group beyond the two defined in TR-010.

### Likely Targets

* Entra ID security group "Demo Contributors" (or an organization-standard equivalent name reflecting the same purpose): new group to hold Contributor-role principals for the demo subscription.
* Entra ID security group "Demo Readers" (or an organization-standard equivalent name reflecting the same purpose): new group to hold Reader-role principals for the demo subscription.
* If Infrastructure-as-Code is used for group creation, likely resource type is `Microsoft.Graph/groups` (via the Microsoft Graph Bicep extension) or an equivalent Microsoft Graph API call, since Entra ID groups are Microsoft Graph resources, not Azure Resource Manager resources under `Microsoft.Authorization` or `Microsoft.Resources`.

### Dependencies

* None — this phase has no dependency on other phases and should be completed first since P02 role assignments require both groups to already exist.

### Validation Expectations

* Both groups are visible in the Entra ID portal (or `az ad group list` / Microsoft Graph query) with the expected display name, description, and security-enabled group type.
* Both groups are selectable as a principal when starting to create a new Azure role assignment at the subscription scope (confirms the group is mail-disabled/security-enabled correctly for RBAC use).

### Completion Evidence

* Object ID of the created Demo Contributors group.
* Object ID of the created Demo Readers group.
* Confirmation that both groups show as security-enabled (not Microsoft 365/distribution groups), since only security-enabled groups can be assigned Azure roles.

### Unresolved Items

* Exact naming convention (e.g., a required prefix or naming standard for the organization's Entra ID tenant) is not specified in current evidence; the names "Demo Contributors" and "Demo Readers" from TR-010 are placeholders that should be confirmed against any existing tenant naming convention before creation, but this does not block proceeding since the functional requirement is the group's purpose and role assignment, not its exact display name.

<!-- rpi:task id=P01-T01 -->
### P01-T01: Define and create the Demo Contributors group

#### Context

TR-010's Demo Contributors group definition in docs/project-planning/azure-demo-subscription-technical-requirements.md states its members "need to create and manage Azure resources (networking, virtual machines, Key Vault, storage, app services, and similar resource types) within the demo subscription." This group is the principal that will receive the PIM-eligible Contributor assignment in P02-T02.

#### Intent

Create a security-enabled Entra ID group representing the Demo Contributors population, with a description that ties it back to its resource-creation purpose and its PIM-eligible (not standing) access model, so its purpose is discoverable without cross-referencing the technical requirements document.

#### Boundaries

* Included: Group name, description referencing its Contributor/PIM-eligible purpose, group type and membership type selection, group creation.
* Excluded: Adding any specific user as a member; assigning any Azure role (handled in P02-T02); configuring the PIM policy (handled in P03-T01).

#### Likely Targets

* New Entra ID group: Demo Contributors (name subject to tenant convention confirmation per P01 Unresolved Items).

#### Dependencies

* None

#### Validation Expectations

* The group exists, is security-enabled, and its description documents that membership grants PIM-eligible Contributor access to the demo subscription (not standing access), so a future reviewer immediately understands the access model without needing the BRD.

#### Completion Evidence

* Object ID and display name of the created group, recorded in the implementation changes record.

#### Unresolved Items

* None beyond the naming-convention note already captured at the P01 phase level.

<!-- rpi:task id=P01-T02 -->
### P01-T02: Define and create the Demo Readers group

#### Context

TR-010's Demo Readers group definition states its members "need to view and query resources and their configuration in the subscription ... without the ability to create, modify, or delete resources." This group is the principal that will receive the standing Reader assignment in P02-T01.

#### Intent

Create a security-enabled Entra ID group representing the Demo Readers population, with a description that ties it back to its read-only purpose and confirms its Reader assignment is standing (not PIM-gated), since Reader carries no write/delete capability.

#### Boundaries

* Included: Group name, description referencing its read-only, standing-access purpose, group type and membership type selection, group creation.
* Excluded: Adding any specific user as a member; assigning any Azure role (handled in P02-T01).

#### Likely Targets

* New Entra ID group: Demo Readers (name subject to tenant convention confirmation per P01 Unresolved Items).

#### Dependencies

* None

#### Validation Expectations

* The group exists, is security-enabled, and its description documents that membership grants standing Reader access to the demo subscription.

#### Completion Evidence

* Object ID and display name of the created group, recorded in the implementation changes record.

#### Unresolved Items

* None beyond the naming-convention note already captured at the P01 phase level.

<!-- rpi:phase id=P02 -->
## P02: Deploy the group role assignments

### Context

TR-010 requires the Demo Contributors group to hold the built-in Contributor role at subscription scope as a PIM-eligible assignment (not standing), and the Demo Readers group to hold the built-in Reader role at subscription scope as a standing assignment, since Reader is explicitly exempted from the standing-access restriction in TR-006 ("The Demo Readers group's Reader role assignment may remain standing/active since it carries no write, delete, or management capability"). The existing `policy/policyDefinitions/deny-standing-privileged-role-assignments.json` custom policy already targets standing Owner, Contributor, and User Access Administrator role definition IDs (`8e3af657-...`, `b24988ac-...`, `18d7d88d-...`) and denies/audits them unless the principal is in `allowedOwnerPrincipalIds`; a standing Contributor assignment for the Demo Contributors group would conflict with that existing guardrail once its effect is `Deny`, which is why the Contributor grant must be expressed as an eligible (PIM) assignment rather than a standing one.

### Intent

Grant each group exactly the Azure RBAC role it needs at subscription scope, using the assignment mechanism (standing vs. PIM-eligible) that matches its access model, so the deployed environment matches TR-010 and remains compatible with the existing policy guardrail.

### Boundaries

* Included: One standing Reader role assignment for Demo Readers at subscription scope; one PIM-eligible Contributor role assignment for Demo Contributors at subscription scope; an inventory of existing direct (per-user) Reader/Contributor role assignments and remediation of any that conflict with the group-only access model.
* Excluded: Any additional role beyond Reader and Contributor (for example, Key Vault Administrator/Secrets Officer scoped roles noted as optional in TR-010 are not required by the current user decisions and are left as a follow-up rather than an active task); activating the eligible assignment (activation is a per-user, per-session runtime action, not a deployment-time task); configuring the activation policy itself (handled in P03).

### Likely Targets

* `Microsoft.Authorization/roleAssignments` (standing assignment) scoped to the subscription, principal = Demo Readers group object ID, role definition = built-in Reader (`acdd72a7-3385-48ef-bd42-f606fba81ae7`).
* `Microsoft.Authorization/roleEligibilityScheduleRequests` (PIM-eligible assignment) scoped to the subscription, principal = Demo Contributors group object ID, role definition = built-in Contributor (`b24988ac-6180-42a0-ab88-20f7382dd24c`).

### Dependencies

* P01 (both groups must exist and have known object IDs before either role assignment can be created).

### Validation Expectations

* The Reader assignment for Demo Readers is visible immediately in the subscription's Access control (IAM) "Role assignments" view without any activation step.
* The Contributor assignment for Demo Contributors is visible in the subscription's Access control (IAM) "PIM" or "Eligible assignments" view, and does NOT appear in the standing "Role assignments" view until a member activates it.

### Completion Evidence

* Resource ID or confirmation screenshot/export of the standing Reader `roleAssignments` entry for Demo Readers.
* Resource ID or confirmation of the `roleEligibilityScheduleRequests`/resulting eligibility schedule for Demo Contributors' Contributor role.

### Unresolved Items

* None — both role definitions (Reader, Contributor) are well-known built-in Azure roles with stable GUIDs, and both assignment mechanisms (`roleAssignments` for standing, `roleEligibilityScheduleRequests` for eligible) are documented, current Azure Resource Manager resource types.

<!-- rpi:task id=P02-T01 -->
### P02-T01: Assign the Demo Readers group a standing Reader role at subscription scope

#### Context

TR-010 states the Demo Readers group "is assigned the built-in Reader role at the subscription scope" and that this assignment "may be a standing assignment because Reader access does not grant write or management permissions and is not restricted by TR-006's standing-access limitation."

#### Intent

Create a standing Azure RBAC role assignment granting the Demo Readers group Reader access at the subscription scope, active immediately without requiring PIM activation.

#### Boundaries

* Included: One `Microsoft.Authorization/roleAssignments` resource at subscription scope for the Demo Readers group and the built-in Reader role.
* Excluded: Any additional read-oriented role (Monitoring Reader, Cost Management Reader) noted as optional in TR-010; those remain a follow-up item, not part of this task, unless a future user decision confirms them as required.

#### Likely Targets

* `Microsoft.Authorization/roleAssignments` resource, scope = subscription, `roleDefinitionId` = built-in Reader (`acdd72a7-3385-48ef-bd42-f606fba81ae7`), `principalId` = Demo Readers group object ID, `principalType` = `Group`.

#### Dependencies

* P01-T02 (Demo Readers group must exist with a known object ID).

#### Validation Expectations

* The role assignment appears in the subscription's IAM "Role assignments" tab scoped to "This resource" (subscription) with principal type Group and role Reader.

#### Completion Evidence

* Role assignment resource ID (GUID) recorded in the implementation changes record.

#### Unresolved Items

* None.

<!-- rpi:task id=P02-T02 -->
### P02-T02: Assign the Demo Contributors group a PIM-eligible Contributor role at subscription scope

#### Context

TR-010 states the Demo Contributors group's "Contributor assignment is configured as PIM-eligible (not a standing/active assignment) per TR-006, with a maximum 10-hour activation duration." Microsoft Learn's `Microsoft.Authorization/roleEligibilityScheduleRequests` template reference (fetched during planning) confirms this resource type is the current mechanism for creating a PIM eligible-assignment request at subscription scope via Bicep/ARM, using `requestType: 'AdminAssign'`, a `principalId`, a `roleDefinitionId`, and a `scheduleInfo` block (start time and expiration type, for example `NoExpiration` for the eligibility duration itself — distinct from the per-activation 10-hour duration configured in P03).

#### Intent

Create a PIM-eligible Contributor assignment for the Demo Contributors group at subscription scope, so that group members can activate Contributor access on demand rather than holding it as a standing assignment, keeping the deployment compatible with the existing `deny-standing-privileged-role-assignments` policy.

#### Boundaries

* Included: One `Microsoft.Authorization/roleEligibilityScheduleRequests` resource (or equivalent current API surface) at subscription scope for the Demo Contributors group and the built-in Contributor role.
* Excluded: Any additional role beyond Contributor; the per-activation policy settings (10-hour cap, no approval), which belong to P03; scoped Key Vault data-plane roles noted as optional in TR-010, left as a follow-up.

#### Likely Targets

* `Microsoft.Authorization/roleEligibilityScheduleRequests` resource, scope = subscription, `roleDefinitionId` = built-in Contributor (`b24988ac-6180-42a0-ab88-20f7382dd24c`), `principalId` = Demo Contributors group object ID, `requestType` = `AdminAssign`, `scheduleInfo.expiration.type` = an eligibility duration decided at implementation time (for example `NoExpiration` for an indefinite eligibility window, distinct from the 10-hour per-activation cap enforced in P03).

#### Dependencies

* P01-T01 (Demo Contributors group must exist with a known object ID).

#### Validation Expectations

* The Demo Contributors group appears in the subscription's PIM "Eligible assignments" view for the Contributor role.
* No corresponding entry for the Demo Contributors group appears in the standing "Role assignments" view for Contributor until a member activates the eligible role.

#### Completion Evidence

* Role eligibility schedule request/resulting schedule resource ID recorded in the implementation changes record.

#### Unresolved Items

* None — the resource type and required properties are confirmed current evidence from the Microsoft Learn template reference retrieved during planning; the specific `scheduleInfo.expiration` value for the eligibility window itself (as opposed to the 10-hour activation cap) is an implementation-time configuration choice with no material risk either way, since either choice satisfies the functional requirement.

<!-- rpi:task id=P02-T03 -->
### P02-T03: Inventory and remediate existing direct Reader/Contributor role assignments

#### Context

TR-010 requires that contributor and reader access to the demo subscription be granted exclusively through the Demo Contributors and Demo Readers groups. Prior to this plan, the subscription may already have direct (per-user) Reader or Contributor role assignments made before the group-based model existed. Deploying the two groups alone does not remove any such pre-existing direct assignment, so without this task the "sole mechanism" outcome in the plan's Goals would not actually be achieved or verified.

#### Intent

Produce a current inventory of subscription-scope Reader/Contributor/Owner-tier role assignments, confirm which principals (besides the subscription owner and the two new groups) hold direct access, and either remove those direct assignments or explicitly document each one as an approved, time-limited exception with an owner and a reason.

#### Boundaries

* Included: Listing all subscription-scope role assignments for Reader, Contributor, Owner, and User Access Administrator; identifying any assignment whose principal is an individual user rather than the Demo Contributors group, the Demo Readers group, or the subscription owner; removing or documenting each such assignment.
* Excluded: Role assignments scoped below the subscription (for example, resource-group- or resource-scoped assignments) unless the user later confirms those are also in scope; roles other than Reader/Contributor/Owner/User Access Administrator.

#### Likely Targets

* Azure CLI/PowerShell or Portal query of `Microsoft.Authorization/roleAssignments` at subscription scope (for example `az role assignment list --scope /subscriptions/<id>`), used as a read-only inventory step rather than a new IaC resource.
* Any direct `Microsoft.Authorization/roleAssignments` entry identified as out of model: removed, or recorded in the implementation changes record as an approved exception.

#### Dependencies

* P01 (groups must exist so the inventory can distinguish "group-based" from "direct" assignments); should run before or alongside P02-T01/P02-T02 so the final assignment state is deliberate rather than incidental.

#### Validation Expectations

* The inventory query result lists only the subscription owner, the Demo Contributors group, and the Demo Readers group as holders of subscription-scope Reader/Contributor/Owner/User Access Administrator access, or every additional entry has a documented, approved exception.

#### Completion Evidence

* Exported role-assignment inventory (before and after) recorded in the implementation changes record.
* For any retained direct assignment, a documented owner, reason, and expected removal or review date.

#### Unresolved Items

* Whether any pre-existing direct assignment currently exists is not known from planning-stage evidence; this task is included specifically to resolve that unknown at implementation time rather than assuming the subscription is already clean.

<!-- rpi:phase id=P03 -->
## P03: Configure the PIM activation policy for the Demo Contributors role

### Context

The user's explicit requirement is that a PIM activation for the Demo Contributors group's Contributor role "can be active for 10 hours at each request" and that "no owner or admin approval needed to activate a privileged role, only a time limit is set." Planning-stage evidence (Microsoft Learn's `Microsoft.Authorization/roleManagementPolicies` template reference, retrieved during planning) shows the resource type exists but its published Bicep/ARM schema (`2024-09-01-preview`) exposes only a `name` property, not the `rules` payload needed to set maximum activation duration or the approval requirement. Complementary web-search evidence (Microsoft Q&A: "How to change PIM Role settings in Azure AD PIM using BICEP or ARM") indicates these specific policy settings are commonly configured through PowerShell, Microsoft Graph, or the Azure Portal rather than plain declarative Bicep/ARM properties as of the evidence gathered during planning.

### Intent

Ensure the role management policy governing the Demo Contributors group's eligible Contributor role enforces exactly the two settings the user specified — 10-hour maximum activation duration and no required approval — as the fixed, settled requirement. The specific configuration surface (exact rule/property names and whether it is set via a declarative resource, a deployment script, or a documented manual/PowerShell or Microsoft Graph step) is an implementation-time confirmation item rather than a proven fact from current planning evidence, since the published schema does not yet expose the full `rules` payload.

### Boundaries

* Included: Setting the `Expiration_EndUser_Assignment` (or equivalent) maximum-duration rule to 10 hours for the Contributor role's eligible-assignment activation, scoped to the subscription; setting the `Approval_EndUser_Assignment` (or equivalent) rule to not require approval for the same activation.
* Excluded: Changing any other PIM rule (for example notification rules, MFA-on-activation requirements, or justification requirements) not specified by the user; changing the policy for any role other than the Demo Contributors group's Contributor role.

### Likely Targets

* `Microsoft.Authorization/roleManagementPolicyAssignments` resource at subscription scope, associated with the Contributor role definition, pointing to a `Microsoft.Authorization/roleManagementPolicies` resource whose `rules` array is expected to set the activation-duration and approval rules — this is a hypothesis based on the resource type's existence, not a confirmed working Bicep/ARM pattern, since the published schema exposes only `name`.
* If direct declarative support proves insufficient at implementation time, an ARM `Microsoft.Resources/deploymentScripts` resource (Azure CLI or PowerShell script body) or a documented one-time manual/PowerShell configuration step recorded in the implementation changes record, per the explicit user preference (noted in a prior turn of this session) to avoid creating standalone automation scripts as documentation deliverables — the implementer should weigh that preference against the technical necessity of a scripted or manual step for this specific PIM policy setting and document the choice made.

### Dependencies

* P02-T02 (the Demo Contributors group's eligible Contributor assignment must exist so its role management policy has a concrete assignment to govern).

### Validation Expectations

* The Entra ID PIM "Role settings" view for the Contributor role (scoped to the subscription) shows "Activation: Maximum duration = 10 hours" and "Require approval to activate = No" for the Demo Contributors group's eligibility.
* A test activation by a Demo Contributors group member succeeds without an approval step and expires at or before 10 hours from activation.

### Completion Evidence

* Exported or screenshotted PIM role settings confirming the 10-hour maximum and no-approval configuration.
* A recorded test activation showing start and expiration timestamps consistent with the 10-hour cap.

### Unresolved Items

* The exact implementation mechanism (declarative resource vs. deployment script vs. documented manual/PowerShell step) for setting the activation-duration and approval rules is not fully resolved by current planning-stage evidence and is deferred to implementation-time confirmation; this is recorded as an assumption, not a blocker, since the functional outcome (10-hour cap, no approval) is unambiguous and only the deployment mechanism is open.

<!-- rpi:task id=P03-T01 -->
### P03-T01: Set the 10-hour maximum activation duration and remove the approval requirement

#### Context

See P03 Context above. This task is the concrete configuration action; P03 carries the phase-level ambiguity note about the deployment mechanism.

#### Intent

Configure the Contributor role's PIM role management policy, scoped to the subscription and specific to the Demo Contributors group's eligible assignment, so activation is capped at 10 hours and does not require approval.

#### Boundaries

* Included: The two specific rule settings (10-hour maximum duration; no approval required) for the Contributor role's end-user activation.
* Excluded: Any other role's PIM policy; any other PIM rule category (MFA, justification, notification) not requested by the user.

#### Likely Targets

* `Microsoft.Authorization/roleManagementPolicies` `rules` entries of type `Expiration_EndUser_Assignment` (set `maximumDuration` to `PT10H`) and `Approval_EndUser_Assignment` (set `enabled` to `false` / remove the approval stage), applied via whichever mechanism P03's boundary note resolves at implementation time — these exact rule-type names are the best current evidence-based hypothesis, not confirmed working configuration, and should be verified against the live API/Portal at implementation time.

#### Dependencies

* P02-T02

#### Validation Expectations

* PIM role settings for Contributor (scoped to this subscription, applicable to the Demo Contributors group's eligibility) show a 10-hour maximum activation duration and no approval requirement.

#### Completion Evidence

* Confirmed role settings export or screenshot; a successful no-approval activation test within the 10-hour cap.

#### Unresolved Items

* Same deployment-mechanism assumption noted at the P03 phase level; implementation should record the mechanism actually used in the changes record so the decision is traceable.

<!-- rpi:phase id=P04 -->
## P04: Reconcile with existing policy guardrails and document the access model

### Context

The demo subscription already has a deployable custom Azure Policy, `policy/policyDefinitions/deny-standing-privileged-role-assignments.json`, that denies/audits standing Owner, Contributor, or User Access Administrator role assignments except for principals listed in its `allowedOwnerPrincipalIds` parameter. Once P02 and P03 are complete, the subscription's access model should consist of exactly: the subscription owner (standing, exempted via `allowedOwnerPrincipalIds`), the Demo Contributors group (PIM-eligible Contributor, not standing, so it is not subject to that policy's Deny condition), and the Demo Readers group (standing Reader, a role not targeted by that policy's `restrictedRoleDefinitionIds`).

### Intent

Confirm no configuration drift or conflict exists between the newly deployed groups/role assignments and the existing policy guardrail, and leave a clear, current record of the finished access model so a future reviewer does not need to reconstruct it from the BRD, technical requirements, and this plan separately.

### Boundaries

* Included: Confirming whether the `deny-standing-privileged-role-assignments` policy is currently assigned to the demo subscription (via `demo-environment-cost-governance-assignment.json` or the containing initiative) and at what effect; a policy compliance check against the demo subscription for that policy once confirmed assigned; confirming `allowedOwnerPrincipalIds` in the deployed assignment contains only the subscription owner's principal ID; a short documentation update (for example in the policy README or a subscription access-model note) capturing the final group/role state.
* Excluded: Any change to the policy's `restrictedRoleDefinitionIds` or other parameters beyond confirming/updating `allowedOwnerPrincipalIds`; deploying the policy assignment for the first time if it is found not yet assigned — that is a separate follow-up decision, not an in-scope remediation of this phase.

### Likely Targets

* `policy/policyAssignments/demo-environment-cost-governance-assignment.json`: authoritative source of the deployed `allowedOwnerPrincipalIds` parameter value and the assignment's actual scope/effect; confirmation or update target for P04-T01.
* `policy/policyDefinitions/deny-standing-privileged-role-assignments.json`: reference only — this file declares the parameter's schema and the restricted role definition IDs, it is not where the effective exemption list is set.
* `policy/README.md` or a new short access-model note: documentation of the final Demo Contributors/Demo Readers group and role-assignment state.

### Dependencies

* P02, P03 (the actual deployed role assignments and PIM policy must exist before a compliance check is meaningful).

### Validation Expectations

* P04-T01 confirms and records the deployed policy assignment's scope, effect, and current `allowedOwnerPrincipalIds` value before any compliance scan is run.
* An on-demand Azure Policy compliance scan (P04-T02) shows no non-compliant resource for the Demo Contributors or Demo Readers role assignments under the `deny-standing-privileged-role-assignments` policy.
* `allowedOwnerPrincipalIds` contains the correct, current subscription owner principal ID and no unintended additional principals.

### Completion Evidence

* Confirmed policy assignment scope/effect record (P04-T01).
* Policy compliance scan result or export showing the relevant assignments as compliant (P04-T02).
* Updated documentation reflecting the final group/role/PIM state, committed alongside the other planning artifacts.

### Unresolved Items

* Whether the `deny-standing-privileged-role-assignments` policy has already been assigned to the demo subscription (as opposed to only defined) is not confirmed by current evidence; P04-T01 exists specifically to resolve this before P04-T02's compliance check is attempted.

<!-- rpi:task id=P04-T01 -->
### P04-T01: Confirm the deployed policy assignment state and the authoritative owner-exemption value

#### Context

See P04 Context above. Prior planning evidence establishes the policy definition's schema and intent, but not whether the demo subscription currently has a live assignment of that policy (via the `demo-environment-cost-governance` initiative) or what `allowedOwnerPrincipalIds` value is actually deployed.

#### Intent

Confirm, from the live subscription, whether the `deny-standing-privileged-role-assignments` policy (through its initiative) is assigned, at what scope and effect, and whether `policy/policyAssignments/demo-environment-cost-governance-assignment.json`'s `allowedOwnerPrincipalIds` parameter matches the actual deployed value and lists only the current subscription owner. Correct the deployed parameter if it does not.

#### Boundaries

* Included: Querying the live policy assignment state; comparing the deployed `allowedOwnerPrincipalIds` value against the current subscription owner's principal ID; correcting the deployed value if it is missing, stale, or includes unintended principals.
* Excluded: Running the compliance scan itself (handled in P04-T02, which depends on this task's confirmation); changing the policy definition file's parameter schema.

#### Likely Targets

* `policy/policyAssignments/demo-environment-cost-governance-assignment.json`: the authoritative artifact for the deployed `allowedOwnerPrincipalIds` value; this task confirms or corrects its live counterpart in Azure, not the definition file.

#### Dependencies

* None beyond the policy artifacts already existing; should complete before P04-T02.

#### Validation Expectations

* A query of the live policy assignment (for example `az policy assignment show`) confirms its scope, effect, and current `allowedOwnerPrincipalIds` value, and that value is corrected if it does not match the current subscription owner.

#### Completion Evidence

* Recorded live assignment scope/effect and confirmed or corrected `allowedOwnerPrincipalIds` value in the implementation changes record.

#### Unresolved Items

* Whether the assignment currently exists at all is unknown from planning evidence; if it does not exist, this task should record that fact so P04-T02 and the broader plan can treat "policy not yet assigned" as a documented finding rather than a silent assumption.

<!-- rpi:task id=P04-T02 -->
### P04-T02: Run the policy compliance scan and document the final access model

#### Context

Once P04-T01 confirms the `deny-standing-privileged-role-assignments` policy is assigned (or documents that it is not), this task runs the actual compliance check against the deployed Demo Contributors and Demo Readers role assignments and records the final access-model state.

#### Intent

Run a policy compliance check for the `deny-standing-privileged-role-assignments` policy against the demo subscription after P02/P03/P04-T01 are complete, and produce a short documentation update capturing the final group/role/PIM state.

#### Boundaries

* Included: Compliance check; documentation update.
* Excluded: Any policy definition, initiative, or assignment parameter change (handled in P04-T01 if needed).

#### Likely Targets

* Azure Policy compliance scan output for the demo subscription, filtered to the `deny-standing-privileged-role-assignments` policy.
* `policy/README.md` or a new short access-model note.

#### Dependencies

* P04-T01 (the policy's assignment state must be confirmed before this scan is meaningful).

#### Validation Expectations

* Compliance scan shows both groups' role assignments as compliant with the standing-access-restriction policy.

#### Completion Evidence

* Compliance scan result; updated documentation reflecting the final group/role/PIM state.

#### Unresolved Items

* None, contingent on P04-T01 having confirmed the policy is assigned; if P04-T01 finds it is not assigned, this task's scan is deferred until that assignment decision is made.
