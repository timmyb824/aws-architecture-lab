# AWS Architecture Lab

A hands-on Terraform lab series for learning core AWS architecture patterns. Each project builds on the last, progressing from foundational networking through resilient data layers, observability, and a full production-style deployment.

## Projects

| #   | Lab               | Focus                                            |
| --- | ----------------- | ------------------------------------------------ |
| 01  | VPC Foundation    | VPC, subnets, NAT, ALB, EC2 Auto Scaling         |
| 02  | Resilient Data    | RDS, ElastiCache, Secrets Manager                |
| 03  | Observability     | CloudTrail, GuardDuty, AWS Config, VPC Flow Logs |
| 04  | Full Architecture | CloudFront, WAF, Route 53, budgets               |

## Prerequisites

- Terraform >= 1.15
- AWS CLI configured with appropriate credentials
- A registered domain name (Lab 04 — Route 53 creates a hosted zone and expects NS records delegated from your DNS provider to AWS)
- See `docs/00-bootstrap-prereqs.md` for first-time setup
