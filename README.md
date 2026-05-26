# AWS Architecture Lab

A hands-on Terraform lab series for learning core AWS architecture patterns. Each project builds on the last, progressing from foundational networking through resilient data layers, observability, and a full production-style deployment.

## Projects

| #   | Lab               | Focus                                            |
| --- | ----------------- | ------------------------------------------------ |
| 01  | VPC Foundation    | VPC, subnets, NAT, ALB, EC2 Auto Scaling         |
| 02  | Resilient Data    | RDS, ElastiCache, Secrets Manager                |
| 03  | Observability     | CloudTrail, GuardDuty, AWS Config, VPC Flow Logs |
| 04  | Full Architecture | CloudFront, WAF, Route 53, budgets               |

## ⚠️ Cost Warning

These labs provision real AWS resources that **will incur charges** while running. Some resources (NAT Gateway, RDS, ElastiCache) are particularly expensive if left on overnight.

`scripts/session.sh` is provided to tear down the most costly resources at the end of a session and recreate them the next day:

```bash
# End of day — stop the cost clock
./scripts/session.sh down

# Start of day — bring resources back up
./scripts/session.sh up
```

`session.sh` only targets a subset of resources. **You are responsible for running `terraform destroy` in each project directory when you are done with a lab entirely.** Always verify your AWS console to confirm no unexpected resources remain running.

## Prerequisites

- Terraform >= 1.15
- AWS CLI configured with appropriate credentials
- A registered domain name (Lab 04 — Route 53 creates a hosted zone and expects NS records delegated from your DNS provider to AWS)
- See `docs/00-bootstrap-prereqs.md` for first-time setup
