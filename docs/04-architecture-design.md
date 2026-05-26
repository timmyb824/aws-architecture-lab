# Architecture Design: Multi-Tier SaaS Platform on AWS

**Project:** aws-architecture-lab
**Author:** aws-arch-lab
**Date:** May 2026
**Status:** Implemented

---

## Executive Summary

This document describes the design and implementation of a production-grade, multi-tier
web application architecture on AWS. The architecture demonstrates core cloud engineering
principles: network isolation, high availability, elastic scaling, defense-in-depth
security, and comprehensive observability — all managed through Terraform with remote
state and a least-privilege IAM model.

The system is live at `https://lab.example.com`.

---

## Architecture Overview

```
                          Internet
                             │
                    ┌────────┴────────┐
                    │   CloudFront    │  CDN + HTTPS termination
                    │   + WAF         │  Rate limiting, OWASP rules
                    └────────┬────────┘
                             │
                    ┌────────┴────────┐
                    │      ALB        │  Application Load Balancer
                    │  (public subnet)│  Multi-AZ, health checks
                    └────────┬────────┘
                             │
              ┌──────────────┴──────────────┐
              │         EC2 + ASG            │  Auto Scaling Group
              │  us-east-1a  │  us-east-1b   │  2-4 instances, t3.micro
              │  (private)   │  (private)    │  nginx, SSM access only
              └──────┬───────┴───────┬───────┘
                     │               │
              ┌──────┴──────┐ ┌──────┴──────┐
              │  RDS MySQL  │ │ ElastiCache │
              │  Multi-AZ   │ │   Redis     │
              │  db.t3.micro│ │cache.t3.micro│
              └─────────────┘ └─────────────┘

Observability layer (always on):
  VPC Flow Logs → CloudWatch → metric filters → alarms → SNS
  CloudTrail → S3 (encrypted, log file validation)
  GuardDuty → EventBridge → SNS
  Config → 3 compliance rules → continuous evaluation
```

---

## Design Decisions

### 1. Network Architecture

**Decision:** Custom VPC with public/private subnet separation across two AZs.

**Alternatives considered:**

- Default VPC — rejected. No isolation, no control over CIDR ranges, not reproducible.
- Single AZ — rejected. Single point of failure for both compute and data tiers.

**Rationale:** Private subnets for EC2 and data resources mean instances have no public
IP addresses and no inbound internet route. The only inbound path is ALB → EC2 on port 80,
enforced by security group chaining. Outbound traffic routes through NAT Gateway for
package installs and SSM connectivity. This contains blast radius if any instance is
compromised.

**CIDR layout:**

```
VPC:              10.0.0.0/16
Public AZ-a:      10.0.1.0/24   (ALB, NAT Gateway)
Public AZ-b:      10.0.2.0/24   (ALB)
Private AZ-a:     10.0.10.0/24  (EC2, RDS primary)
Private AZ-b:     10.0.11.0/24  (EC2, RDS standby)
Reserved:         10.0.20.0/24  (future: dedicated DB subnet tier)
```

The gap between `10.0.2.x` and `10.0.10.x` is intentional — allows adding subnet tiers
without renumbering.

---

### 2. Compute Layer

**Decision:** EC2 Auto Scaling Group behind ALB, no SSH keys, SSM Session Manager for access.

**Alternatives considered:**

- ECS Fargate — would eliminate instance management but adds container orchestration
  complexity. EC2 + ASG is simpler to reason about for this architecture.
- Fixed instance count — rejected. No elasticity, wastes capacity at low load.

**Rationale:** ASG with 2 desired / 1 min / 4 max spans both AZs. ALB distributes traffic
and routes around unhealthy instances automatically. SSM Session Manager provides shell
access with zero open ports — no bastion host, no key management, IAM-controlled.

**Scaling policy:**

- Scale out: CPU > 60% for 3 consecutive minutes → add 1 instance
- Scale in: CPU < 30% for 10 consecutive minutes → remove 1 instance
- Cooldown: 300 seconds between actions

Asymmetric evaluation periods (3 vs 10 minutes) prevent thrashing — respond to load
quickly, remove capacity conservatively.

**IAM:** EC2 instances use instance profiles with `AmazonSSMManagedInstanceCore` only.
No static credentials anywhere. Credential rotation is automatic via the instance
metadata service.

---

### 3. Data Layer

**Decision:** RDS MySQL Multi-AZ for relational data, ElastiCache Redis for caching and
session storage.

**Alternatives considered:**

- RDS Single-AZ — rejected. Single point of failure, no automatic failover.
- Aurora — would provide better performance and faster failover, but higher cost for a lab.
  At production scale, Aurora Global Database would be the correct choice for cross-region DR.
- DynamoDB — considered for session storage but Redis is better suited for its data
  structures and existing familiarity.

**Rationale:** RDS Multi-AZ provides synchronous replication to a standby in a second AZ.
Failover is automatic in ~60 seconds with zero data loss. The application endpoint DNS
name doesn't change during failover — no config changes required on the app side.

**Tested:** Forced failover via `reboot-db-instance --force-failover`. Standby promoted
in 45 seconds. AZ flipped from `us-east-1b` to `us-east-1a`. Endpoint unchanged.

**Credentials:** Database password generated by Terraform's `random_password` resource
and stored in Secrets Manager. Never appears in code, state files, or plan output.
Applications retrieve credentials at runtime via the AWS SDK.

---

### 4. CDN and Edge Security

**Decision:** CloudFront distribution in front of ALB with WAF Web ACL.

**Alternatives considered:**

- ALB directly — rejected. No HTTPS with custom domain without ACM + ALB listener,
  no edge caching, no WAF at edge.
- Third-party CDN — rejected. AWS-native integration is simpler and keeps everything
  in one control plane.

**Rationale:** CloudFront terminates HTTPS at the edge using an ACM certificate for
`lab.example.com`. Traffic from CloudFront to ALB is HTTP on the internal AWS network
— acceptable because it never traverses the public internet. `redirect-to-https` on the
viewer protocol policy ensures all client traffic is encrypted.

**WAF rules (priority order):**

1. Rate limit — 1,000 requests per 5 minutes per IP (blocks brute force)
2. AWSManagedRulesCommonRuleSet — OWASP Top 10 (SQL injection, XSS, path traversal)
3. AWSManagedRulesKnownBadInputsRuleSet — known malicious patterns

AWS managed rule groups are maintained by AWS — no manual signature updates required.

**DNS:** Route 53 hosted zone for `lab.example.com` with NS delegation from Cloudflare.
CloudFront alias A record (free) instead of CNAME (charged per query).

---

### 5. Observability

**Decision:** Four-layer observability stack: flow logs, audit trail, threat detection,
compliance.

**Rationale:**

- **VPC Flow Logs → CloudWatch:** Network forensics. Every accepted and rejected connection
  logged. Metric filter alarms on REJECT spikes — early signal for misconfiguration or
  probing.
- **CloudTrail:** Every AWS API call recorded with log file validation. Who did what,
  when, from where. Multi-region trail captures IAM and STS events regardless of region.
- **GuardDuty:** ML-based threat detection across flow logs, CloudTrail, and DNS.
  Zero infrastructure to manage. Findings route via EventBridge → SNS.
- **Config:** Continuous compliance evaluation. Three rules: no unrestricted SSH,
  S3 public access blocked, RDS not publicly accessible. Found a real finding on
  day one — a forgotten 2019 S3 bucket with no public access block. Remediated immediately.

---

### 6. IAM and Least Privilege

**Decision:** Deployer IAM user with three scoped policy documents, no AdministratorAccess.

The deployer user (`aws-arch-lab-deployer`) has exactly the permissions needed for lab
work, split across three policies to stay within the 6,144 character policy size limit:

| Policy              | Scope                                                     |
| ------------------- | --------------------------------------------------------- |
| `lab-networking`    | EC2, VPC, ALB, ASG, WAF, CloudFront, Route 53             |
| `lab-data`          | RDS, ElastiCache, Secrets Manager, S3                     |
| `lab-observability` | CloudWatch, CloudTrail, GuardDuty, Config, SNS, IAM roles |

Bootstrap infrastructure (state bucket, deployer user) is managed separately using
`bootstrap-admin` with AdminAccess — the "break glass" identity used only for account-level
changes.

---

## Cost Analysis

### Per-Session Costs (resources running)

| Resource                   | Rate                         | Notes                      |
| -------------------------- | ---------------------------- | -------------------------- |
| NAT Gateway                | $0.045/hr + data             | Destroyed between sessions |
| RDS db.t3.micro Multi-AZ   | $0.023/hr                    | Destroyed between sessions |
| ElastiCache cache.t3.micro | $0.017/hr                    | Destroyed between sessions |
| EC2 t3.micro x2            | $0.0104/hr each              | Running continuously       |
| ALB                        | $0.008/hr + LCU              | Running continuously       |
| CloudFront                 | $0.0085/10k requests         | Usage-based                |
| WAF                        | $1.00/mo + $0.60/1M requests | Minimal at lab traffic     |

**Estimated monthly cost if left fully running:** ~$60-80/month
**Actual cost with session management (teardown/rebuild daily):** ~$15-25/month

### Cost Controls Implemented

- NAT Gateway destroyed between sessions via `session.sh`
- RDS and ElastiCache destroyed between sessions via `session.sh`
- AWS Budget alert at 80% ($40) and 100% ($50) forecasted
- CloudFront `PriceClass_100` — US, Canada, Europe only (cheapest tier)

---

## Failure Scenarios

### AZ Failure (us-east-1b goes down)

- ALB stops routing to instances in 1b, continues serving from 1a ✅
- RDS automatically promotes standby (was in 1a) in ~60 seconds ✅
- ElastiCache single node — temporary cache unavailability, application falls back to DB ⚠️
- **Mitigation at scale:** ElastiCache replication group with Multi-AZ

### EC2 Instance Failure

- ASG detects unhealthy instance via ALB health check
- Terminates and replaces automatically within ~3 minutes ✅
- Minimum size of 1 ensures at least one instance always running ✅

### Database Connection Exhaustion

- RDS `db.t3.micro` supports ~66 connections
- At scale, add RDS Proxy to pool connections ⚠️

### DDoS / Traffic Spike

- WAF rate limiting blocks >1,000 req/5min per IP ✅
- CloudFront absorbs layer 3/4 attacks at edge ✅
- ASG scales out on CPU pressure (3 minute lag) ⚠️
- **Mitigation:** AWS Shield Advanced for guaranteed DDoS response

---

## What I Would Do Differently at Scale

1. **Aurora Global Database** instead of RDS Multi-AZ — sub-second RPO, cross-region
   failover in under 1 minute, better read scaling via read endpoints

2. **ECS Fargate** instead of EC2 ASG — eliminates instance management, faster scaling
   (seconds vs minutes), better bin packing

3. **ElastiCache Replication Group** instead of single node — Multi-AZ Redis with
   automatic failover, read replicas for scaling

4. **RDS Proxy** — connection pooling between application and RDS, especially important
   for serverless or high-connection-count workloads

5. **Multi-account strategy** — separate AWS accounts for dev/staging/prod with
   cross-account IAM roles, AWS Organizations SCPs for guardrails

6. **Terraform modules** — extract VPC, RDS, and ASG patterns into reusable modules
   with published versions

7. **CI/CD pipeline** — GitHub Actions running `terraform plan` on PR, `terraform apply`
   on merge to main, with plan review step for production

8. **WAF logging** — enable WAF log delivery to S3/CloudWatch for blocked request analysis

---

## Terraform Architecture

```
aws-architecture-lab/
├── bootstrap/                    # Account foundation — run with admin
│   ├── main.tf                   # S3 backend, provider
│   ├── iam.tf                    # Deployer user, three scoped policies
│   └── state.tf                  # State bucket, versioning, encryption
├── projects/
│   ├── 01-vpc-foundation/        # VPC, ALB, EC2, ASG, SSM, alarms
│   ├── 02-resilient-data/        # RDS Multi-AZ, ElastiCache, Secrets Manager
│   ├── 03-observability/         # Flow logs, CloudTrail, GuardDuty, Config
│   └── 04-full-architecture/     # CloudFront, WAF, Route 53, scaling, budget
├── scripts/
│   └── session.sh                # Daily start/stop for expensive resources
└── docs/
    ├── 00-bootstrap-prereqs.md
    ├── 01-vpc-foundation.md
    ├── 02-resilient-data.md
    ├── 03-observability.md
    ├── 04-architecture-design.md  ← this document
    └── aws-cli-cheatsheet.md
```

**Remote state:** Each project maintains isolated state in S3 under a separate key.
Projects reference each other's outputs via `terraform_remote_state` data sources —
no hardcoded resource IDs anywhere.

**IAM model:** Two identities. `bootstrap-admin` (AdminAccess) for bootstrap only.
`aws-arch-lab-deployer` (scoped) for all lab Terraform. Credentials in `~/.aws/credentials`,
never in code.

---

## Interview Talking Points

**On network design:**

> "I never use default VPCs. Every environment gets a custom VPC with explicit public/private
> subnet separation. EC2 instances have no public IPs — the only inbound path is through
> the ALB, enforced by security group chaining at the identity level, not the IP level."

**On database resilience:**

> "I've tested RDS Multi-AZ failover hands-on. The standby promoted in 45 seconds with
> zero data loss — synchronous replication means the standby is always current. The
> application endpoint doesn't change during failover, so there's no config change required."

**On security:**

> "Defense in depth: WAF at the CloudFront edge blocks OWASP Top 10 and rate limits
> before traffic reaches my VPC. Security groups use chaining so only the ALB can reach
> EC2. No static credentials anywhere — instance profiles with automatic rotation.
> GuardDuty watching for anomalies. Config found a real misconfiguration on day one."

**On cost:**

> "I treat cost like a first-class concern. NAT Gateway and RDS are destroyed between
> sessions — that alone cuts the monthly bill by 60%. Budget alerts at 80% and 100%.
> CloudFront PriceClass_100 to avoid paying for edge locations I don't need."

**On Terraform:**

> "Everything is code. Isolated state per project, remote state references between
> projects instead of hardcoded IDs, least-privilege deployer IAM, and a session script
> that manages expensive resources so I'm not paying for idle infrastructure."
