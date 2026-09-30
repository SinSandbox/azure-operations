# Entra ID Group + PIM Role Assignment Automation

This folder contains the Bicep template and az CLI scripts that implement the Entra ID
group-based access model defined in:
- `docs/project-planning/azure-demo-subscription-technical-requirements.md` (TR-006, TR-010)
- `.copilot-tracking/plans/2026-08-24/entra-pim-group-role-deployment-plan.md` (phases P01–P04)
- `.copilot-tracking/details/2026-08-24/entra-pim-group-role-deployment-phase-details.md`

Deployment is orchestrated by `.github/workflows/deploy-entra-pim-groups.yml`.

## Why Bicep + az CLI, not Bicep alone

Entra ID security groups are a **Microsoft Graph** concept, not an Azure Resource Manager
resource, and the PIM role management policy (`Microsoft.Authorization/roleManagementPolicies`)
does not yet expose its `rules` payload in the published Bicep/ARM schema. This is a deliberate
split, not an oversight:

| Mechanism | Used for | Why |
| --- | --- | --- |
| Bicep (`bicep/main.bicep`) | Standing Reader role assignment (P02-T01); PIM-eligible Contributor role assignment (P02-T02) | Both are native `Microsoft.Authorization` ARM resources with confirmed Bicep support. |
| az CLI script (`scripts/create-entra-groups.sh`) | Entra ID group creation (P01) | Groups are Microsoft Graph objects (`az ad group`), not ARM resources. |
| az CLI script (`scripts/configure-pim-policy.sh`) | 10-hour max activation, no-approval rule (P03) | The ARM REST API supports the full policy `rules` payload; the published Bicep type does not (as of 2024-09-01-preview). |
| az CLI script (`scripts/inventory-role-assignments.sh`) | Inventory/remediation of pre-existing direct assignments (P02-T03) | One-time/idempotent read-and-report operation, not a deployable resource. |
| az CLI script (`scripts/check-policy-compliance.sh`) | Confirm policy assignment state and compliance (P04) | Reads live assignment/compliance state; not a deployment action. |

## Folder structure

```
automation/
├── bicep/
│   ├── main.bicep         # Subscription-scope: Reader assignment + Contributor PIM eligibility
│   └── main.bicepparam    # Reads group object IDs / environment name from environment variables
└── scripts/
    ├── create-entra-groups.sh          # P01 — create/reuse the two Entra ID groups
    ├── inventory-role-assignments.sh   # P02-T03 — flag direct assignments outside the group model
    ├── configure-pim-policy.sh         # P03-T01 — 10-hour cap, no approval required
    ├── check-policy-compliance.sh      # P04 — confirm policy assignment + compliance scan
    ├── find-deletable-resources.sh     # Cleanup step 1 — list non-VM resources missing a "Do Not Delete" tag
    ├── delete-approved-resources.sh    # Cleanup step 2/3 — delete the reviewed/approved candidates
    └── confirm-resource-deletion.sh    # Cleanup step 3/4 — confirm deletion + report remaining resources
```

## Prerequisites

The identity used to run this automation (a federated/OIDC app registration or user-assigned
managed identity) needs:
- Microsoft Graph application permission **Group.ReadWrite.All** (or **Directory.ReadWrite.All**) — group creation.
- Azure RBAC **User Access Administrator** (or **Owner**) at subscription scope — role assignment and PIM eligibility.
- Entra ID **Privileged Role Administrator** — PIM role management policy configuration.
- Azure RBAC **Reader** (or higher) — inventory and compliance checks.

## Running via GitHub Actions

The workflow `.github/workflows/deploy-entra-pim-groups.yml` is `workflow_dispatch`-triggered and
targets a GitHub **environment** (default `dev`) that must define these secrets:

| Secret | Purpose |
| --- | --- |
| `AZURE_MI_CLIENT_ID` | Client ID of the federated identity used for `azure/login` OIDC sign-in. |
| `AZURE_TENANT_ID` | Entra ID tenant ID. |
| `AZURE_SUB_ID` | Target Azure subscription ID. |

Workflow inputs let you override the group names, target region, PIM activation cap, whether the
inventory step (P02-T03) removes flagged direct assignments (`remediateDirectAssignments`,
default `false` — report-only), and whether the PIM policy step (P03-T01) is a dry run.

## Running locally

```bash
export AZURE_SUB_ID="<subscription-id>"
az login  # or az login --identity, depending on context

bash automation/scripts/create-entra-groups.sh   # exports DEMO_CONTRIBUTORS_GROUP_OBJECT_ID / DEMO_READERS_GROUP_OBJECT_ID

export ENVIRONMENT_NAME="dev"
az deployment sub create \
  --location eastus \
  --template-file automation/bicep/main.bicep \
  --parameters automation/bicep/main.bicepparam

bash automation/scripts/inventory-role-assignments.sh
bash automation/scripts/configure-pim-policy.sh
bash automation/scripts/check-policy-compliance.sh
```

## Resource cleanup automation (untagged, non-VM resources)

`scripts/find-deletable-resources.sh`, `scripts/delete-approved-resources.sh`, and
`scripts/confirm-resource-deletion.sh` are a separate, unrelated automation that lives in this
folder for consistency with the other az CLI scripts. They are orchestrated by
`.github/workflows/cleanup-untagged-non-vm-resources.yml`, which:

1. Logs in to the subscription and queries every resource that is **not** a Virtual Machine
   (`Microsoft.Compute/virtualMachines`) and does **not** carry a `Do Not Delete` tag (key match is
   case-insensitive).
2. Publishes that candidate list as a job summary and artifact for human review, then pauses at a
   GitHub Environment approval gate (configure **Required reviewers** on the environment) before
   deleting anything.
3. Deletes the approved candidates and confirms which ones were actually removed.
4. Outputs the full set of resources remaining in the subscription after the run.

Run `workflow_dispatch` with `dryRun: true` to preview deletions without calling
`az resource delete`. Locally:

```bash
export AZURE_SUB_ID="<subscription-id>"
az login

bash automation/scripts/find-deletable-resources.sh      # writes deletable-resources.json for review
bash automation/scripts/delete-approved-resources.sh     # deletes the reviewed candidates
bash automation/scripts/confirm-resource-deletion.sh     # confirms deletion + lists remaining resources
```

## Known open item

`configure-pim-policy.sh` targets rule IDs `Expiration_EndUser_Assignment` and
`Approval_EndUser_Assignment` on `Microsoft.Authorization/roleManagementPolicies`, based on the
best available planning-stage evidence. This is an implementation-time hypothesis, not a value
confirmed against a live tenant response — run the script once with `DRY_RUN=true` in a new
tenant and confirm the rule shape before relying on it, per the plan's P03-T01 task note.
