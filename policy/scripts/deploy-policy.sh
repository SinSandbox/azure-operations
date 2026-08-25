#!/usr/bin/env bash
# Deploys the demo environment's Azure Policy artifacts to a subscription, in order:
#   1. Custom policy definitions (policy/policyDefinitions/*.json)
#   2. The policy initiative bundling them (policy/policyInitiatives/*-initiative.json)
#   3. The subscription-scope policy assignment (policy/policyAssignments/*-assignment.json)
#
# See policy/README.md for the requirement-to-policy mapping (TR-001, TR-002, TR-004 through TR-007).
#
# Idempotent: each step checks whether the resource already exists and updates it in place rather
# than failing on re-run.
#
# Requires: az CLI logged in with Resource Policy Contributor (or Owner) at subscription scope;
# jq installed (preinstalled on GitHub-hosted ubuntu runners).
#
# Environment variables:
#   AZURE_SUB_ID           (required) target subscription ID.
#   POLICY_PRINCIPAL_ID    (required) single object ID exempt from the
#                          standing-access-restriction policy (TR-006). Overrides the
#                          placeholder value checked into the assignment JSON file.
#   LOCATION               (optional) region for the policy assignment's managed
#                          identity. Defaults to the value in the assignment JSON file.

set -euo pipefail

: "${AZURE_SUB_ID:?AZURE_SUB_ID is required}"
: "${POLICY_PRINCIPAL_ID:?POLICY_PRINCIPAL_ID is required (single object ID exempt from the standing-access policy)}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEFINITIONS_DIR="$REPO_ROOT/policy/policyDefinitions"
INITIATIVE_FILE="$REPO_ROOT/policy/policyInitiatives/demo-environment-cost-governance-initiative.json"
ASSIGNMENT_FILE="$REPO_ROOT/policy/policyAssignments/demo-environment-cost-governance-assignment.json"
LOCATION="${LOCATION:-$(jq -r '.location // "eastus"' "$ASSIGNMENT_FILE")}"

deploy_policy_definition() {
  local file="$1"
  local name display_name description mode
  name=$(jq -r '.name' "$file")
  display_name=$(jq -r '.properties.displayName' "$file")
  description=$(jq -r '.properties.description' "$file")
  mode=$(jq -r '.properties.mode // "Indexed"' "$file")

  local rules_file params_file
  rules_file=$(mktemp)
  params_file=$(mktemp)
  jq '.properties.policyRule' "$file" > "$rules_file"
  jq '.properties.parameters // {}' "$file" > "$params_file"

  local -a metadata_args=()
  while IFS= read -r kv; do
    [[ -n "$kv" ]] && metadata_args+=("$kv")
  done < <(jq -r '.properties.metadata // {} | to_entries[] | "\(.key)=\(.value)"' "$file")

  local -a az_args=(
    --name "$name"
    --display-name "$display_name"
    --description "$description"
    --rules "$rules_file"
    --params "$params_file"
    --mode "$mode"
    --subscription "$AZURE_SUB_ID"
  )
  if [[ ${#metadata_args[@]} -gt 0 ]]; then
    az_args+=(--metadata "${metadata_args[@]}")
  fi

  if az policy definition show --name "$name" --subscription "$AZURE_SUB_ID" >/dev/null 2>&1; then
    echo "  Updating policy definition: $name"
    az policy definition update "${az_args[@]}" >/dev/null
  else
    echo "  Creating policy definition: $name"
    az policy definition create "${az_args[@]}" >/dev/null
  fi

  rm -f "$rules_file" "$params_file"
}

deploy_policy_initiative() {
  local file="$INITIATIVE_FILE"
  local name display_name description
  name=$(jq -r '.name' "$file")
  display_name=$(jq -r '.properties.displayName' "$file")
  description=$(jq -r '.properties.description' "$file")

  # policyDefinitionId values for custom (non-built-in) definitions are checked in as the
  # unresolved ARM expression "[concat(subscription().id, '/providers/.../<name>')]" so the JSON
  # self-documents intent without a hardcoded subscription ID. `az policy set-definition create`
  # does not evaluate ARM template functions (it is not an ARM template deployment), so this
  # expression must be resolved to a literal "/subscriptions/<id>/providers/..." string here
  # before being handed to the CLI, or the API rejects it with InvalidCreatePolicySetDefinitionRequest.
  local concat_prefix="[concat(subscription().id, '/providers/Microsoft.Authorization/policyDefinitions/"
  local concat_suffix="')]"
  local resolved_prefix="/subscriptions/${AZURE_SUB_ID}/providers/Microsoft.Authorization/policyDefinitions/"

  local params_file definitions_file groups_file
  params_file=$(mktemp)
  definitions_file=$(mktemp)
  groups_file=$(mktemp)
  jq '.properties.parameters // {}' "$file" > "$params_file"
  jq --arg prefix "$concat_prefix" --arg suffix "$concat_suffix" --arg resolved "$resolved_prefix" \
    '.properties.policyDefinitions | map(
       if (.policyDefinitionId | startswith($prefix)) then
         .policyDefinitionId = ($resolved + (.policyDefinitionId | ltrimstr($prefix) | rtrimstr($suffix)))
       else . end
     )' "$file" > "$definitions_file"
  jq '.properties.policyDefinitionGroups // []' "$file" > "$groups_file"

  local -a az_args=(
    --name "$name"
    --display-name "$display_name"
    --description "$description"
    --params "$params_file"
    --definitions "$definitions_file"
    --definition-groups "$groups_file"
    --subscription "$AZURE_SUB_ID"
  )

  if az policy set-definition show --name "$name" --subscription "$AZURE_SUB_ID" >/dev/null 2>&1; then
    echo "  Updating policy initiative: $name"
    az policy set-definition update "${az_args[@]}" >/dev/null
  else
    echo "  Creating policy initiative: $name"
    az policy set-definition create "${az_args[@]}" >/dev/null
  fi

  rm -f "$params_file" "$definitions_file" "$groups_file"
}

deploy_policy_assignment() {
  local file="$ASSIGNMENT_FILE"
  local name display_name description enforcement_mode
  name=$(jq -r '.name' "$file")
  display_name=$(jq -r '.properties.displayName' "$file")
  description=$(jq -r '.properties.description' "$file")
  enforcement_mode=$(jq -r '.properties.enforcementMode // "Default"' "$file")

  local policy_set_definition_name
  policy_set_definition_name=$(jq -r '.name' "$INITIATIVE_FILE")

  local owner_ids_json
  owner_ids_json=$(jq -n --arg owner "$POLICY_PRINCIPAL_ID" '[$owner]')

  local params_file
  params_file=$(mktemp)
  jq --argjson ownerIds "$owner_ids_json" \
     '.properties.parameters | (.allowedOwnerPrincipalIds.value = $ownerIds)' \
     "$file" > "$params_file"

  local scope="/subscriptions/${AZURE_SUB_ID}"

  if az policy assignment show --name "$name" --scope "$scope" >/dev/null 2>&1; then
    echo "  Updating policy assignment: $name"
    az policy assignment update \
      --name "$name" \
      --scope "$scope" \
      --display-name "$display_name" \
      --description "$description" \
      --params "$params_file" \
      --enforcement-mode "$enforcement_mode" \
      >/dev/null
  else
    echo "  Creating policy assignment: $name"
    az policy assignment create \
      --name "$name" \
      --display-name "$display_name" \
      --description "$description" \
      --scope "$scope" \
      --policy-set-definition "$policy_set_definition_name" \
      --params "$params_file" \
      --enforcement-mode "$enforcement_mode" \
      --mi-system-assigned \
      --location "$LOCATION" \
      >/dev/null
  fi

  rm -f "$params_file"
}

echo "Step 1/3: Deploying policy definitions from $DEFINITIONS_DIR ..."
for definition_file in "$DEFINITIONS_DIR"/*.json; do
  deploy_policy_definition "$definition_file"
done

echo "Step 2/3: Deploying policy initiative..."
deploy_policy_initiative

echo "Step 3/3: Deploying policy assignment..."
deploy_policy_assignment

echo "Policy deployment complete: 7 definitions, 1 initiative, 1 assignment."
