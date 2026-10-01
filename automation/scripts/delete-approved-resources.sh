#!/usr/bin/env bash
# Resource cleanup, step 2 (post-approval): Delete every resource listed in the reviewed candidate
# file produced by find-deletable-resources.sh. This step only runs after a human has reviewed the
# candidate list and the workflow's approval gate (GitHub Environment protection rule / required
# reviewers) has been satisfied — see .github/workflows/cleanup-untagged-non-vm-resources.yml.
#
# Deletion order: resources are first sorted so nested children (resources whose ARM ID has more
# path segments, e.g. a subnet inside a virtual network) are attempted before their parents. Any
# deletion that still fails (e.g. a NIC referenced by a virtual network/subnet/NSG without being
# nested under it) is retried in a subsequent pass, so resources with no remaining dependents keep
# succeeding and unblocking their parents/referents. Passes continue until every resource is
# deleted or a full pass makes no progress, at which point anything left is reported as "failed".
#
# Requires: az CLI logged in with Contributor (or higher) access to the resources being deleted;
# jq installed (preinstalled on GitHub-hosted ubuntu runners).
#
# Environment variables:
#   AZURE_SUB_ID              (required) subscription ID the candidates belong to.
#   CANDIDATES_OUTPUT_FILE    (optional, default: deletable-resources.json) input file from step 1.
#   DELETION_RESULTS_FILE     (optional, default: deletion-results.json)
#   DRY_RUN                   (optional, default: false) set to "true" to log intended deletions
#                               without calling `az resource delete`.
#   MAX_PASSES                (optional, default: candidate count) upper bound on retry passes;
#                               a pass that deletes nothing always stops the loop early.
#   PRECHECK_NETWORK_DEPS     (optional, default: true) set to "false" to skip the subnet/virtual
#                               network dependency pre-check below and rely solely on retries.

set -euo pipefail

: "${AZURE_SUB_ID:?AZURE_SUB_ID is required}"

CANDIDATES_OUTPUT_FILE="${CANDIDATES_OUTPUT_FILE:-deletable-resources.json}"
DELETION_RESULTS_FILE="${DELETION_RESULTS_FILE:-deletion-results.json}"
DRY_RUN="${DRY_RUN:-false}"
PRECHECK_NETWORK_DEPS="${PRECHECK_NETWORK_DEPS:-true}"

# Per Microsoft's subnet/virtual network deletion guidance
# (https://learn.microsoft.com/en-us/troubleshoot/azure/virtual-network/virtual-network-troubleshoot-cannot-delete-modify-subnet),
# a subnet can't be deleted while it still has ipConfigurations (NICs/load balancers),
# privateEndpoints, serviceAssociationLinks, a natGateway, a networkSecurityGroup, a routeTable, or
# delegations; a virtual network can't be deleted while it still has subnets. Rather than letting
# `az resource delete` fail with a generic ARM error and relying purely on the retry loop below,
# query these specific associations up front so a blocked resource is skipped with a precise
# diagnostic and retried next pass once the blocker is gone. Any other resource type, or any query
# failure (resource already gone, insufficient permissions, etc.), falls through and lets the real
# delete call surface the error instead.
precheck_network_blockers() {
  local resource_id="$1"
  local info="" blockers="" subnet_ids=""

  if [[ "$resource_id" == *"/providers/Microsoft.Network/virtualNetworks/"*"/subnets/"* ]]; then
    if ! info=$(az network vnet subnet show --ids "$resource_id" \
          --query '{ipConfigurations: ipConfigurations, privateEndpoints: privateEndpoints, serviceAssociationLinks: serviceAssociationLinks, natGateway: natGateway, networkSecurityGroup: networkSecurityGroup, routeTable: routeTable, delegations: delegations}' \
          -o json 2>/dev/null); then
      return 0
    fi
    blockers=$(jq -r '
      [
        (if ((.ipConfigurations // []) | length) > 0 then "ipConfigurations (NICs/load balancers): " + ((.ipConfigurations // []) | map(.id) | join(", ")) else empty end),
        (if ((.privateEndpoints // []) | length) > 0 then "privateEndpoints: " + ((.privateEndpoints // []) | map(.id) | join(", ")) else empty end),
        (if ((.serviceAssociationLinks // []) | length) > 0 then "serviceAssociationLinks: " + ((.serviceAssociationLinks // []) | map(.linkedResourceType) | join(", ")) else empty end),
        (if (.natGateway // null) != null then "natGateway: " + .natGateway.id else empty end),
        (if (.networkSecurityGroup // null) != null then "networkSecurityGroup: " + .networkSecurityGroup.id else empty end),
        (if (.routeTable // null) != null then "routeTable: " + .routeTable.id else empty end),
        (if ((.delegations // []) | length) > 0 then "delegations: " + ((.delegations // []) | map(.serviceName) | join(", ")) else empty end)
      ] | map(select(. != null)) | join("; ")
    ' <<< "$info")
  elif [[ "$resource_id" == *"/providers/Microsoft.Network/virtualNetworks/"* ]]; then
    if ! subnet_ids=$(az network vnet show --ids "$resource_id" --query "subnets[].id" -o tsv 2>/dev/null); then
      return 0
    fi
    if [[ -n "$subnet_ids" ]]; then
      blockers="subnets still present: $(tr '\n' ',' <<< "$subnet_ids" | sed 's/,$//')"
    fi
  else
    return 0
  fi

  if [[ -n "$blockers" ]]; then
    echo "$blockers"
    return 1
  fi
  return 0
}

if [[ ! -f "$CANDIDATES_OUTPUT_FILE" ]]; then
  echo "Candidate file $CANDIDATES_OUTPUT_FILE not found. Run find-deletable-resources.sh first." >&2
  exit 1
fi

candidate_count=$(jq 'length' "$CANDIDATES_OUTPUT_FILE")
echo "Deleting $candidate_count approved resource(s) from subscription $AZURE_SUB_ID..."

echo "[]" > "$DELETION_RESULTS_FILE"

if [[ "$candidate_count" -eq 0 ]]; then
  echo "No candidate resources to delete."
  exit 0
fi

# Order candidates so nested child resources (longer ARM resource IDs, e.g. a subnet inside a
# virtual network) are attempted before their parents. This alone does not capture every Azure
# dependency (for example a NIC referencing a virtual network/subnet/NSG by ID without being
# nested under it), so the retry loop below reattempts any failures across multiple passes,
# letting resources with no remaining dependents succeed and unblock their parents/referents in
# the next pass. A pass that deletes nothing ends the loop early to avoid spinning on genuine
# errors (permissions, locks, etc.).
# Use a tab delimiter (not space) when sorting, since resource names/IDs may contain spaces.
mapfile -t resource_ids < <(
  jq -r '.[] | .id' "$CANDIDATES_OUTPUT_FILE" \
    | awk -F'/' '{printf "%d\t%s\n", NF, $0}' \
    | sort -t $'\t' -k1,1rn \
    | cut -f2-
)

declare -A status_map
remaining=("${resource_ids[@]}")
max_passes="${MAX_PASSES:-$candidate_count}"
if [[ "$max_passes" -lt 1 ]]; then
  max_passes=1
fi

pass=1
while [[ ${#remaining[@]} -gt 0 && "$pass" -le "$max_passes" ]]; do
  echo "--- Deletion pass $pass (${#remaining[@]} resource(s) remaining) ---"
  next_remaining=()
  progress=0
  for resource_id in "${remaining[@]}"; do
    if [[ "$DRY_RUN" == "true" ]]; then
      echo "DRY_RUN: would delete $resource_id"
      status_map["$resource_id"]="skipped-dry-run"
      progress=1
      continue
    fi
    if [[ "$PRECHECK_NETWORK_DEPS" == "true" ]]; then
      if ! blockers=$(precheck_network_blockers "$resource_id"); then
        echo "  SKIPPED (pass $pass): $resource_id still has dependent resources — $blockers"
        next_remaining+=("$resource_id")
        continue
      fi
    fi

    echo "Deleting: $resource_id"
    if az resource delete --ids "$resource_id" 2>/tmp/delete-error.log; then
      status_map["$resource_id"]="deleted"
      progress=1
    else
      echo "  WARNING: failed to delete $resource_id (pass $pass)"
      cat /tmp/delete-error.log >&2 || true
      next_remaining+=("$resource_id")
    fi
  done
  remaining=("${next_remaining[@]}")
  if [[ "$progress" -eq 0 ]]; then
    echo "No progress made in pass $pass; remaining resource(s) likely have unresolved dependencies or errors."
    break
  fi
  pass=$((pass + 1))
done

# Anything still outstanding after the retry loop (dependency never resolved, or a genuine error)
# is reported as failed.
for resource_id in "${remaining[@]}"; do
  status_map["$resource_id"]="failed"
done

for resource_id in "${resource_ids[@]}"; do
  status="${status_map[$resource_id]:-failed}"
  jq -n --arg id "$resource_id" --arg status "$status" '{id: $id, status: $status}' \
    >> "$DELETION_RESULTS_FILE.ndjson"
done

# Fold the newline-delimited per-resource results into a single JSON array.
if [[ -f "$DELETION_RESULTS_FILE.ndjson" ]]; then
  jq -s '.' "$DELETION_RESULTS_FILE.ndjson" > "$DELETION_RESULTS_FILE"
  rm -f "$DELETION_RESULTS_FILE.ndjson"
fi

failed_count=$(jq '[.[] | select(.status == "failed")] | length' "$DELETION_RESULTS_FILE")
echo "Deletion pass complete. Failed: $failed_count / $candidate_count"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "failed_count=$failed_count" >> "$GITHUB_OUTPUT"
fi
