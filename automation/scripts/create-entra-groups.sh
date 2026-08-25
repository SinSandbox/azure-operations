#!/usr/bin/env bash
# P01: Define and provision the Demo Contributors and Demo Readers Entra ID security groups.
#
# Entra ID group creation is a Microsoft Graph operation, not an Azure Resource Manager resource,
# so it is handled here via `az ad group` (Microsoft Graph-backed) rather than in Bicep — see
# docs/project-planning/azure-demo-subscription-technical-requirements.md (TR-010) and
# .copilot-tracking/plans/2026-08-24/entra-pim-group-role-deployment-plan.md (P01, P01-T01, P01-T02).
#
# Idempotent: re-running this script does not create duplicate groups; it looks up an existing
# group by display name first.
#
# Requires: az CLI logged in (or federated OIDC login in CI) with Microsoft Graph permission
# Group.ReadWrite.All (or Directory.ReadWrite.All) granted to the calling principal.
#
# Environment variables (all optional, defaults shown):
#   DEMO_CONTRIBUTORS_GROUP_NAME        (default: "Demo Contributors")
#   DEMO_READERS_GROUP_NAME             (default: "Demo Readers")
#   DEMO_CONTRIBUTORS_GROUP_DESCRIPTION (default: see below)
#   DEMO_READERS_GROUP_DESCRIPTION      (default: see below)
#
# Outputs (also appended to $GITHUB_ENV / $GITHUB_OUTPUT when running in GitHub Actions):
#   DEMO_CONTRIBUTORS_GROUP_OBJECT_ID
#   DEMO_READERS_GROUP_OBJECT_ID

set -euo pipefail

DEMO_CONTRIBUTORS_GROUP_NAME="${DEMO_CONTRIBUTORS_GROUP_NAME:-Demo Contributors}"
DEMO_READERS_GROUP_NAME="${DEMO_READERS_GROUP_NAME:-Demo Readers}"
DEMO_CONTRIBUTORS_GROUP_DESCRIPTION="${DEMO_CONTRIBUTORS_GROUP_DESCRIPTION:-Demo application builders with PIM-eligible Contributor access to the demo subscription (TR-010).}"
DEMO_READERS_GROUP_DESCRIPTION="${DEMO_READERS_GROUP_DESCRIPTION:-Standing read-only access to query and review resources in the demo subscription (TR-010).}"

create_or_get_group() {
  local display_name="$1"
  local description="$2"
  local mail_nickname
  # Mail nickname must be alphanumeric-ish; strip spaces and lowercase for a stable value.
  mail_nickname=$(echo "$display_name" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')

  local object_id
  object_id=$(az ad group list --display-name "$display_name" --query "[0].id" -o tsv 2>/dev/null || true)

  if [[ -z "$object_id" || "$object_id" == "null" ]]; then
    echo "Creating Entra ID group: $display_name" >&2
    object_id=$(az ad group create \
      --display-name "$display_name" \
      --mail-nickname "$mail_nickname" \
      --description "$description" \
      --query id -o tsv)
  else
    echo "Group already exists, reusing: $display_name ($object_id)" >&2
  fi

  echo "$object_id"
}

demo_contributors_group_object_id=$(create_or_get_group "$DEMO_CONTRIBUTORS_GROUP_NAME" "$DEMO_CONTRIBUTORS_GROUP_DESCRIPTION")
demo_readers_group_object_id=$(create_or_get_group "$DEMO_READERS_GROUP_NAME" "$DEMO_READERS_GROUP_DESCRIPTION")

echo "Demo Contributors group object ID: $demo_contributors_group_object_id"
echo "Demo Readers group object ID:      $demo_readers_group_object_id"

if [[ -n "${GITHUB_ENV:-}" ]]; then
  {
    echo "DEMO_CONTRIBUTORS_GROUP_OBJECT_ID=$demo_contributors_group_object_id"
    echo "DEMO_READERS_GROUP_OBJECT_ID=$demo_readers_group_object_id"
  } >> "$GITHUB_ENV"
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "demo_contributors_group_object_id=$demo_contributors_group_object_id"
    echo "demo_readers_group_object_id=$demo_readers_group_object_id"
  } >> "$GITHUB_OUTPUT"
fi
