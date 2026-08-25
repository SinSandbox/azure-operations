#!/usr/bin/env bash
# P03-T01: Configure the PIM role management policy governing the Demo Contributors group's
# eligible Contributor assignment so activation is capped at a maximum duration and requires no
# approval.
#
# Microsoft.Authorization/roleManagementPolicies is an Azure Resource Manager resource type, but
# its published Bicep/ARM template schema (2024-09-01-preview, as of planning-stage research) does
# not expose the `rules` payload needed to set these settings declaratively — see
# .copilot-tracking/plans/2026-08-24/entra-pim-group-role-deployment-plan.md (P03) and its P03-T01
# task note. This script configures the policy directly via the ARM REST API (`az rest`), which
# does support the full `rules` payload.
#
# IMPORTANT: The rule `id` values referenced below (Expiration_EndUser_Assignment,
# Approval_EndUser_Assignment) are the best current evidence-based expectation for this resource
# type's rule shape, not a value confirmed against this tenant's live API response. Before relying
# on this script in a new tenant, run it once with DRY_RUN=true, inspect the printed GET response,
# and adjust the jq filters below if the rule `id` values differ.
#
# Requires: az CLI logged in with Privileged Role Administrator (or equivalent) rights over the
# subscription's PIM configuration; jq installed.
#
# Environment variables:
#   AZURE_SUB_ID                  (required) subscription ID.
#   CONTRIBUTOR_ROLE_DEFINITION_ID (optional, default: built-in Contributor GUID)
#   PIM_MAX_DURATION_HOURS         (optional, default: 10)
#   DRY_RUN                        (optional, default: false) when "true", prints the computed
#                                   policy update but does not PATCH it.

set -euo pipefail

: "${AZURE_SUB_ID:?AZURE_SUB_ID is required}"
CONTRIBUTOR_ROLE_DEFINITION_ID="${CONTRIBUTOR_ROLE_DEFINITION_ID:-b24988ac-6180-42a0-ab88-20f7382dd24c}"
PIM_MAX_DURATION_HOURS="${PIM_MAX_DURATION_HOURS:-10}"
DRY_RUN="${DRY_RUN:-false}"
API_VERSION="2020-10-01"

role_definition_resource_id="/subscriptions/${AZURE_SUB_ID}/providers/Microsoft.Authorization/roleDefinitions/${CONTRIBUTOR_ROLE_DEFINITION_ID}"

echo "Looking up the role management policy assignment for role definition: $role_definition_resource_id"
policy_assignments=$(az rest --method get \
  --url "https://management.azure.com/subscriptions/${AZURE_SUB_ID}/providers/Microsoft.Authorization/roleManagementPolicyAssignments?api-version=${API_VERSION}")

policy_id=$(echo "$policy_assignments" | jq -r --arg roleId "$CONTRIBUTOR_ROLE_DEFINITION_ID" \
  '.value[] | select(.properties.roleDefinitionId | endswith($roleId)) | .properties.policyId' | head -n1)

if [[ -z "$policy_id" || "$policy_id" == "null" ]]; then
  echo "ERROR: Could not find a roleManagementPolicyAssignment for role definition GUID $CONTRIBUTOR_ROLE_DEFINITION_ID at subscription scope." >&2
  echo "Confirm the Demo Contributors group's eligible assignment (P02-T02) has been deployed before running this script." >&2
  exit 1
fi

echo "Found policy: $policy_id"
policy=$(az rest --method get --url "https://management.azure.com${policy_id}?api-version=${API_VERSION}")

updated_policy=$(echo "$policy" | jq --argjson maxHours "$PIM_MAX_DURATION_HOURS" '
  .properties.rules |= map(
    if .id == "Expiration_EndUser_Assignment" then
      .maximumDuration = ("PT" + ($maxHours | tostring) + "H")
    elif .id == "Approval_EndUser_Assignment" then
      (.setting.isApprovalRequired = false)
    else
      .
    end
  )
')

echo "Computed policy update (rules only):"
echo "$updated_policy" | jq '.properties.rules'

if [[ "$DRY_RUN" == "true" ]]; then
  echo "DRY_RUN=true: not applying the update."
  exit 0
fi

echo "Applying updated policy to $policy_id..."
az rest --method patch \
  --url "https://management.azure.com${policy_id}?api-version=${API_VERSION}" \
  --body "$(echo "$updated_policy" | jq '{properties: .properties}')"

echo "PIM role management policy updated: maximum activation duration = ${PIM_MAX_DURATION_HOURS}h, approval required = false."
