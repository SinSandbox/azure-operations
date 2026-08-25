# Azure Policy — Demo Environment Cost Governance

This folder contains deployable Azure Policy artifacts that implement the controls defined in:
- `docs/project-planning/azure-demo-subscription-cost-control-brd.md`
- `docs/project-planning/azure-demo-subscription-technical-requirements.md`

## Folder structure

```
policy/
├── policyDefinitions/          # Individual custom policy definitions
├── policyInitiatives/          # Policy set (initiative) bundling custom + built-in policies
└── policyAssignments/          # Assignment template to apply the initiative to a subscription
```

## Policy definitions and requirement mapping

| File | Policy name | Requirement | What it enforces |
| --- | --- | --- | --- |
| `require-mandatory-tags.json` | demo-require-mandatory-tags | TR-001 | Denies resources missing `Environment`, `Owner`, `CostCenter`, `Purpose`, or `ExpirationDate` tags. |
| `enforce-expiration-date-limit.json` | demo-enforce-expiration-date-limit | TR-005 | Denies resources whose `ExpirationDate` tag is more than 5 calendar days (parameterized, default `P5D`) from now. |
| `deny-disallowed-resource-types.json` | demo-deny-disallowed-resource-types | TR-002 | Denies deployment of production-tier/enterprise services (Synapse, Databricks, AKS, dedicated SQL VMs, HDInsight, Kusto, Recovery Services vaults, etc.). |
| `allowed-vm-skus.json` | demo-allowed-vm-skus | TR-002 | Restricts virtual machines to an allow-list of small/low-cost SKUs (B-series, small D-series). |
| `deny-public-ip-addresses.json` | demo-deny-public-ip-addresses | TR-002, TR-007 | Denies public IP address resources unless an approval exception tag is present. |
| `audit-vm-autoshutdown-schedule.json` | demo-audit-vm-autoshutdown-schedule | TR-004 | Audits VMs that do not have an enabled auto-shutdown schedule (`Microsoft.DevTestLab/schedules`). |
| `deny-standing-privileged-role-assignments.json` | demo-deny-standing-privileged-role-assignments | TR-006 | Denies/audits standing (permanent) Owner, Contributor, or User Access Administrator role assignments except for the designated subscription owner principal(s). |

The initiative also references the built-in **Allowed locations** policy (`e56962a6-4747-49cd-b67b-bf8b01975c4c`) to restrict deployment regions.

## Initiative

`policyInitiatives/demo-environment-cost-governance-initiative.json` bundles all of the above into a single policy set named **Demo Environment Cost Governance Initiative**, grouped by requirement ID (TR-001, TR-002, TR-004, TR-005, TR-006, TR-007) for compliance reporting.

All effects and allow-lists are exposed as initiative parameters so they can be tuned per environment without editing the policy definitions.

## Assignment

`policyAssignments/demo-environment-cost-governance-assignment.json` is the ready-to-deploy assignment for a subscription — it no longer contains manual placeholders:
- `policyDefinitionId` uses the `[concat(subscription().id, '/providers/Microsoft.Authorization/policySetDefinitions/demo-environment-cost-governance')]` policy function, so it self-resolves to whichever subscription it is deployed into (Azure Policy evaluates this function natively; no ARM template deployment is required). `policy/scripts/deploy-policy.sh` bypasses this field entirely and resolves the initiative via `--policy-set-definition <name>` instead, so either mechanism works.
- `allowedOwnerPrincipalIds` defaults to an empty array in the checked-in file and **must** be supplied at deployment time via the `POLICY_PRINCIPAL_ID` environment variable (local run) or the `AZURE_MI_PRINCIPAL_ID` environment secret (`.github/workflows/deploy-policy.yml`) — `deploy-policy.sh` always overrides this parameter from that value, so editing the JSON file directly has no effect on deployment.

Review the default effect values before deploying — `standingAccessEffect` defaults to `Audit` so the access-restriction rule can be validated before switching to `Deny`.

## Automated deployment

`policy/scripts/deploy-policy.sh` deploys all three artifact types, in order, and is idempotent (creates on first run, updates on subsequent runs):
1. Every custom policy definition in `policyDefinitions/*.json`.
2. The policy initiative in `policyInitiatives/demo-environment-cost-governance-initiative.json`.
3. The subscription-scope policy assignment in `policyAssignments/demo-environment-cost-governance-assignment.json`, with `allowedOwnerPrincipalIds` supplied via the `POLICY_PRINCIPAL_ID` environment variable.

Run it locally with:
```bash
export AZURE_SUB_ID="<subscription-id>"
export POLICY_PRINCIPAL_ID="<owner-object-id>"
az login
bash policy/scripts/deploy-policy.sh
```

Or trigger `.github/workflows/deploy-policy.yml` (`workflow_dispatch`) against a GitHub environment (default `dev`) configured with `AZURE_MI_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUB_ID`, and `AZURE_MI_PRINCIPAL_ID` secrets and OIDC federation; the workflow maps `AZURE_MI_PRINCIPAL_ID` to `POLICY_PRINCIPAL_ID` for `deploy-policy.sh`.

After deployment:
- Run an on-demand policy compliance scan and review the compliance dashboard.
- Start all effects in `Audit` mode, validate for a review cycle, then switch enforcement effects to `Deny` for TR-001, TR-002, and TR-005 per the BRD's mandatory guardrails.

## Requirements intentionally not covered by Azure Policy

- **Budget alerts and spend thresholds (TR-003)** — configured through Azure Cost Management budgets and action groups, not Azure Policy.
- **Automated shutdown execution and cleanup workflows (TR-004, TR-005)** — the initiative only *audits* for the presence of a shutdown schedule; the shutdown/cleanup automation itself (Automation Account runbooks, Logic Apps, or Azure DevTest Labs schedules) is implementation tooling, not policy, and remains a separate follow-up.
- **PIM 10-hour activation limit (TR-006)** — Azure Policy can restrict *standing* role assignments (implemented above), but the actual just-in-time activation duration, approval requirements, and eligible-role configuration are set in **Microsoft Entra Privileged Identity Management (PIM) role settings**, which is an Entra ID configuration, not an Azure Resource Manager policy.
- **Workbook/dashboard reporting (TR-008, TR-009)** — built from Azure Monitor Workbooks and Cost Management data using the compliance and cost data these policies generate; not a policy artifact itself.

## Traceability to BRD

| BRD requirement | Policy artifact |
| --- | --- |
| BG-006 / NFR-001 — $0 cost after cleanup | Supported indirectly via TR-004 (shutdown audit) and TR-005 (expiration enforcement); actual $0 outcome depends on cleanup automation, not policy alone. |
| BR-003/BR-004 — mandatory tags and 5-day expiration | `require-mandatory-tags.json`, `enforce-expiration-date-limit.json` |
| BR-006/BR-007/BR-008 — no standing privileged access, PIM JIT, 10-hour limit | `deny-standing-privileged-role-assignments.json` (standing-access portion only; PIM duration is configured in Entra ID) |
| CON-003 — avoid premium/enterprise services | `deny-disallowed-resource-types.json`, `allowed-vm-skus.json` |
