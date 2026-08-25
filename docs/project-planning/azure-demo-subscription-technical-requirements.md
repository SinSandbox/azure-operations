# Azure Demo Subscription Technical Requirements

## 1. Overview

This technical requirements document defines the platform controls, policy, and operational guardrails required to govern an Azure subscription used exclusively for demo purposes. The environment is not intended for production workloads, and cost control is the primary design requirement.

The technical controls must enforce:
- low-cost resource choices
- short-lived resource lifecycles
- automated shutdown and cleanup
- access restrictions via least privilege and PIM
- budget alerts and reporting
- clear ownership and compliance visibility

## 2. Objective

The purpose of the environment is to host demo applications, proof-of-concept work, training sessions, and short-lived experiments while minimizing operational cost and reducing risk of unmanaged resources.

The technical solution must support a secure, low-friction, low-cost operating model without allowing standing administrative access for non-owner users. When no demo application is actively running after cleanup, the environment must trend toward $0 Azure charges for idle or unused resources.

## 3. Scope

### In scope
- Azure subscription configuration and governance
- Azure Policy enforcement
- monitor, alert, and dashboard configuration
- VM and compute shutdown automation logic
- resource tagging and lifecycle enforcement
- cleanup and expiration workflow design
- privileged access model using Azure PIM

### Out of scope
- production application deployments
- production-grade failover and disaster recovery designs
- long-lived business workloads
- enterprise landing zone transformations beyond this demo subscription
- script implementation or runtime automation deployment details

## 4. Design Principles

- Cost is the governing constraint.
- All resources must have an owner and expiration date.
- Demo resources must be short-lived and easy to teardown.
- Production-grade features are avoided unless specifically required by the demo.
- Access must be time-bound and least privileged.
- The environment must be auditable and visible to the subscription owner.

## 5. Functional Requirements

### TR-001: Resource tagging and metadata requirements
The environment must require all deployed resources to include the following metadata:
- Environment
- Owner
- CostCenter
- Purpose
- ExpirationDate

Acceptance criteria:
- All newly created resources include the required tags.
- Resources missing required tags are rejected or flagged for remediation.
- Resource owner is identifiable for every active demo workload.
- ExpirationDate is set for each resource and is not later than 5 calendar days from creation unless an approved exception exists.

### TR-002: Allowed resource model and SKU control
The environment must restrict deployments to demo-appropriate Azure services and SKUs.

Acceptance criteria:
- Premium, production-scale, or enterprise-tier services are denied by default.
- Disallowed service types and high-cost SKUs are blocked through Azure Policy.
- Small compute, low-cost app hosting, and serverless patterns are preferred.
- Production-only services are not allowed without a documented exception.

### TR-003: Budget enforcement
The subscription must have a defined monthly cost ceiling and alerting rules.

Acceptance criteria:
- A monthly budget is configured for the subscription before use.
- Alert thresholds are configured for 50%, 80%, and 100% of the budget.
- Notifications are sent to designated owners.
- Cost telemetry is available in an Azure cost dashboard or workbook.
- Deployment or spending actions can be triggered when the budget threshold is reached.
- When there is no demo application running after resources cleanup, the Azure subscription must be at $0 cost.
- The environment must allow no active Azure spend after cleanup when all demo workloads are terminated and no quota or service billing remains.

### TR-004: Automatic shutdown and idle lifecycle control
Compute resources must be scheduled and stopped outside active usage periods.

Acceptance criteria:
- VM or compute workspaces are configured for scheduled shutdown when not in active use.
- Idle resources are stopped after a defined inactivity period.
- The default operating model is low-cost and auto-stopped rather than always-on.
- Demo owners can identify which resources are scheduled for shutdown.

### TR-005: Resource expiration and teardown governance
The environment must support automatic expiration and cleanup of short-lived workloads.

Acceptance criteria:
- Every deployed resource has an expiration date or project end date.
- Resources must be set to expire in fewer than 5 calendar days unless an approved exception exists.
- Resources with no owner or no expiration date are flagged for remediation.
- Expired resources are identified and sent to cleanup workflow.
- Workload owners are notified before cleanup or shutdown actions are applied.

### TR-006: Access restriction and least privilege
Access to the environment must be tightly controlled.

Acceptance criteria:
- Except for the subscription owner, no user has standing Owner, Administrator, or Contributor access.
- All non-owner privileged access uses least-privilege accounts.
- Privileged access is granted through Azure PIM just-in-time activation.
- Privileged access is limited to a maximum of 10 hours per activation request.
- No active privileged assignment remains beyond the valid time window without a new activation.
- Privileged access is granted through Entra ID group-based role assignments as defined in TR-010, not through direct per-user role assignments.

### TR-010: Entra ID group-based role assignment model
Access to the subscription must be managed through two Entra ID security groups rather than individual user role assignments, so that role assignments, PIM eligibility, and access reviews are managed centrally at the group level.

#### Demo Contributors group
Members of this group are demo application builders who need to create and manage Azure resources (networking, virtual machines, Key Vault, storage, app services, and similar resource types) within the demo subscription.

Required role assignment:
- The group is assigned the built-in **Contributor** role at the subscription scope.
- The group's Contributor assignment is configured as PIM-eligible (not a standing/active assignment) per TR-006, with a maximum 10-hour activation duration.
- The group does not receive **Owner**, **User Access Administrator**, or other identity/RBAC-management roles; role and permission administration remains reserved for the subscription owner.
- Where Key Vault uses Azure RBAC for data-plane authorization, the group is additionally assigned **Key Vault Administrator** or **Key Vault Secrets/Certificates/Crypto Officer** roles as needed for demo scenarios, scoped to the relevant Key Vault or resource group rather than the full subscription when practical.

#### Demo Readers group
Members of this group are users who need to view and query resources and their configuration in the subscription (for example, to review a demo, audit configuration, or investigate an issue) without the ability to create, modify, or delete resources.

Required role assignment:
- The group is assigned the built-in **Reader** role at the subscription scope.
- The group's Reader assignment may be a standing assignment because Reader access does not grant write or management permissions and is not restricted by TR-006's standing-access limitation, which applies to Owner, Contributor, and User Access Administrator roles.
- The group does not receive any role that permits creating, modifying, or deleting resources, secrets, or role assignments.
- The group may optionally be assigned **Monitoring Reader** or **Cost Management Reader** where query access to logs, metrics, or cost data supports demo review activities, scoped to the subscription.

Acceptance criteria:
- Two Entra ID security groups exist: a Demo Contributors group and a Demo Readers group.
- All non-owner contributor access to the subscription is granted only through membership in the Demo Contributors group, never through a direct per-user role assignment.
- All read-only access to the subscription is granted only through membership in the Demo Readers group, never through a direct per-user role assignment.
- The Demo Contributors group's Contributor role assignment is PIM-eligible and time-bound per TR-006.
- The Demo Readers group's Reader role assignment may remain standing/active since it carries no write, delete, or management capability.
- Group membership changes are auditable and reviewable by the subscription owner.

### TR-007: Azure Policy guardrails
The platform must implement policy-based controls to enforce environment governance.

Acceptance criteria:
- Resource type restrictions are enforced.
- Mandatory tags are required for resource creation.
- Expiration rules are enforced by policy or policy remediation.
- High-cost or production-tier SKUs are blocked by default.
- Public exposure rules are enforced for demo workloads when not explicitly needed.
- Policy compliance is visible through Azure compliance and reporting surfaces.

### TR-008: Monitoring and workload visibility
The subscription must provide operational visibility into cost, compliance, and resource state.

Acceptance criteria:
- Cost trends are viewable by subscription owner.
- Daily and monthly spend are visible through dashboard or workbook views.
- Expired or non-compliant resources are visible to the owner.
- Unused resources and idle compute are tracked and reported.
- Governance and compliance status are visible without manual reporting.

### TR-009: Workbook and governance reporting
The solution must provide a consolidated operational view for demo environment governance.

Acceptance criteria:
- A dashboard or workbook shows resource count by owner and team.
- Resources missing tags, expiration dates, or owners are visible in one report.
- Cost and compliance trends are displayed together.
- The status of auto-shutdown and expiration compliance is visible.
- The report supports periodic review by the subscription owner and demo team leads.

## 6. Non-Functional Requirements

### NFR-001: Cost control
The environment must remain within the approved budget for the subscription and should default to the lowest-cost suitable configuration for any demo workload. When no demo application is running after cleanup, the environment must trend toward $0 Azure charges for idle or unused resources.

### NFR-002: Simplicity
The environment must be easy to deploy, operate, and decommission without specialized operational effort.

### NFR-003: Security baseline
The environment must enforce least privilege, limited exposure, and time-bounded privileged access using Azure PIM.

### NFR-004: Maintainability
The environment must support quick cleanup, repeatable re-provisioning, and low operational effort for demo resources.

### NFR-005: Auditability
All resources must be attributable to an owner, project, or demo purpose and must be reviewable through cost and compliance reports.

### NFR-006: Reliability for non-production use
The environment must be stable enough to support demonstrations but does not require production-grade SLAs or high-availability design.

## 7. Technical Constraints

- The subscription is for demo use only and must not host production applications.
- Cost is the primary technical decision driver.
- Premium or production-tier services are not allowed unless explicitly approved.
- No resource may remain active for more than 5 calendar days without an approved exception.
- No user other than the subscription owner may retain standing privileged access.
- Privileged admin or contributor access must be time-bound and activated using PIM.
- Contributor and reader access to the subscription must be granted through Entra ID security groups (Demo Contributors, Demo Readers) rather than direct per-user role assignments.

## 8. Operational Model

The environment should operate under the following control model:
- Azure Policy enforces restrictions and required metadata.
- Azure Monitor and cost tooling provide alerts and reporting.
- Workbooks or dashboards provide visibility into spend, compliance, and resource lifecycle.
- Cleanup and shutdown workflows are triggered on expiration, inactivity, or budget alerts.
- PIM controls privileged access to reduce standing risk.

## 9. Governance and Review

The technical design must be reviewed by the subscription owner and demo stakeholders before onboarding workloads. Any exception to the cost policy, service catalog restrictions, or access model must be documented with a defined expiration date and reason.

## 10. Acceptance Summary

The solution is considered technically compliant when all required controls are active and the following outcomes are met:
- cost limits and alerts are in place
- resources are tagged and expiration-based
- all workloads are short-lived and department-owned
- no non-owner retains standing privileged access
- PIM-backed access is activated only within the 10-hour limit
- idle resources are shut down automatically
- expired resources are cleaned up or stopped
- when no demo application is running after cleanup, the subscription trends toward $0 Azure charges for idle or unused resources
- dashboards show current compliance and cost posture
- contributor and reader access are granted exclusively through the Demo Contributors and Demo Readers Entra ID groups, with no direct per-user role assignments

## 11. Traceability to BRD

| BRD Requirement | Technical Requirement |
| --- | --- |
| Cost control is the primary goal | TR-003, TR-004, TR-005, TR-008 |
| Enforced tagging and expiration | TR-001, TR-005, TR-007 |
| Limited service catalog and low-cost choices | TR-002, TR-007 |
| Access control and JIT access | TR-006, TR-010 |
| Monitoring and governance visibility | TR-008, TR-009 |
| Cleanup and decommissioning | TR-005, TR-009 |

## 12. Version

- Version 0.1
- Initial technical requirement draft derived from the Azure demo subscription BRD
