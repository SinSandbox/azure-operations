#!/usr/bin/env bash
# P02-T03: Inventory existing direct (per-user) Reader/Contributor/Owner/User Access Administrator
# role assignments at subscription scope, and flag any principal other than the subscription
# owner, the Demo Contributors group, or the Demo Readers group.
#
# This script is read-only/reporting by default (REMEDIATE=false). It does not delete role
# assignments automatically, because removing a live user's access is a decision the subscription
# owner should confirm — see .copilot-tracking/plans/2026-08-24/entra-pim-group-role-deployment-plan.md
# (P02-T03) and the plan's PC-001 critique disposition.
#
# Requires: az CLI logged in with at least Reader access to subscription-scope role assignments;
# jq installed (preinstalled on GitHub-hosted ubuntu runners).
#
# Environment variables:
#   AZURE_SUB_ID                       (required) subscription ID to inventory.
#   DEMO_CONTRIBUTORS_GROUP_OBJECT_ID   (required) object ID of the Demo Contributors group.
#   DEMO_READERS_GROUP_OBJECT_ID        (required) object ID of the Demo Readers group.
#   SUBSCRIPTION_OWNER_PRINCIPAL_IDS    (optional) comma-separated list of principal IDs that are
#                                        approved standing exceptions (e.g. the subscription owner).
#   INVENTORY_OUTPUT_FILE              (optional, default: role-assignment-inventory.json)
#   FLAGGED_OUTPUT_FILE                (optional, default: role-assignment-inventory-flagged.json)
#   REMEDIATE                          (optional, default: false) set to "true" to delete flagged
#                                        direct assignments instead of only reporting them.

set -euo pipefail

: "${AZURE_SUB_ID:?AZURE_SUB_ID is required}"
: "${DEMO_CONTRIBUTORS_GROUP_OBJECT_ID:?DEMO_CONTRIBUTORS_GROUP_OBJECT_ID is required}"
: "${DEMO_READERS_GROUP_OBJECT_ID:?DEMO_READERS_GROUP_OBJECT_ID is required}"

SUBSCRIPTION_OWNER_PRINCIPAL_IDS="${SUBSCRIPTION_OWNER_PRINCIPAL_IDS:-}"
INVENTORY_OUTPUT_FILE="${INVENTORY_OUTPUT_FILE:-role-assignment-inventory.json}"
FLAGGED_OUTPUT_FILE="${FLAGGED_OUTPUT_FILE:-role-assignment-inventory-flagged.json}"
REMEDIATE="${REMEDIATE:-false}"

RESTRICTED_ROLES='["Owner","Contributor","User Access Administrator","Reader"]'

echo "Listing subscription-scope role assignments for restricted roles..."
az role assignment list \
  --subscription "$AZURE_SUB_ID" \
  --scope "/subscriptions/$AZURE_SUB_ID" \
  --all \
  -o json > "$INVENTORY_OUTPUT_FILE"

# Build the allow-list of principal IDs that are not considered "direct/unexpected" assignments.
allowed_principal_ids_json=$(jq -n \
  --arg contrib "$DEMO_CONTRIBUTORS_GROUP_OBJECT_ID" \
  --arg readers "$DEMO_READERS_GROUP_OBJECT_ID" \
  --arg owners "$SUBSCRIPTION_OWNER_PRINCIPAL_IDS" \
  '[$contrib, $readers] + ($owners | split(",") | map(select(length > 0)))')

jq --argjson restricted "$RESTRICTED_ROLES" \
   --argjson allowed "$allowed_principal_ids_json" \
   '[.[] | select(.roleDefinitionName as $r | $restricted | index($r) != null)
       | select(.principalId as $p | $allowed | index($p) == null)]' \
   "$INVENTORY_OUTPUT_FILE" > "$FLAGGED_OUTPUT_FILE"

flagged_count=$(jq 'length' "$FLAGGED_OUTPUT_FILE")

if [[ "$flagged_count" -eq 0 ]]; then
  echo "No unexpected direct Reader/Contributor/Owner/User Access Administrator assignments found."
  exit 0
fi

echo "WARNING: Found $flagged_count direct role assignment(s) outside the group-based access model:"
jq -r '.[] | "  - " + .principalName + " (" + .principalType + ") -> " + .roleDefinitionName + " @ " + .scope' "$FLAGGED_OUTPUT_FILE"

if [[ "$REMEDIATE" == "true" ]]; then
  echo "REMEDIATE=true: removing flagged assignments..."
  jq -r '.[] | .id' "$FLAGGED_OUTPUT_FILE" | while read -r assignment_id; do
    echo "Deleting role assignment: $assignment_id"
    az role assignment delete --ids "$assignment_id"
  done
else
  echo "REMEDIATE is not 'true' — flagged assignments were reported only, not removed."
  echo "Review $FLAGGED_OUTPUT_FILE and either document each as an approved exception or re-run with REMEDIATE=true."
fi
