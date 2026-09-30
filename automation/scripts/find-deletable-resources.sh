#!/usr/bin/env bash
# Resource cleanup, step 1: Query the target subscription for all resources that are NOT tagged
# "Do Not Delete" (tag key match is case-insensitive; the tag's value is irrelevant — only its
# presence exempts the resource) and are NOT Virtual Machines (Microsoft.Compute/virtualMachines).
#
# This script is read-only. It produces a candidate list for human review before any deletion is
# attempted — see the "Provide resources for review" step in
# .github/workflows/cleanup-untagged-non-vm-resources.yml.
#
# Requires: az CLI logged in with at least Reader access to the subscription; jq installed
# (preinstalled on GitHub-hosted ubuntu runners).
#
# Environment variables:
#   AZURE_SUB_ID              (required) subscription ID to scan.
#   CANDIDATES_OUTPUT_FILE    (optional, default: deletable-resources.json)
#   SUMMARY_OUTPUT_FILE       (optional, default: deletable-resources-summary.md)

set -euo pipefail

: "${AZURE_SUB_ID:?AZURE_SUB_ID is required}"

CANDIDATES_OUTPUT_FILE="${CANDIDATES_OUTPUT_FILE:-deletable-resources.json}"
SUMMARY_OUTPUT_FILE="${SUMMARY_OUTPUT_FILE:-deletable-resources-summary.md}"

echo "Listing all resources in subscription $AZURE_SUB_ID..."
az resource list \
  --subscription "$AZURE_SUB_ID" \
  -o json > all-resources.json

# Exclude Virtual Machines and any resource that carries a "Do Not Delete" tag key (case-insensitive).
jq '[.[]
      | select(.type != "Microsoft.Compute/virtualMachines")
      | select((.tags // {}) | to_entries | all(.key | ascii_downcase != "do not delete"))
      | {id, name, type, resourceGroup, location, tags}]' \
   all-resources.json > "$CANDIDATES_OUTPUT_FILE"

candidate_count=$(jq 'length' "$CANDIDATES_OUTPUT_FILE")

{
  echo "# Resources proposed for deletion"
  echo ""
  echo "Subscription: \`$AZURE_SUB_ID\`"
  echo ""
  echo "Candidates found: **$candidate_count** (excludes Virtual Machines and resources tagged \"Do Not Delete\")"
  echo ""
  if [[ "$candidate_count" -gt 0 ]]; then
    echo "| Name | Type | Resource Group | Location |"
    echo "| --- | --- | --- | --- |"
    jq -r '.[] | "| " + .name + " | " + .type + " | " + .resourceGroup + " | " + .location + " |"' "$CANDIDATES_OUTPUT_FILE"
  else
    echo "No resources match the deletion criteria."
  fi
} > "$SUMMARY_OUTPUT_FILE"

echo "Wrote $candidate_count candidate resource(s) to $CANDIDATES_OUTPUT_FILE"
cat "$SUMMARY_OUTPUT_FILE"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  cat "$SUMMARY_OUTPUT_FILE" >> "$GITHUB_STEP_SUMMARY"
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "candidate_count=$candidate_count" >> "$GITHUB_OUTPUT"
fi
