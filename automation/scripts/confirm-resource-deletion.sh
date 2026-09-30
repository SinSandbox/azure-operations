#!/usr/bin/env bash
# Resource cleanup, steps 3 & 4: Confirm which of the approved-for-deletion resources were
# actually removed from the subscription, and output the full set of resources that remain in the
# subscription after the cleanup run.
#
# Requires: az CLI logged in with at least Reader access to the subscription; jq installed
# (preinstalled on GitHub-hosted ubuntu runners).
#
# Environment variables:
#   AZURE_SUB_ID                  (required) subscription ID that was cleaned up.
#   CANDIDATES_OUTPUT_FILE        (optional, default: deletable-resources.json) list attempted for deletion.
#   STILL_PRESENT_OUTPUT_FILE     (optional, default: still-present-resources.json) candidates that
#                                   were NOT successfully removed.
#   REMAINING_OUTPUT_FILE         (optional, default: remaining-resources.json) full current
#                                   resource inventory of the subscription, post-cleanup.
#   SUMMARY_OUTPUT_FILE           (optional, default: cleanup-confirmation-summary.md)

set -euo pipefail

: "${AZURE_SUB_ID:?AZURE_SUB_ID is required}"

CANDIDATES_OUTPUT_FILE="${CANDIDATES_OUTPUT_FILE:-deletable-resources.json}"
STILL_PRESENT_OUTPUT_FILE="${STILL_PRESENT_OUTPUT_FILE:-still-present-resources.json}"
REMAINING_OUTPUT_FILE="${REMAINING_OUTPUT_FILE:-remaining-resources.json}"
SUMMARY_OUTPUT_FILE="${SUMMARY_OUTPUT_FILE:-cleanup-confirmation-summary.md}"

echo "Re-listing all resources currently in subscription $AZURE_SUB_ID..."
az resource list \
  --subscription "$AZURE_SUB_ID" \
  -o json > "$REMAINING_OUTPUT_FILE"

remaining_count=$(jq 'length' "$REMAINING_OUTPUT_FILE")

# Step 3: confirm deletion — of the resources we attempted to delete, which ones are still present?
if [[ -f "$CANDIDATES_OUTPUT_FILE" ]]; then
  attempted_count=$(jq 'length' "$CANDIDATES_OUTPUT_FILE")
  jq -n \
    --slurpfile candidates "$CANDIDATES_OUTPUT_FILE" \
    --slurpfile remaining "$REMAINING_OUTPUT_FILE" \
    '($remaining[0] | map(.id)) as $remaining_ids
     | [$candidates[0][] | select(.id as $id | $remaining_ids | index($id) != null)]' \
    > "$STILL_PRESENT_OUTPUT_FILE"
else
  echo "No candidate file ($CANDIDATES_OUTPUT_FILE) found; skipping deletion confirmation." >&2
  attempted_count=0
  echo "[]" > "$STILL_PRESENT_OUTPUT_FILE"
fi

still_present_count=$(jq 'length' "$STILL_PRESENT_OUTPUT_FILE")
deleted_count=$((attempted_count - still_present_count))

{
  echo "# Cleanup confirmation"
  echo ""
  echo "Subscription: \`$AZURE_SUB_ID\`"
  echo ""
  echo "- Attempted deletions: **$attempted_count**"
  echo "- Confirmed deleted: **$deleted_count**"
  echo "- Still present (not deleted): **$still_present_count**"
  echo "- Total resources remaining in subscription: **$remaining_count**"
  echo ""
  if [[ "$still_present_count" -gt 0 ]]; then
    echo "## Resources that failed to delete"
    echo ""
    echo "| Name | Type | Resource Group |"
    echo "| --- | --- | --- |"
    jq -r '.[] | "| " + .name + " | " + .type + " | " + .resourceGroup + " |"' "$STILL_PRESENT_OUTPUT_FILE"
    echo ""
  fi
  echo "## All resources remaining in subscription"
  echo ""
  echo "| Name | Type | Resource Group | Location |"
  echo "| --- | --- | --- | --- |"
  jq -r '.[] | "| " + .name + " | " + .type + " | " + .resourceGroup + " | " + .location + " |"' "$REMAINING_OUTPUT_FILE"
} > "$SUMMARY_OUTPUT_FILE"

cat "$SUMMARY_OUTPUT_FILE"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  cat "$SUMMARY_OUTPUT_FILE" >> "$GITHUB_STEP_SUMMARY"
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "still_present_count=$still_present_count"
    echo "remaining_count=$remaining_count"
  } >> "$GITHUB_OUTPUT"
fi

if [[ "$still_present_count" -gt 0 ]]; then
  echo "WARNING: $still_present_count resource(s) targeted for deletion are still present in the subscription."
fi
