#!/usr/bin/env bash
# Resource cleanup, step 2 (post-approval): Delete every resource listed in the reviewed candidate
# file produced by find-deletable-resources.sh. This step only runs after a human has reviewed the
# candidate list and the workflow's approval gate (GitHub Environment protection rule / required
# reviewers) has been satisfied — see .github/workflows/cleanup-untagged-non-vm-resources.yml.
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

set -euo pipefail

: "${AZURE_SUB_ID:?AZURE_SUB_ID is required}"

CANDIDATES_OUTPUT_FILE="${CANDIDATES_OUTPUT_FILE:-deletable-resources.json}"
DELETION_RESULTS_FILE="${DELETION_RESULTS_FILE:-deletion-results.json}"
DRY_RUN="${DRY_RUN:-false}"

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

jq -r '.[] | .id' "$CANDIDATES_OUTPUT_FILE" | while read -r resource_id; do
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "DRY_RUN: would delete $resource_id"
    status="skipped-dry-run"
  else
    echo "Deleting: $resource_id"
    if az resource delete --ids "$resource_id" 2>/tmp/delete-error.log; then
      status="deleted"
    else
      status="failed"
      echo "  WARNING: failed to delete $resource_id"
      cat /tmp/delete-error.log >&2 || true
    fi
  fi
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
