#!/usr/bin/env bash
# Resource cleanup, steps 7 & 8: Confirm which of the approved-for-deletion empty resource groups
# were actually removed from the subscription, and output the full set of resource groups that
# remain in the subscription after the cleanup run.
#
# Requires: az CLI logged in with at least Reader access to the subscription; jq installed
# (preinstalled on GitHub-hosted ubuntu runners).
#
# Environment variables:
#   AZURE_SUB_ID                  (required) subscription ID that was cleaned up.
#   CANDIDATES_OUTPUT_FILE        (optional, default: empty-resource-groups.json) list attempted
#                                   for deletion.
#   STILL_PRESENT_OUTPUT_FILE     (optional, default: still-present-resource-groups.json)
#                                   candidates that were NOT successfully removed.
#   REMAINING_OUTPUT_FILE         (optional, default: remaining-resource-groups.json) full current
#                                   resource-group inventory of the subscription, post-cleanup.
#   SUMMARY_OUTPUT_FILE           (optional, default: empty-rg-cleanup-confirmation-summary.md)

set -euo pipefail

: "${AZURE_SUB_ID:?AZURE_SUB_ID is required}"

CANDIDATES_OUTPUT_FILE="${CANDIDATES_OUTPUT_FILE:-empty-resource-groups.json}"
STILL_PRESENT_OUTPUT_FILE="${STILL_PRESENT_OUTPUT_FILE:-still-present-resource-groups.json}"
REMAINING_OUTPUT_FILE="${REMAINING_OUTPUT_FILE:-remaining-resource-groups.json}"
SUMMARY_OUTPUT_FILE="${SUMMARY_OUTPUT_FILE:-empty-rg-cleanup-confirmation-summary.md}"

echo "Re-listing all resource groups currently in subscription $AZURE_SUB_ID..."
az group list \
  --subscription "$AZURE_SUB_ID" \
  -o json > "$REMAINING_OUTPUT_FILE"

remaining_count=$(jq 'length' "$REMAINING_OUTPUT_FILE")

# Confirm deletion — of the resource groups we attempted to delete, which ones are still present?
if [[ -f "$CANDIDATES_OUTPUT_FILE" ]]; then
  attempted_count=$(jq 'length' "$CANDIDATES_OUTPUT_FILE")
  jq -n \
    --slurpfile candidates "$CANDIDATES_OUTPUT_FILE" \
    --slurpfile remaining "$REMAINING_OUTPUT_FILE" \
    '($remaining[0] | map(.name | ascii_downcase)) as $remaining_names
     | [$candidates[0][] | select((.name | ascii_downcase) as $name | $remaining_names | index($name) != null)]' \
    > "$STILL_PRESENT_OUTPUT_FILE"
else
  echo "No candidate file ($CANDIDATES_OUTPUT_FILE) found; skipping deletion confirmation." >&2
  attempted_count=0
  echo "[]" > "$STILL_PRESENT_OUTPUT_FILE"
fi

still_present_count=$(jq 'length' "$STILL_PRESENT_OUTPUT_FILE")
deleted_count=$((attempted_count - still_present_count))

{
  echo "# Empty resource group cleanup confirmation"
  echo ""
  echo "Subscription: \`$AZURE_SUB_ID\`"
  echo ""
  echo "- Attempted deletions: **$attempted_count**"
  echo "- Confirmed deleted: **$deleted_count**"
  echo "- Still present (not deleted): **$still_present_count**"
  echo "- Total resource groups remaining in subscription: **$remaining_count**"
  echo ""
  if [[ "$still_present_count" -gt 0 ]]; then
    echo "## Resource groups that failed to delete"
    echo ""
    echo "| Name |"
    echo "| --- |"
    jq -r '.[] | "| " + .name + " |"' "$STILL_PRESENT_OUTPUT_FILE"
    echo ""
  fi
  echo "## All resource groups remaining in subscription"
  echo ""
  echo "| Name | Location |"
  echo "| --- | --- |"
  jq -r '.[] | "| " + .name + " | " + .location + " |"' "$REMAINING_OUTPUT_FILE"
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
  echo "WARNING: $still_present_count resource group(s) targeted for deletion are still present in the subscription."
fi
