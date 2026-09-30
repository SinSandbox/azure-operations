#!/usr/bin/env bash
# Resource cleanup, step 6 (post-approval): Delete every resource group listed in the reviewed
# candidate file produced by find-empty-resource-groups.sh. This step only runs after a human has
# reviewed the candidate list and the workflow's approval gate (GitHub Environment protection
# rule / required reviewers) has been satisfied — see
# .github/workflows/cleanup-untagged-non-vm-resources.yml.
#
# Requires: az CLI logged in with Contributor (or higher) access to the resource groups being
# deleted; jq installed (preinstalled on GitHub-hosted ubuntu runners).
#
# Environment variables:
#   AZURE_SUB_ID              (required) subscription ID the candidates belong to.
#   CANDIDATES_OUTPUT_FILE    (optional, default: empty-resource-groups.json) input file from step 5.
#   DELETION_RESULTS_FILE     (optional, default: empty-rg-deletion-results.json)
#   DRY_RUN                   (optional, default: false) set to "true" to log intended deletions
#                               without calling `az group delete`.

set -euo pipefail

: "${AZURE_SUB_ID:?AZURE_SUB_ID is required}"

CANDIDATES_OUTPUT_FILE="${CANDIDATES_OUTPUT_FILE:-empty-resource-groups.json}"
DELETION_RESULTS_FILE="${DELETION_RESULTS_FILE:-empty-rg-deletion-results.json}"
DRY_RUN="${DRY_RUN:-false}"

if [[ ! -f "$CANDIDATES_OUTPUT_FILE" ]]; then
  echo "Candidate file $CANDIDATES_OUTPUT_FILE not found. Run find-empty-resource-groups.sh first." >&2
  exit 1
fi

candidate_count=$(jq 'length' "$CANDIDATES_OUTPUT_FILE")
echo "Deleting $candidate_count approved empty resource group(s) from subscription $AZURE_SUB_ID..."

echo "[]" > "$DELETION_RESULTS_FILE"

if [[ "$candidate_count" -eq 0 ]]; then
  echo "No candidate empty resource groups to delete."
  exit 0
fi

jq -r '.[] | .name' "$CANDIDATES_OUTPUT_FILE" | while read -r rg_name; do
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "DRY_RUN: would delete resource group $rg_name"
    status="skipped-dry-run"
  else
    echo "Deleting resource group: $rg_name"
    if az group delete --subscription "$AZURE_SUB_ID" --name "$rg_name" --yes 2>/tmp/rg-delete-error.log; then
      status="deleted"
    else
      status="failed"
      echo "  WARNING: failed to delete resource group $rg_name"
      cat /tmp/rg-delete-error.log >&2 || true
    fi
  fi
  jq -n --arg name "$rg_name" --arg status "$status" '{name: $name, status: $status}' \
    >> "$DELETION_RESULTS_FILE.ndjson"
done

# Fold the newline-delimited per-resource-group results into a single JSON array.
if [[ -f "$DELETION_RESULTS_FILE.ndjson" ]]; then
  jq -s '.' "$DELETION_RESULTS_FILE.ndjson" > "$DELETION_RESULTS_FILE"
  rm -f "$DELETION_RESULTS_FILE.ndjson"
fi

failed_count=$(jq '[.[] | select(.status == "failed")] | length' "$DELETION_RESULTS_FILE")
echo "Resource group deletion pass complete. Failed: $failed_count / $candidate_count"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "failed_count=$failed_count" >> "$GITHUB_OUTPUT"
fi
