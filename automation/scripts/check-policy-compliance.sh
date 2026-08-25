#!/usr/bin/env bash
# P04-T01/P04-T02: Confirm whether the deny-standing-privileged-role-assignments policy (via the
# demo-environment-cost-governance initiative) is assigned to the demo subscription, confirm its
# allowedOwnerPrincipalIds parameter, and run a compliance scan for the Demo Contributors/Demo
# Readers role assignments.
#
# See .copilot-tracking/plans/2026-08-24/entra-pim-group-role-deployment-plan.md (P04-T01, P04-T02)
# and policy/policyAssignments/demo-environment-cost-governance-assignment.json, which is the
# authoritative source for the deployed allowedOwnerPrincipalIds value (the policy definition file
# only declares the parameter's schema).
#
# Requires: az CLI logged in with at least Reader access to Policy Insights and policy assignments.
#
# Environment variables:
#   AZURE_SUB_ID                    (required) subscription ID.
#   POLICY_ASSIGNMENT_NAME          (optional, default: demo-environment-cost-governance-assignment)
#   COMPLIANCE_OUTPUT_FILE          (optional, default: policy-compliance-summary.json)

set -euo pipefail

: "${AZURE_SUB_ID:?AZURE_SUB_ID is required}"
POLICY_ASSIGNMENT_NAME="${POLICY_ASSIGNMENT_NAME:-demo-environment-cost-governance-assignment}"
COMPLIANCE_OUTPUT_FILE="${COMPLIANCE_OUTPUT_FILE:-policy-compliance-summary.json}"

echo "P04-T01: Confirming policy assignment state for '$POLICY_ASSIGNMENT_NAME'..."
assignment=$(az policy assignment show \
  --name "$POLICY_ASSIGNMENT_NAME" \
  --scope "/subscriptions/${AZURE_SUB_ID}" \
  -o json 2>/dev/null || true)

if [[ -z "$assignment" ]]; then
  echo "NOT ASSIGNED: '$POLICY_ASSIGNMENT_NAME' is not currently assigned at subscription scope."
  echo "Deploy policy/policyAssignments/demo-environment-cost-governance-assignment.json before running the compliance scan (P04-T02)."
  exit 0
fi

standing_access_effect=$(echo "$assignment" | jq -r '.parameters.standingAccessEffect.value // "not set"')
allowed_owner_principal_ids=$(echo "$assignment" | jq -c '.parameters.allowedOwnerPrincipalIds.value // []')

echo "Assigned. standingAccessEffect = $standing_access_effect"
echo "Current allowedOwnerPrincipalIds = $allowed_owner_principal_ids"
echo "Confirm this list contains only the current subscription owner's principal ID; update"
echo "policy/policyAssignments/demo-environment-cost-governance-assignment.json and redeploy the"
echo "assignment if it does not."

echo ""
echo "P04-T02: Running compliance scan for the Demo Contributors/Demo Readers role assignments..."
az policy state trigger-scan --resource "/subscriptions/${AZURE_SUB_ID}" >/dev/null || true

az policy state list \
  --resource "/subscriptions/${AZURE_SUB_ID}" \
  --filter "PolicyAssignmentName eq '${POLICY_ASSIGNMENT_NAME}'" \
  -o json > "$COMPLIANCE_OUTPUT_FILE"

non_compliant_count=$(jq '[.[] | select(.complianceState == "NonCompliant")] | length' "$COMPLIANCE_OUTPUT_FILE")

if [[ "$non_compliant_count" -eq 0 ]]; then
  echo "No non-compliant resources found for policy assignment '$POLICY_ASSIGNMENT_NAME'."
else
  echo "WARNING: $non_compliant_count non-compliant resource(s) found under '$POLICY_ASSIGNMENT_NAME'."
  jq -r '.[] | select(.complianceState == "NonCompliant") | "  - " + .resourceId' "$COMPLIANCE_OUTPUT_FILE"
fi
