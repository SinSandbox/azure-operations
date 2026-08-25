// Deploys the ARM-native pieces of the Entra ID group + PIM role model defined in
// docs/project-planning/azure-demo-subscription-technical-requirements.md (TR-006, TR-010) and
// .copilot-tracking/plans/2026-08-24/entra-pim-group-role-deployment-plan.md (P02-T01, P02-T02).
//
// This template does NOT create the Entra ID security groups themselves — group creation is a
// Microsoft Graph operation, not an Azure Resource Manager resource, and is handled by
// automation/scripts/create-entra-groups.sh before this deployment runs (per plan P01 and the
// PC-004 critique disposition distinguishing ARM-native vs. Microsoft Graph-based mechanisms).
targetScope = 'subscription'

@description('Object ID of the Demo Contributors Entra ID security group (created by create-entra-groups.sh).')
param demoContributorsGroupObjectId string

@description('Object ID of the Demo Readers Entra ID security group (created by create-entra-groups.sh).')
param demoReadersGroupObjectId string

@description('Built-in Contributor role definition GUID.')
param contributorRoleDefinitionId string = 'b24988ac-6180-42a0-ab88-20f7382dd24c'

@description('Built-in Reader role definition GUID.')
param readerRoleDefinitionId string = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'

@description('Environment label used only for resource naming/description context (e.g. dev).')
param environmentName string = 'dev'

@description('Start timestamp for the Demo Contributors PIM eligibility window. Defaults to deployment time.')
param eligibilityStartDateTime string = utcNow('u')

@description('Eligibility window expiration type. NoExpiration keeps the group eligible indefinitely; the 10-hour cap is enforced per-activation by the PIM role management policy (P03), not by this eligibility window.')
@allowed([
  'NoExpiration'
  'AfterDateTime'
  'AfterDuration'
])
param eligibilityExpirationType string = 'NoExpiration'

var subscriptionScope = subscription().id
var readerRoleDefinitionResourceId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', readerRoleDefinitionId)
var contributorRoleDefinitionResourceId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', contributorRoleDefinitionId)

// Deterministic, idempotent names so re-running this deployment does not create duplicate assignments.
var demoReadersRoleAssignmentName = guid(subscriptionScope, demoReadersGroupObjectId, readerRoleDefinitionId, 'standing')
var demoContributorsEligibilityRequestName = guid(subscriptionScope, demoContributorsGroupObjectId, contributorRoleDefinitionId, 'pim-eligible')

// P02-T01: Demo Readers group receives a standing Reader assignment (TR-010 — Reader is exempt
// from the standing-access restriction because it grants no write/delete/management capability).
resource demoReadersRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: demoReadersRoleAssignmentName
  properties: {
    roleDefinitionId: readerRoleDefinitionResourceId
    principalId: demoReadersGroupObjectId
    principalType: 'Group'
    description: 'Standing Reader access for the Demo Readers group (TR-010) — environment: ${environmentName}.'
  }
}

// P02-T02: Demo Contributors group receives a PIM-eligible (not standing) Contributor assignment.
// This keeps the group compliant with policy/policyDefinitions/deny-standing-privileged-role-assignments.json,
// which denies/audits standing Owner/Contributor/User Access Administrator assignments outside
// allowedOwnerPrincipalIds. The 10-hour maximum activation duration and no-approval rule are
// configured separately by automation/scripts/configure-pim-policy.sh (P03), since the published
// Microsoft.Authorization/roleManagementPolicies Bicep/ARM schema does not yet expose the `rules`
// payload needed to set those settings declaratively.
resource demoContributorsEligibility 'Microsoft.Authorization/roleEligibilityScheduleRequests@2020-10-01' = {
  name: demoContributorsEligibilityRequestName
  properties: {
    principalId: demoContributorsGroupObjectId
    roleDefinitionId: contributorRoleDefinitionResourceId
    requestType: 'AdminAssign'
    justification: 'PIM-eligible Contributor access for the Demo Contributors group (TR-006, TR-010) — environment: ${environmentName}.'
    scheduleInfo: {
      startDateTime: eligibilityStartDateTime
      expiration: {
        type: eligibilityExpirationType
      }
    }
  }
}

output demoReadersRoleAssignmentId string = demoReadersRoleAssignment.id
output demoContributorsEligibilityRequestId string = demoContributorsEligibility.id
