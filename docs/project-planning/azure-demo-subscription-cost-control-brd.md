---
title: Azure Demo Subscription Cost Control BRD
version: 0.1
status: Draft
author: Copilot
last_updated: 2026-08-24
---

# Azure Demo Subscription Cost Control BRD

## 1. Executive Summary

This document defines the requirements for an Azure subscription used exclusively for demonstrations, proof-of-concept work, and internal learning activities. The subscription will not host production applications or business-critical workloads. The primary objective is to keep operational cost under control while preserving enough flexibility for demos and experimentation.

The solution must be designed around a low-cost, low-risk operating model with strict guardrails, tight resource lifecycle controls, and automated monitoring. Cost management is not an afterthought; it is a governing requirement for the environment.

## 2. Business Context

The environment supports demo activity and short-lived experimentation, not production delivery. Because the workload is non-production, business continuity, high availability, and full-scale enterprise operations are not required. This allows the organization to optimize for affordability, simplicity, and rapid teardown rather than resilience or scale.

The subscription must be safe to use by multiple demo teams while preventing accidental overspend caused by unplanned services, oversized virtual machines, idle resources, or forgotten workloads.

## 3. Business Goals

- BG-001: Keep monthly Azure spend for the demo subscription within a defined budget cap.
- BG-002: Prevent expensive or unnecessary services from being created in a non-production environment.
- BG-003: Provide a simple, low-friction environment for demo teams while maintaining basic governance.
- BG-004: Ensure the subscription can be cleaned up quickly at the end of demo cycles or project phases.
- BG-005: Minimize operational overhead by using automation instead of manual monitoring.

## 4. Scope

### In Scope
- Azure subscription setup for demo use only
- Resource creation rules for low-cost services
- Cost controls, alerts, and automatic shutdown
- Resource tagging and ownership tracking
- Decommissioning and cleanup of short-lived demo resources
- Restricted use of production-grade services and architectures

### Out of Scope
- Production workloads, production SLAs, or disaster recovery design
- High-availability enterprise database configurations
- Large-scale performance testing or load generation
- Regulatory-compliance programs for production systems
- Multi-subscription enterprise landing zone controls beyond the demo environment

## 5. Stakeholders

- Sponsor: Platform or IT leadership
- Primary users: Demo team, sales enablement, engineering enablement, training teams
- Technical owners: Azure administrators / cloud operations
- End users: Internal presenters and workshop facilitators
- Security approver: Minimal governance for non-production use

## 6. Functional Requirements

### FR-001: Budget controls and spending limits
The subscription must enforce an approved monthly cost ceiling and notify owners before the budget is exceeded.

Acceptance criteria:
- AC-001: A monthly budget is established for the subscription before first use.
- AC-002: Cost alerts are configured at 50%, 80%, and 100% of the budget.
- AC-003: Budget notifications are sent to designated owners through email or Azure Monitor alerts.
- AC-004: A spend limit or action policy prevents service creation when the threshold is exceeded.

### FR-002: Resource tagging and ownership
Every resource in the subscription must be tagged with ownership and lifecycle metadata.

Acceptance criteria:
- AC-005: Required tags include `Environment`, `Owner`, `CostCenter`, `Purpose`, and `ExpirationDate`.
- AC-006: New resources cannot be deployed without required tags.
- AC-007: Resource owners are identifiable for any active demo workload.

### FR-003: Cost-aware resource catalog
The environment must allow only low-cost, demo-appropriate Azure services.

Acceptance criteria:
- AC-008: The default service catalog excludes production-only PaaS and expensive data services.
- AC-009: Azure Policy or deployment guardrails block high-cost SKUs unless explicitly approved.
- AC-010: Standard compute choices prioritize small VMs, low-cost app services, or serverless options where possible.

### FR-004: Automatic shutdown of idle workloads
Non-production compute resources must automatically shut down when not actively in use.

Acceptance criteria:
- AC-011: VM or compute schedules are configured for all demo environments that are not continuously active.
- AC-012: Idle resources are stopped after a defined inactivity window.
- AC-013: Start/stop schedules are documented and visible to demo owners.

### FR-005: Cleanup and decommissioning process
Demo environments must have a clear teardown process and expiration rules.

Acceptance criteria:
- AC-014: Every demo environment has an expiration date or project end date.
- AC-015: A resource lifecycle must be set to expire in fewer than 5 calendar days from creation unless an approved exception is granted.
- AC-016: A cleanup workflow exists to remove resources after the expiration date.
- AC-017: Resources without an owner or expiration date are flagged for review.

### FR-006: Access control and separation of duties
Access to the subscription must be limited to authorized users and roles.

Acceptance criteria:
- AC-017: Except for the subscription owner, no user may have standing owner, administrator, or contributor access to the environment.
- AC-018: All non-owner contributor and administrator access must be granted through a least-privilege account using Azure PIM just-in-time access.
- AC-019: Each PIM activation request may be active for no more than 10 hours.
- AC-020: A user may activate a privileged role without explicit approval from an owner or administrator, provided the activation stays within the configured time limit.
- AC-021: Shared or generic administrative accounts are avoided.

### FR-007: Monitoring and cost visibility
The subscription must provide visibility into cost drivers and resource activity.

Acceptance criteria:
- AC-020: Cost analysis dashboards are available to subscription owners.
- AC-021: Monthly and daily cost trends are reviewed at regular intervals.
- AC-022: Unused resources are reported and reviewed for cleanup.

### FR-008: Architecture simplification for demo use
The environment must favor the simplest technology patterns that satisfy demo needs.

Acceptance criteria:
- AC-023: Single-tenant or small-scale patterns are preferred over multi-region or high-availability designs.
- AC-024: Secondary services are only added when essential to the demo scenario.
- AC-025: Production-grade features such as disaster recovery, premium backups, and large-scale caching are not required by default.

## 7. Non-Functional Requirements

### NFR-001: Cost control
The total monthly spend for the subscription must remain under the approved limit for the environment.

### NFR-002: Simplicity
The environment must be easy to deploy, operate, and decommission by non-specialist demo teams.

### NFR-003: Security baseline
The environment must use least-privileged access, minimal external exposure, and basic monitoring, even though it is not a production environment. Privileged access must be time-bounded and granted only through PIM for just-in-time activation.

### NFR-004: Maintainability
The environment must support recurring updates, cleanup, and re-provisioning without excessive manual effort.

### NFR-005: Auditability
All resources must be attributable to an owner, project, or limited-purpose demo use case.

### NFR-006: Reliability for demo workload
The platform must be stable enough for demonstration scenarios, but it is not required to support production-grade uptime commitments.

## 8. Constraints

- CON-001: The subscription is intended for demonstration use only and will not host production applications.
- CON-002: Cost is the primary design constraint for all infrastructure choices.
- CON-003: The environment should avoid premium or enterprise-tier services unless clearly justified.
- CON-004: Resource lifecycles must align with short-term demo or learning objectives.
- CON-005: No resource may remain active for 5 calendar days or longer without an approved exception.
- CON-006: Use of production security, networking, and resiliency patterns is discouraged unless a demo specifically requires them.
- CON-007: Except for the subscription owner, no user may have standing owner, administrator, or contributor access to the environment; privileged access must be granted through Azure PIM just-in-time activation.

## 9. Business Rules

- BR-001: No production app or production data may be deployed to the subscription.
- BR-002: Any resource exceeding the approved cost threshold must be reviewed and either approved or removed.
- BR-003: All resources must be tagged before use and must include an expiration date.
- BR-004: No resource may be assigned an expiration window of 5 calendar days or longer; all demo resources must be set to expire in fewer than 5 calendar days unless a documented exception is approved.
- BR-005: Demo resources that remain active past their expiration date are subject to cleanup and escalation.
- BR-006: Except for the subscription owner, no user may keep standing administrator or contributor access to the environment.
- BR-007: All non-owner administrator and contributor access must use a least-privilege account and Azure PIM just-in-time activation.
- BR-008: A PIM activation may remain active for up to 10 hours per request, and no privileged access may remain active beyond that time limit without a new activation.
- BR-009: New Azure services may be requested only if they fit the demo-only, low-cost operating model.

## 10. Success Metrics

- Monthly Azure spend remains at or below the agreed budget and forecast.
- At least 90% of demo workloads are shut down automatically outside active demo windows.
- 100% of resources have required tags, an owner, and an expiration date shorter than 5 calendar days.
- Unused or expired resources are cleaned up within a defined review cycle.
- Deployment errors caused by unauthorized or expensive service choices are minimized.

## 11. Risks and Mitigations

### Risk: Accidental overspend from forgotten or idle resources
Mitigation: automate shutdown, enforce budgets, require tags and expiration dates.

### Risk: Teams deploy production-like services in a non-production environment
Mitigation: restrict the service catalog, apply policy guardrails, and review exceptions.

### Risk: Unclear ownership leads to untracked resources
Mitigation: mandatory tags and periodic cleanup reviews.

### Risk: Demo environment becomes operationally complex and expensive
Mitigation: maintain a simple architecture, favor serverless and small-scale resources, and default to teardown after demo use.

## 12. Traceability Matrix

| Requirement ID | Linked BG | Summary |
| --- | --- | --- |
| FR-001 | BG-001 | Enforce budget and alerts |
| FR-002 | BG-003, BG-005 | Required resource tagging and ownership |
| FR-003 | BG-001, BG-002 | Restrict to cost-aware service catalog |
| FR-004 | BG-001, BG-005 | Auto shutdown idle workloads |
| FR-005 | BG-004 | Cleanup and decommissioning |
| FR-006 | BG-003 | Access control and least privilege |
| FR-007 | BG-001, BG-005 | Monitoring and cost visibility |
| FR-008 | BG-002, BG-003 | Simpler architecture for demo use |

## 13. Governance / Review

This BRD should be reviewed by Azure administrators, demo owners, and business sponsors before onboarding workloads. Any exception to the budget or service restrictions requires documented approval and a defined sunset date.

## 14. Version History

- 0.1: Initial draft covering demo-only Azure environment requirements, cost controls, and governance guardrails.

## 15. Appendix: Suggested Initial Budgeting Baseline

For an early-stage demo environment, a practical starting point is to design for low-cost monthly use with a not-to-exceed target, for example:

- Budget target: set below a conservative monthly cap based on available credits or internal spend policy
- Reserved cost room: maintain a small buffer to avoid surprise overages while allowing start/stop scheduling
- Exclusions: avoid long-running premium services, large SQL instances, and always-on VMs unless explicitly approved

This baseline should be revised by the subscription owner according to actual usage patterns and organizational policy.
