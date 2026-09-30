#!/usr/bin/env bash
# Resource cleanup, step 5: Query the target subscription for all resource groups that contain
# zero resources ("empty"), excluding any resource group that carries a tag whose VALUE (not key)
# is "Do Not Delete" (case-insensitive; any tag key qualifies — only the value is checked).
#
# This script is read-only. It produces a candidate list for human review before any resource
# group is removed — see the "Manual approval gate" comments in
# .github/workflows/cleanup-untagged-non-vm-resources.yml.
#
# Requires: az CLI logged in with at least Reader access to the subscription; jq installed
# (preinstalled on GitHub-hosted ubuntu runners).
#
# Environment variables:
#   AZURE_SUB_ID              (required) subscription ID to scan.
#   CANDIDATES_OUTPUT_FILE    (optional, default: empty-resource-groups.json)
#   SUMMARY_OUTPUT_FILE       (optional, default: empty-resource-groups-summary.md)

set -euo pipefail

: "${AZURE_SUB_ID:?AZURE_SUB_ID is required}"

CANDIDATES_OUTPUT_FILE="${CANDIDATES_OUTPUT_FILE:-empty-resource-groups.json}"
SUMMARY_OUTPUT_FILE="${SUMMARY_OUTPUT_FILE:-empty-resource-groups-summary.md}"

echo "Listing all resource groups in subscription $AZURE_SUB_ID..."
az group list \
  --subscription "$AZURE_SUB_ID" \
  -o json > all-resource-groups.json

echo "Listing all resources in subscription $AZURE_SUB_ID..."
az resource list \
  --subscription "$AZURE_SUB_ID" \
  -o json > all-resources.json

# A resource group is "empty" when no resource in the subscription reports it as its resourceGroup
# (case-insensitive name match). Exclude any resource group carrying a tag whose value is
# "Do Not Delete" (case-insensitive; the tag key is irrelevant).
jq --slurpfile resources all-resources.json \
  '($resources[0] | map(.resourceGroup | ascii_downcase)) as $usedGroups
   | [.[]
       | select((.name | ascii_downcase) as $rg | $usedGroups | index($rg) == null)
       | select((.tags // {}) | to_entries | all(.value | ascii_downcase != "do not delete"))
       | {name, location, tags}]' \
  all-resource-groups.json > "$CANDIDATES_OUTPUT_FILE"

candidate_count=$(jq 'length' "$CANDIDATES_OUTPUT_FILE")

{
  echo "# Empty resource groups proposed for deletion"
  echo ""
  echo "Subscription: \`$AZURE_SUB_ID\`"
  echo ""
  echo "Candidates found: **$candidate_count** (resource groups with zero resources, excluding any resource group carrying a tag whose value is \"Do Not Delete\")"
  echo ""
  if [[ "$candidate_count" -gt 0 ]]; then
    echo "| Name | Location |"
    echo "| --- | --- |"
    jq -r '.[] | "| " + .name + " | " + .location + " |"' "$CANDIDATES_OUTPUT_FILE"
  else
    echo "No empty resource groups found."
  fi
} > "$SUMMARY_OUTPUT_FILE"

echo "Wrote $candidate_count candidate empty resource group(s) to $CANDIDATES_OUTPUT_FILE"
cat "$SUMMARY_OUTPUT_FILE"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  cat "$SUMMARY_OUTPUT_FILE" >> "$GITHUB_STEP_SUMMARY"
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "candidate_count=$candidate_count" >> "$GITHUB_OUTPUT"
fi
